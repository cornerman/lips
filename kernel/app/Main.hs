{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI (crystallization plan).
--
-- Every path it reads or writes comes from 'Lips.Identity': a program sits
-- alone beside a folder named after its language, which holds everything the
-- machine wrote (see that module for the shape).
--
--   * @lips generate [model] \<program\>@ is the one AI step: the model mints a
--     /language/ (patterns) for the loose program; the kernel crystallizes the
--     program with it and validates by a full run; only then are the language
--     (@\<language\>/\<language\>.lang@), the crystal witness
--     (@\<language\>/out/\<instance\>.decisions@), and the generation record
--     written.
--   * @lips compile \<program\>@ takes the loose program directly. It verifies
--     the committed @.expect@ contract, then crystallizes with the language's
--     @.lang@ and realizes into a DIRECTORY (@default.nix@ plus a staged
--     @artifacts/@), deterministically, with no AI. If the language is
--     missing, the program escaped it, or the module drops a promised value,
--     it fails loud (and names @generate@ where that is the remedy).
--   * @lips check \<program\>@ is the gate alone: diagnostics plus the
--     committed @.expect@ contract against the realized module, offline.
--   * Running is not a lips verb: @compile@ prints the stock @nix@ commands
--     over the compiled directory, and the user picks one.
module Main (main) where

import           Control.Exception  (IOException, try)
import           Control.Monad      (forM, forM_, unless)
import qualified Data.ByteString.Lazy as BL
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getEnvironment, lookupEnv)
import           System.Exit        (ExitCode (..), exitFailure)
import           System.IO          (hFlush, hSetEncoding, stderr, stdout, utf8)
import           System.Directory   (doesPathExist)
import           System.FilePath    (takeFileName, (</>))
import           System.Process     (CreateProcess (..), callCommand, proc, readCreateProcessWithExitCode, readProcessWithExitCode)

import           Lips.Kernel.Engine.Aggregate   (assembleSubject, mergeModeOf)
import           Lips.Kernel.Engine.Data       (bindSelf, toDemand, toRule)
import           Lips.Generate.Readme   (renderReadme)
import           Lips.Identity                 (readmePath, artifactsPath, artifactsPathIn, compiledPath, decisionsPath, directionPath, expectPath, expectPathIn, generationPath, generationPathIn, instanceName, langDir, langPath, langPathIn, languageName, outDir, resolveLangDir)
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), CheckOpts (..), OptionsOpts (..), cliParserInfo)
import           Options.Applicative    (execParser)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Minting  (EngineItem (..), Gap (..), ItemCandidate (..), SourceFile (..), assemble, carriesEngineMeaning, expectsOf, gapsOf, parseEngineCandidates, promptWithDirection, reportOf, sourcesOf, uncheckableExpects)
import           Lips.Generate.PiJson   (PiReply (..), parsePiReply)
import           Lips.Generate.Record   (genId, record)
import           Lips.Kernel.Base       (Conflict (..), Base)
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect     (Expect (..), bindSelfExpect, checkValues, evalExpr, expandExpects, expectedValue, readExpect, renderExpect)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Refine     (RefineError (..))
import           Lips.Kernel.Run
import           Lips.Kernel.Lang.Crystallize  (CrystError (..), LineOutcome (..), crystallize)
import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..), diagnose)
import           Lips.Kernel.Lang.Store         (EngineData (..), readLang, renderLang)
import           Lips.Kernel.Engine.Overlap    (renderRuleOverlap, ruleOverlaps)
import           Lips.Kernel.OptionType        (Answer (..), answerQuery, checkEmits, dotted, renderOptionError, renderOptionType)
import           Lips.Nix.Flake                (flakeText, runCommands)
import           Lips.Nix.Options              (parseNixOptionsJson)
import           Lips.Nix.Target               (Target (..), defaultTarget, parseTarget, targetSlug)
import           Lips.Lsp.Server               (runLsp)

-- | Refinement step budget: generous, since a runaway rule fails loud anyway.
budget :: Int
budget = 10000

-- | A minted language is admitted only if every pattern is at least this
-- certain; otherwise generate fails loud (deduce-or-fail), writing nothing.
-- Overridable per invocation with @--confidence@; the chosen value is pinned
-- into the generation record.
defaultConfidence :: Double
defaultConfidence = 0.7

main :: IO ()
main = do
  -- lips' messages carry non-ASCII (the "→" every remedy line opens with), and
  -- the handle encoding otherwise follows the ambient locale: under LANG=C a
  -- write would die with "cannot encode character", turning a helpful error
  -- into a crash. Pin UTF-8 so what lips prints does not depend on the
  -- environment it is run from. (@lsp@ sets its own binary mode afterwards.)
  mapM_ (`hSetEncoding` utf8) [stdout, stderr]
  cmd <- execParser (cliParserInfo defaultConfidence)
  case cmd of
    Generate go -> generate (goTarget go) (goConfidence go) (goRenew go) (goVerbose go) (goModel go) (goFiles go)
    Compile co  -> compileLoose (coOut co) (coLangDir co) (coFile co)
    Check co    -> checkLoose (ceLangDir co) (ceFile co)
    Options oo  -> optionsQuery (ooTarget oo) (ooLimit oo) (T.pack (ooQuery oo))
    Lsp         -> runLsp

-- | @compile@: verify the program's committed contract, then crystallize +
-- realize and materialize a DIRECTORY -- default @<language>/out/<instance>/@, or
-- @--out <dir>@ -- holding @default.nix@ plus a staged @artifacts/@ tree. A
-- directory, not stdout, so an engine with artifacts is complete and
-- @imports = [ ./<dir> ]@ resolves default.nix. The output is derived, and it
-- lands inside the language's @out/@, which 'ensureDerived' makes
-- self-ignoring, so it never gets committed by accident.
--
-- The behavioral gate runs FIRST (the same one @check@ runs), so compile never
-- materializes a module that dropped a pinned value: a misroute an offline edit
-- can introduce fails loud here instead of importing a silently-wrong config.
-- Nix is the compile target, so the gate's @nix eval@ is no new dependency
-- (every compile invocation already runs through nix, and the output is only
-- meaningful where nix runs); the output stays bit-identical and deterministic,
-- the gate only refuses a bad one.
-- Beside @default.nix@ it writes @flake.nix@ (the addressable
-- entry) and, when the program declares artifacts, @artifact.nix@ (the
-- buildable derivations, extracted from the same ground base as the module).
-- Then it prints the exact @nix@ commands that run it: running a lips program
-- is not a lips verb, it is stock @nix@ over this directory, so compile emits
-- the handles and names the commands (only those the program's shape supports,
-- so no impossible command is ever shown -- deduce-or-fail).
compileLoose :: Maybe FilePath -> Maybe FilePath -> FilePath -> IO ()
compileLoose mout mLangDir file = do
  dir <- either die pure (resolveLangDir file mLangDir)
  checkLoose mLangDir file
  program <- readProgramOrDie file
  eng     <- loadLangOrDie dir file
  target  <- readRecordedTarget dir file
  case validate file eng program of
    Left f                 -> die (printFail file f)
    Right (_, nixMod, art) -> do
      let outDirPath = maybe (compiledPath file) id mout
      ensureDerived file
      callCommand ("mkdir -p " <> shq outDirPath)
      TIO.writeFile (outDirPath </> "default.nix") nixMod
      stageFromDisk dir file (outDirPath </> "artifacts")
      artNames <- case art of
        Nothing            -> pure []
        Just (body, names) -> TIO.writeFile (outDirPath </> "artifact.nix") body >> pure names
      TIO.writeFile (outDirPath </> "flake.nix") (flakeText target (not (null artNames)))
      TIO.hPutStrLn stderr ("compiled " <> T.pack file <> " -> " <> T.pack outDirPath)
      TIO.hPutStrLn stderr "run it with nix over the compiled dir:"
      mapM_ (TIO.hPutStrLn stderr) (runCommands target artNames outDirPath)

-- | Create a language's derived subtree and make it ignore itself: @out/@ gets
-- a @.gitignore@ holding @*@. lips writes that rule rather than asking the
-- user's repo to carry one, so derived output (crystal witnesses, compiled
-- module dirs) stays untracked wherever a program lives, with no setup.
-- Written once; an existing file is left alone, so a user can edit it.
ensureDerived :: FilePath -> IO ()
ensureDerived file = do
  callCommand ("mkdir -p " <> shq (outDir file))
  let ign = outDir file </> ".gitignore"
  there <- doesPathExist ign
  unless there (TIO.writeFile ign "*\n")

-- | The world an engine was minted for, read from its committed .generation
-- record (the @target:@ line). An engine minted before targets existed has no
-- such line and defaults to nixos, so old engines keep working.
readRecordedTarget :: FilePath -> FilePath -> IO Target
readRecordedTarget dir file = do
  m <- tryRead (generationPathIn dir file)
  pure $ case m of
    Nothing  -> defaultTarget
    Just src -> case [ t | l <- T.lines src
                         , Just rest <- [T.stripPrefix "target:" l]
                         , Just t <- [parseTarget (T.unpack (T.strip rest))] ] of
      (t : _) -> t
      []      -> defaultTarget

-- | @check@: verify the program's committed behavioral contract holds against
-- its realized module, deterministically (no AI). This is the offline guardian
-- of the @.expect@ spec; @generate@ runs the same check before accepting an
-- engine, and the flake check shells this per example.
checkLoose :: Maybe FilePath -> FilePath -> IO ()
checkLoose mLangDir file = do
  dir     <- either die pure (resolveLangDir file mLangDir)
  program <- readProgramOrDie file
  eng     <- loadLangOrDie dir file
  -- First phase, pure and offline: how the program sits in its language.
  -- Always shown, so authoring is never blind; the behavioral gate runs only
  -- once the program crystallizes cleanly and completely.
  let d = diagnose file eng program
  TIO.putStrLn (renderDiagnosis file d)
  hFlush stdout  -- so the report lands before any stderr failure below
  if any escapes (diagLines d)
    then die (report
           (T.pack file <> " has lines its language cannot read yet.")
           []
           ("→ grow the language: lips generate " <> T.pack file))
    else if not (null (diagOpen d))
      then die (report
             (T.pack file <> " is incomplete while these questions stay open.")
             []
             "→ answer them by stating the detail in the program.")
      else expectGate dir file eng program
  where
    escapes Matched{} = False
    escapes _         = True

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
expectGate :: FilePath -> FilePath -> EngineData -> Text -> IO ()
expectGate dir file eng program = do
  expSrc <- tryRead (expectPathIn dir file)
  case expSrc of
    Nothing  -> TIO.putStrLn
      (T.pack file <> ": crystallizes cleanly; no behavioral contract yet ("
        <> T.pack (expectPathIn dir file) <> " is missing, written by generate).")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        | otherwise -> case validate file eng program of
        Left f       -> die (printFail file f)
        Right (base, nixMod, _) -> do
          -- Bind <self> in the contract's option paths to this instance, so it
          -- checks against the realized (already-bound) module.
          res <- runExpects (stageFromDisk dir file) (map (bindSelfExpect (instanceName file)) expects) base nixMod
          case res of
            Right () -> TIO.putStrLn (T.pack file <> ": all "
                          <> tshow (length expects) <> " checks pass.")
            Left (ToolMissing e) -> die (nixMissing file "check the program" "check" e)
            Left (EvalFailed e)  -> die (nixEvalFailed file "check" e)
            Left (Violations fs) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))

-- | Render the authoring diagnosis: a coverage headline, one line per program
-- line (matched to which pattern and subject, or unread, or ambiguous), then
-- the open questions. Pure view over 'diagnose'; a future editor paints the
-- same outcomes as squiggles.
renderDiagnosis :: FilePath -> Diagnosis -> Text
renderDiagnosis file d = T.intercalate "\n" (headline : map row (diagLines d) ++ openBlock)
  where
    headline = T.pack file <> ": " <> tshow (diagMatched d) <> " of "
                 <> tshow (diagTotal d) <> " lines crystallize."
    row (Matched n _ pid decs) =
      "  line " <> tshow n <> "  ok        " <> pid <> "  "
        <> T.intercalate ", " (map (subjectPath . dSubject) decs)
    row (Unmatched n t) =
      "  line " <> tshow n <> "  no match  \"" <> t <> "\""
    row (Ambiguous n _ ids) =
      "  line " <> tshow n <> "  ambiguous " <> T.intercalate "," ids
    openBlock
      | null (diagOpen d) = []
      | otherwise = "" : ("open questions (" <> tshow (length (diagOpen d)) <> "):")
                       : ["  - " <> q | q <- diagOpen d]
    subjectPath (Subject segs) = T.intercalate "." segs

-- | Load and parse a program's @.lang@ (found under @dir@), or fail loud
-- naming @generate@.
loadLangOrDie :: FilePath -> FilePath -> IO EngineData
loadLangOrDie dir file = do
  let langFile = langPathIn dir file
  msrc <- tryRead langFile
  case msrc of
    Nothing  -> die (report
      (T.pack file <> " isn't set up yet (" <> T.pack langFile <> " is missing).")
      []
      ("→ create it: lips generate " <> T.pack file))
    Just src -> case readLang src of
      Left es  -> die (unreadable file ".lang" es)
      Right eng -> pure eng

-- | Read the program file, or fail with a plain message instead of a raw
-- exception when the path is wrong (a common typo at the shell).
readProgramOrDie :: FilePath -> IO Text
readProgramOrDie file = do
  m <- tryRead file
  case m of
    Just t  -> pure t
    Nothing -> die (report
      ("lips can't read " <> T.pack file <> ".")
      []
      "→ check the path, or create the program file first.")

tryRead :: FilePath -> IO (Maybe Text)
tryRead p = either (const Nothing) Just <$> (try (TIO.readFile p) :: IO (Either IOException Text))

-- | @generate@: the one AI step. The model mints a whole engine (patterns,
-- rules, demands); the kernel crystallizes the program with it and validates
-- by a full run plus a Nix parse before writing anything.
generate :: Target -> Double -> Bool -> Bool -> Maybe String -> [FilePath] -> IO ()
-- Unreachable: Lips.Cli.generateOpts's `some` guarantees at least one file by
-- construction. Kept only so this function stays total (-Wall incomplete-patterns).
generate _ _ _ _ _ [] = die "lips generate needs at least one program (unreachable: the CLI parser requires one)."
generate target confidence renew verbose mmodel files@(rep : _) = do
  let lang = languageName rep
  -- One language per invocation: the grammar is shared, so mixed extensions
  -- would mean two languages. Fail loud.
  case [ f | f <- files, languageName f /= lang ] of
    (_ : _) -> die (report
      "lips generate mints ONE language at a time, but these programs are not all the same language."
      [ T.pack f <> " is ." <> T.pack (languageName f) | f <- files ]
      ("→ generate the ." <> T.pack lang <> " programs together, other languages separately."))
    [] -> pure ()
  progs <- forM files (\f -> (,) f <$> readProgramOrDie f)
  -- Owner taste is language-level (shared); read once from the language path.
  direction <- tryRead (directionPath rep)
  let prompt = promptWithDirection direction target
      -- The mint sees the whole example set at once, so the grammar generalizes
      -- across them (anti-unification): tokens that vary between examples become
      -- holes, tokens that agree stay literal. One program is the corpus-of-one
      -- case. The same set is the regeneration corpus below.
      corpus = T.intercalate "\n"
        [ "=== program " <> T.pack (takeFileName f) <> " ===\n" <> t | (f, t) <- progs ]
  (reply, model) <- callPi mmodel prompt corpus target
  -- --verbose: echo the model's raw reply verbatim before parsing, so the
  -- whole minted engine is inspectable even when it validates cleanly (a
  -- refusal already shows the offending lines). To stderr, leaving stdout the
  -- pipeable module.
  if verbose
    then TIO.hPutStr stderr (T.unlines
           [ "--- raw model reply (" <> model <> ") ---", reply, "--- end reply ---" ])
    else pure ()
  let (errs, candidates) = parseEngineCandidates reply
      -- A because-note explains a low-confidence item; keyed by shared id, it
      -- never gates the build and never enters the engine.
      notes = [(icId c, r) | c <- candidates, ItemNote r <- [icItem c]]
      -- Deduce-or-fail: the programs are the only source of truth, so an item
      -- the model cannot confidently derive means they underspecify it.
      unsure = [c | c <- candidates, carriesEngineMeaning (icItem c)
                  , let Confidence x = icConfidence c, x < confidence]
      gaps = gapsOf (map icItem candidates)
  if not (null errs) || not (null unsure)
    then die (refusalReport rep confidence errs unsure notes gaps)
    else do
      -- A mint without an explanation is incomplete: the human's review
      -- artifact is the report, not the .lang. A structural guard, so the
      -- channel cannot rot into an optional pleasantry the model skips.
      reportBody <- case reportOf (map icItem candidates) of
        Just b | not (T.null (T.strip b)) -> pure b
        _ -> die (report
          ("the mint for ." <> T.pack lang <> " came back without a report block.")
          ["lips needs the language explained in plain words before it commits it."]
          ("\8594 run generate again: lips generate " <> T.pack rep))
      let eng0 = assemble (map icItem candidates)
      -- Validate the engine EXACTLY as it will be persisted: render to .lang and
      -- read it back, so any render/read round-trip drift is caught at mint
      -- time, not on a later `print`. The read-back engine is what we write.
      eng <- case readLang (renderLang (FromSource (SourceLoc "lang" 0)) eng0) of
        Left es -> die (validationReport rep ("the setup can't be saved and reloaded cleanly:\n" <> T.unlines (map renderParseError es)))
        Right e -> pure e
      assertRulesOrthogonal rep eng
      assertOptionsAdmissible target rep eng
      -- Every program must crystallize, run, and parse as Nix under the shared
      -- engine: the example set is the regeneration corpus.
      validated <- forM progs $ \(f, t) -> case validate f eng t of
        -- An unmet demand at generate is ambiguous by construction (the kernel
        -- is domain-blind): name both remedies rather than blame one side.
        Left (FailRun (OpenQuestions qs)) -> die (demandGenerateFail f qs)
        Left ff -> die (validationReport f (failureReport f ff))
        Right (base, nixModule, _) -> do
          nixCheck <- nixParses nixModule
          case nixCheck of
            Left (NixToolMissing e) -> die (nixMissing f "verify the output" "generate" e)
            Left (NixInvalid why)   -> die (validationReport f ("the configuration lips produced isn't valid Nix:\n" <> why))
            Right ()                -> pure (f, base, nixModule)
      -- Sources are minted in memory; stage them (not yet on disk) so the
      -- behavioral gate can evaluate the artifact derivations.
      let minted = sourcesOf (map icItem candidates)
      -- The contract is language-level. On regeneration the COMMITTED contract
      -- governs (the stable spec regeneration may not silently break); on first
      -- generation the minted assertions bootstrap it.
          mintedExpects = expectsOf (map icItem candidates)
      -- --renew re-blesses the behavioral contract: ignore the committed
      -- .expect (do not even read it) so the minted assertions bootstrap it
      -- afresh and overwrite the file below. Every correctness gate above and
      -- the behavioral gate below still run, so a bad mint still writes nothing.
      committed <- if renew then pure Nothing else tryRead (expectPath rep)
      expects <- case maybe (Right mintedExpects) readExpect committed of
        Left es -> die (report
          (T.pack (expectPath rep) <> " is unreadable, so lips can't verify against it:")
          [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
          ("→ fix or delete " <> T.pack (expectPath rep) <> ", then run generate again."))
        Right xs -> pure xs
      case uncheckableExpects (edRules eng) expects of
        bad@(_ : _) -> die (uncheckableReport rep bad)
        []          -> pure ()
      -- The shared contract gates every program, each bound to its own <self>.
      forM_ validated $ \(f, base, nixModule) -> do
        gate <- runExpects (\dst -> writeSources dst minted)
                           (map (bindSelfExpect (instanceName f)) expects) base nixModule
        case gate of
          Left (ToolMissing e) -> die (nixMissing f "verify the output" "generate" e)
          Left (EvalFailed e)  -> die (nixEvalFailed f "generate" e)
          Left (Violations fs) -> die (report
            ("lips built a setup for " <> T.pack f <> ", but it doesn't produce what the program promises:")
            fs
            ("→ run generate again. If you changed the program on purpose, accept "
              <> "the new behavior: lips generate --renew " <> T.pack rep
              <> " (rewrites " <> T.pack (expectPath rep) <> ")."))
          Right () -> pure ()
      -- All held: write the shared language once, a crystal per instance. Every
      -- engine line is stamped with the content id of the .generation record,
      -- checkable by re-hashing it.
      let rec = record model target confidence prompt corpus reply
      -- The language folder holds every minted and derived file; create it (and
      -- its derived out/ subtree) before writing, so a first mint beside a bare
      -- program just works.
      callCommand ("mkdir -p " <> shq (langDir rep))
      TIO.writeFile (langPath rep) (renderLang (FromGeneration (genId rec)) eng)
      TIO.writeFile (generationPath rep) rec
      TIO.writeFile (readmePath rep) (renderReadme (T.pack lang) reportBody gaps)
      writeSources (artifactsPath rep) minted
      forM_ validated $ \(f, base, _) -> do
        ensureDerived f
        TIO.writeFile (decisionsPath f) (renderBase base)
      -- Bootstrap the contract on first generation only; keep the committed
      -- spec stable across regenerations.
      maybe (TIO.writeFile (expectPath rep) (renderExpect mintedExpects))
            (const (pure ())) committed
      -- Prose to stderr so stdout stays a pipeable module (the first program's).
      TIO.hPutStr stderr $ T.unlines $
        [ "lips set up ." <> T.pack lang <> " from " <> tshow (length files)
            <> " program(s) and verified each produces a valid NixOS configuration."
        , "" ]
        ++ take 5 [ l | l <- T.lines (T.strip reportBody), not (T.null (T.strip l)) ]
        ++ [ "\8594 read the whole account: " <> T.pack (readmePath rep) ]
        ++ (if null gaps then [] else
             [ "", "lips could not do these, and says why in " <> T.pack (readmePath rep) <> ":" ]
             ++ [ "  - " <> gapSlug g | g <- gaps ])
        ++ [ "" ]
        ++ [ "→ preview:  lips compile " <> T.pack f | (f, _, _) <- validated ]
      case [ m | (f, _, m) <- validated, f == rep ] of
        (m : _) -> TIO.putStr m
        []      -> pure ()

-- | @options@: look a query up in the target world's pinned option schema and
-- print the answer. This verb is both a human's lookup and the target of the
-- mint's one tool (@query_options@), so what a human reads here is exactly what
-- the model is told -- there is no second, model-facing renderer to drift.
--
-- It never calls a model (invariant 1 holds trivially: no model runs anywhere
-- but generate) and it never writes anything.
optionsQuery :: Target -> Int -> Text -> IO ()
optionsQuery target limit query = do
  schemaPath <- ensureOptionSchema target ("options " <> query)
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  bytes <- case mbytes of
    Left e -> die (report
      ("lips can't read the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run it again.")
    Right b -> pure b
  case parseNixOptionsJson bytes of
    Left why -> die (report
      ("lips can't parse the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [why]
      "→ run it again.")
    -- Exit 0 even for Nowhere: "no option matches that" is a valid answer to a
    -- question, not a failure of the command.
    Right schema -> TIO.putStr (renderAnswer query (answerQuery limit query schema))

-- | Render a lookup for a reader who must decide what to ask NEXT, which is why
-- a namespace answer says how to drill in and a miss suggests how to re-word.
renderAnswer :: Text -> Answer -> Text
renderAnswer query ans = case ans of
  Leaves ls -> T.unlines
    [ dotted p <> " : " <> renderOptionType t | (p, t) <- ls ]
  Namespaces ns hidden -> T.unlines $
    [ dotted p <> " (" <> plural n "option" <> ")" | (p, n) <- ns ]
      ++ [ "… and " <> plural hidden "more namespace" <> "." | hidden > 0 ]
      ++ [ "Ask again with one of these paths to see its options." ]
  Nowhere -> T.unlines
    [ "no option matches " <> query
    , "Try a shorter query, or a different word for the same thing."
    ]

-- | @3 options@ but @1 option@: a count a reader trips over is a count they
-- reread instead of acting on.
plural :: Int -> Text -> Text
plural n word = tshow n <> " " <> word <> (if n == 1 then "" else "s")

-- | Orthogonality is checked statically, before an engine is written: two
-- rules whose left-hand sides unify could claim one decision, so refinement
-- would not be a function. The refiner enforces the same property at run time
-- ('Lips.Kernel.Refine.Overlap'), but only for an overlap some concrete
-- decision witnesses -- and an engine may ship an ambiguity no program in the
-- corpus happens to hit, which then fails on the author's machine instead of
-- here. Rejecting at the mint gate is where the defect is still cheap.
assertRulesOrthogonal :: FilePath -> EngineData -> IO ()
assertRulesOrthogonal file eng =
  case ruleOverlaps (edRules eng) of
    []  -> pure ()
    ovs -> die (validationReport file
      ("two of its rules claim the same decision, so it has no single reading:\n"
        <> T.unlines (map (("  - " <>) . renderRuleOverlap) ovs)))

-- | Deduce-or-fail: every minted rule must fill a real, correctly typed NixOS
-- option. The schema is the pinned nixpkgs @optionsJSON@; its path arrives via
-- @LIPS_OPTIONS_JSON@ (the justfile wires it from the flake). An unset variable
-- or an unreadable schema fails loud -- an unverifiable engine is not written.
-- The check is domain-blind: 'checkEmits' takes a typed schema, and the NixOS
-- specifics live in 'Lips.Nix.Options'.
assertOptionsAdmissible :: Target -> FilePath -> EngineData -> IO ()
assertOptionsAdmissible target file eng = do
  schemaPath <- ensureOptionSchema target ("generate " <> T.pack file)
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  case mbytes of
    Left e -> die (report
      ("lips can't read the NixOS option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run generate again.")
    Right bytes -> case parseNixOptionsJson bytes of
      Left why -> die (report
        ("lips can't parse the NixOS option schema at " <> T.pack schemaPath <> ":")
        [why]
        "→ run generate again.")
      Right schema -> case checkEmits schema (edRules eng) of
        []   -> pure ()
        errs -> die (validationReport file
          ("its rules use NixOS options that don't exist or have the wrong type:\n"
            <> T.unlines (map (("  - " <>) . renderOptionError) errs)))

-- | Locate the NixOS @options.json@ used for the check. An explicit
-- @LIPS_OPTIONS_JSON@ wins (a test seam, or a caller-supplied schema).
-- Otherwise build it lazily from the pinned nixpkgs baked into
-- @LIPS_NIXPKGS_FLAKE@ (set by the packaged binary). The build is announced,
-- since the first one evaluates the whole NixOS manual (~11 MB) before nix
-- caches it; every later generate is a store cache hit. Only generate and the
-- read-only @options@ lookup pay this -- compile\/check never touch the schema.
--
-- @remedy@ is the invocation to suggest when the schema cannot be had; it is a
-- parameter because this function serves two verbs and knows about neither.
ensureOptionSchema :: Target -> Text -> IO FilePath
ensureOptionSchema target remedy = do
  override <- lookupEnv "LIPS_OPTIONS_JSON"
  case override of
    Just p  -> pure p
    Nothing -> do
      -- Each world builds its own optionsJSON from its own pinned flake, baked
      -- into the binary. The file sub-path differs per world; the JSON shape
      -- is identical (both are nixosOptionsDoc output).
      let (envVar, subPath) = case target of
            Nixos       -> ("LIPS_NIXPKGS_FLAKE", "/share/doc/nixos/options.json")
            HomeManager -> ("LIPS_HM_FLAKE",      "/share/doc/home-manager/options.json")
      mflake <- lookupEnv envVar
      case mflake of
        Nothing -> die (report
          ("lips can't read the setup's options: no " <> targetSlug target <> " option schema source is configured.")
          ["neither LIPS_OPTIONS_JSON nor " <> T.pack envVar <> " is set."]
          ("→ run the packaged lips: nix run . -- " <> remedy <> " (it bakes the pinned flakes)."))
        Just flakeref -> do
          TIO.hPutStrLn stderr
            ("checking options against the " <> targetSlug target
              <> " schema: building it from pinned flake (" <> T.pack flakeref <> ").")
          TIO.hPutStrLn stderr
            "  the first build evaluates the manual and can take a few minutes; nix caches it afterwards."
          built <- try (readProcessWithExitCode "nix"
            [ "build", "--impure", "--no-link", "--print-out-paths"
            , "--expr", T.unpack (schemaExpr target flakeref) ] "")
          case built of
            Left e -> die (report
              "lips needs nix to build the option schema, but couldn't run it:"
              (T.lines (tshow (e :: IOException)))
              ("→ install nix, or run lips through it: nix run . -- " <> remedy))
            Right (ExitFailure _, _, err) -> die (report
              ("lips couldn't build the " <> targetSlug target <> " option schema:")
              (T.lines (T.pack err))
              ("→ run it again: nix run . -- " <> remedy))
            Right (ExitSuccess, out, _) ->
              pure (T.unpack (T.strip (T.pack out)) <> T.unpack subPath)

-- | The Nix expression producing the target world's optionsJSON derivation.
-- NixOS: the pinned nixpkgs NixOS manual optionsJSON (the same options.json
-- search.nixos.org is built from). home-manager: the pinned home-manager
-- flake's docs-json. Both are the same optionsJSON shape, so only the
-- derivation differs. Pins via @builtins.getFlake@; @--impure@ covers
-- @builtins.currentSystem@.
schemaExpr :: Target -> String -> Text
schemaExpr Nixos flakeref = T.pack $ concat
  [ "let np = builtins.getFlake \"", flakeref, "\"; in "
  , "(import (np.outPath + \"/nixos\") "
  , "{ configuration = {}; system = builtins.currentSystem; })"
  , ".config.system.build.manual.optionsJSON" ]
schemaExpr HomeManager flakeref = T.pack $ concat
  [ "let hm = builtins.getFlake \"", flakeref, "\"; in "
  , "hm.packages.${builtins.currentSystem}.docs-json" ]

-- | Crystallize and fully run the program with a candidate engine; on success
-- return the crystal and the realized module.
-- The module and the artifact.nix (the buildable derivations, or Nothing) are
-- projected from the same bound rules and ground base, so the artifacts a
-- compiled flake addresses are exactly the ones the module @let@-binds.
validate :: FilePath -> EngineData -> Text -> Either Failure (Base, Text, Maybe (Text, [Text]))
validate file eng program =
  case crystallize file (edPatterns eng) program of
    Left errs  -> Left (FailRead errs)
    Right base ->
      -- Language reuse: the shared grammar names its per-instance attrsOf key by
      -- <self>, bound here to this program's instance name (its file basename).
      -- The merge mode is derived from the rule emits (a subject whose rule
      -- emits a VList rhs appends); the BOUND emits carry the instance name in
      -- place of <self>, so they match the concrete Meta subjects resolve sees.
      let inst       = instanceName file
          boundRules = map (bindSelf inst) (edRules eng)
          modeOf     = mergeModeOf boundRules
          rules      = map toRule boundRules
          demands    = map toDemand (edDemands eng)
      in case runBase modeOf assembleSubject budget rules demands base of
        Left err        -> Left (FailRun err)
        Right nixModule -> case runBaseArtifact modeOf assembleSubject budget rules demands base of
          Left err  -> Left (FailRun err)
          Right art -> Right (base, nixModule, art)

-- | Check the realized module parses as Nix (closes the garbage-rhs hole at
-- mint time). A missing @nix-instantiate@ is a loud failure: an unverifiable
-- engine is not written (deduce-or-fail).
-- | Two outcomes of the Nix parse check, kept apart so the CLI can tell the
-- user to install nix (tool missing) rather than blame the generated setup
-- (invalid Nix).
data NixParse = NixToolMissing Text | NixInvalid Text

nixParses :: Text -> IO (Either NixParse ())
nixParses nixModule = do
  result <- try (readProcessWithExitCode "nix-instantiate" ["--parse", "-"] (T.unpack nixModule))
  pure $ case result of
    Left e -> Left (NixToolMissing (tshow (e :: IOException)))
    Right (ExitSuccess, _, _)   -> Right ()
    Right (ExitFailure _, _, e) -> Left (NixInvalid (T.pack e))

-- | Call pi in json print mode as the model gateway: no tools, no session, a
-- fixed system prompt, the program as the user prompt. pi handles provider
-- auth. lips picks no model by default: when none is given @--model@ is
-- omitted and pi's own configured default applies. Either way the json stream
-- reports the model actually used, which the caller records, so provenance
-- stays concrete without a model baked into the deliverable.
callPi :: Maybe String -> Text -> Text -> Target -> IO (Text, Text)
callPi mmodel system userPrompt target = do
  -- The mint's one tool ships with the binary; without it a mint would have to
  -- recall option names instead of looking them up, which is the guessing this
  -- whole path exists to prevent. So a missing extension is fatal, not a
  -- silent downgrade to a weaker mint.
  -- An EMPTY variable counts as unset: lookupEnv reports Just "" for it, which
  -- would hand pi a bare @-e ""@ and fail somewhere less obvious.
  toolsPath <- lookupEnv "LIPS_MINT_TOOLS"
  extArgs <- case toolsPath of
    Just p | not (null p) -> pure ["-e", p]
    _ -> die (report
      "lips can't run the mint: its tool extension is not installed."
      ["LIPS_MINT_TOOLS is unset."]
      "→ run the packaged lips: nix run . -- generate <program>")
  -- The extension reads the world to search from the environment, and refuses
  -- to load without it: a mint for one world must never be answered from
  -- another world's schema.
  parentEnv <- getEnvironment
  let childEnv = ("LIPS_MINT_TARGET", T.unpack (targetSlug target))
        : filter ((/= "LIPS_MINT_TARGET") . fst) parentEnv
      -- Hermetic by explicit subtraction: -nbt drops pi's built-in tools (read,
      -- bash, edit, write, grep, find, ls -- none of which the mint may touch),
      -- --no-extensions/--no-skills/--no-prompt-templates drop whatever the user
      -- happens to have installed, -nc drops ambient AGENTS.md/CLAUDE.md context
      -- files (global, and walking up from cwd). What remains is the one tool
      -- this run loads on purpose, so the mint's world equals what the record
      -- pins -- no input steers generation without entering genId's hash.
      -- --mode json: so the model pi resolved, and every lookup it made, are
      -- machine-readable in the reply.
      args = [ "-p", "-nbt", "-nc", "--no-extensions", "--no-skills"
             , "--no-prompt-templates", "--no-session", "--mode", "json"
             , "--system-prompt", T.unpack system ]
               ++ extArgs ++ maybe [] (\m -> ["--model", m]) mmodel
  (code, out, err) <-
    readCreateProcessWithExitCode (proc "pi" args) { env = Just childEnv }
      (T.unpack userPrompt)
  case code of
    ExitSuccess   -> do
      let PiReply { prReply = reply, prModel = model } = parsePiReply (T.pack out)
      if T.null reply
        then die (report "the AI model returned no usable reply." [] "→ run generate again.")
        -- pi always reports the model; an empty value would break provenance.
        else if T.null model
          then die (report "pi didn't report which model it used, so lips can't record provenance." [] "→ update pi, then run generate again.")
          else pure (reply, model)
    ExitFailure c -> die (report
      ("lips couldn't run the AI model (pi exited " <> tshow c <> "):")
      (T.lines (T.pack err))
      "→ check that pi is installed and authenticated, then run generate again.")

-- | Evaluate the realized module with @nix@ and judge a contract against it.
-- One eval reads every asserted option; the pure comparison lives in
-- 'Lips.Kernel.Expect'. An empty contract passes trivially.
-- | Three outcomes of the behavioral check, kept apart so the CLI gives the
-- right action: install nix (tool missing), fix the environment (eval failed),
-- or the config doesn't carry the promised values (violations).
data ExpectFail = ToolMissing Text | EvalFailed Text | Violations [Text]

runExpects :: (FilePath -> IO ()) -> [Expect] -> Base -> Text -> IO (Either ExpectFail ())
runExpects _     []      _    _         = pure (Right ())
runExpects stage expects0 base nixModule =
  -- Expand any value-keyed family expect against this program's routes first,
  -- so a shared contract (route.<path>.status) checks every concrete route.
  case expandExpects base expects0 >>= \expects ->
         (,) expects <$> traverse (expectedValue base) expects of
    Left e            -> pure (Left (Violations ["lips can't match a check to the program: " <> e]))
    Right (expects, pvs) -> do
      dir <- mkTempDir
      let tmp = dir <> "/module.nix"
      TIO.writeFile tmp nixModule
      stage (dir <> "/artifacts")
      let expr = evalExpr tmp expects
      res <- try (readProcessWithExitCode "nix"
                    ["eval", "--raw", "--impure", "--expr", T.unpack expr] "")
      pure $ case res of
        Left e -> Left (ToolMissing (tshow (e :: IOException)))
        Right (ExitSuccess, out, _) ->
          let evaled = T.splitOn "\n" (T.pack out)
           in if length evaled /= length expects
                then Left (Violations ["nix returned " <> tshow (length evaled)
                           <> " values for " <> tshow (length expects) <> " checks"])
                else case checkValues expects (zip pvs evaled) of
                       [] -> Right ()
                       fs -> Left (Violations fs)
        Right (ExitFailure _, _, err) -> Left (EvalFailed (T.pack err))

die :: Text -> IO a
die msg = TIO.hPutStrLn stderr msg >> exitFailure

-- | A fresh temporary directory. lips writes a module and its staged
-- @artifacts/@ tree here so a relative @src = ./artifacts/<name>@ resolves at
-- evaluation. (Left in place, matching the module temp files elsewhere.)
mkTempDir :: IO FilePath
mkTempDir = do
  (_, out, _) <- readProcessWithExitCode "mktemp" ["-d", "/tmp/lips-XXXXXX"] ""
  pure (T.unpack (T.strip (T.pack out)))

-- | Write minted source files under @<root>/<artifact>/<relpath>@. Used to
-- persist to the language folder's @artifacts/@ and to stage into a temp
-- module dir.
writeSources :: FilePath -> [SourceFile] -> IO ()
writeSources root = mapM_ one
  where
    one sf = do
      let p = root <> "/" <> T.unpack (sfArtifact sf) <> "/" <> T.unpack (sfPath sf)
      callCommand ("mkdir -p " <> shq (parentDir p))
      TIO.writeFile p (sfContent sf)

-- | Stage a language's committed @artifacts@ tree (found under @dir@) into
-- @dst@ (the temp module's @artifacts/@). A no-op when the program has no
-- artifacts.
stageFromDisk :: FilePath -> FilePath -> FilePath -> IO ()
stageFromDisk dir file dst = do
  _ <- (try (readProcessWithExitCode "cp" ["-rT", artifactsPathIn dir file, dst] "")
          :: IO (Either IOException (ExitCode, String, String)))
  pure ()

-- | The directory part of a path (everything up to and including the last @/@).
parentDir :: FilePath -> FilePath
parentDir = T.unpack . fst . T.breakOnEnd "/" . T.pack

-- | Minimal single-quote shell escaping for a path passed to @mkdir -p@.
shq :: FilePath -> String
shq s = "'" <> concatMap (\c -> if c == '\'' then "'\\''" else [c]) s <> "'"

-- | The standard message skeleton: a plain headline, optional indented detail
-- lines, and a final "→" action. Every error the CLI prints is built from it,
-- so the product speaks with one voice.
report :: Text -> [Text] -> Text -> Text
report headline details action =
  T.intercalate "\n" $ [headline] ++ detail ++ ["", action]
  where detail = if null details then [] else "" : map ("  " <>) details

-- | Same skeleton without the action line, for a diagnosis another command
-- wraps with its own action.
reportHead :: Text -> [Text] -> Text
reportHead headline details =
  T.intercalate "\n" $ [headline] ++ (if null details then [] else "" : map ("  " <>) details)

-- | A validation failure kept structured (not pre-rendered) so each command
-- picks the right next action: on print/run some are the author's to edit,
-- others mean regenerate; generate frames all of them as a mint that did not
-- hold up.
data Failure = FailRead [CrystError] | FailRun RunError

-- | What went wrong and where, in plain words, with no action line (the caller
-- appends the action, which depends on the command).
failureReport :: FilePath -> Failure -> Text
failureReport file (FailRead errs) =
  reportHead (T.pack file <> " has lines its setup doesn't handle:") (map crystDetail errs)
  where
    crystDetail (NoPattern n t)   = "line " <> tshow n <> ": " <> t
    crystDetail (Overlapping n _) = "line " <> tshow n <> ": the setup reads this line more than one way"
failureReport file (FailRun err) = case err of
  ParseRejected es ->
    reportHead (T.pack file <> " has lines that couldn't be read:")
               [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  OpenQuestions qs ->
    reportHead (T.pack file <> " leaves questions its setup needs answered:") qs
  Conflicted cs ->
    reportHead (T.pack file <> " sets the same thing two ways:")
               [ niceSubject (conflictSubject c) <> ": "
                   <> loc (conflictLeft c) <> " and " <> loc (conflictRight c) | c <- cs ]
  RefineFailed e ->
    reportHead ("the setup lips built for " <> T.pack file <> " is broken, not your program:")
               [refineDetail e]
  Unmapped ds ->
    reportHead (T.pack file <> " asks for things its setup can't do:")
               [ loc d <> ": " <> niceSubject (dSubject d) | d <- ds ]
  Unrealizable rs ->
    reportHead ("the setup lips built for " <> T.pack file <> " can't be turned into a module:") rs

-- | The full message for a print/run failure: the diagnosis plus the action
-- that fits it -- edit the program (unanswered questions, a contradiction) or
-- rebuild the setup (everything else).
printFail :: FilePath -> Failure -> Text
printFail file f = failureReport file f <> "\n\n" <> act
  where
    act = case f of
      FailRun (OpenQuestions _) -> "→ answer each in " <> T.pack file <> ", then run again."
      FailRun (Conflicted _)    -> "→ keep only one of those lines in " <> T.pack file <> ", then run again."
      _                         -> "→ rebuild the setup: lips generate " <> T.pack file

refineDetail :: RefineError -> Text
refineDetail (Overlap _ _)         = "two of its rules claim the same thing"
refineDetail (Nonterminating _)    = "its rules loop without settling"
refineDetail (RewriteFailed _ _ m) = m

-- | A subject as plain words: its dotted segments spaced out, so route./hello
-- reads as "route /hello".
niceSubject :: Subject -> Text
niceSubject (Subject segs) = T.intercalate " " segs

-- | Where a decision came from, in author terms: a file location, or a note
-- that the setup computed it.
loc :: Decision -> Text
loc d = case dProv d of
  FromSource (SourceLoc f n) -> f <> ":" <> tshow n
  Derived _ _                -> "(computed by the setup)"
  FromGeneration _           -> "(from the setup)"

-- | A committed file lips can't read back (corrupted or hand-edited).
unreadable :: FilePath -> Text -> [ParseError] -> Text
unreadable file suffix es = report
  (T.pack file <> suffix <> " is unreadable, so lips can't use it:")
  [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
  ("→ rebuild it: lips generate " <> T.pack file)

-- | nix is needed but couldn't run: a missing-tool failure (install it), never
-- the fault of the program or the generated setup.
nixMissing :: FilePath -> Text -> Text -> Text -> Text
nixMissing file what cmd detail = report
  ("lips needs nix to " <> what <> ", but couldn't run it:")
  (T.lines detail)
  ("→ install nix, or run lips through it: nix run . -- " <> cmd <> " " <> T.pack file)

-- | nix ran but evaluation failed: usually a missing nixpkgs, not the setup.
nixEvalFailed :: FilePath -> Text -> Text -> Text
nixEvalFailed file cmd detail = report
  "lips couldn't evaluate the configuration to check it:"
  (T.lines detail)
  ("→ this usually means nixpkgs isn't available. Try: nix run . -- " <> cmd <> " " <> T.pack file)

-- | generate couldn't build a setup: either lines lips couldn't read (a
-- capability may be missing) or values the program leaves underspecified.
refusalReport :: FilePath -> Double -> [Text] -> [ItemCandidate] -> [(Text, Text)] -> [Gap] -> Text
refusalReport file _threshold errs unsure notes gaps = T.intercalate "\n" $
  ["lips couldn't build a setup for " <> T.pack file <> "."]
    ++ grammar ++ underspecified ++ missing
  where
    -- A dead mint that names the capability it lacked yields a work item
    -- rather than a shrug: the gap is a kernel bug in the model's own words.
    missing
      | null gaps = []
      | otherwise =
          [ "", "The mint says lips is missing a capability here:" ]
          ++ concat [ ("  - " <> gapSlug g)
                        : [ "      " <> l | l <- T.lines (T.strip (gapBody g)) ]
                    | g <- gaps ]
          ++ [ ""
             , "→ this is a lips bug, not your program. Please report the text above." ]
    grammar
      | null errs = []
      | otherwise =
          [ "", "The AI wrote something lips can't express yet:" ]
          ++ [ "  - " <> e | e <- errs ]
          ++ [ ""
             , "→ if the same item (above) fails every time you run generate,"
             , "  lips is missing a capability it needs here; please report that"
             , "  line. If the failing item changes or it is one-off, run generate"
             , "  again and the model may phrase it differently." ]
    underspecified
      | null unsure = []
      | otherwise =
          [ "", "The program doesn't pin these down (the AI wasn't confident enough):" ]
          ++ concat [ [ "  - " <> icLine c <> "   [confidence " <> conf c <> "]" ]
                       ++ maybe [] (\r -> [ "      why: " <> r ]) (lookup (icId c) notes)
                    | c <- unsure ]
          ++ [ ""
             , "→ state the missing detail in " <> T.pack file <> " and run again."
             , "  If the choice is genuinely free, lower the bar: --confidence " <> suggestedBar ]
    conf c = let Confidence x = icConfidence c in tshow x
    -- Suggest the lowest dropped confidence itself: the filter keeps items with
    -- confidence >= threshold, so this bar admits every currently-unsure item
    -- (and no lower). A constant hint could repeat the value the user just used.
    suggestedBar = tshow (minimum [x | c <- unsure, let Confidence x = icConfidence c])

-- | A behavioral check names an option a rule fills with a package or artifact
-- reference (a derivation, not a program value). Such a check can neither be
-- evaluated under the check's stubs nor meaningfully satisfied, so it is
-- rejected loud instead of crashing the eval (deduce-or-fail).
uncheckableReport :: FilePath -> [Expect] -> Text
uncheckableReport file bad = report
  (T.pack file <> " checks options that hold a package or build, not a plain value:")
  [ T.intercalate "." (exPath e) <> " (check " <> exId e <> ")" | e <- bad ]
  ("→ a check must name an option that holds a value from " <> T.pack file
    <> ", not a package or build. Rebuild the setup: lips generate " <> T.pack file)

-- | A demand the minted engine leaves unmet at generate. Ambiguous by
-- construction (the kernel cannot tell a silent program from patterns that
-- misread a stated value), so it names BOTH remedies and lets the author, who
-- alone knows which, choose. Both paths re-enter generate: a value you add
-- still needs a fresh mint to grow a pattern that reads it.
demandGenerateFail :: FilePath -> [Text] -> Text
demandGenerateFail file qs = T.intercalate "\n" $
  [ T.pack file <> ": lips built a setup but left these unanswered:" , "" ]
    ++ [ "  " <> q | q <- qs ]
    ++ [ ""
       , "Either your program does not state these, or the setup lips built"
       , "misread them; for example, if a value is already there (\"on port 8080\"),"
       , "the setup read it wrong."
       , ""
       , "\x2192 run generate again. If the same facts keep coming up unanswered,"
       , "  state them in " <> T.pack file <> " or report it as a lips bug." ]

-- | generate built a setup but it did not hold up: wrap a diagnosis with the
-- generate-time action (mint again; report a lips bug if it persists). Not the
-- program's fault.
validationReport :: FilePath -> Text -> Text
validationReport file problem = T.intercalate "\n"
  [ "lips built a setup for " <> T.pack file <> ", but it didn't hold up:"
  , ""
  , problem
  , ""
  , "→ run generate again. If it keeps failing the same way, it's a lips bug;"
  , "  please report it with the text above."
  ]

renderParseError :: ParseError -> Text
renderParseError e = "  line " <> tshow (peLine e) <> ": " <> peMessage e

tshow :: Show a => a -> Text
tshow = T.pack . show

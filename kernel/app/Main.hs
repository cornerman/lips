{-# LANGUAGE OverloadedStrings #-}

-- | The @lips@ CLI (crystallization plan).
--
--   * @lips generate [model] \<program\>@ is the one AI step: the model mints a
--     /language/ (patterns) for the loose program; the kernel crystallizes the
--     program with it and validates by a full run; only then are the language
--     (@\<program\>.lang@), the crystal witness (@\<program\>.decisions@), and
--     the generation record written.
--   * @lips compile \<program\>@ takes the loose program directly. It
--     crystallizes it with @\<program\>.lang@ and realizes it into a DIRECTORY
--     (@default.nix@ plus a staged @artifacts/@), deterministically, with no
--     AI. If the language is missing, or the program escaped it, it fails loud
--     and names @generate@.
--   * @lips run \<program\>@ goes one step further and literally runs the
--     realized module: it wraps it in a NixOS system and boots it as a local
--     QEMU VM (a Heile-Welt simulation of the target machine; the host is
--     never mutated). Host deployment stays a separate, explicit step.
module Main (main) where

import           Control.Exception  (IOException, try)
import           Control.Monad      (forM, forM_)
import qualified Data.ByteString.Lazy as BL
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getArgs, lookupEnv)
import           System.Exit        (ExitCode (..), exitFailure)
import           System.IO          (hFlush, stderr, stdout)
import           System.FilePath    (dropExtension, takeFileName, (</>))
import           System.Process     (callCommand, readProcessWithExitCode)

import           Lips.Kernel.Engine.Aggregate   (assembleSubject, mergeModeOf)
import           Lips.Kernel.Engine.Data       (bindSelf, toDemand, toRule)
import           Lips.Identity                 (artifactsPath, decisionsPath, directionPath, expectPath, generationPath, instanceName, langPath, languageName)
import           Lips.Generate.Args     (parseGenerate)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Minting  (EngineItem (..), ItemCandidate (..), SourceFile (..), assemble, expectsOf, parseEngineCandidates, promptWithDirection, sourcesOf, uncheckableExpects)
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
import           Lips.Kernel.OptionType        (checkEmits, renderOptionError)
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
  args <- getArgs
  case args of
    ["compile", file]                -> compileLoose Nothing file
    ["compile", "--out", dir, file]  -> compileLoose (Just dir) file
    ["run", file]                -> runProgram file
    ["check", file]              -> checkLoose file
    ["lsp"]              -> runLsp
    ("generate" : rest)  -> case parseGenerate defaultConfidence rest of
      Just (target, conf, renew, mmodel, fs) -> generate target conf renew mmodel fs
      Nothing                         -> usage >> exitFailure
    _                    -> usage >> exitFailure

-- | Parse @generate@ arguments: optional @--confidence <0..1>@ and
-- @--model <id>@ flags in any position, then @[model] <program-file>...@ --
-- one or more programs (all of one language, checked later). A malformed
-- threshold, a duplicate model, or no program fails loud (returns Nothing).
usage :: IO ()
usage = do
  -- The tool's name is fixed. getProgName would leak the Nix wrapper's real
  -- target (.lips-unwrapped), so name it directly.
  let name = "lips" :: Text
  TIO.hPutStr stderr $ T.unlines
    [ "lips turns a plain-English <instance>.<language> program into a NixOS configuration."
    , ""
    , "usage:"
    , "  " <> name <> " generate [--target nixos|home-manager] [--confidence <0..1>] [--renew] [--model <id>|model] <program>..."
    , "      Mint the language from one or more example programs and verify each."
    , "      The one step that uses AI."
    , "  " <> name <> " compile [--out <dir>] <program>"
    , "      Realize into a directory (default.nix + artifacts/) for import."
    , "  " <> name <> " run <program>"
    , "      Boot as a local VM (nixos) or realize and check (home-manager)."
    , "  " <> name <> " check <program>"
    , "      Verify the program still produces what it promised."
    ]

-- | @compile@: crystallize + realize, then materialize a DIRECTORY -- default
-- @<program without .lips>/@, or @--out <dir>@ -- holding @default.nix@ plus a
-- staged @artifacts/@ tree. A directory, not stdout, so an engine with
-- artifacts is complete and @imports = [ ./<dir> ]@ resolves default.nix. The
-- output is derived, never committed (gitignore it, like .decisions).
compileLoose :: Maybe FilePath -> FilePath -> IO ()
compileLoose mout file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left f            -> die (printFail file f)
    Right (_, nixMod) -> do
      let outDir = maybe (dropExtension file) id mout
      callCommand ("mkdir -p " <> shq outDir)
      TIO.writeFile (outDir </> "default.nix") nixMod
      stageFromDisk file (outDir </> "artifacts")
      TIO.hPutStrLn stderr
        ("compiled " <> T.pack file <> " -> " <> T.pack (outDir </> "default.nix"))

-- | @run@: realize the program, then run it in the world it was minted for.
-- The world is fixed at mint time and read from the engine's committed
-- @.generation@ record; run never overrides it, since a program is only
-- verified against the world it was generated for. nixos boots a QEMU VM;
-- home-manager has no machine, so it is eval-only.
runProgram :: FilePath -> IO ()
runProgram file = do
  target <- readRecordedTarget file
  case target of
    Nixos       -> runVm file
    HomeManager -> runEvalOnly file

-- | The world an engine was minted for, read from its committed .generation
-- record (the @target:@ line). An engine minted before targets existed has no
-- such line and defaults to nixos, so old engines keep working.
readRecordedTarget :: FilePath -> IO Target
readRecordedTarget file = do
  m <- tryRead (generationPath file)
  pure $ case m of
    Nothing  -> defaultTarget
    Just src -> case [ t | l <- T.lines src
                         , Just rest <- [T.stripPrefix "target:" l]
                         , Just t <- [parseTarget (T.unpack (T.strip rest))] ] of
      (t : _) -> t
      []      -> defaultTarget

-- | home-manager run: no VM to boot for a per-user environment. Run the
-- committed world-blind @.expect@ gate so the values are witnessed. Stays
-- hermetic (no home-manager eval); a booted-cluster-style check is deferred.
runEvalOnly :: FilePath -> IO ()
runEvalOnly file = do
  TIO.hPutStrLn stderr
    "home-manager module: no VM to boot; checking its contract (use compile to materialize it)."
  checkLoose file

-- | @runVm@: verify the program's committed contract, then wrap the module in a
-- NixOS system and boot it as a local QEMU VM. The behavioral gate runs FIRST
-- (the same one @check@ runs), so @run@ never boots a module that no longer
-- carries the values its program promises: an offline edit that breaks a
-- pinned relation fails loud here instead of booting a silently-wrong system.
-- home-manager @run@ (@runEvalOnly@) already gates this way, so both worlds are
-- symmetric. Only the booting is impure (it uses the ambient @<nixpkgs>@, a
-- Heile-Welt softness noted in the design). The host is never touched; the VM
-- is a throwaway simulation.
runVm :: FilePath -> IO ()
runVm file = do
  -- Gate before boot: checkLoose prints the diagnosis and the .expect result
  -- and dies on any failure (unread line, open question, contract violation),
  -- so reaching past it means the contract holds and the module is safe to run.
  checkLoose file
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left f            -> die (printFail file f)
    Right (_, nixMod) -> bootVm file (stageFromDisk file) nixMod

bootVm :: FilePath -> (FilePath -> IO ()) -> Text -> IO ()
bootVm file stage nixMod = do
  dir <- mkTempDir
  let tmp = dir <> "/module.nix"
  TIO.writeFile tmp nixMod
  stage (dir <> "/artifacts")
  TIO.hPutStrLn stderr "building a local NixOS VM from your configuration..."
  built <- try (readProcessWithExitCode "nix"
                  [ "build", "--impure", "--no-link", "--print-out-paths"
                  , "--expr", T.unpack (vmExpr tmp) ] "")
  case built of
    Left e -> die (nixMissing file "boot the VM" "run" (tshow (e :: IOException)))
    Right (ExitFailure _, _, err) ->
      die (report
        "the VM didn't build:"
        (T.lines (T.pack err))
        ("→ the run simulation needs nixpkgs. Try: nix run . -- run " <> T.pack file
          <> ", or set NIX_PATH to a nixpkgs."))
    Right (ExitSuccess, out, _) -> do
      let outPath = T.unpack (T.strip (T.pack out))
      TIO.hPutStrLn stderr "booting the VM (quit QEMU with Ctrl-a x)..."
      -- The qemu-vm module names the boot script run-<host>-vm; glob it so the
      -- hostname is not hard-coded. The shell inherits stdio for the console.
      callCommand (outPath <> "/bin/run-*-vm")

-- | An impure Nix expression that turns a realized module (at @modPath@) into a
-- bootable, headless local VM via the stock qemu-vm module.
vmExpr :: FilePath -> Text
vmExpr modPath = T.pack $ unlines
  [ "let"
  , "  system = builtins.currentSystem;"
  , "  nixpkgs = <nixpkgs>;"
  , "  cfg = import (nixpkgs + \"/nixos/lib/eval-config.nix\") {"
  , "    inherit system;"
  , "    modules = ["
  , "      (nixpkgs + \"/nixos/modules/virtualisation/qemu-vm.nix\")"
  , "      " <> modPath
  , "      { system.stateVersion = \"24.11\";"
  , "        virtualisation.graphics = false;"
  , "        users.users.root.password = \"\"; }"
  , "    ];"
  , "  };"
  , "in cfg.config.system.build.vm"
  ]

-- | @check@: verify the program's committed behavioral contract holds against
-- its realized module, deterministically (no AI). This is the offline guardian
-- of the @.expect@ spec; @generate@ runs the same check before accepting an
-- engine, and the flake check shells this per example.
checkLoose :: FilePath -> IO ()
checkLoose file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
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
      else expectGate file eng program
  where
    escapes Matched{} = False
    escapes _         = True

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
expectGate :: FilePath -> EngineData -> Text -> IO ()
expectGate file eng program = do
  expSrc <- tryRead (expectPath file)
  case expSrc of
    Nothing  -> TIO.putStrLn
      (T.pack file <> ": crystallizes cleanly; no behavioral contract yet ("
        <> T.pack (expectPath file) <> " is missing, written by generate).")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        | otherwise -> case validate file eng program of
        Left f       -> die (printFail file f)
        Right (base, nixMod) -> do
          -- Bind <self> in the contract's option paths to this instance, so it
          -- checks against the realized (already-bound) module.
          res <- runExpects (stageFromDisk file) (map (bindSelfExpect (instanceName file)) expects) base nixMod
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

-- | Load and parse a program's @.lang@, or fail loud naming @generate@.
loadLangOrDie :: FilePath -> IO EngineData
loadLangOrDie file = do
  let langFile = langPath file
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
generate :: Target -> Double -> Bool -> Maybe String -> [FilePath] -> IO ()
generate _ _ _ _ [] = usage >> exitFailure
generate target confidence renew mmodel files@(rep : _) = do
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
  (reply, model) <- callPi mmodel prompt corpus
  let (errs, candidates) = parseEngineCandidates reply
      -- A because-note explains a low-confidence item; keyed by shared id, it
      -- never gates the build and never enters the engine.
      notes = [(icId c, r) | c <- candidates, ItemNote r <- [icItem c]]
      -- Deduce-or-fail: the programs are the only source of truth, so an item
      -- the model cannot confidently derive means they underspecify it.
      unsure = [c | c <- candidates, notNote (icItem c)
                  , let Confidence x = icConfidence c, x < confidence]
      notNote i = case i of { ItemNote _ -> False; _ -> True }
  if not (null errs) || not (null unsure)
    then die (refusalReport rep confidence errs unsure notes)
    else do
      let eng0 = assemble (map icItem candidates)
      -- Validate the engine EXACTLY as it will be persisted: render to .lang and
      -- read it back, so any render/read round-trip drift is caught at mint
      -- time, not on a later `print`. The read-back engine is what we write.
      eng <- case readLang (renderLang (FromSource (SourceLoc "lang" 0)) eng0) of
        Left es -> die (validationReport rep ("the setup can't be saved and reloaded cleanly:\n" <> T.unlines (map renderParseError es)))
        Right e -> pure e
      assertOptionsAdmissible target rep eng
      -- Every program must crystallize, run, and parse as Nix under the shared
      -- engine: the example set is the regeneration corpus.
      validated <- forM progs $ \(f, t) -> case validate f eng t of
        -- An unmet demand at generate is ambiguous by construction (the kernel
        -- is domain-blind): name both remedies rather than blame one side.
        Left (FailRun (OpenQuestions qs)) -> die (demandGenerateFail f qs)
        Left ff -> die (validationReport f (failureReport f ff))
        Right (base, nixModule) -> do
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
      TIO.writeFile (langPath rep) (renderLang (FromGeneration (genId rec)) eng)
      TIO.writeFile (generationPath rep) rec
      writeSources (artifactsPath rep) minted
      forM_ validated $ \(f, base, _) -> TIO.writeFile (decisionsPath f) (renderBase base)
      -- Bootstrap the contract on first generation only; keep the committed
      -- spec stable across regenerations.
      maybe (TIO.writeFile (expectPath rep) (renderExpect mintedExpects))
            (const (pure ())) committed
      -- Prose to stderr so stdout stays a pipeable module (the first program's).
      TIO.hPutStr stderr $ T.unlines $
        [ "lips set up ." <> T.pack lang <> " from " <> tshow (length files)
            <> " program(s) and verified each produces a valid NixOS configuration."
        , "" ]
        ++ [ "→ preview:  lips compile " <> T.pack f | (f, _, _) <- validated ]
      case [ m | (f, _, m) <- validated, f == rep ] of
        (m : _) -> TIO.putStr m
        []      -> pure ()

-- | Deduce-or-fail: every minted rule must fill a real, correctly typed NixOS
-- option. The schema is the pinned nixpkgs @optionsJSON@; its path arrives via
-- @LIPS_OPTIONS_JSON@ (the justfile wires it from the flake). An unset variable
-- or an unreadable schema fails loud -- an unverifiable engine is not written.
-- The check is domain-blind: 'checkEmits' takes a typed schema, and the NixOS
-- specifics live in 'Lips.Nix.Options'.
assertOptionsAdmissible :: Target -> FilePath -> EngineData -> IO ()
assertOptionsAdmissible target file eng = do
  schemaPath <- ensureOptionSchema target file
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  case mbytes of
    Left e -> die (report
      ("lips can't read the NixOS option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "\226\134\146 run generate again.")
    Right bytes -> case parseNixOptionsJson bytes of
      Left why -> die (report
        ("lips can't parse the NixOS option schema at " <> T.pack schemaPath <> ":")
        [why]
        "\226\134\146 run generate again.")
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
-- caches it; every later generate is a store cache hit. Only generate pays
-- this -- print\/run\/check never touch the schema.
ensureOptionSchema :: Target -> FilePath -> IO FilePath
ensureOptionSchema target file = do
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
          ("lips can't check the setup's options: no " <> targetSlug target <> " option schema source is configured.")
          ["neither LIPS_OPTIONS_JSON nor " <> T.pack envVar <> " is set."]
          "\226\134\146 run the packaged lips: nix run . -- generate <program> (it bakes the pinned flakes).")
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
            Left e -> die (nixMissing file "build the option schema" "generate" (tshow (e :: IOException)))
            Right (ExitFailure _, _, err) -> die (validationReport file
              ("lips couldn't build the " <> targetSlug target <> " option schema:\n" <> T.pack err))
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
validate :: FilePath -> EngineData -> Text -> Either Failure (Base, Text)
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
      in case runBase modeOf assembleSubject budget
                  (map toRule boundRules) (map toDemand (edDemands eng)) base of
        Left err        -> Left (FailRun err)
        Right nixModule -> Right (base, nixModule)

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
callPi :: Maybe String -> Text -> Text -> IO (Text, Text)
callPi mmodel system userPrompt = do
  (code, out, err) <-
    readProcessWithExitCode "pi"
      -- -nc: the mint must be hermetic. pi otherwise injects ambient AGENTS.md/CLAUDE.md
      -- context files (global + walking up from cwd) - inputs that would steer generation
      -- without entering the .generation record or the genId hash.
      -- --mode json: so the model pi resolved is machine-readable in the reply.
      ([ "-p", "-nt", "-nc", "--no-session", "--mode", "json", "--system-prompt", T.unpack system ]
        ++ maybe [] (\m -> ["--model", m]) mmodel)
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
-- persist to @<program>.artifacts@ and to stage into a temp module dir.
writeSources :: FilePath -> [SourceFile] -> IO ()
writeSources root = mapM_ one
  where
    one sf = do
      let p = root <> "/" <> T.unpack (sfArtifact sf) <> "/" <> T.unpack (sfPath sf)
      callCommand ("mkdir -p " <> shq (parentDir p))
      TIO.writeFile p (sfContent sf)

-- | Stage a program's committed @<file>.artifacts@ tree into @dst@ (the temp
-- module's @artifacts/@). A no-op when the program has no artifacts.
stageFromDisk :: FilePath -> FilePath -> IO ()
stageFromDisk file dst = do
  _ <- (try (readProcessWithExitCode "cp" ["-rT", artifactsPath file, dst] "")
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
refusalReport :: FilePath -> Double -> [Text] -> [ItemCandidate] -> [(Text, Text)] -> Text
refusalReport file _threshold errs unsure notes = T.intercalate "\n" $
  ["lips couldn't build a setup for " <> T.pack file <> "."]
    ++ grammar ++ underspecified
  where
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

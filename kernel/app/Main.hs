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

import           Control.Concurrent (forkIO)
import           Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import           Control.Exception  (IOException, finally, try)
import           Control.Monad      (forM, forM_, unless, when, void)
import           Data.IORef         (IORef, newIORef, modifyIORef', readIORef, writeIORef)
import           Data.Bifunctor     (first)
import           Data.List          (intercalate, tails)
import           Data.Maybe         (fromMaybe)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getEnvironment, lookupEnv)
import           System.Exit        (ExitCode (..), exitWith)
import           GHC.IO.Encoding     (setLocaleEncoding)
import           System.IO          (BufferMode (..), hClose, hGetContents,
                                     hIsEOF, hSetBuffering, hSetEncoding, stderr, stdout, utf8)
import           System.Directory   (createDirectoryIfMissing, doesFileExist,
                                     doesPathExist, listDirectory, removePathForcibly)
import           System.FilePath    (dropExtension, takeDirectory, takeExtension, (</>))
import           System.Process     (CreateProcess (..), StdStream (..), createProcess, proc,
                                     readProcessWithExitCode, waitForProcess)

import           Lips.Kernel.Engine.Aggregate   (assembleWith, mergeModeOf)
import           Lips.Kernel.Engine.Data       (bindSelf, keepsRepeats, renderAttrPath, toDemand, toRule)
import           Lips.Generate.Readme   (renderReadme)
import           Lips.Identity                 (requireProgram, readmePathIn, gapPathIn, artifactsPath, artifactsPathIn, compiledPath, decisionsPath, directionPath, expectPathIn, generationPathIn, grammarPathIn, instanceName, langDir, languageName, outDir, resolveLangDir, rulesPathIn, worldDirIn, worldPathIn)
import           Lips.Language                 (grammarIsFrozen, mintedWorlds)
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), CheckOpts (..), OptionsOpts (..), cliParserInfo)
import           Lips.Cli.Output        (die, note, report, say, sayAnswer, setState, step, tshow)
import           Lips.Gate              (ExpectFail (..), artifactGate, artifactNixpkgs, claimGate,
                                        clauseClaimGate, mintClaimGate, runExpects, sourceSpecGate,
                                        stagedGate)
import           Lips.Stage             (fillStagedTree, siteNameOf, stageBeside, stageFromDisk,
                                         stagedSizes, withTempDir, writeSite, writeSources)
import           Lips.Schema            (assertOptionsAdmissible, ensureOptionSchema,
                                         optionsQuery)
import           Lips.Report            (Failure (..), demandGenerateFail, failureReport,
                                         gapArtifact, nixEvalFailed, nixMissing, plural,
                                         printFail, refusalReport, renderDiagnosis,
                                         renderParseError, unanswerableReport,
                                         uncheckableReport, unportableReport, unreadable, validationReport)
import           Options.Applicative    (execParser)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Draft    (DraftTree (..), materializeDraft, splitEngine)
import           Lips.Generate.Minting  (EngineItem (..), Gap (..), ItemCandidate (..), SourceFile (..), appendOnlyViolations, assemble, carriesEngineMeaning, mergeGrammar, expectsOf, gapsOf, parseEngineCandidates, promptWithDirection, reportOf, sourcesOf, uncheckableExpects, claimlessBakedSource, unplaceableClaims, unnamedSources)
import           Lips.Generate.PiJson   (PiEvent (..), PiReply (..), abbreviate, parsePiReply,
                                         progressEvent, resultSummary)
import           Lips.Generate.Record   (corpusText, genId, record,
                                         recordedSchema, recordedWorld, renderStampFault, stampFaults, worldHash)
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect     (Compat (..), Expect (..), bindSelfExpect, compatSlug, readExpect, rebless, renderExpect, smallestCompat)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Run
import           Lips.Kernel.Grounding  (groundingReport)
import           Lips.Runtime            (schemeVocabulary)
import           Lips.Kernel.Lang.Crystallize  (LineOutcome (..), crystallize)

import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..), diagnose)
import           Lips.Kernel.Lang.Store         (EngineData (..), readLang, renderLang)
import           Lips.Kernel.Engine.Answerable (unanswerableDemands)
import           Lips.Kernel.Engine.Gate       (engineViolations)
import           Lips.Nix.Claims               (claimsFile)
import           Lips.Nix.Flake                (Rungs (..), SiteRung (..), flakeText,
                                                runCommands)
import           Lips.World                     (World (..), parseWorld)
import           Lips.World.Builtin             (builtinWorld)
import           Lips.World.Resolve            (builtinNames, resolveWorld)
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
  -- Both streams line-buffered, so what lips says arrives in the order it said
  -- it. Redirected to a file or a pipe, GHC would buffer stdout in blocks and
  -- a progress line on stderr would land in the middle of an answer on stdout
  -- (observed: a diagnosis table cut a verdict line in half).
  mapM_ (`hSetBuffering` LineBuffering) [stdout, stderr]
  -- Every FILE lips reads is UTF-8 too, and a committed record legitimately
  -- carries non-ASCII (a .generation embeds the mint prompt, em dashes and all).
  -- Without this the encoding of a READ follows the ambient locale, so the same
  -- committed engine decodes under LANG=C.UTF-8 and throws under LANG unset --
  -- which is exactly the environment a nix build runs in. That failure was
  -- silent where a reader treats "unreadable" as "absent", and it compiled a
  -- kubenix program into a NixOS flake. Pin it once, here.
  setLocaleEncoding utf8
  cmd <- execParser (cliParserInfo defaultConfidence)
  case cmd of
    Generate go -> do
      -- Every world is resolved before anything else runs: a name that names
      -- nothing must cost no model call and write no file, and that has to hold
      -- for the LAST name in the list as much as the first. Beside the FIRST
      -- program, which is the one whose language folder the mint writes; the
      -- CLI parser guarantees there is one.
      let base = case goFiles go of
                   (f : _) -> takeDirectory f
                   []      -> "."
      worlds <- mapM (resolveWorldOrDie base (goWorlds go)) (goTarget go)
      -- One model call per world, left to right. Sequential rather than
      -- combined because a world's preamble is absolute prose about the one
      -- namespace to emit into: concatenating four of them contradicts itself.
      -- Each world is paired with the worlds still upcoming, ITSELF INCLUDED:
      -- a world being minted right now does not inherit its own committed
      -- grammar, or a re-mint could never change a pattern.
      forM_ (zip worlds (tails (goTarget go))) $ \(world, upcoming) -> do
        inherited <- inheritedGrammar upcoming (goFiles go)
        generate world inherited (goSchema go) (goConfidence go) (goCompat go) (goVerbose go) (goModel go) (goThinking go) (goFiles go)
    Compile co  -> compileLoose (coOut co) (coLangDir co) (coNoContract co) (coFile co)
    Check co
      | ceDraft co -> checkDraft (ceFile co)
      | otherwise  -> checkLoose True True (ceLangDir co) (ceFile co)
                        >>= exitUnlessEveryWorldHeld (ceFile co)
    Options oo  -> do
      -- A lookup has no program, so a house world is resolved against the
      -- directory the human stands in (or --worlds).
      world <- resolveWorldOrDie "." (ooWorlds oo) (ooTarget oo)
      optionsQuery world (ooSchema oo) (ooLimit oo) (T.pack (ooQuery oo))
    WorldCmd dir mname -> worldVerb dir mname
    Lsp         -> runLsp

-- | The committed grammar a mint must REUSE, or 'Nothing' when it is free to
-- write its own ('Lips.Language.grammarIsFrozen' decides which). Read fresh
-- before each world of a run, so world two inherits what world one just wrote.
-- @upcoming@ is the worlds still to be minted, this one included.
inheritedGrammar :: [Text] -> [FilePath] -> IO (Maybe Text)
inheritedGrammar _ []                = pure Nothing
inheritedGrammar upcoming (rep : _)  = do
  let dir = langDir rep
  committed <- mintedWorlds dir rep
  if grammarIsFrozen committed upcoming then tryRead (grammarPathIn dir rep)
                                        else pure Nothing

-- | Resolve a world name or die naming the remedy. The one door: every verb
-- that takes @--target@ comes through here, so a name means the same thing
-- everywhere.
resolveWorldOrDie :: FilePath -> Maybe FilePath -> Text -> IO World
resolveWorldOrDie base override name = do
  r <- resolveWorld base override name
  case r of
    Right w  -> pure w
    Left why -> die (report ("lips can't use the world " <> name <> ":") [why]
                       "\8594 name a world lips ships (lips world), or write one beside the program.")

-- | @world@: print the world a name resolves to, or list every world reachable
-- from here. The listing marks which are local, because that is the difference
-- a reader acts on: a local file is theirs to edit, a shipped one is not.
worldVerb :: Maybe FilePath -> Maybe Text -> IO ()
worldVerb dir (Just name) = do
  w <- resolveWorldOrDie "." dir name
  -- On stdout, undecorated: this is what a human redirects into a file to
  -- start a house world, and what the migration one-off writes beside an engine.
  sayAnswer (wRaw w)
worldVerb dir Nothing = do
  let here = fromMaybe "." dir
  entries <- listDirectory here
  let locals = [ T.pack (dropExtension f) | f <- entries, takeExtension f == ".world" ]
  sayAnswer (T.unlines
    ([ n <> "   (lips ships it)" | n <- builtinNames ]
      ++ [ n <> "   (" <> T.pack (worldPathIn here n) <> ")"
         | n <- locals, n `notElem` builtinNames ]))

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
compileLoose :: Maybe FilePath -> Maybe FilePath -> Bool -> FilePath -> IO ()
compileLoose mout mLangDir noContract file = do
  dir <- either die pure (resolveLangDir file mLangDir)
  -- The gate runs first and hands back its realization, so compile writes the
  -- very output the contract judged (and the pipeline runs once, not twice).
  -- @--no-contract@ is the one caller that cannot gate (a compile inside a nix
  -- derivation has no nix to evaluate with); it still crystallizes and realizes.
  rls <- checkLoose (not noContract) (not noContract) mLangDir file
  forM_ [ (w, rl) | (w, Right rl) <- rls ] (compileWorld mout dir file)
  exitUnlessEveryWorldHeld file rls

-- | Stop with a failing exit code when any world did not hold, after the ones
-- that did have been reported and written. Deliberate: you get the artifact you
-- can have, and CI still cannot mistake a program that reaches only some of its
-- worlds for one that reaches them all.
exitUnlessEveryWorldHeld :: FilePath -> [(Text, Either Text Realization)] -> IO ()
exitUnlessEveryWorldHeld file rls = case [ w | (w, Left _) <- rls ] of
  []   -> pure ()
  bad  -> do
    say ""
    say (T.pack file <> " does not reach " <> T.intercalate ", " bad
           <> "; the other worlds above hold.")
    exitWith (ExitFailure 1)

-- | Materialize ONE world's module directory from the realization @check@
-- already validated. Every world the language was minted into is written, each
-- into its own directory: a compiled module is a world's shape, so two worlds
-- sharing one directory would leave only the last one written.
compileWorld :: Maybe FilePath -> FilePath -> FilePath -> (Text, Realization) -> IO ()
compileWorld mout dir file (w, rl) = do
  world   <- readRecordedWorld dir w file
  -- An explicit @--out@ splits by world too, for the same reason the default
  -- path does: the flag names where the outputs go, not which one survives.
  let outDirPath = maybe (compiledPath file w) (</> T.unpack w) mout
  (artNames, rungs) <- step ("write " <> T.pack outDirPath) $ do
    ensureDerived file
    createDirectoryIfMissing True outDirPath
    TIO.writeFile (outDirPath </> "default.nix") (rlModule rl)
    stageFromDisk dir file (outDirPath </> "artifacts")
    -- The committed source keeps its markers (it is the template); the COMPILED
    -- source is filled, like every other derived output.
    fillStagedTree file (outDirPath </> "artifacts") (rlFills rl)
    -- The clause core, when the program states behaviour: one site directory
    -- holding the runtime's adapters, the minted core, the assembled entry and
    -- the runtime's own builder. A configuration-only program writes none, so
    -- its output stays byte-identical.
    hasSite <- writeSite outDirPath rl
    -- Always written, empty set when the program declares none: the flake text
    -- imports it unconditionally.
    let (artBody, artNames) = rlArtifact rl
    TIO.writeFile (outDirPath </> "artifact.nix") artBody
    -- The experiments the program states, beside the artifacts they observe. A
    -- claim-free program writes no file and its output stays byte-identical.
    hasClaims' <- case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
      Nothing   -> pure False
      Just body -> TIO.writeFile (outDirPath </> "claims.nix") body >> pure True
    let rungs = Rungs { hasArtifacts = not (null artNames), hasClaims = hasClaims'
                        -- The name the module binds, so every rung of the
                        -- compiled directory builds the same derivation.
                      , siteRung = if not hasSite then Nothing
                                   else Just (SiteRung (siteNameOf rl)
                                                       (not (null (rlClauseClaims rl)))) }
    TIO.writeFile (outDirPath </> "flake.nix") (flakeText world rungs)
    pure (artNames, rungs)
  say ("→ run it with nix over " <> T.pack outDirPath <> ":")
  mapM_ note (runCommands world artNames rungs outDirPath)

-- | Create a language's derived subtree and make it ignore itself: @out/@ gets
-- a @.gitignore@ holding @*@. lips writes that rule rather than asking the
-- user's repo to carry one, so derived output (crystal witnesses, compiled
-- module dirs) stays untracked wherever a program lives, with no setup.
-- Written once; an existing file is left alone, so a user can edit it.
ensureDerived :: FilePath -> IO ()
ensureDerived file = do
  createDirectoryIfMissing True (outDir file)
  let ign = outDir file </> ".gitignore"
  there <- doesPathExist ign
  unless there (TIO.writeFile ign "*\n")

-- | The world an engine was minted into: named by its committed .generation
-- record, and READ from the copy that travels beside the engine. The copy is
-- required -- lips never falls back to what it ships, because a world is data
-- now and the shipped one may have moved on. When the record carries a pin, the
-- copy must hash to it, so a compiled flake can never come from physics the
-- record does not name.
readRecordedWorld :: FilePath -> Text -> FilePath -> IO World
readRecordedWorld dir w file = do
  let path = generationPathIn dir w file
  there <- doesPathExist path
  m <- tryRead path
  src <- case (there, m) of
    (True, Nothing) -> die (report
      ("lips can't read the generation record at " <> T.pack path <> ",")
      ["so it cannot tell which world this engine was minted for."]
      "\8594 restore the file, or re-mint: lips generate <program>.")
    (_, Nothing) -> die (report
      ("lips can't compile " <> T.pack file <> ": there is no generation record at "
        <> T.pack path <> ".")
      []
      "\8594 mint it: lips generate <program>.")
    (_, Just s) -> pure s
  (name, mpin) <- either (\why -> die (report
      ("lips can't compile " <> T.pack file <> ": " <> why <> ".")
      [T.pack path <> " is the record it read."]
      "\8594 re-mint it: lips generate <program>.")) pure (recordedWorld src)
  -- The copy lives in the world's own folder, which is NAMED after the world
  -- the record declares, so the two cannot disagree about which world this is.
  let wpath = worldPathIn (worldDirIn dir name) name
  mraw <- tryRead wpath
  raw <- case mraw of
    Just r  -> pure r
    Nothing -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file is missing.")
      [ T.pack path <> " names the world " <> name <> ", and " <> T.pack wpath <> " is not there." ]
      ("\8594 restore it: lips world " <> name <> " > " <> T.pack wpath
        <> " (for a world lips ships), or put your own copy back."))
  world <- either (\why -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file does not read.")
      [T.pack wpath <> ": " <> why]
      "\8594 restore it from the copy the record was minted with.")) pure (parseWorld raw)
  -- A record from before the pin existed cannot be re-hashed (a committed
  -- record is sealed: editing one would invalidate every stamp it names), so
  -- the copy is required but unpinned there.
  case mpin of
    Just pin | worldHash world /= pin -> die (report
      ("lips can't compile " <> T.pack file <> ": its world file is not the one it was minted with.")
      [ T.pack path <> " pins " <> pin <> ", and " <> T.pack wpath <> " hashes to " <> worldHash world ]
      "\8594 restore that world file, or re-mint against this one: lips generate <program>.")
    _ -> pure ()
  pure world

-- | @check@: verify the program's committed behavioral contract holds against
-- its realized module, deterministically (no AI). This is the offline guardian
-- of the @.expect@ spec; @generate@ runs the same check before accepting an
-- engine, and the flake check shells this per example.
-- Returns the realization it validated, so @compile@ -- which gates through
-- this same verb -- materializes that run's output instead of running the whole
-- pipeline a second time.
-- Two flags, one per gate, so each skip is named at the call site instead of
-- riding along with another. @contract@ is the behavioral gate: only a compile
-- inside a nix build passes 'False' (see @--no-contract@). @claims@ is the
-- observational gate, which builds and may boot: 'checkDraft' passes 'False'
-- for it alone, because a per-call VM boot would block a mint on a machine
-- without KVM. Everything before both -- crystallization, the open questions,
-- the staged-source check -- runs either way, because none of it needs nix.
-- Per world, the verdict is an 'Either': a world the program does not reach
-- fails alone (see 'unportableReport'), so the worlds that DO hold are still
-- reported, and still compiled.
checkLoose :: Bool -> Bool -> Maybe FilePath -> FilePath -> IO [(Text, Either Text Realization)]
checkLoose contract claims mLangDir file = do
  dir     <- either die pure (resolveLangDir file mLangDir)
  program <- readProgramOrDie file
  ws      <- mintedWorlds dir file
  when (null ws) $ die (report
    (T.pack file <> " isn't set up yet (" <> T.pack dir <> " holds no world).")
    []
    ("\8594 create it: lips generate " <> T.pack file))
  -- Provenance before content: an engine whose lines do not name a record
  -- beside it is not the engine those records produced, so every later verdict
  -- would be about an unidentified file (invariant 6). Once for the language,
  -- because the grammar and every world's rules are stamped against the same
  -- set of records.
  assertStamps dir ws file
  forM ws $ \w -> do
    -- Each world is judged on its own and says so, because the verdicts
    -- genuinely differ: a line answered by one world's rules can stay open in
    -- another's, and only the pattern half of the diagnosis is shared.
    say ("world " <> w <> ":")
    r <- checkWorld contract claims dir w file program
    case r of
      Left why -> say why
      Right _  -> pure ()
    pure (w, r)

-- | One world's verdict on a program: its rules read on top of the shared
-- grammar, its diagnosis, its contract, its claims.
-- The one non-fatal defect is the world's own: ground decisions no rule of THIS
-- world places. Every other failure is a fact about the PROGRAM (a conflict, an
-- unanswered demand, a line no pattern reads) and holds in every world, so it
-- stays fatal -- reporting it once per world would repeat one defect N times.
checkWorld :: Bool -> Bool -> FilePath -> Text -> FilePath -> Text -> IO (Either Text Realization)
checkWorld contract claims dir w file program = do
  eng <- loadLangOrDie dir w file
  step ("crystallize " <> T.pack file) $ do
    -- An engine unsound on its own terms makes every later verdict meaningless
    -- (an ambiguous line reads as the author's problem when it is the engine's),
    -- so it fails before the diagnosis. Same gate generate runs before accepting
    -- a mint, so a committed engine cannot drift below what minting required.
    case engineViolations eng of
      []      -> pure ()
      (v : _) -> die (validationReport file v)
    -- First phase, pure and offline: how the program sits in its language.
    -- Always shown, so authoring is never blind; the behavioral gate runs only
    -- once the program crystallizes cleanly and completely.
    let d = diagnose file eng program
    sayAnswer (renderDiagnosis file d <> "\n")
    if any escapes (diagLines d)
      then die (report
             (T.pack file <> " has lines its language cannot read yet.")
             []
             ("→ grow the language: lips generate " <> T.pack file))
      else if not (null (diagOpen d))
        -- An open question is the author's to answer -- unless no program could:
        -- a demand outside every emitted subject family is an engine defect, and
        -- telling the author to state a fact they already stated sends them in
        -- circles. So blame the side that can fix it.
        then case unanswerableDemands (edPatterns eng) (edDemands eng) of
          []  -> die (report
                   (T.pack file <> " is incomplete while these questions stay open.")
                   []
                   "→ answer them by stating the detail in the program.")
          uds -> die (unanswerableReport file uds)
        else pure ()
  -- Validated ONCE, here, so the two readings of the outcome (is this world
  -- reachable, and does its contract hold) judge the same run.
  case validate file eng program of
    Left (FailRun (Unmapped ds)) -> pure (Left (unportableReport file w ds))
    Left ff -> die (printFail file ff)
    Right rl0 -> do
      rl <- expectGate contract claims dir w file eng program rl0
      -- What vouches for each assertion, always printed. An unvouched assertion
      -- (foreign text in an artifact argument, a staged source tree) is the one
      -- thing lips cannot check, so the count is stated on every run rather than
      -- discovered later by a reviewer reading generated code.
      mapM_ note (groundingReport (rlGrounding rl))
      -- A staged tree's size is the one thing the kernel cannot report: it is
      -- pure and owns no filesystem, so the path counts as one word while the
      -- file behind it may hold seventy lines nobody reviewed. The caller that
      -- stages measures.
      mapM_ note =<< stagedSizes dir file (rlGrounding rl)
      pure (Right rl)
  where
    escapes Matched{} = False
    escapes _         = True

-- | @check --draft@: judge an engine the mint has not committed yet. The draft
-- arrives on stdin in reply format; lips materializes it into a throwaway
-- language folder and runs the ordinary verifier over it, so what the model is
-- told is what lips itself would say -- there is no second, model-facing
-- verifier to drift.
--
-- The COMMAND claim gate is deliberately NOT run, and the output says so: a
-- sandbox claim compiles the artifact and a machine claim boots a VM, so it costs
-- minutes per call and hard-fails without KVM, which would be a false RED
-- blocking the model from validating at all. "Not verified" is stated, never
-- rendered as verified.
--
-- The CLAUSE claim gate IS run, for the same reason by the same rule: it costs a
-- small derivation, needs no machine and no compiler, so the cost argument that
-- excludes the others does not apply. That lets a model fix a failing claim
-- inside the one call instead of spending a whole mint on it.
--
-- The gate that DECIDES is unchanged: generate still runs every one of these
-- checks afterwards, so a model that skips this door is refused exactly as
-- before.
checkDraft :: FilePath -> IO ()
checkDraft file = do
  reply <- TIO.getContents
  -- Which contract governs is generate's rule, not this function's: it exports
  -- the answer (the committed .expect on a regeneration, empty under --renew or
  -- on a first mint) so the two cannot drift apart.
  governing <- lookupEnv "LIPS_MINT_EXPECT" >>= \m -> case m of
    Just p | not (null p) -> tryRead p
    _                     -> pure Nothing
  -- The world the draft is minted into decides where its rules go, so the
  -- throwaway folder has the shape check reads: generate states it, and a draft
  -- for a world lips cannot name is unjudgeable.
  draftW <- wName <$> draftWorldOrDefault
  withTempDir $ \root -> case materializeDraft root draftW file reply governing of
    Left errs -> die (validationReport file ("the draft cannot be read as an engine:\n"
                        <> T.unlines [ "  - " <> e | e <- errs ]))
    Right t   -> do
      createDirectoryIfMissing True (worldDirIn (dtLangDir t) (dtWorld t))
      TIO.writeFile (grammarPathIn (dtLangDir t) file) (dtGrammar t)
      TIO.writeFile (rulesPathIn (dtLangDir t) (dtWorld t) file) (dtRules t)
      TIO.writeFile (expectPathIn (dtLangDir t) (dtWorld t) file) (dtExpect t)
      writeSources (artifactsPathIn (dtLangDir t) file) (dtSources t)
      -- The schema gate cannot live in check, which stays nixpkgs-free so a
      -- committed engine is judged offline. The draft path runs on the mint
      -- side, where generate has already built a schema and hands over its
      -- path, so it runs the gate itself: without it a draft naming an option
      -- that does not exist would read as clean here and be refused by the
      -- final gate, which is the false-green direction.
      mschema <- lookupEnv "LIPS_MINT_SCHEMA"
      case mschema of
        Just p | not (null p) -> do
          world <- draftWorld
          eng <- loadLangOrDie (dtLangDir t) (dtWorld t) file
          assertOptionsAdmissible world p file eng
        _ -> pure ()
      -- One world, named rather than discovered: a draft folder holds no
      -- .generation (a draft HAS no generation), so there is nothing to find by
      -- looking, and generate already said which world it is minting into.
      program <- readProgramOrDie file
      -- A draft is judged for ONE world, so a world it does not reach is that
      -- draft's whole verdict, and fatal here.
      rl <- either die pure =<< checkWorld True False (dtLangDir t) (dtWorld t) file program
      world <- draftWorldOrDefault
      clauseClaimGate world file rl
      note "the command claim gate and the artifact build were NOT run"

-- | The draft's world where generate stated one, else the default. Used only
-- where a wrong guess is harmless (which flake shape a throwaway directory gets);
-- the schema gate keeps using 'draftWorld', which refuses to guess.
draftWorldOrDefault :: IO World
draftWorldOrDefault = do
  mt <- lookupEnv "LIPS_MINT_WORLD"
  pure (fromMaybe (fromMaybe (error "lips ships no nixos world") (builtinWorld "nixos"))
                  (mt >>= builtinWorld . T.pack))

-- | Which world a draft is grounded against. Read from the environment generate
-- controls, never defaulted: a silent default would ground a mint against the
-- wrong world's schema and report the wrong names as missing.
draftWorld :: IO World
draftWorld = do
  mt <- lookupEnv "LIPS_MINT_WORLD"
  case mt >>= builtinWorld . T.pack of
    Just w  -> pure w
    Nothing -> die (report
      "lips can't check this draft: the world it is minted for is not stated."
      ["LIPS_MINT_SCHEMA names a schema, but LIPS_MINT_WORLD is missing or not a world lips ships."]
      "\8594 this is generate's to set; report it as a lips bug.")

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
-- Validates once, up front: the module, its artifacts and the paths it names
-- all come from that one run, so the staged-source gate below and the contract
-- judge the same realization.
expectGate :: Bool -> Bool -> FilePath -> Text -> FilePath -> EngineData -> Text -> Realization -> IO Realization
expectGate contract claims dir w file eng program rl = do
  stagedGate (stageBeside dir file rl) file rl
  sourceSpecGate dir w file eng program
  expSrc <- if contract then tryRead (expectPathIn dir w file) else pure Nothing
  case expSrc of
    -- A skipped or absent contract is stated, never rendered as a pass: the
    -- step's own ✓ would otherwise claim a gate that did not run.
    Nothing | not contract ->
      note "contract skipped (--no-contract): nix is needed to evaluate it"
    Nothing  -> note ("no contract yet: " <> T.pack (expectPathIn dir w file)
                        <> " is written by generate")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        | otherwise -> step ("contract: " <> plural (length expects) "check") $ do
          -- Bind <self> in the contract's option paths to this instance, so it
          -- checks against the realized (already-bound) module.
          res <- runExpects (stageBeside dir file rl) (map (bindSelfExpect (instanceName file)) expects) rl
          case res of
            Right () -> pure ()
            Left (ToolMissing e) -> die (nixMissing file "check the program" "check" e)
            Left (EvalFailed e)  -> die (nixEvalFailed file "check" e)
            Left (Violations fs _) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))
  when claims $ do
    world <- readRecordedWorld dir w file
    claimGate world dir file rl
  pure rl

-- | Load and parse one world's engine: the shared grammar plus that world's
-- rules, read as the concatenation they are rendered from. Fails loud naming
-- @generate@ -- a missing grammar means the language was never minted, a
-- missing rules file means it was never minted INTO THIS WORLD, so the remedy
-- names the world.
loadLangOrDie :: FilePath -> Text -> FilePath -> IO EngineData
loadLangOrDie dir w file = do
  let grammarFile = grammarPathIn dir file
      rulesFile   = rulesPathIn dir w file
  mgrammar <- tryRead grammarFile
  grammar  <- case mgrammar of
    Nothing -> die (report
      (T.pack file <> " isn't set up yet (" <> T.pack grammarFile <> " is missing).")
      []
      ("→ create it: lips generate " <> T.pack file))
    Just g  -> pure g
  mrules <- tryRead rulesFile
  rules  <- case mrules of
    Nothing -> die (report
      (T.pack file <> " is not minted for the world " <> w <> " ("
        <> T.pack rulesFile <> " is missing).")
      []
      ("→ mint it there: lips generate --target " <> w <> " " <> T.pack file))
    Just r  -> pure r
  case readLang (grammar <> rules) of
    Left es  -> die (unreadable file ".lang" es)
    Right eng -> pure eng

-- | Invariant 6, enforced at the door every committed engine passes: re-hash
-- the @.generation@ beside the engine and refuse a @\@gen:@ stamp that
-- disagrees with it. Deterministic and offline, so @check@ stays nixpkgs-free.
--
-- Without it the invariant was a promise: a change to what the record CONTAINS
-- would silently invalidate every committed engine's stamps while all gates
-- stayed green, and only a reader re-hashing by hand would ever notice.
--
-- An engine with no record at all is judged the other way round ('stampFaults'):
-- it may claim no generation. A record that EXISTS and cannot be read is a loud
-- failure rather than the no-record reading, exactly as 'readRecordedWorld'
-- treats it -- guessing there would turn a broken repository into a green check.
assertStamps :: FilePath -> [Text] -> FilePath -> IO ()
assertStamps dir ws file = do
  recs <- fmap concat $ forM ws $ \w -> do
    let recPath = generationPathIn dir w file
    there <- doesPathExist recPath
    mrec  <- tryRead recPath
    case (there, mrec) of
      -- A world with no record at all is a hand-written engine, judged by the
      -- inverted rule (no line may claim a generation). A record that EXISTS
      -- and cannot be read is the other case entirely: reading it as absent is
      -- what would turn a damaged repository green.
      (False, _)      -> pure []
      (True, Nothing) -> die (report
        ("lips can't read the generation record at " <> T.pack recPath <> ",")
        ["so it cannot tell which generation wrote this engine."]
        "\8594 restore the file, or re-mint: lips generate <program>.")
      (True, Just r)  -> pure [r]
  -- File by file, so a reported line number is that file's own; a grammar line
  -- may name any world's mint, which is why every record is offered to each.
  faults <- forM (grammarPathIn dir file : [ rulesPathIn dir w file | w <- ws ]) $ \p -> do
    msrc <- tryRead p
    pure [ (p, f) | f <- maybe [] (stampFaults recs) msrc ]
  case concat faults of
    [] -> pure ()
    bad -> die (report
      (T.pack file <> "'s engine does not name the generations that wrote it:")
      [ T.pack p <> ": " <> renderStampFault f | (p, f) <- bad ]
      ("\8594 re-mint it: lips generate " <> T.pack file
        <> " (a minted file is never hand-edited)."))

-- | One line of a rendered engine, by its id, for a message that has to show
-- what changed. Absent means the mint dropped it.
lineOf :: Text -> Text -> Text
lineOf i src = case [ l | l <- T.lines src, take 1 (T.words l) == [i] ] of
  (l : _) -> l
  []      -> "(dropped)"

-- | Read the program file, or fail with a plain message instead of a raw
-- exception when the path is wrong (a common typo at the shell).
readProgramOrDie :: FilePath -> IO Text
readProgramOrDie file = do
  -- The one door every verb reads a program through, so the .lips marker is
  -- checked once, here: a path without it would otherwise be reinterpreted by
  -- Lips.Identity (a .lang read as a program in language "lang").
  either die pure (requireProgram file)
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
-- The inherited grammar, when there is one, is both an INPUT (the mint is told
-- to reuse it, so it enters the prompt and the record) and a GUARD (what comes
-- back is checked against it).
generate :: World -> Maybe Text -> Maybe String -> Double -> Compat -> Bool -> Maybe String -> String -> [FilePath] -> IO ()
-- Unreachable: Lips.Cli.generateOpts's `some` guarantees at least one file by
-- construction. Kept only so this function stays total (-Wall incomplete-patterns).
generate _ _ _ _ _ _ _ _ [] = die "lips generate needs at least one program (unreachable: the CLI parser requires one)."
generate world inherited mschema confidence compat verbose mmodel thinking files@(rep : _) = do
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
  let prompt = promptWithDirection direction inherited [world]
      -- The mint sees the whole example set at once, so the grammar generalizes
      -- across them (anti-unification): tokens that vary between examples become
      -- holes, tokens that agree stay literal. One program is the corpus-of-one
      -- case. The same set is the regeneration corpus below.
      corpus = corpusText progs
  -- Resolve the grounding schema BEFORE the model runs: it is an input of the
  -- generation event (it decides which rules are admissible), it is recorded as
  -- such, and a schema that cannot be built must not cost an AI call first.
  (schemaPath, schemaPin) <- ensureOptionSchema world mschema ("generate " <> T.pack rep)
  -- A re-mint grounds against the pin this binary carries (or --schema), NOT
  -- against the one the committed record names: fresh grounding is the point of
  -- re-minting, and replaying an old one is impossible anyway. The only hole
  -- that leaves is silence, so say it -- a re-ground engine is a different
  -- engine, and the reader deserves to learn that here rather than from the
  -- .generation diff afterwards.
  oldPin <- (>>= recordedSchema) <$> tryRead (generationPathIn (langDir rep) (wName world) rep)
  case oldPin of
    Just p | p /= schemaPin -> do
      note ("re-grounding: the committed engine was minted against " <> p)
      note ("this run grounds against " <> schemaPin)
    _ -> pure ()
  -- The mint's validation tool judges a draft against the contract that will
  -- actually gate it: the committed .expect on a regeneration, the draft's own
  -- minted expects on a first mint or under --compat none. That rule is
  -- generate's (it is read again below, where the gate itself uses it), so the
  -- tool is told the answer instead of re-deriving it and drifting into a false
  -- green.
  committedExpectPath <- if compat == None
    then pure Nothing
    else do
      let p = expectPathIn (langDir rep) (wName world) rep
      there <- doesFileExist p
      pure (if there then Just p else Nothing)
  (reply, model, transcript) <-
    step ("mint ." <> T.pack lang <> " from " <> plural (length files) "program") $
      callPi verbose mmodel thinking prompt corpus world files committedExpectPath schemaPath
  note ("minted by " <> model <> ", thinking " <> T.pack thinking)
  -- --verbose: echo the model's raw reply verbatim before parsing, so the
  -- whole minted engine is inspectable even when it validates cleanly (a
  -- refusal already shows the offending lines).
  when verbose $ say (T.unlines
    [ "--- raw model reply (" <> model <> ") ---", reply, "--- end reply ---" ])
  let (errs, candidates) = parseEngineCandidates [wName world] reply
      -- A because-note explains a low-confidence item; keyed by shared id, it
      -- never gates the build and never enters the engine.
      notes = [(icId c, r) | c <- candidates, ItemNote r <- [icItem c]]
      -- Deduce-or-fail: the programs are the only source of truth, so an item
      -- the model cannot confidently derive means they underspecify it.
      unsure = [c | c <- candidates, carriesEngineMeaning (icItem c)
                  , let Confidence x = icConfidence c, x < confidence]
      gaps = gapsOf (map icItem candidates)
  if not (null errs) || not (null unsure)
    then do
      -- Machine-readable twin of the on-screen refusal: the cross-repo
      -- escalation workflow (DESIGN Doctrine) needs a shippable artifact, not
      -- only text that scrolls off a terminal. Same fields, same fingerprint
      -- scheme as a successful '.generation' record (built the same way, from
      -- the same in-scope values), so a refusal is pinned exactly as an
      -- acceptance would have been.
      let rec = record model [(wName world, worldHash world, schemaPin)] (T.pack thinking) confidence prompt corpus transcript reply
      -- The refusal is the first thing written for a world, so its directory
      -- (<language>/<world>/) need not exist yet.
      createDirectoryIfMissing True (worldDirIn (langDir rep) (wName world))
      let gap = gapPathIn (langDir rep) (wName world) rep
      TIO.writeFile gap (gapArtifact rec errs unsure gaps)
      die (refusalReport rep gap confidence errs unsure notes gaps)
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
      -- The schema-free gates, the same ones check runs over an engine already
      -- committed. Only the first is shown: it is what dying on the first gate
      -- has always done, and a later verdict is rarely meaningful once an
      -- earlier one rejected the engine.
      case engineViolations eng of
        []      -> pure ()
        (v : _) -> die (validationReport rep v)
      -- Before any gate that costs a build: a later world may only APPEND to
      -- the grammar its predecessors wrote, because their committed rules were
      -- lowered from exactly those patterns and this run does not re-mint them.
      case inherited of
        Nothing -> pure ()
        Just g  -> let fresh = fst (splitEngine
                         (renderLang (FromSource (SourceLoc "lang" 0)) eng))
                   in case appendOnlyViolations g fresh of
          []  -> pure ()
          ids -> do
            held <- mintedWorlds (langDir rep) rep
            die (report
              ("the " <> wName world <> " mint changed " <> plural (length ids) "pattern"
                <> " the language's other worlds are built on:")
              -- Both lines, not just the id: what the change WAS is the whole
              -- question a reader has here, and neither file holds the new one
              -- (this mint writes nothing).
              (concat [ [ i <> " committed: " <> lineOf i g
                        , i <> " minted:    " <> lineOf i fresh ] | i <- ids ])
              ("\8594 re-mint every world together, so they agree: lips generate --target "
                <> T.intercalate "," (held ++ [ wName world | wName world `notElem` held ])
                <> " " <> T.pack rep))
      assertOptionsAdmissible world schemaPath rep eng
      -- Every program must crystallize, run, and parse as Nix under the shared
      -- engine: the example set is the regeneration corpus.
      validated <- forM progs $ \(f, t) -> case validate f eng t of
        -- An unmet demand at generate is ambiguous by construction (the kernel
        -- is domain-blind): name both remedies rather than blame one side.
        Left (FailRun (OpenQuestions qs)) -> die (demandGenerateFail f qs)
        Left ff -> die (validationReport f (failureReport f ff))
        Right rl -> do
          nixCheck <- nixParses (rlModule rl)
          case nixCheck of
            Left (NixToolMissing e) -> die (nixMissing f "verify the output" "generate" e)
            Left (NixInvalid why)   -> die (validationReport f ("the configuration lips produced isn't valid Nix:\n" <> why))
            Right ()                -> pure (f, rl)
      -- Sources are minted in memory; stage them (not yet on disk) so a staged
      -- @src = ./artifacts/<name>@ resolves during the behavioral eval and so
      -- the staged-source gate below judges the tree this mint actually writes.
      -- The artifact itself is BUILT by 'artifactGate' further down, which is the
      -- only way to learn what the build contains: nothing lips evaluates forces
      -- a derivation (the contract cannot assert one, 'uncheckableExpects'
      -- forbids it, and nix is lazy), so before that gate a malformed builder or
      -- a binary named differently by the source shipped and failed at the
      -- user's `nix run`.
      let minted = sourcesOf (map icItem candidates)
      -- The contract is language-level. On regeneration the COMMITTED contract
      -- governs (the stable spec regeneration may not silently break); on first
      -- generation the minted assertions bootstrap it.
          mintedExpects = expectsOf (map icItem candidates)
      -- A source tree is written under the artifact name the block gives, so a
      -- name still holding a hole makes a directory called "<self>" and the
      -- module's src points at nothing. Refused here, where the mint is still
      -- rejectable, instead of as a missing path two gates later.
      case unnamedSources minted of
        []  -> pure ()
        bad -> die (report
          (T.pack rep <> ": " <> plural (length bad) "source file"
            <> " named for an artifact whose name is still a hole:")
          [ sfArtifact sf <> "/" <> sfPath sf | sf <- bad ]
          ("\8594 a baked source tree needs the concrete name this program gives it"
            <> " (the RULE keeps the hole); run generate again."))
      -- Where an engine BAKES source, the module text says nothing about what
      -- that code does, so without one stated observable nothing holds the
      -- implementation -- or any future re-mint -- to the author's own words.
      --
      -- REFUSED, not said (changed 2026-08-04). It was a warning, on the argument
      -- that an otherwise-correct engine is worth having and a witness cannot be
      -- conjured. `logscan` spent months as the counter-example: 76 lines of Go,
      -- roughly fifteen traceable, a silent `continue` against fail-loud doctrine,
      -- two mints disagreeing about what the program did, and every gate green
      -- throughout. The cost of refusing is a re-mint, which the message names.
      -- A pure-configuration mint is unaffected, and so is an engine whose
      -- behaviour is clauses with a claim over them.
      --
      -- Addressed to the MINT, not to the author (measured 2026-08-06): opus-5
      -- minted `examples/function.lips` unmodified, with no witness sentence in
      -- it, and deduced four claims from the program's own words. Deducing the
      -- observable is the mint's job; the author states one only where the mint
      -- reports it cannot.
      -- Clauses nothing observes are refused one tier down, by
      -- 'Lips.Kernel.Realize.realizeClauseClaims', which knows the actual clause
      -- set and can require every definition to be REACHED by a claim rather than
      -- merely accompanied by one. So the validation above has already refused it,
      -- for every verb, and this door only has to answer for baked source.
      let allClaims = concatMap (rlClaims . snd) validated
          unobserved = claimlessBakedSource minted allClaims
      when unobserved $ die (report
        (T.pack rep <> " builds a program from source, and nothing observes what"
          <> " that program does:")
        [ sfArtifact sf <> "/" <> sfPath sf | sf <- minted ]
        ("\8594 the mint must deduce an example from the program's own words --"
          <> " what it is given and what it prints -- and file a claim over it;"
          <> " mint again: lips generate " <> T.pack rep
          <> ". State the example in the program only where the mint reports it"
          <> " cannot deduce one."))
      case unplaceableClaims (wClaims world) allClaims of
        []  -> pure ()
        ids -> die (report
          (T.pack rep <> ": " <> plural (length ids) "claim"
            <> " must be observed in a booted machine, and the " <> wName world
            <> " world has none.")
          ids
          ("\8594 state the observable over the program's own binary, which needs no"
            <> " machine, and mint again: lips generate " <> T.pack rep))
      -- Which contract governs is one word from the human (--compat), applied
      -- to the committed set and this run's minted one. Every correctness gate
      -- above and the behavioral gate below still run whatever the word, so a
      -- bad mint still writes nothing.
      committed <- tryRead (expectPathIn (langDir rep) (wName world) rep)
      committedExpects <- case maybe (Right []) readExpect committed of
        Left es -> die (report
          (T.pack (expectPathIn (langDir rep) (wName world) rep)
            <> " is unreadable, so lips can't verify against it:")
          [ "line " <> tshow (peLine e) <> ": " <> peMessage e | e <- es ]
          ("→ fix or delete " <> T.pack (expectPathIn (langDir rep) (wName world) rep)
            <> ", then run generate again."))
        Right xs -> pure xs
      expects <- case rebless compat (edRules eng) committedExpects mintedExpects of
        Right xs  -> pure xs
        Left kept -> die (report
          (T.pack rep <> ": this run drops " <> plural (length kept) "check"
            <> " the engine still fills, which --compat forwards does not permit:")
          [ renderAttrPath (exPath e) | e <- kept ]
          ("→ keep them (drop --compat forwards), or accept the loss deliberately: "
            <> "lips generate --compat none " <> T.pack rep))
      case uncheckableExpects (edRules eng) expects of
        bad@(_ : _) -> die (uncheckableReport rep bad)
        []          -> pure ()
      -- Every relative path a module names must be in the tree this mint stages:
      -- a mint that emits `src ./artifacts/<name>` but writes its source under
      -- another name is refused here instead of shipping a broken build.
      forM_ validated $ \(f, rl) ->
        stagedGate (\root -> writeSources (root </> "artifacts") minted
                               >> void (writeSite root rl)) f rl
      -- The shared contract gates every program, each bound to its own <self>.
      step ("contract: " <> plural (length expects) "check") $ forM_ validated $ \(f, rl) -> do
        gate <- runExpects (\root -> writeSources (root </> "artifacts") minted
                                      >> void (writeSite root rl))
                           (map (bindSelfExpect (instanceName f)) expects) rl
        case gate of
          Left (ToolMissing e) -> die (nixMissing f "verify the output" "generate" e)
          Left (EvalFailed e)  -> die (nixEvalFailed f "generate" e)
          Left (Violations fs broken) -> die (report
            ("lips built a setup for " <> T.pack f <> ", but it doesn't produce what the program promises:")
            fs
            -- Name the SMALLEST mode that would admit this change: an assertion
            -- on an option the engine stopped filling may simply leave
            -- (forwards), while one the engine still fills is a real behaviour
            -- change and takes the whole word (none).
            ("→ run generate again. If you changed the program on purpose, accept "
              <> "the new behavior: lips generate --compat "
              <> compatSlug (smallestCompat (edRules eng) broken) <> " " <> T.pack rep
              <> " (rewrites " <> T.pack (expectPathIn (langDir rep) (wName world) rep) <> ")."))
          Right () -> pure ()
      -- Last gate, and the only one that observes rather than reads: build each
      -- artifact and look inside it. Deliberately after the cheap gates, so a
      -- mint that fails for a readable reason never pays a build.
      when (any (not . null . snd . rlArtifact . snd) validated) $ do
        nixpkgs <- artifactNixpkgs ("generate " <> T.pack rep)
        forM_ validated $ \(f, rl) ->
          artifactGate nixpkgs (\root -> writeSources (root </> "artifacts") minted
                                          >> void (writeSite root rl)) f rl
      -- And the gate that observes what the program DOES: run every claim the
      -- mint stated. Against the pinned nixpkgs, so the mint observes the world
      -- it was grounded against.
      -- The clause claims first: they are the ONLY contract a clause program has
      -- (a clause is no option, so .expect can pin nothing about it), and they
      -- cost a small derivation rather than a boot. Without this the mint would
      -- write an engine whose stated behaviour was never observed.
      forM_ validated $ \(f, rl) -> clauseClaimGate world f rl
      when (not (null allClaims)) $ do
        nixpkgs <- artifactNixpkgs ("generate " <> T.pack rep)
        forM_ validated $ \(f, rl) ->
          mintClaimGate nixpkgs (\root -> writeSources (root </> "artifacts") minted
                                           >> void (writeSite root rl)) f rl
      -- All held: write the shared language once, a crystal per instance. Every
      -- engine line is stamped with the content id of the .generation record,
      -- checkable by re-hashing it.
      let rec = record model [(wName world, worldHash world, schemaPin)] (T.pack thinking) confidence prompt corpus transcript reply
          dir  = langDir rep
          w    = wName world
          (minted', rulesText) = splitEngine (renderLang (FromGeneration (genId rec)) eng)
          -- An inherited grammar is written back verbatim, with only this
          -- mint's additions appended: the lines belong to the mint that wrote
          -- them, and the other worlds' rules were lowered from those bytes.
          grammarText = maybe minted' (`mergeGrammar` minted') inherited
      step ("write " <> T.pack (worldDirIn dir w)) $ do
        -- The language folder holds every minted and derived file, and the
        -- world's folder everything this lowering owns; create both (and the
        -- derived out/ subtree) before writing, so a first mint beside a bare
        -- program just works.
        createDirectoryIfMissing True (worldDirIn dir w)
        -- The grammar is the language's, shared by every world; the rules are
        -- this world's alone. Rendered as one engine and split by subject, so
        -- the two halves read back as the engine that was validated.
        TIO.writeFile (grammarPathIn dir rep) grammarText
        TIO.writeFile (rulesPathIn dir w rep) rulesText
        -- The world travels WITH the engine: the record pins this copy by
        -- hash, and compile reads the copy, never the search path. So a
        -- committed engine carries the physics it was minted into, and a
        -- checkout on another machine compiles the same way.
        TIO.writeFile (worldPathIn (worldDirIn dir w) w) (wRaw world)
        TIO.writeFile (generationPathIn dir w rep) rec
        TIO.writeFile (readmePathIn dir w) (renderReadme (T.pack lang) reportBody gaps)
        -- A refusal artifact describes a run that produced no engine, so it is a
        -- lie once one exists: the accepted mint deletes the .gap an earlier
        -- refused attempt left behind.
        removePathForcibly (gapPathIn dir w rep)
        -- The artifacts tree is machine-owned and minted whole, so REPLACE it: a
        -- previous mint's tree under another artifact name would otherwise stay
        -- committed forever, dead source nothing builds (the http re-mint left a
        -- helloserver/ tree beside its new hello/ one).
        removePathForcibly (artifactsPath rep)
        writeSources (artifactsPath rep) minted
        forM_ validated $ \(f, rl) -> do
          ensureDerived f
          TIO.writeFile (decisionsPath f) (renderBase (rlBase rl))
        -- Write the contract the mode settled on, and only when it differs from
        -- what is committed: --compat full writes nothing (the default keeps the
        -- committed spec byte-identical), a first mint bootstraps, and the two
        -- relaxing modes leave the .expect diff as the semantic changelog.
        let contract = renderExpect expects
        when (committed /= Just contract) $ TIO.writeFile (expectPathIn dir w rep) contract
        mapM_ note $
          [ T.pack (grammarPathIn dir rep) <> "  the language, "
              <> plural (length (edPatterns eng)) "pattern"
          , T.pack (rulesPathIn dir w rep) <> "  the " <> w <> " lowering, "
              <> plural (length (edRules eng)) "rule"
          , T.pack (expectPathIn dir w rep) <> "  the contract, " <> plural (length expects) "check"
          , T.pack (readmePathIn dir w) <> "  what the language means, in plain words"
          , T.pack (generationPathIn dir w rep) <> "  how it was made" ]
          ++ [ T.pack (artifactsPath rep) <> "  " <> plural (length minted) "source file"
             | not (null minted) ]
      -- The account of the mint, in the mint's own words: the first lines of the
      -- report, then where to read the rest. Not the engine and not the module --
      -- both are files now, and a human reads them there.
      say ""
      say ("✓ ." <> T.pack lang <> " holds for " <> plural (length files) "program"
             <> " as a " <> wName world <> " configuration.")
      say ""
      mapM_ say (take 5 [ l | l <- T.lines (T.strip reportBody), not (T.null (T.strip l)) ])
      unless (null gaps) $ do
        say ""
        say ("lips could not do these, and says why in "
               <> T.pack (readmePathIn (langDir rep) (wName world)) <> ":")
        mapM_ (\g -> note ("- " <> gapSlug g)) gaps

      say ""
      say ("→ read the whole account: " <> T.pack (readmePathIn (langDir rep) (wName world)))
      mapM_ (\(f, _) -> say ("→ build it:              lips compile " <> T.pack f)) validated

-- | Crystallize and fully run the program with a candidate engine; on success
-- return the crystal and the realized module.
-- The module and the artifact.nix (the buildable derivations, or Nothing) are
-- projected from the same bound rules and ground base, so the artifacts a
-- compiled flake addresses are exactly the ones the module @let@-binds.
validate :: FilePath -> EngineData -> Text -> Either Failure Realization
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
          -- Whether a list option keeps repeated elements is knowledge about that
          -- option, so the engine states it; nothing declared means a set (two
          -- program lines naming one thing name it once).
          assembleList = assembleWith (keepsRepeats (edMerges eng))
      in first FailRun (runBase modeOf assembleList schemeVocabulary budget rules demands base)

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
callPi :: Bool -> Maybe String -> String -> Text -> Text -> World -> [FilePath] -> Maybe FilePath -> FilePath -> IO (Text, Text, Text)
callPi verbose mmodel thinking system userPrompt world files mExpect schemaPath = do
  -- The mint's tools ship with the binary; without them a mint would have to
  -- recall option names instead of looking them up, and could not check a draft
  -- before answering -- the guessing this whole path exists to prevent. So a
  -- missing extension is fatal, not a silent downgrade to a weaker mint.
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
  --
  -- What the draft tool may NOT choose is also set here: the programs it is
  -- judged against (a model picking its own corpus could validate against one
  -- that is not being minted), the governing contract, and the schema this run
  -- was grounded against.
  parentEnv <- getEnvironment
  let ours = [ ("LIPS_MINT_WORLD",    T.unpack (wName world))
             , ("LIPS_MINT_PROGRAMS", intercalate "\n" files)
             -- Empty means "the draft's own minted expects govern", which is a
             -- first mint or --renew.
             , ("LIPS_MINT_EXPECT",   fromMaybe "" mExpect)
             , ("LIPS_MINT_SCHEMA",   schemaPath)
             ]
      childEnv = ours ++ filter ((`notElem` map fst ours) . fst) parentEnv
      -- Hermetic by explicit subtraction: -nbt drops pi's built-in tools (read,
      -- bash, edit, write, grep, find, ls -- none of which the mint may touch),
      -- --no-extensions/--no-skills/--no-prompt-templates drop whatever the user
      -- happens to have installed, -nc drops ambient AGENTS.md/CLAUDE.md context
      -- files (global, and walking up from cwd). What remains is the two tools
      -- this run loads on purpose, so the mint's world equals what the record
      -- pins -- no input steers generation without entering genId's hash.
      -- --mode json: so the model pi resolved, and every lookup it made, are
      -- machine-readable in the reply.
      args = [ "-p", "-nbt", "-nc", "--no-extensions", "--no-skills"
             , "--no-prompt-templates", "--no-session", "--mode", "json"
             , "--system-prompt", T.unpack system
             -- --thinking is ALWAYS passed: an inherited reasoning level would
             -- steer the mint without entering the record (invariant 6).
             , "--thinking", thinking ]
               ++ extArgs ++ maybe [] (\m -> ["--model", m]) mmodel
  -- Everything that goes out, before anything comes back: under --verbose the
  -- prompt is shown as SENT (system prompt, direction and corpus), so a mint is
  -- reproducible from what the terminal showed.
  when verbose $ do
    say "--- system prompt (as sent) ---"
    say system
    say "--- programs (as sent) ---"
    say userPrompt
    say "--- waiting for the model ---"
  (code, out, err) <- streamPi verbose ((proc "pi" args) { env = Just childEnv }) userPrompt
  case code of
    ExitSuccess   -> do
      let PiReply { prReply = reply, prModel = model, prTranscript = transcript } =
            parsePiReply (T.pack out)
      if T.null reply
        then die (report "the AI model returned no usable reply." [] "→ run generate again.")
        -- pi always reports the model; an empty value would break provenance.
        else if T.null model
          then die (report "pi didn't report which model it used, so lips can't record provenance." [] "→ update pi, then run generate again.")
          -- An empty transcript is legitimate: a mint that needed no lookup made
          -- none. Only a MISSING record of one it did make would break invariant 6.
          else pure (reply, model, transcript)
    ExitFailure c -> die (report
      ("lips couldn't run the AI model (pi exited " <> tshow c <> "):")
      (T.lines (T.pack err))
      "→ check that pi is installed and authenticated, then run generate again.")

-- | Run pi and show what it does WHILE it does it. The mint is the one phase
-- that takes minutes, and reading its whole output at the end (which is what
-- @readCreateProcessWithExitCode@ does) made a working model and a hung one look
-- identical for that whole time.
--
-- Three streams, three jobs: the prompt is written by its own thread (a prompt
-- larger than a pipe buffer would deadlock if written inline, as soon as pi's
-- output filled ours), stderr is drained by another (it is only read on
-- failure, but an undrained pipe blocks the child), and the main loop reads
-- stdout line by line, showing each event and keeping every line -- so
-- 'parsePiReply' still sees the complete stream and the record is unchanged.
streamPi :: Bool -> CreateProcess -> Text -> IO (ExitCode, String, String)
streamPi verbose cp promptText = do
  (mIn, mOut, mErr, ph) <- createProcess cp
    { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe }
  (hin, hout, herr) <- case (mIn, mOut, mErr) of
    (Just a, Just b, Just c) -> pure (a, b, c)
    -- Unreachable: all three are CreatePipe above. Loud rather than a pattern
    -- match failure with no explanation.
    _ -> die (report "lips couldn't open a pipe to the AI model." []
                     "→ report this as a lips bug.")
  mapM_ (`hSetEncoding` utf8) [hin, hout, herr]
  hSetBuffering hout LineBuffering
  _ <- forkIO (TIO.hPutStr hin promptText `finally` hClose hin)
  errVar <- newEmptyMVar
  _ <- forkIO (hGetContents herr >>= \e -> length e `seq` putMVar errVar e)
  prose <- newIORef T.empty   -- partial line of the model's own words (verbose)
  seen  <- newIORef []        -- every stdout line, newest first
  let loop = do
        eof <- hIsEOF hout
        unless eof $ do
          l <- TIO.hGetLine hout
          modifyIORef' seen (l :)
          showEvent verbose prose (progressEvent l)
          loop
  loop
  leftover <- readIORef prose
  when (verbose && not (T.null leftover)) (say leftover)
  code <- waitForProcess ph
  errText <- takeMVar errVar
  ls <- reverse <$> readIORef seen
  pure (code, T.unpack (T.unlines ls), errText)

-- | Show one mint event. The ordinary view is one dim line per tool call and
-- one per answer, with the model's state on the live line; @--verbose@ adds the
-- model's own words as they arrive and the untruncated arguments and answers.
showEvent :: Bool -> IORef Text -> Maybe PiEvent -> IO ()
showEvent _ _ Nothing = pure ()
showEvent verbose prose (Just ev) = case ev of
  PiTool name args -> do
    setState ("running " <> name)
    note (name <> "  " <> if verbose then args else abbreviate 60 args)
  PiToolEnd name failed text -> do
    setState "waiting for the model"
    if verbose
      then note ("  → " <> name <> (if failed then " failed:" else " answered:")) >> say text
      else note ("  → " <> resultSummary failed text)
  PiState s -> setState s
  PiProse d -> do
    setState "writing the engine"
    -- Deltas arrive mid-word, so verbose prints them a LINE at a time: the
    -- remainder waits in the buffer until its newline shows up.
    when verbose $ do
      buffered <- readIORef prose
      let (whole, partial) = T.breakOnEnd "\n" (buffered <> d)
      writeIORef prose partial
      mapM_ say (T.lines whole)


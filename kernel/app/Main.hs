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
import           Control.Monad      (filterM, forM, forM_, unless, when, void)
import           Data.IORef         (IORef, newIORef, modifyIORef', readIORef, writeIORef)
import           Data.Bifunctor     (first)
import           Data.List          (intercalate, partition)
import           Data.Maybe         (fromMaybe, isJust)
import           Data.Aeson         (Value (..), decode)
import qualified Data.Aeson.KeyMap  as KM
import qualified Data.ByteString    as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Environment (getEnvironment, lookupEnv)
import           System.Exit        (ExitCode (..))
import           GHC.IO.Encoding     (setLocaleEncoding)
import           System.IO          (BufferMode (..), hClose, hGetContents,
                                     hIsEOF, hSetBuffering, hSetEncoding, stderr, stdout, utf8)
import           System.Directory   (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removeFile,
                                     doesPathExist, getTemporaryDirectory, listDirectory,
                                     removeDirectoryRecursive, removePathForcibly,
                                     getPermissions, setPermissions, setOwnerWritable)
import           System.FilePath    (takeDirectory, takeFileName, (</>))
import           System.Posix.Temp  (mkdtemp)
import           System.Process     (CreateProcess (..), StdStream (..), createProcess, proc,
                                     readProcessWithExitCode, waitForProcess)

import           Lips.Kernel.Engine.Aggregate   (assembleWith, mergeModeOf)
import           Lips.Kernel.Engine.Data       (bindSelf, keepsRepeats, toDemand, toRule)
import           Lips.Generate.Readme   (renderReadme)
import           Lips.Identity                 (requireProgram, readmePath, gapPath, artifactsPath, artifactsPathIn, compiledPath, decisionsPath, directionPath, expectPath, expectPathIn, generationPath, generationPathIn, instanceName, langDir, langPath, langPathIn, languageName, outDir, resolveLangDir)
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), CheckOpts (..), OptionsOpts (..), cliParserInfo)
import           Lips.Cli.Output        (die, note, report, reportHead, say, sayAnswer, setState, step)
import           Options.Applicative    (execParser)
import           Lips.Generate.Harness  (Confidence (..))
import           Lips.Generate.Draft    (DraftTree (..), materializeDraft)
import           Lips.Generate.Minting  (EngineItem (..), Gap (..), ItemCandidate (..), SourceFile (..), assemble, carriesEngineMeaning, expectsOf, gapsOf, parseEngineCandidates, promptWithDirection, reportOf, sourcesOf, uncheckableExpects, claimlessBakedSource, unplaceableClaims, unnamedSources)
import           Lips.Generate.PiJson   (PiEvent (..), PiReply (..), abbreviate, parsePiReply,
                                         progressEvent, resultSummary)
import           Lips.Generate.Record   (corpusText, genId, hashBytes, record, recordedPrograms)
import           Lips.Kernel.Base       (Conflict (..))
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect     (Expect (..), bindSelfExpect, checkArtifactValues, checkValues, evalExpr, expandExpects, expectedValue, isGroundExpect, readExpect, renderExpect)
import           Lips.Kernel.Reader     (ParseError (..), renderBase)
import           Lips.Kernel.Refine     (RefineError (..))
import           Lips.Kernel.Run
import           Lips.Kernel.Grounding  (Grounding, Unvouched (..), gStaged, groundingReport)
import           Lips.Runtime            (runtimeAsset, runtimes, schemeVocabulary)
import           Lips.Site               (SitePlan (..), planSite)
import           Lips.Kernel.Source     (fillTree)
import           Lips.Kernel.Lang.Crystallize  (CrystError (..), LineOutcome (..), crystallize)
import           Lips.Kernel.Claim             (Claim (..), ClaimPlace (..))
import           Lips.Kernel.Lang.Diagnose     (Diagnosis (..), SourceSpecVerdict (..), diagnose,
                                                sourceSpecVerdict)
import           Lips.Kernel.Lang.Store         (EngineData (..), readLang, renderLang)
import           Lips.Kernel.Engine.Answerable (UnanswerableDemand, unanswerableDemands)
import           Lips.Kernel.Engine.Gate       (engineViolations, unanswerableProblem)
import           Lips.Kernel.OptionType        (Answer (..), answerQuery, checkEmits, dotted, renderOptionError, renderOptionType)
import           Lips.Nix.Claims               (claimsFile)
import           Lips.Nix.Flake                (Rungs (..), SiteRung (..), flakeText, noRungs,
                                                runCommands)
import           Lips.Nix.Schema               (schemaFor)
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
    Generate go -> generate (goTarget go) (goSchema go) (goConfidence go) (goRenew go) (goVerbose go) (goModel go) (goThinking go) (goFiles go)
    Compile co  -> compileLoose (coOut co) (coLangDir co) (coNoContract co) (coFile co)
    Check co
      | ceDraft co -> checkDraft (ceFile co)
      | otherwise  -> () <$ checkLoose True True (ceLangDir co) (ceFile co)
    Options oo  -> optionsQuery (ooTarget oo) (ooSchema oo) (ooLimit oo) (T.pack (ooQuery oo))
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
compileLoose :: Maybe FilePath -> Maybe FilePath -> Bool -> FilePath -> IO ()
compileLoose mout mLangDir noContract file = do
  dir <- either die pure (resolveLangDir file mLangDir)
  -- The gate runs first and hands back its realization, so compile writes the
  -- very output the contract judged (and the pipeline runs once, not twice).
  -- @--no-contract@ is the one caller that cannot gate (a compile inside a nix
  -- derivation has no nix to evaluate with); it still crystallizes and realizes.
  rl  <- checkLoose (not noContract) (not noContract) mLangDir file
  target  <- readRecordedTarget dir file
  let outDirPath = maybe (compiledPath file) id mout
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
    artNames <- case rlArtifact rl of
      Nothing            -> pure []
      Just (body, names) -> TIO.writeFile (outDirPath </> "artifact.nix") body >> pure names
    -- The experiments the program states, beside the artifacts they observe. A
    -- claim-free program writes no file and its output stays byte-identical.
    hasClaims' <- case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
      Nothing   -> pure False
      Just body -> TIO.writeFile (outDirPath </> "claims.nix") body >> pure True
    let rungs = Rungs { hasArtifacts = not (null artNames), hasClaims = hasClaims'
                      , siteRung = if not hasSite then Nothing
                                   else if null (rlClauseClaims rl) then Just SiteOnly
                                        else Just SiteWithClaims }
    TIO.writeFile (outDirPath </> "flake.nix") (flakeText target rungs)
    pure (artNames, rungs)
  say ("→ run it with nix over " <> T.pack outDirPath <> ":")
  mapM_ note (runCommands target artNames rungs outDirPath)

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

-- | The world an engine was minted for, read from its committed .generation
-- record (the @target:@ line). An engine minted before targets existed has no
-- record line and defaults to nixos, so old engines keep working -- but a record
-- that EXISTS and cannot be read is a loud failure, never the default world:
-- guessing here compiles a program into the wrong world's flake, and the whole
-- output still looks plausible (deduce-or-fail).
readRecordedTarget :: FilePath -> FilePath -> IO Target
readRecordedTarget dir file = do
  let path = generationPathIn dir file
  there <- doesPathExist path
  m <- tryRead path
  case (there, m) of
    (True, Nothing) -> die (report
      ("lips can't read the generation record at " <> T.pack path <> ",")
      ["so it cannot tell which world this engine was minted for."]
      "\8594 restore the file, or re-mint: lips generate <program>.")
    (_, Nothing) -> pure defaultTarget
    (_, Just src) -> pure $ case [ t | l <- T.lines src
                                     , Just rest <- [T.stripPrefix "target:" l]
                                     , Just t <- [parseTarget (T.unpack (T.strip rest))] ] of
      (t : _) -> t
      []      -> defaultTarget

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
checkLoose :: Bool -> Bool -> Maybe FilePath -> FilePath -> IO Realization
checkLoose contract claims mLangDir file = do
  dir     <- either die pure (resolveLangDir file mLangDir)
  program <- readProgramOrDie file
  eng     <- loadLangOrDie dir file
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
  rl <- expectGate contract claims dir file eng program
  -- What vouches for each assertion, always printed. An unvouched assertion
  -- (foreign text in an artifact argument, a staged source tree) is the one
  -- thing lips cannot check, so the count is stated on every run rather than
  -- discovered later by a reviewer reading generated code.
  mapM_ note (groundingReport (rlGrounding rl))
  -- A staged tree's size is the one thing the kernel cannot report: it is pure
  -- and owns no filesystem, so the path counts as one word while the file behind
  -- it may hold seventy lines nobody reviewed. The caller that stages measures.
  mapM_ note =<< stagedSizes dir file (rlGrounding rl)
  pure rl
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
  withTempDir $ \root -> case materializeDraft root file reply governing of
    Left errs -> die (validationReport file ("the draft cannot be read as an engine:\n"
                        <> T.unlines [ "  - " <> e | e <- errs ]))
    Right t   -> do
      createDirectoryIfMissing True (dtLangDir t)
      TIO.writeFile (langPathIn (dtLangDir t) file) (dtLang t)
      TIO.writeFile (expectPathIn (dtLangDir t) file) (dtExpect t)
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
          target <- draftTarget
          eng <- loadLangOrDie (dtLangDir t) file
          assertOptionsAdmissible target p file eng
        _ -> pure ()
      rl <- checkLoose True False (Just (dtLangDir t)) file
      target <- draftTargetOrDefault
      clauseClaimGate target file rl
      note "the command claim gate and the artifact build were NOT run"

-- | The draft's world where generate stated one, else the default. Used only
-- where a wrong guess is harmless (which flake shape a throwaway directory gets);
-- the schema gate keeps using 'draftTarget', which refuses to guess.
draftTargetOrDefault :: IO Target
draftTargetOrDefault = do
  mt <- lookupEnv "LIPS_MINT_TARGET"
  pure (maybe defaultTarget id (mt >>= parseTarget))

-- | Which world a draft is grounded against. Read from the environment generate
-- controls, never defaulted: a silent default would ground a mint against the
-- wrong world's schema and report the wrong names as missing.
draftTarget :: IO Target
draftTarget = do
  mt <- lookupEnv "LIPS_MINT_TARGET"
  case mt >>= parseTarget of
    Just t  -> pure t
    Nothing -> die (report
      "lips can't check this draft: the world it is minted for is not stated."
      ["LIPS_MINT_SCHEMA names a schema, but LIPS_MINT_TARGET is missing or not one of "
        <> T.intercalate ", " (map targetSlug [minBound .. maxBound]) <> "."]
      "\8594 this is generate's to set; report it as a lips bug.")

-- | The behavioral gate: the committed @.expect@ contract against the realized
-- module. Reached only after diagnostics confirm the program crystallizes.
-- Validates once, up front: the module, its artifacts and the paths it names
-- all come from that one run, so the staged-source gate below and the contract
-- judge the same realization.
expectGate :: Bool -> Bool -> FilePath -> FilePath -> EngineData -> Text -> IO Realization
expectGate contract claims dir file eng program = do
  rl <- either (die . printFail file) pure (validate file eng program)
  stagedGate (stageBeside dir file rl) file rl
  sourceSpecGate dir file eng program
  expSrc <- if contract then tryRead (expectPathIn dir file) else pure Nothing
  case expSrc of
    -- A skipped or absent contract is stated, never rendered as a pass: the
    -- step's own ✓ would otherwise claim a gate that did not run.
    Nothing | not contract ->
      note "contract skipped (--no-contract): nix is needed to evaluate it"
    Nothing  -> note ("no contract yet: " <> T.pack (expectPathIn dir file)
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
            Left (Violations fs) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))
  when claims $ do
    target <- readRecordedTarget dir file
    claimGate target dir file rl
  pure rl

-- | The claim gate: every observable the program states must actually hold.
--
-- This is the ONE gate that observes a running thing rather than reading the
-- module text, so it is what holds minted source -- and every future re-mint --
-- to the author's own words.
--
-- It builds the compiled directory's @#claims@ rung, which is the very command
-- @compile@ prints, so what CI runs and what an author runs cannot drift. A
-- sandbox claim is a plain build; a machine claim boots the module, so it needs
-- KVM, and without it the gate FAILS naming the remedy rather than skipping:
-- "not verified" must never render as verified.
--
-- Consequence, stated rather than hidden: for a claim-bearing program @check@
-- needs an ambient nixpkgs (the compiled flake resolves @flake:nixpkgs@, as it
-- does for every other rung). A claim-free program is untouched and @check@
-- stays nixpkgs-free for it.
claimGate :: Target -> FilePath -> FilePath -> Realization -> IO ()
claimGate target dir file rl =
  clauseClaimGate target file rl >> commandClaimGate dir file rl

-- | The clause claims, judged: one small derivation that evaluates the program's
-- own definitions with the runtime's list-backed adapters. No machine boots and
-- no binary is compiled, so this gate costs a fraction of the one below and can
-- observe a single definition rather than a whole process.
--
-- It is still a @nix build@, so a clause-claiming program's @check@ needs an
-- ambient nixpkgs exactly as a command-claiming one does. A program that states
-- no observable is untouched and its @check@ stays nixpkgs-free.
clauseClaimGate :: Target -> FilePath -> Realization -> IO ()
clauseClaimGate target file rl
  | null (rlClauseClaims rl) = pure ()
  | otherwise =
      step ("clause claims: " <> plural (length (rlClauseClaims rl)) "claim") $
        withTempDir $ \tmp -> do
          _ <- writeSite tmp rl
          TIO.writeFile (tmp </> "flake.nix")
            (flakeText target noRungs { siteRung = Just SiteWithClaims })
          res <- try (readProcessWithExitCode "nix"
            ["build", "--no-link", "path:" <> tmp <> "#site-claims"] "")
          case res of
            Left e -> die (nixMissing file "judge the clauses it states" "check"
                            (tshow (e :: IOException)))
            Right (ExitFailure _, _, err) -> die (report
              (T.pack file <> ": what the program says its behaviour does is not what it does.")
              (T.lines (T.pack err))
              ("\8594 the behaviour is clauses, so the program and its claims disagree:"
                <> " fix the sentence, or the claim that pins it."))
            Right (ExitSuccess, _, _) -> pure ()

commandClaimGate :: FilePath -> FilePath -> Realization -> IO ()
commandClaimGate dir file rl
  | null (rlClaims rl) = pure ()
  | otherwise = do
      let machine = [ clId c | c <- rlClaims rl, clPlace c == PlaceMachine ]
      kvm <- doesPathExist "/dev/kvm"
      when (not kvm && not (null machine)) $ die (report
        (T.pack file <> " states " <> plural (length machine) "claim"
          <> " that must be observed in a booted machine, and this host has no /dev/kvm.")
        machine
        ("\8594 run it where KVM exists, or state the observable over the program's"
          <> " own binary, which needs no machine."))
      target <- readRecordedTarget dir file
      step ("claims: " <> plural (length (rlClaims rl)) "claim") $ withTempDir $ \tmp -> do
        TIO.writeFile (tmp </> "default.nix") (rlModule rl)
        stageBeside dir file rl tmp
        fillStagedTree file (tmp </> "artifacts") (rlFills rl)
        artNames <- case rlArtifact rl of
          Nothing            -> pure []
          Just (body, names) -> TIO.writeFile (tmp </> "artifact.nix") body >> pure names
        case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
          Nothing   -> pure ()   -- unreachable: the claim list is non-empty here
          Just body -> TIO.writeFile (tmp </> "claims.nix") body
        TIO.writeFile (tmp </> "flake.nix")
          (flakeText target noRungs { hasArtifacts = not (null artNames), hasClaims = True })
        res <- try (readProcessWithExitCode "nix"
          ["build", "--no-link", "path:" <> tmp <> "#claims"] "")
        case res of
          Left e -> die (nixMissing file "run the claims it states" "check" (tshow (e :: IOException)))
          Right (ExitFailure _, _, err) -> die (report
            (T.pack file <> ": what the program says it does is not what it does.")
            (T.lines (T.pack err))
            ("\8594 the behaviour lives in minted source, so rebuild it from the"
              <> " program as it stands: lips generate " <> T.pack file))
          Right (ExitSuccess, _, _) -> pure ()

-- | Render the authoring diagnosis: a coverage headline, one line per program
-- line (matched to which pattern and subject, or unread, or ambiguous), then
-- the open questions. Pure view over 'diagnose'; a future editor paints the
-- same outcomes as squiggles.
renderDiagnosis :: FilePath -> Diagnosis -> Text
renderDiagnosis file d =
  T.intercalate "\n" (headline : map row (diagLines d)
                        ++ headBlock ++ inertBlock ++ restatedBlock ++ droppedBlock
                        ++ unfitBlock ++ openBlock)
  where
    headline = T.pack file <> ": " <> tshow (diagMatched d) <> " of "
                 <> tshow (diagTotal d) <> " lines crystallize."
    row (Matched n _ pid par decs) =
      "  line " <> tshow n <> "  ok        " <> pid <> "  "
        <> T.intercalate ", " (map (subjectPath . dSubject) decs)
        <> maybe "" (\b -> "  in the block at line " <> tshow b) par
    row (Unmatched n t) =
      "  line " <> tshow n <> "  no match  \"" <> t <> "\""
    row (Ambiguous n _ ids) =
      "  line " <> tshow n <> "  ambiguous " <> T.intercalate "," ids
    row (Orphan n _ qs) =
      "  line " <> tshow n <> "  no block  needs a line above it matching "
        <> T.intercalate " or " qs
    row (Illegible n _ why) =
      "  line " <> tshow n <> "  unreadable  " <> why
    -- A line the language reads and then drops realizes nothing, so editing it
    -- changes nothing. Naming it is the point: a heading is legitimately
    -- decorative, but so is a line the mint quietly declined to honor, and only
    -- the author can tell which this is.
    -- A line that opens a block realizes nothing itself, but the lines inside it
    -- carry its words, so it is not decoration and must not be listed as such.
    headBlock
      | null (diagHeads d) = []
      | otherwise =
          "" : ("opens a block (" <> tshow (length (diagHeads d))
                  <> ") -- realizes nothing itself; the lines inside it do:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  (" <> tshow k
                    <> (if k == 1 then " line" else " lines") <> " inside)"
                | (n, t, k) <- diagHeads d ]
    inertBlock
      | null (diagInert d) = []
      | otherwise =
          "" : ("decorative, realizing nothing (" <> tshow (length (diagInert d))
                  <> ") -- editing these changes no output:")
              : ["  line " <> tshow n <> "  \"" <> t <> "\"" | (n, t) <- diagInert d]
    -- A line whose fact an earlier line already stated: it merges away, so it
    -- produces nothing of its own and editing it changes no output. Two
    -- statements of one fact are one fact, so this is reported, never refused.
    restatedBlock
      | null (diagRestated d) = []
      | otherwise =
          "" : ("already stated (" <> tshow (length (diagRestated d))
                  <> ") -- these lines add nothing to an earlier line:")
              : [ "  line " <> tshow n <> "  repeats line " <> tshow earlier
                    <> "  (" <> subj <> ")"
                | (n, earlier, subj) <- diagRestated d ]
    -- A word the language binds and no rule carries: the line looks
    -- load-bearing and is not, so editing that word changes nothing. The gate
    -- refuses such an engine now; this names it for engines committed earlier.
    droppedBlock
      | null (diagDropped d) = []
      | otherwise =
          "" : ("read and discarded (" <> tshow (length (diagDropped d))
                  <> ") -- these words reach no output:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  <"
                    <> T.intercalate "> <" hs <> ">"
                | (n, t, hs) <- diagDropped d ]
    -- A word the rule spending it cannot take. Refine refuses it a phase later
    -- naming a decision id; here it is named on the line the author wrote, which
    -- is the only place they can fix it.
    unfitBlock
      | null (diagUnfit d) = []
      | otherwise =
          "" : ("does not fit (" <> tshow (length (diagUnfit d))
                  <> ") -- these values are not what the option takes:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  " <> why
                | (n, t, whys) <- diagUnfit d, why <- whys ]
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
generate :: Target -> Maybe String -> Double -> Bool -> Bool -> Maybe String -> String -> [FilePath] -> IO ()
-- Unreachable: Lips.Cli.generateOpts's `some` guarantees at least one file by
-- construction. Kept only so this function stays total (-Wall incomplete-patterns).
generate _ _ _ _ _ _ _ [] = die "lips generate needs at least one program (unreachable: the CLI parser requires one)."
generate target mschema confidence renew verbose mmodel thinking files@(rep : _) = do
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
      corpus = corpusText progs
  -- Resolve the grounding schema BEFORE the model runs: it is an input of the
  -- generation event (it decides which rules are admissible), it is recorded as
  -- such, and a schema that cannot be built must not cost an AI call first.
  (schemaPath, schemaPin) <- ensureOptionSchema target mschema ("generate " <> T.pack rep)
  -- The mint's validation tool judges a draft against the contract that will
  -- actually gate it: the committed .expect on a regeneration, the draft's own
  -- minted expects on a first mint or under --renew. That rule is generate's
  -- (it is read again below, where the gate itself uses it), so the tool is
  -- told the answer instead of re-deriving it and drifting into a false green.
  committedExpectPath <- if renew
    then pure Nothing
    else do
      there <- doesFileExist (expectPath rep)
      pure (if there then Just (expectPath rep) else Nothing)
  (reply, model, transcript) <-
    step ("mint ." <> T.pack lang <> " from " <> plural (length files) "program") $
      callPi verbose mmodel thinking prompt corpus target files committedExpectPath schemaPath
  note ("minted by " <> model <> ", thinking " <> T.pack thinking)
  -- --verbose: echo the model's raw reply verbatim before parsing, so the
  -- whole minted engine is inspectable even when it validates cleanly (a
  -- refusal already shows the offending lines).
  when verbose $ say (T.unlines
    [ "--- raw model reply (" <> model <> ") ---", reply, "--- end reply ---" ])
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
    then do
      -- Machine-readable twin of the on-screen refusal: the cross-repo
      -- escalation workflow (DESIGN Doctrine) needs a shippable artifact, not
      -- only text that scrolls off a terminal. Same fields, same fingerprint
      -- scheme as a successful '.generation' record (built the same way, from
      -- the same in-scope values), so a refusal is pinned exactly as an
      -- acceptance would have been.
      let rec = record model target schemaPin (T.pack thinking) confidence prompt corpus transcript reply
      -- The refusal is the first thing written for a language, so its directory
      -- (<language>/, home of .lang/.expect/.generation) need not exist yet.
      createDirectoryIfMissing True (langDir rep)
      TIO.writeFile (gapPath rep) (gapArtifact rec errs unsure gaps)
      die (refusalReport rep (gapPath rep) confidence errs unsure notes gaps)
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
      assertOptionsAdmissible target schemaPath rep eng
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
      -- throughout. The cost of refusing is one sentence from the author, which
      -- the message names. A pure-configuration mint is unaffected, and so is an
      -- engine whose behaviour is clauses with a claim over them.
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
        ("\8594 state an example in the program -- what it is given and what it"
          <> " prints -- and mint again: lips generate " <> T.pack rep))
      case unplaceableClaims target allClaims of
        []  -> pure ()
        ids -> die (report
          (T.pack rep <> ": " <> plural (length ids) "claim"
            <> " must be observed in a booted machine, and the " <> targetSlug target
            <> " world has none.")
          ids
          ("\8594 state the observable over the program's own binary, which needs no"
            <> " machine, and mint again: lips generate " <> T.pack rep))
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
          Left (Violations fs) -> die (report
            ("lips built a setup for " <> T.pack f <> ", but it doesn't produce what the program promises:")
            fs
            ("→ run generate again. If you changed the program on purpose, accept "
              <> "the new behavior: lips generate --renew " <> T.pack rep
              <> " (rewrites " <> T.pack (expectPath rep) <> ")."))
          Right () -> pure ()
      -- Last gate, and the only one that observes rather than reads: build each
      -- artifact and look inside it. Deliberately after the cheap gates, so a
      -- mint that fails for a readable reason never pays a build.
      when (any (isJust . rlArtifact . snd) validated) $ do
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
      forM_ validated $ \(f, rl) -> clauseClaimGate target f rl
      when (not (null allClaims)) $ do
        nixpkgs <- artifactNixpkgs ("generate " <> T.pack rep)
        forM_ validated $ \(f, rl) ->
          mintClaimGate nixpkgs (\root -> writeSources (root </> "artifacts") minted
                                           >> void (writeSite root rl)) f rl
      -- All held: write the shared language once, a crystal per instance. Every
      -- engine line is stamped with the content id of the .generation record,
      -- checkable by re-hashing it.
      let rec = record model target schemaPin (T.pack thinking) confidence prompt corpus transcript reply
      step ("write " <> T.pack (langDir rep)) $ do
        -- The language folder holds every minted and derived file; create it (and
        -- its derived out/ subtree) before writing, so a first mint beside a bare
        -- program just works.
        createDirectoryIfMissing True (langDir rep)
        TIO.writeFile (langPath rep) (renderLang (FromGeneration (genId rec)) eng)
        TIO.writeFile (generationPath rep) rec
        TIO.writeFile (readmePath rep) (renderReadme (T.pack lang) reportBody gaps)
        -- A refusal artifact describes a run that produced no engine, so it is a
        -- lie once one exists: the accepted mint deletes the .gap an earlier
        -- refused attempt left behind.
        removePathForcibly (gapPath rep)
        -- The artifacts tree is machine-owned and minted whole, so REPLACE it: a
        -- previous mint's tree under another artifact name would otherwise stay
        -- committed forever, dead source nothing builds (the http re-mint left a
        -- helloserver/ tree beside its new hello/ one).
        removePathForcibly (artifactsPath rep)
        writeSources (artifactsPath rep) minted
        forM_ validated $ \(f, rl) -> do
          ensureDerived f
          TIO.writeFile (decisionsPath f) (renderBase (rlBase rl))
        -- Bootstrap the contract on first generation only; keep the committed
        -- spec stable across regenerations.
        maybe (TIO.writeFile (expectPath rep) (renderExpect mintedExpects))
              (const (pure ())) committed
        mapM_ note $
          [ T.pack (langPath rep) <> "  the language, " <> plural (length (edPatterns eng)) "pattern"
              <> ", " <> plural (length (edRules eng)) "rule"
          , T.pack (expectPath rep) <> "  the contract, " <> plural (length expects) "check"
          , T.pack (readmePath rep) <> "  what the language means, in plain words"
          , T.pack (generationPath rep) <> "  how it was made" ]
          ++ [ T.pack (artifactsPath rep) <> "  " <> plural (length minted) "source file"
             | not (null minted) ]
      -- The account of the mint, in the mint's own words: the first lines of the
      -- report, then where to read the rest. Not the engine and not the module --
      -- both are files now, and a human reads them there.
      say ""
      say ("✓ ." <> T.pack lang <> " holds for " <> plural (length files) "program"
             <> " as a " <> targetSlug target <> " configuration.")
      say ""
      mapM_ say (take 5 [ l | l <- T.lines (T.strip reportBody), not (T.null (T.strip l)) ])
      unless (null gaps) $ do
        say ""
        say ("lips could not do these, and says why in " <> T.pack (readmePath rep) <> ":")
        mapM_ (\g -> note ("- " <> gapSlug g)) gaps

      say ""
      say ("→ read the whole account: " <> T.pack (readmePath rep))
      mapM_ (\(f, _) -> say ("→ build it:              lips compile " <> T.pack f)) validated

-- | @options@: look a query up in the target world's pinned option schema and
-- print the answer. This verb is both a human's lookup and the target of the
-- mint's lookup tool (@query_options@), so what a human reads here is exactly what
-- the model is told -- there is no second, model-facing renderer to drift.
--
-- It never calls a model (invariant 1 holds trivially: no model runs anywhere
-- but generate) and it never writes anything.
optionsQuery :: Target -> Maybe String -> Int -> Text -> IO ()
optionsQuery target mschema limit query = do
  -- The pin is discarded here: a lookup records nothing. Only generate, which
  -- commits an engine, has a record to name it in.
  (schemaPath, _) <- ensureOptionSchema target mschema ("options " <> query)
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  bytes <- case mbytes of
    Left e -> die (report
      ("lips can't read the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run it again.")
    Right b -> pure b
  case schemaFor target bytes of
    Left why -> die (report
      ("lips can't parse the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [why]
      "→ run it again.")
    -- Exit 0 even for Nowhere: "no option matches that" is a valid answer to a
    -- question, not a failure of the command.
    Right schema -> sayAnswer (renderAnswer query (answerQuery limit query schema))

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
  -- The honest answer for a free-form region: the path is admissible (the same
  -- schema's gate accepts it), and the schema knows nothing about it. Saying
  -- "no option matches" here would call a legal path a typo; saying only "fine"
  -- would sell an unchecked name as confirmed.
  Freeform anc t -> T.unlines
    [ query <> " is below " <> dotted anc <> " : " <> renderOptionType t
    , "That option is free-form: every path under it is accepted, and none of"
    , "them is checked -- this schema cannot confirm the name " <> query <> "."
    , "Emit it only from documentation you actually have; otherwise refuse."
    ]
  Nowhere -> T.unlines
    [ "no option matches " <> query
    , "Try a shorter query, or a different word for the same thing."
    ]

-- | @3 options@ but @1 option@: a count a reader trips over is a count they
-- reread instead of acting on.
plural :: Int -> Text -> Text
plural n word = tshow n <> " " <> word <> (if n == 1 then "" else "s")

-- | One voice for the defect, whether it is caught at the mint gate or found in
-- an engine already committed: the wording lives with the gate
-- ('Lips.Kernel.Engine.Gate'), this only wraps it in the generate-time action.
unanswerableReport :: FilePath -> [UnanswerableDemand] -> Text
unanswerableReport file = validationReport file . unanswerableProblem

-- | Deduce-or-fail: every minted rule must fill a real, correctly typed NixOS
-- option. The schema document is located ONCE per run by 'ensureOptionSchema'
-- and handed in, so the schema this gate judges against is the very one the
-- record names -- a second resolution could disagree with it. An unreadable
-- schema fails loud: an unverifiable engine is not written.
-- The check is domain-blind: 'checkEmits' takes a typed schema, and the NixOS
-- specifics live in 'Lips.Nix.Options'.
assertOptionsAdmissible :: Target -> FilePath -> FilePath -> EngineData -> IO ()
assertOptionsAdmissible target schemaPath file eng = do
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  case mbytes of
    Left e -> die (report
      ("lips can't read the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run generate again.")
    Right bytes -> case schemaFor target bytes of
      Left why -> die (report
        ("lips can't parse the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
        [why]
        "→ run generate again.")
      Right schema -> case checkEmits schema (edRules eng) of
        []   -> pure ()
        errs -> die (validationReport file
          ("its rules use " <> targetSlug target <> " options that don't exist or have the wrong type:\n"
            <> T.unlines (map (("  - " <>) . renderOptionError) errs)))

-- | Locate the target world's @options.json@, and say WHICH schema that is:
-- the returned pin is what @.generation@ records, so grounding stops being
-- invisible after the mint.
--
-- Precedence is by explicitness. @--schema \<flakeref\>@ (a caller whose own
-- world is not the one lips was built against) beats @LIPS_OPTIONS_JSON@ (a
-- prebuilt document: the suite's offline fixture), which beats the flakeref
-- baked into the packaged binary -- the zero-configuration default, so nobody
-- has to author a pin to run generate at all.
--
-- A flakeref is resolved through @nix flake metadata@ and both BUILT and
-- RECORDED as the locked url nix reports, so the pin cannot float: recording
-- @nixpkgs@ or a branch name would name a different schema every week and the
-- record would lie about what admitted the rules. A supplied document has no
-- ref, so it is pinned by content instead ('genId' over its bytes).
--
-- The build is announced, since the first one evaluates the whole NixOS manual
-- (~11 MB) before nix caches it; every later generate is a store cache hit. Only
-- generate and the read-only @options@ lookup pay this -- compile\/check never
-- touch the schema.
--
-- @remedy@ is the invocation to suggest when the schema cannot be had; it is a
-- parameter because this function serves two verbs and knows about neither.
ensureOptionSchema :: Target -> Maybe String -> Text -> IO (FilePath, Text)
ensureOptionSchema target (Just ref) remedy = do
  locked <- lockFlakeRef ref remedy
  path <- buildOptionSchema target locked remedy
  pure (path, locked)
ensureOptionSchema target Nothing remedy = do
  override <- lookupEnv "LIPS_OPTIONS_JSON"
  case override of
    -- Pinned by content: a path names a file that changes, so the record would
    -- say nothing checkable. The hash is the same function the record's own id
    -- uses, so one hash function serves the whole provenance story.
    Just p  -> do
      mbytes <- try (BS.readFile p) :: IO (Either IOException BS.ByteString)
      case mbytes of
        Left e -> die (report
          ("lips can't read the option schema at " <> T.pack p <> " (LIPS_OPTIONS_JSON):")
          [tshow e]
          ("→ point LIPS_OPTIONS_JSON at a readable options.json, or unset it: " <> remedy))
        Right bytes -> pure (p, "options-json:" <> hashBytes bytes)
    Nothing -> do
      -- The world's own env var, set by the packaged binary from lips's flake
      -- lock. Unset means no schema source is configured at all.
      mflake <- lookupEnv (bakedPinVar target)
      case mflake of
        Nothing -> die (report
          ("lips can't read the setup's options: no " <> targetSlug target <> " option schema source is configured.")
          ["none of --schema, LIPS_OPTIONS_JSON or " <> T.pack (bakedPinVar target) <> " is set."]
          ("→ run the packaged lips: nix run . -- " <> remedy <> " (it bakes the pinned flakes)."))
        Just flakeref -> do
          locked <- lockFlakeRef flakeref remedy
          path <- buildOptionSchema target locked remedy
          pure (path, locked)

-- | The env var carrying the flakeref baked into the packaged binary for one
-- world. Per world, because each world's schema comes from its own flake.
bakedPinVar :: Target -> String
bakedPinVar Nixos       = "LIPS_NIXPKGS_FLAKE"
bakedPinVar HomeManager = "LIPS_HM_FLAKE"
bakedPinVar Kubenix     = "LIPS_KUBENIX_FLAKE"
bakedPinVar Terranix    = "LIPS_TERRANIX_FLAKE"

-- | Resolve any flakeref to the LOCKED url nix reports for it, which is then
-- both built and recorded. Asking nix (rather than inspecting the ref's shape)
-- keeps one authority for what a ref locks to: @flake:nixpkgs@, a branch, a
-- @path:@ working tree and an already-pinned @github:owner\/repo\/\<rev\>@ all
-- come back naming fixed content.
lockFlakeRef :: String -> Text -> IO Text
lockFlakeRef ref remedy = do
  res <- try (readProcessWithExitCode "nix" ["flake", "metadata", "--json", ref] "")
  case res of
    Left e -> die (report
      "lips needs nix to resolve the option schema's flake, but couldn't run it:"
      (T.lines (tshow (e :: IOException)))
      ("→ install nix, or run lips through it: nix run . -- " <> remedy))
    Right (ExitFailure _, _, err) -> die (report
      ("lips can't resolve the option schema's flake " <> T.pack ref <> ":")
      (T.lines (T.pack err))
      "→ pass a flakeref nix can fetch, e.g. --schema github:NixOS/nixpkgs/nixos-24.11.")
    Right (ExitSuccess, out, _) -> case lockedUrl (BLC.pack out) of
      Just u  -> pure u
      -- Deduce-or-fail: without the locked url the record could only name the
      -- ref the caller typed, which may float. Refuse rather than record that.
      Nothing -> die (report
        ("lips can't tell what " <> T.pack ref <> " locks to: nix reported no locked url.")
        []
        "→ update nix, or pass an already-pinned ref (github:owner/repo/<rev>).")

-- | The @url@ field of @nix flake metadata --json@: nix's own locked form of the
-- ref it was given.
lockedUrl :: BL.ByteString -> Maybe Text
lockedUrl bytes = do
  Object o <- decode bytes
  String u <- KM.lookup "url" o
  pure u

-- | Build one world's optionsJSON from a locked flakeref and return the path of
-- the document inside it.
buildOptionSchema :: Target -> Text -> Text -> IO FilePath
buildOptionSchema target locked remedy = step (targetSlug target <> " option schema") $ do
  -- The pin without nix's hash query, which is half a line of noise a reader
  -- never types back in.
  note ("pinned flake " <> T.takeWhile (/= '?') locked)
  -- On the live line, not as a note: a cache hit takes a second, and a warning
  -- about minutes that stays on screen afterwards is a line that misinforms.
  setState "a cache miss evaluates the whole manual, which takes minutes"
  built <- try (readProcessWithExitCode "nix"
    [ "build", "--impure", "--no-link", "--print-out-paths"
    , "--expr", T.unpack (schemaExpr target (T.unpack locked)) ] "")
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
      pure (T.unpack (T.strip (T.pack out)) <> schemaSubPath target)

-- | Where the options document sits inside the built derivation. The JSON shape
-- is identical across worlds (all are nixosOptionsDoc output); only the path
-- differs -- and kubenix and terranix, whose documents lips builds itself with
-- nixosOptionsDoc, inherit that helper's NixOS default path.
schemaSubPath :: Target -> FilePath
schemaSubPath Nixos       = "/share/doc/nixos/options.json"
schemaSubPath HomeManager = "/share/doc/home-manager/options.json"
schemaSubPath Kubenix     = "/share/doc/nixos/options.json"
schemaSubPath Terranix    = "/share/doc/nixos/options.json"

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
-- kubenix declares its Kubernetes resource fields as module options generated
-- from the Kubernetes API, so the document comes from nixosOptionsDoc over an
-- otherwise EMPTY kubenix evaluation: the option TREE is what grounds a rule,
-- and no program's own values may enter the schema.
-- nixpkgs comes from the kubenix flake's OWN pinned input, never resolved
-- ambiently: a grounding schema must be reproducible from the recorded ref
-- alone.
schemaExpr Kubenix flakeref = T.pack $ concat
  [ "let k = builtins.getFlake \"", flakeref, "\"; "
  , "system = builtins.currentSystem; "
  , "pkgs = import k.inputs.nixpkgs { inherit system; }; "
  , "e = k.evalModules.${system} { module = { kubenix, ... }: "
  , "{ imports = [ kubenix.modules.k8s ]; }; }; in "
  , "(pkgs.nixosOptionsDoc { options = e.options; warningsAreErrors = false; }).optionsJSON" ]
-- terranix publishes @lib.terranixOptions@, but that helper documents the
-- USER's modules: its jq pass deletes resource, data, provider, output and
-- every other core namespace, which are exactly the paths a program writes. So
-- lips evaluates terranix's own core modules and runs nixosOptionsDoc over
-- them, the same mechanism the other worlds use. The lib.extend mirrors
-- terranix's core/default.nix, whose modules use those lib helpers.
schemaExpr Terranix flakeref = T.pack $ concat
  [ "let t = builtins.getFlake \"", flakeref, "\"; "
  , "system = builtins.currentSystem; "
  , "pkgs = import t.inputs.nixpkgs { inherit system; }; "
  , "lib = pkgs.lib.extend (import (t + \"/core/helpers.nix\") pkgs); "
  , "e = lib.evalModules { modules = [ "
  , "{ imports = [ (t + \"/core/terraform-options.nix\") (t + \"/modules\") ]; } "
  , "{ _module.args = { inherit pkgs; }; } ]; }; in "
  , "(pkgs.nixosOptionsDoc { options = e.options; warningsAreErrors = false; }).optionsJSON" ]

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
callPi :: Bool -> Maybe String -> String -> Text -> Text -> Target -> [FilePath] -> Maybe FilePath -> FilePath -> IO (Text, Text, Text)
callPi verbose mmodel thinking system userPrompt target files mExpect schemaPath = do
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
  let ours = [ ("LIPS_MINT_TARGET",   T.unpack (targetSlug target))
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

-- | Evaluate the realized module with @nix@ and judge a contract against it.
-- One eval reads every asserted option; the pure comparison lives in
-- 'Lips.Kernel.Expect'. An empty contract passes trivially.
-- | Three outcomes of the behavioral check, kept apart so the CLI gives the
-- right action: install nix (tool missing), fix the environment (eval failed),
-- or the config doesn't carry the promised values (violations).
data ExpectFail = ToolMissing Text | EvalFailed Text | Violations [Text]

runExpects :: (FilePath -> IO ()) -> [Expect] -> Realization -> IO (Either ExpectFail ())
runExpects _     []       _  = pure (Right ())
runExpects stage expects0 rl =
  -- Expand any value-keyed family expect against this program's routes first,
  -- so a shared contract (route.<path>.status) checks every concrete route.
  case expandExpects base expects0 >>= \expects ->
         (,) expects <$> traverse (expectedValue base) expects of
    Left e            -> pure (Left (Violations ["lips can't match a check to the program: " <> e]))
    Right (expects, pvs) -> do
      -- Two kinds of assertion, judged where their value actually lives: a
      -- module option is read by evaluating the module, an artifact arg is a
      -- literal in the ground base (a builder consumes it, so it is no attribute
      -- of the derivation and no eval could reach it).
      let (artExpects, optExpects) = partition (isGroundExpect . fst) (zip expects pvs)
          artFails = checkArtifactValues (rlGround rl) artExpects
      optRes <- evalOptionExpects stage (rlModule rl) optExpects
      pure $ case (artFails, optRes) of
        ([], r)      -> r
        (fs, Right ()) -> Left (Violations fs)
        (fs, Left (Violations more)) -> Left (Violations (fs ++ more))
        (_,  Left other) -> Left other
  where
    base = rlBase rl

-- | The nix half of the gate: evaluate the realized module once and judge every
-- option assertion against it.
evalOptionExpects :: (FilePath -> IO ()) -> Text -> [(Expect, Text)] -> IO (Either ExpectFail ())
evalOptionExpects _     _         []    = pure (Right ())
evalOptionExpects stage nixModule pairs = withTempDir $ \dir -> do
      let expects = map fst pairs
          pvs     = map snd pairs
          tmp     = dir <> "/module.nix"
      TIO.writeFile tmp nixModule
      -- The module may name things BESIDE it: a staged source tree, and the site
      -- its own clauses build. So the callback stages the whole neighbourhood
      -- rather than one subdirectory of it; a module referencing ./site/build.nix
      -- in a directory nobody wrote it into dies inside nix, naming no remedy.
      stage dir
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

-- | A fresh temporary directory. lips writes a module and its staged
-- @artifacts/@ tree here so a relative @src = ./artifacts/<name>@ resolves at
-- evaluation. (Left in place, matching the module temp files elsewhere.)
withTempDir :: (FilePath -> IO a) -> IO a
withTempDir act = do
  tmp <- getTemporaryDirectory
  dir <- mkdtemp (tmp </> "lips-")
  -- Removed even when the action dies (exitFailure throws), so a failing check
  -- does not leave a scratch tree behind on every run.
  act dir `finally` removeDirectoryRecursive dir

-- | Write minted source files under @<root>/<artifact>/<relpath>@. Used to
-- persist to the language folder's @artifacts/@ and to stage into a temp
-- module dir.
writeSources :: FilePath -> [SourceFile] -> IO ()
writeSources root = mapM_ one
  where
    one sf = do
      let p = root </> T.unpack (sfArtifact sf) </> T.unpack (sfPath sf)
      createDirectoryIfMissing True (takeDirectory p)
      TIO.writeFile p (sfContent sf)

-- | The staged-source gate: every relative path the realized module names must
-- exist in the tree lips stages beside it (an artifact's minted source).
-- Without it such a path reaches nix, which fails with @path '...' does not
-- exist@ over a store path, naming neither lips, the program, the artifact nor
-- a remedy -- and only at the user's @nix run@ for a program lips does not build
-- (the artifact gate below builds every artifact a mint declares, but this gate
-- runs on the cheap path too). Checked against a real staging into a temp dir,
-- not against a guess at how a path maps to the language folder, so the gate
-- sees exactly what nix will see.
--
-- A path filled from a program word (@src ./artifacts/\<name\>@) is how this
-- fails in practice: the staged tree exists under the ONE name that was minted,
-- so renaming the command in the program leaves the path pointing at nothing.
-- Hence the remedy is regeneration: the source tree is minted, never edited.
stagedGate :: (FilePath -> IO ()) -> FilePath -> Realization -> IO ()
stagedGate stage file rl
  | null staged && null (rlFills rl) = pure ()
  | otherwise = withTempDir $ \dir -> do
  stage dir
  -- The same fill compile performs, so a fill defect (a value no source names, a
  -- marker no engine declares) is refused here rather than shipping @marker@
  -- verbatim into a compiled program.
  fillStagedTree file (dir </> "artifacts") (rlFills rl)
  missing <- filterM (fmap not . doesPathExist . (dir </>) . T.unpack . fst) staged
  case missing of
    [] -> pure ()
    ms -> die (report
      (T.pack file <> " names " <> plural (length ms) "file" <> " that lips never staged:")
      [ p <> " (named by " <> niceSubject (dSubject d) <> ")" | (p, d) <- ms ]
      ("→ the source tree is minted, so rebuild it: lips generate " <> T.pack file))
  where staged = rlStaged rl

-- | The build gate: every artifact the engine declares must BUILD, and every
-- path the output names inside one must really be there.
--
-- Why observation and not a static check: what a build CONTAINS is decided by
-- the source, and a binary's name is spelled in a @go.mod@ or a @Cargo.toml@,
-- never in the derivation. So an engine emitting
-- @ExecStart = "${artifact.hello}\/bin\/hello"@ beside a @go.mod@ saying
-- @module server@ is well-formed everywhere lips can read: it passed the mint
-- gate, @check@, and the artifact EVAL check, and shipped a unit that cannot
-- start -- twice. Knowing the answer requires looking inside the result, and
-- teaching lips what each builder names its output would be an open list the
-- kernel enumerates (the doctrine forbids it).
--
-- Why in @generate@ only: it is the one verb that is already online and already
-- builds a pinned nixpkgs, so the cost is a build it can afford. @compile@ stays
-- offline and nixpkgs-free always; @check@ does too EXCEPT for a program that
-- states observables, which it must build something to observe (an artifact for a
-- command claim, a small derivation for a clause claim). Stated where the rule
-- is, so nobody reads "offline" as a promise the claim gates cannot keep.
artifactGate :: Text -> (FilePath -> IO ()) -> FilePath -> Realization -> IO ()
artifactGate nixpkgs stage file rl = case rlArtifact rl of
  Nothing            -> pure ()
  Just (body, names) -> step ("build " <> plural (length names) "artifact") $ withTempDir $ \dir -> do
    -- The build reads the tree exactly as compile writes it: artifact.nix beside
    -- a staged, FILLED artifacts/ tree, so `src = ./artifacts/<name>` resolves.
    TIO.writeFile (dir </> "artifact.nix") body
    -- The whole neighbourhood, since an artifact's own argument may name the
    -- site: a wrapper renaming the program is exactly that shape.
    stage dir
    fillStagedTree file (dir </> "artifacts") (rlFills rl)
    note ("looking inside " <> T.intercalate ", " names)
    built <- forM names (\n -> (,) n <$> buildArtifact nixpkgs file dir n)
    -- A path whose artifact did not build is unreachable: the build above dies
    -- first, so every name here has an output path.
    missing <- filterM (fmap not . doesPathExist . inside built) (rlArtPaths rl)
    case missing of
      [] -> pure ()
      ms -> die (report
        (T.pack file <> ": the output names " <> plural (length ms) "path"
          <> " inside a build that does not contain it:")
        [ "${artifact." <> n <> "}" <> p <> " (named by " <> niceSubject (dSubject d)
            <> "), built as " <> maybe "?" T.pack (lookup n built)
        | (n, p, d) <- ms ]
        ("\8594 the name in that path is decided by the source lips minted, not by"
          <> " the build, so both are rebuilt together: lips generate " <> T.pack file))
  where
    inside built (n, p, _) = maybe "" id (lookup n built) <> T.unpack p

-- | The mint-time claim gate: every observable the mint stated must actually
-- hold, before the engine is written.
--
-- Twin of 'artifactGate' one step further out: that one asks whether the build
-- CONTAINS what the output names, this one asks whether the built thing DOES
-- what the author said. Both are observations, so both live in @generate@ -- the
-- one verb that is already online and already builds a pinned nixpkgs.
--
-- Built against that same pin, so the mint observes the world it was grounded
-- against. A machine claim boots the module and so needs KVM; without it the
-- mint REFUSES rather than admitting an engine whose claims never ran.
mintClaimGate :: Text -> (FilePath -> IO ()) -> FilePath -> Realization -> IO ()
mintClaimGate nixpkgs stage file rl
  | null (rlClaims rl) = pure ()
  | otherwise = do
      let machine = [ clId c | c <- rlClaims rl, clPlace c == PlaceMachine ]
      kvm <- doesPathExist "/dev/kvm"
      when (not kvm && not (null machine)) $ die (report
        (T.pack file <> " states " <> plural (length machine) "claim"
          <> " that must be observed in a booted machine, and this host has no /dev/kvm.")
        machine
        ("\8594 mint where KVM exists: an engine whose claims lips cannot run is an"
          <> " engine lips cannot vouch for, so it is not written."))
      step ("claims: " <> plural (length (rlClaims rl)) "claim") $ withTempDir $ \dir -> do
        TIO.writeFile (dir </> "default.nix") (rlModule rl)
        -- The whole neighbourhood: the module, its claims file, or an artifact
        -- argument may all name the site.
        stage dir
        fillStagedTree file (dir </> "artifacts") (rlFills rl)
        artNames <- case rlArtifact rl of
          Nothing            -> pure []
          Just (body, names) -> TIO.writeFile (dir </> "artifact.nix") body >> pure names
        case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
          Nothing   -> pure ()   -- unreachable: the claim list is non-empty here
          Just body -> TIO.writeFile (dir </> "claims.nix") body
        note ("observing " <> T.intercalate ", " (map clId (rlClaims rl)))
        forM_ (rlClaims rl) (buildClaim nixpkgs file dir)

-- | Run ONE claim out of a staged @claims.nix@. A failure is the claim's own
-- verdict (the comparison raises inside the build), surfaced verbatim so the
-- author reads what was observed against what they stated.
buildClaim :: Text -> FilePath -> FilePath -> Claim -> IO ()
buildClaim nixpkgs file dir c = do
  res <- try (readProcessWithExitCode "nix"
    [ "build", "--impure", "--no-link", "--print-out-paths", "--expr", T.unpack expr ] "")
  case res of
    Left e -> die (nixMissing file "run the claim it stated" "generate" (tshow (e :: IOException)))
    Right (ExitFailure _, _, err) -> die (report
      (T.pack file <> ": the setup lips minted does not do what the program says.")
      (T.lines (T.pack err))
      ("\8594 the behaviour lives in the source lips minted, so both are rebuilt"
        <> " together: lips generate " <> T.pack file))
    Right (ExitSuccess, _, _) -> pure ()
  where
    -- The claim id is identifier text, so it is indexed as a quoted key, exactly
    -- as an artifact name is (a '-' is legal in an attribute name but not in a
    -- dotted selection).
    expr = T.pack (concat
      [ "let np = builtins.getFlake \"", T.unpack nixpkgs, "\"; "
      , "pkgs = import np { system = builtins.currentSystem; }; in "
      , "(import ", show (dir </> "claims.nix"), " { inherit pkgs; })"
      , ".${", show (T.unpack (clId c)), "}" ])

-- | Build ONE artifact out of a staged @artifact.nix@ and return its output
-- path. Built against the pinned nixpkgs the generation records, so the gate
-- observes the same world the mint was grounded against; @--impure@ covers
-- @builtins.currentSystem@, exactly as the schema build does.
buildArtifact :: Text -> FilePath -> FilePath -> Text -> IO FilePath
buildArtifact nixpkgs file dir name = do
  res <- try (readProcessWithExitCode "nix"
    [ "build", "--impure", "--no-link", "--print-out-paths", "--expr", T.unpack expr ] "")
  case res of
    Left e -> die (nixMissing file "build the artifact it wrote" "generate" (tshow (e :: IOException)))
    Right (ExitFailure _, _, err) -> die (report
      (T.pack file <> ": the artifact " <> name <> " lips wrote does not build.")
      (T.lines (T.pack err))
      ("\8594 the build and its source are minted together, so rebuild both:"
        <> " lips generate " <> T.pack file))
    Right (ExitSuccess, out, _) -> pure (T.unpack (T.strip (T.pack out)))
  where
    -- The artifact name is identifier text (letters, digits, - and _), so it is
    -- indexed as a quoted key: a '-' is legal in an attribute name but not in a
    -- dotted selection.
    expr = T.pack (concat
      [ "let np = builtins.getFlake \"", T.unpack nixpkgs, "\"; "
      , "pkgs = import np { system = builtins.currentSystem; }; in "
      , "(import ", show (dir </> "artifact.nix"), " { inherit pkgs; })"
      , ".${", show (T.unpack name), "}" ])

-- | The nixpkgs the artifact build runs against: lips's own baked pin, locked.
-- One authority for every world, because BUILDERS live in nixpkgs, while a
-- world's schema pin may name home-manager, kubenix or terranix -- or no flake
-- at all (@LIPS_OPTIONS_JSON@ pins by content). Resolved only when a mint
-- actually declares an artifact, so a configuration-only mint needs none.
artifactNixpkgs :: Text -> IO Text
artifactNixpkgs remedy = do
  mflake <- lookupEnv "LIPS_NIXPKGS_FLAKE"
  case mflake of
    Just ref -> lockFlakeRef ref remedy
    -- Deduce-or-fail: an artifact lips cannot build is an artifact lips cannot
    -- vouch for, and "not verified" must never ship as verified.
    Nothing  -> die (report
      "lips can't build the artifact it minted: no nixpkgs is pinned."
      ["LIPS_NIXPKGS_FLAKE is unset, so there is no nixpkgs to build against."]
      ("\8594 run the packaged lips: nix run . -- " <> remedy <> " (it bakes the pinned flakes)."))

-- | Fill a staged source tree in place: every @\@marker\@@ becomes the text the
-- engine declared for it (kernel physics, 'Lips.Kernel.Source.fillTree'), so a
-- word the program states reaches inside the compiled program. Each immediate
-- subdirectory of the staged root is one artifact's tree, which is where its own
-- fills apply; a file lying loose in the root belongs to no artifact and so has
-- no fills, and a marker in it is a defect like any other undeclared one.
fillStagedTree :: FilePath -> FilePath -> [(Text, Text, Text)] -> IO ()
fillStagedTree file root fills = do
  there <- doesDirectoryExist root
  when there $ do
    entries <- listDirectory root
    forM_ entries $ \e -> do
      isDir <- doesDirectoryExist (root </> e)
      let art   = if isDir then T.pack e else ""
          label = if isDir then art else "(staged root)"
          decl  = [ (m, t) | (a, m, t) <- fills, a == art ]
      -- Paths stay RELATIVE to the staged root: the root is a temp dir at the
      -- gate, so an absolute path would name a file the reader cannot look at.
      paths <- if isDir then map (e </>) <$> treeFiles (root </> e) else pure [e]
      texts <- mapM (TIO.readFile . (root </>)) paths
      case fillTree label decl (zip paths texts) of
        Left defects -> die (report
          (T.pack file <> ": the source lips bakes and the values it fills disagree:")
          defects
          ("→ the source tree and its fills are minted together, so rebuild both: "
            <> "lips generate " <> T.pack file))
        Right filled -> forM_ filled $ \(p, t) ->
          when (Just t /= lookup p (zip paths texts)) (TIO.writeFile (root </> p) t)

-- | Every file under a directory, recursively, named relative to it.
treeFiles :: FilePath -> IO [FilePath]
treeFiles dir = do
  entries <- listDirectory dir
  fmap concat $ forM entries $ \e -> do
    isDir <- doesDirectoryExist (dir </> e)
    if isDir then map (e </>) <$> treeFiles (dir </> e) else pure [e]

-- | The source-specification gate: where a language BAKES source (a committed
-- @artifacts\/@ tree, minted from the program), the program lines that produced
-- 'Concept' decisions are part of that source's specification. A Concept
-- realizes nothing, so without this gate such a line could be dropped or
-- reworded while every other gate stayed green -- and the committed source would
-- go on implementing a specification the program no longer states.
--
-- Two directions, both judged by 'sourceSpecVerdict' (pure, so the conformance
-- suite reaches them):
--
--   * the program HAS a recorded section: every concept the mint saw must still
--     be stated;
--   * the program has NO recorded section (added or renamed after the mint):
--     every concept it states must be one the mint saw in SOME program of the
--     language. A sibling reusing the language restates concepts verbatim (a
--     concept pattern is all-literal), so reuse stays free, while a sentence the
--     source was never written from is refused instead of silently skipped.
--
-- What the programs said at mint time is read from the committed @.generation@
-- record, which stores the corpus verbatim, so this stays offline and
-- deterministic (no AI, no nix). A language with no baked source is untouched: a
-- concept there is a heading, and a heading must stay freely editable.
sourceSpecGate :: FilePath -> FilePath -> EngineData -> Text -> IO ()
sourceSpecGate dir file eng program = do
  baked <- doesDirectoryExist (artifactsPathIn dir file)
  when baked $ do
    mrec <- tryRead (generationPathIn dir file)
    case mrec of
      -- A baked tree whose record cannot be read cannot be judged at all, and an
      -- unjudged specification must never pass as a judged one.
      Nothing  -> die (report
        (T.pack file <> ": the language bakes source, but its generation record"
          <> " is missing or unreadable, so the specification that source was"
          <> " written from cannot be read.")
        [T.pack (generationPathIn dir file)]
        ("\8594 rebuild both from the program as it stands: lips generate " <> T.pack file))
      Just rec -> case crystallize file (edPatterns eng) program of
        Left _    -> pure ()  -- the current program's own read errors are reported by the caller
        Right now -> do
          let sections = recordedPrograms rec
              cryst t  = crystallize file (edPatterns eng) t
              staleRecord = die (report
                ("the program recorded in " <> T.pack (generationPathIn dir file)
                  <> " no longer crystallizes with the committed language.")
                []
                ("\8594 rebuild both from the program as it stands: lips generate " <> T.pack file))
          corpus <- forM sections $ \(_, t) -> either (const staleRecord) pure (cryst t)
          mwas <- case lookup (takeFileName file) sections of
            Nothing -> pure Nothing
            Just t  -> Just <$> either (const staleRecord) pure (cryst t)
          case sourceSpecVerdict mwas corpus now of
            SpecHolds -> pure ()
            SpecRetired retired -> die (report
              (T.pack file <> " dropped " <> plural (length retired) "line"
                <> " that the built source was written from:")
              [ a <> " (" <> niceSubject (dSubject d) <> ")"
              | d <- retired, let Assertion a = dAssertion d ]
              ("\8594 state it again, or rebuild the source for the program as it stands: "
                <> "lips generate " <> T.pack file))
            SpecUnrecorded unknown -> die (report
              (T.pack file <> " states " <> plural (length unknown) "line"
                <> " the built source was never written from:")
              [ a <> " (" <> niceSubject (dSubject d) <> ")"
              | d <- unknown, let Assertion a = dAssertion d ]
              ("\8594 the source is minted from the program, so rebuild it: "
                <> "lips generate " <> T.pack file))

-- | Stage a language's committed @artifacts@ tree (found under @dir@) into
-- @dst@ (the temp module's @artifacts\/@). A no-op when the language has no
-- artifacts tree, since a program without artifacts stages nothing.
--
-- A copy failure is NOT swallowed: it used to shell out to @cp -rT@ and discard
-- every error, so an unreadable source tree surfaced later as a missing path or
-- a confusing nix eval. Any IO error now propagates, naming the file.
stageFromDisk :: FilePath -> FilePath -> FilePath -> IO ()
stageFromDisk dir file dst = do
  let src = artifactsPathIn dir file
  there <- doesDirectoryExist src
  when there (copyTree src dst)

-- | Everything a realized module names beside itself: the staged source tree and
-- the site its clauses build. Handed to a gate that materializes the module into
-- a temp directory, so what nix evaluates there is what a compiled directory
-- holds.
stageBeside :: FilePath -> FilePath -> Realization -> FilePath -> IO ()
stageBeside dir file rl root = do
  stageFromDisk dir file (root </> "artifacts")
  void (writeSite root rl)

-- | Write the site a plan describes, and remove what it says is stale. The
-- decisions (which runtime, which files, what to prune) are pure and live in
-- 'Lips.Site'; this is the shell that touches the disk. Returns whether a site
-- was written, which is what decides the compiled flake's rungs.
writeSite :: FilePath -> Realization -> IO Bool
writeSite outDirPath rl = case planSite runtimeAsset runtimes rl of
  Left (why, remedy) -> die (report
    "lips can't build this program's behaviour."
    [why]
    remedy)
  Right Nothing -> pure False
  Right (Just plan) -> do
    let siteDir = outDirPath </> "site"
    createDirectoryIfMissing True siteDir
    -- The plan is the whole content, so anything else in the directory is from a
    -- compile that no longer applies: a claims file for claims the program has
    -- dropped, an adapter from a runtime the covering no longer chooses. Left
    -- there, it would keep being loaded by an assembly nobody stated.
    present <- listDirectory siteDir
    mapM_ (removeIfPresent siteDir)
          (filter (`notElem` map fst (spFiles plan)) present)
    forM_ (spFiles plan) (\(name, body) -> TIO.writeFile (siteDir </> name) body)
    pure True

-- | Delete a derived file that should no longer be there. Compile writes into a
-- directory it may have written before, so a file it stops producing must be
-- removed rather than left to be loaded by a stale assembly.
removeIfPresent :: FilePath -> FilePath -> IO ()
removeIfPresent dir name = do
  let path = dir </> name
  there <- doesFileExist path
  when there (removeFile path)

-- | How much source each staged tree actually holds, in lines and files. The
-- number that matters for review: an unvouched path is cheap to write and
-- expensive to trust, and only its size says which it is.
stagedSizes :: FilePath -> FilePath -> Grounding -> IO [Text]
stagedSizes dir file g = mapM one (gStaged g)
  where
    one u = do
      let root = artifactsPathIn dir file
      (ls, fs) <- treeSize root
      pure ("  staged tree: " <> subjectDots (uSubject u) <> " holds "
             <> T.pack (show ls) <> " lines in " <> T.pack (show fs)
             <> (if fs == 1 then " file" else " files")
             <> ", vouched by nothing")
    subjectDots (Subject ss) = T.intercalate "." ss

-- | Total lines and file count under a directory, recursively. Zero for a path
-- that is not there, so a program whose tree is missing reports honestly rather
-- than failing here (the staged-source gate is the one that refuses).
treeSize :: FilePath -> IO (Int, Int)
treeSize root = do
  there <- doesDirectoryExist root
  if not there then pure (0, 0) else do
    entries <- listDirectory root
    sizes <- forM entries $ \e -> do
      let path = root </> e
      isDir <- doesDirectoryExist path
      if isDir then treeSize path else do
        body <- TIO.readFile path
        pure (length (T.lines body), 1)
    pure (sum (map fst sizes), sum (map snd sizes))

-- | Copy a directory tree, creating @dst@ and mirroring files and subdirectories
-- (the @cp -rT@ shape: contents of @src@ land directly in @dst@). Loud on any
-- IO error, by not catching it.
copyTree :: FilePath -> FilePath -> IO ()
copyTree src dst = do
  createDirectoryIfMissing True dst
  entries <- listDirectory src
  forM_ entries $ \e -> do
    isDir <- doesDirectoryExist (src </> e)
    if isDir then copyTree (src </> e) (dst </> e)
             else do
               copyFile (src </> e) (dst </> e)
               -- A staged tree is lips's own working copy: source fills WRITE into
               -- it. Copying preserves the mode, and a language folder read from
               -- the nix store is read-only (a compile inside a derivation), so
               -- the copy is made writable or the fill dies with EACCES.
               perms <- getPermissions (dst </> e)
               setPermissions (dst </> e) (setOwnerWritable True perms)

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
    -- The line is fine; what is missing is the line that should open its block
    -- above it. Naming that is the remedy, so say it rather than "unreadable".
    crystDetail (NoParentBlock n t _) =
      "line " <> tshow n <> ": " <> t <> " -- this belongs inside a block, and no line above it opens one"
    -- The setup names one of this line's words as an identity, and the word
    -- cannot be one: what the line states could not be written down and read
    -- back, so the decisions file would stop being readable text.
    crystDetail (Unreadable n t why) =
      "line " <> tshow n <> ": " <> t
        <> " -- what this line states cannot be written down and read back (" <> why <> ")"
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
  -- A rewrite that fails is the one refine error whose cause can be EITHER side:
  -- a word the option cannot take (the program's) or a rule that cannot fill its
  -- own emit (the engine's). Both are named rather than one guessed, and the
  -- per-line report from 'diagnose' says which line stated the word.
  RefineFailed e@(RewriteFailed {}) ->
    reportHead ("lips could not fit what " <> T.pack file
                  <> " states into the setup it was built with:")
               [refineDetail e]
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
      FailRun (RefineFailed (RewriteFailed {})) ->
        "→ state a value that fits in " <> T.pack file
          <> ", or rebuild the setup: lips generate " <> T.pack file
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

-- | The machine-readable twin of 'refusalReport', written to 'gapPath'
-- whenever generate refuses. Same content the record for a SUCCESSFUL mint
-- would have carried (model, target, schema pin, thinking, confidence, the full system
-- prompt, program corpus, tool transcript and raw reply -- 'record', the same
-- function '.generation' uses), fingerprinted the same way ('genId'), plus
-- the refusal-specific summary up front: this is what makes it a shippable
-- bug report for the cross-repo escalation workflow (DESIGN Doctrine) rather
-- than only on-screen text. A mint-reported 'Gap' already names its own
-- blocked line and repro (the mint's job, not this renderer's), so it is
-- listed verbatim.
gapArtifact :: Text -> [Text] -> [ItemCandidate] -> [Gap] -> Text
gapArtifact rec errs unsure gaps = T.unlines $
  [ "# lips generate refusal report. Machine-readable; rewritten on every refusal, never hand-edited."
  , "# fingerprint: " <> genId rec <> " (re-hash the record below with the same function '.generation' uses to verify)"
  , ""
  , "--- refused lines (a line the AI wrote that lips's grammar can't express) ---"
  ] ++ (if null errs then ["(none)"] else map ("- " <>) errs) ++
  [ "", "--- underspecified (the program didn't pin these down with enough confidence) ---" ] ++
  (if null unsure then ["(none)"] else [ "- " <> icLine c | c <- unsure ]) ++
  [ "", "--- missing capability (the mint's own words; each names its blocked line and a repro) ---" ] ++
  (if null gaps then ["(none)"]
   else concat [ ("- " <> gapSlug g) : [ "    " <> l | l <- T.lines (T.strip (gapBody g)) ] | g <- gaps ]) ++
  [ "", "--- generation record (model, target, schema, thinking, confidence, system prompt, program, tool transcript, raw reply) ---", rec ]

-- | generate couldn't build a setup: either lines lips couldn't read (a
-- capability may be missing) or values the program leaves underspecified.
refusalReport :: FilePath -> FilePath -> Double -> [Text] -> [ItemCandidate] -> [(Text, Text)] -> [Gap] -> Text
refusalReport file gapFile _threshold errs unsure notes gaps = T.intercalate "\n" $
  ["lips couldn't build a setup for " <> T.pack file <> "."]
    ++ grammar ++ underspecified ++ missing
    ++ [ "", "\8594 the full refusal (refused lines, fingerprint, raw reply) is saved to " <> T.pack gapFile
       , "  -- a shippable artifact for a bug report if this looks like a lips gap." ]
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

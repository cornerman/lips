{-# LANGUAGE OverloadedStrings #-}

-- | The gates every deterministic verb passes a REALIZATION through.
--
-- Each one judges the same object -- the realization of one program with its
-- committed language -- against something outside the text: the tree lips
-- stages beside the module, the build a mint declared, the claims the program
-- states, the specification a baked source tree was written from. They live
-- together because they share that subject and because a verb picks a SUBSET of
-- them ('Main' composes; this module only judges).
--
-- What is NOT here: the static gates over an engine (those are pure and live in
-- @Lips.Kernel.Engine.Gate@ and @Lips.Kernel.Clause.Gate@, where the conformance
-- suite reaches them), and the verb-level composition (`Main`, which owns which
-- gate a verb runs and what it does with the verdict).
--
-- Every gate here refuses by 'die', so a caller cannot forget a verdict: there
-- is no value to ignore. That is the same reason the messages are built from
-- 'Lips.Report' -- one voice per defect, whichever verb reached it.
module Lips.Gate
  ( -- * The contract
    ExpectFail (..)
  , runExpects
  , groundExpectFaults
    -- * Gates over one realization
  , stagedGate
  , sourceSpecGate
  , claimGate
  , clauseClaimGate
  , artifactGate
  , mintClaimGate
    -- * The nixpkgs a build runs against
  , artifactNixpkgs
  ) where

import           Control.Exception  (IOException, try)
import           Control.Monad      (filterM, forM, forM_, when)
import           Data.List          (partition)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (doesDirectoryExist, doesPathExist)
import           System.Environment (lookupEnv)
import           System.Exit        (ExitCode (..))
import           System.FilePath    (takeFileName, (</>))
import           System.Process     (readProcessWithExitCode)

import           Lips.Cli.Output    (die, note, report, step, tshow)
import           Lips.Generate.Record (recordedPrograms)
import           Lips.Identity      (artifactsPathIn, generationPathIn, languageName)
import           Lips.Kernel.Claim  (Claim (..), ClaimPlace (..))
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect (Expect, checkArtifactValues, checkValues, evalExpr,
                                     expandExpects, expectedValue, isGroundExpect)
import           Lips.Kernel.Lang.Crystallize (crystallize)
import           Lips.Kernel.Lang.Diagnose (SourceSpecVerdict (..), sourceSpecVerdict)
import           Lips.Kernel.Lang.Store (EngineData (..))
import           Lips.Kernel.Run
import           Lips.Nix.Claims    (claimsFile)
import           Lips.Nix.Flake     (Rungs (..), SiteRung (..), flakeText, noRungs)
import           Lips.World         (World)
import           Lips.Report        (niceSubject, nixMissing, plural)
import           Lips.Schema        (lockFlakeRef)
import           Lips.Stage         (fillStagedTree, siteNameOf, stageBeside, withTempDir, writeSite)

-- | Read a file that may be absent. The gates here read only files lips itself
-- wrote (a generation record), so an unreadable one is the same event as a
-- missing one: the gate says what it could not judge and refuses.
readIfPresent :: FilePath -> IO (Maybe Text)
readIfPresent p = either (const Nothing) Just <$> (try (TIO.readFile p) :: IO (Either IOException Text))

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
claimGate :: World -> FilePath -> FilePath -> Realization -> IO ()
claimGate world dir file rl =
  clauseClaimGate world file rl >> commandClaimGate world dir file rl

-- | The clause claims, judged: one small derivation that evaluates the program's
-- own definitions with the runtime's list-backed adapters. No machine boots and
-- no binary is compiled, so this gate costs a fraction of the one below and can
-- observe a single definition rather than a whole process.
--
-- It is still a @nix build@, so a clause-claiming program's @check@ needs an
-- ambient nixpkgs exactly as a command-claiming one does. A program that states
-- no observable is untouched and its @check@ stays nixpkgs-free.
clauseClaimGate :: World -> FilePath -> Realization -> IO ()
clauseClaimGate world file rl
  | null (rlClauseClaims rl) = pure ()
  | otherwise =
      step ("clause claims: " <> plural (length (rlClauseClaims rl)) "claim") $
        withTempDir $ \tmp -> do
          _ <- writeSite (T.pack (languageName file)) tmp rl
          TIO.writeFile (tmp </> "flake.nix")
            (flakeText world noRungs { siteRung = Just (SiteRung (siteNameOf rl) True) })
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

commandClaimGate :: World -> FilePath -> FilePath -> Realization -> IO ()
commandClaimGate world dir file rl
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
      step ("claims: " <> plural (length (rlClaims rl)) "claim") $ withTempDir $ \tmp -> do
        TIO.writeFile (tmp </> "default.nix") (rlModule rl)
        stageBeside dir file rl tmp
        fillStagedTree file (tmp </> "artifacts") (rlFills rl)
        let (artBody, artNames) = rlArtifact rl
        TIO.writeFile (tmp </> "artifact.nix") artBody
        case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
          Nothing   -> pure ()   -- unreachable: the claim list is non-empty here
          Just body -> TIO.writeFile (tmp </> "claims.nix") body
        TIO.writeFile (tmp </> "flake.nix")
          (flakeText world noRungs { hasArtifacts = not (null artNames), hasClaims = True })
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

-- | Evaluate the realized module with @nix@ and judge a contract against it.
-- One eval reads every asserted option; the pure comparison lives in
-- 'Lips.Kernel.Expect'. An empty contract passes trivially.
-- | Three outcomes of the behavioral check, kept apart so the CLI gives the
-- right action: install nix (tool missing), fix the environment (eval failed),
-- or the config doesn't carry the promised values (violations).
-- 'Violations' carries the messages AND the assertions that failed (empty for a
-- message no assertion owns, like a mismatched eval arity), so a caller can ask
-- which re-bless mode would admit the change ('smallestCompat') instead of
-- naming the biggest one.
data ExpectFail = ToolMissing Text | EvalFailed Text | Violations [Text] [Expect]

-- | One failure list as both readings: the messages a human reads, and the
-- assertions a caller asks about a re-bless mode.
violations :: [(Expect, Text)] -> ExpectFail
violations fs = Violations (map snd fs) (map fst fs)

-- | The 'Text' is the program's instance name. It is a parameter rather than a
-- binding each caller applies, because a caller that forgot it judged
-- @site.\<self\>.command@ against a base holding @site.logscan.command@.
runExpects :: (FilePath -> IO ()) -> Text -> [Expect] -> Realization -> IO (Either ExpectFail ())
runExpects _     _    []       _  = pure (Right ())
runExpects stage inst expects0 rl =
  -- Expand any value-keyed family expect against this program's routes first,
  -- so a shared contract (route.<path>.status) checks every concrete route.
  case expandExpects inst base expects0 >>= \expects ->
         (,) expects <$> traverse (expectedValue base) expects of
    Left e            -> pure (Left (Violations ["lips can't match a check to the program: " <> e] []))
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
        (fs, Right ()) -> Left (violations fs)
        (fs, Left (Violations more es)) -> Left (Violations (map snd fs ++ more) (map fst fs ++ es))
        (_,  Left other) -> Left other
  where
    base = rlBase rl

-- | The GROUND half of a contract alone: every assertion over a slot lips owns
-- itself (a claim, a clause, a site, an artifact arg), judged against the ground
-- base with no nix and no eval. Empty is the sound case.
--
-- This is what lets a MINT be held to its own new promises. Grading a model
-- against expects it just wrote is flattery for an option assertion, since the
-- rule that fills the option and the assertion that reads it come from the same
-- pen -- but a ground assertion that names a slot the realization does not have,
-- or the wrong slot of its own claim, is self-CONTRADICTORY rather than
-- self-fulfilling, and no amount of writing makes it pass. Three mints in a row
-- died on exactly that, a quarter of an hour after the door had let them past.
groundExpectFaults :: Text -> [Expect] -> Realization -> [Text]
groundExpectFaults _    []       _  = []
groundExpectFaults inst expects0 rl =
  case expandExpects inst base expects0 >>= \es -> (,) es <$> traverse (expectedValue base) es of
    Left e  -> ["lips can't match a check to the program: " <> e]
    Right (es, pvs) ->
      map snd (checkArtifactValues (rlGround rl)
                 (filter (isGroundExpect . fst) (zip es pvs)))
  where base = rlBase rl

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
                           <> " values for " <> tshow (length expects) <> " checks"] [])
                else case checkValues expects (zip pvs evaled) of
                       [] -> Right ()
                       fs -> Left (violations fs)
        Right (ExitFailure _, _, err) -> Left (EvalFailed (T.pack err))

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
  (_, [])         -> pure ()
  (body, names) -> step ("build " <> plural (length names) "artifact") $ withTempDir $ \dir -> do
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
        let (artBody, artNames) = rlArtifact rl
        TIO.writeFile (dir </> "artifact.nix") artBody
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
-- deterministic (no AI, no nix). One world's record, because each world's mint
-- saw its own corpus: the source a world bakes was written from the programs
-- THAT mint read. A language with no baked source is untouched: a
-- concept there is a heading, and a heading must stay freely editable.
sourceSpecGate :: FilePath -> Text -> FilePath -> EngineData -> Text -> IO ()
sourceSpecGate dir world file eng program = do
  baked <- doesDirectoryExist (artifactsPathIn dir file)
  when baked $ do
    mrec <- readIfPresent (generationPathIn dir world file)
    case mrec of
      -- A baked tree whose record cannot be read cannot be judged at all, and an
      -- unjudged specification must never pass as a judged one.
      Nothing  -> die (report
        (T.pack file <> ": the language bakes source, but its generation record"
          <> " is missing or unreadable, so the specification that source was"
          <> " written from cannot be read.")
        [T.pack (generationPathIn dir world file)]
        ("\8594 rebuild both from the program as it stands: lips generate " <> T.pack file))
      Just rec -> case crystallize file (edPatterns eng) program of
        Left _    -> pure ()  -- the current program's own read errors are reported by the caller
        Right now -> do
          let sections = recordedPrograms rec
              cryst t  = crystallize file (edPatterns eng) t
              staleRecord = die (report
                ("the program recorded in " <> T.pack (generationPathIn dir world file)
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


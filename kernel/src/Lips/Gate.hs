{-# LANGUAGE OverloadedStrings #-}

-- | The gates every deterministic verb passes a REALIZATION through.
--
-- Each one judges the same object -- the realization of one program with its
-- committed language -- against something outside the text: the tree lips
-- stages beside the module, the build a mint declared, the claims the program
-- states. They live together because they share that subject and because a
-- verb picks a SUBSET of them ('Main' composes; this module only judges).
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
  , claimGate
  , clauseClaimGate
  , artifactGate
  , mintClaimGate
  , worldGate
    -- * The nixpkgs a build runs against
  , artifactNixpkgs
  ) where

import           Control.Exception  (IOException, try)
import           Control.Monad      (filterM, forM, forM_, when)
import           Data.List          (partition)
import           Data.Text          (Text)
import qualified Data.Text          as T
import qualified Data.Text.IO       as TIO
import           System.Directory   (doesPathExist)
import           System.Environment (lookupEnv)
import           System.Exit        (ExitCode (..))
import           System.FilePath    ((</>))
import           System.Process     (readProcessWithExitCode)

import           Lips.Cli.Output    (die, note, report, step, tshow)
import           Lips.Identity      (languageName)
import           Lips.Kernel.Claim  (Claim (..), ClaimPlace (..))
import           Lips.Kernel.Decision
import           Lips.Kernel.Expect (Expect, checkArtifactValues, checkValues, evalExpr,
                                     expandExpects, expectedValue, isGroundExpect)
import           Lips.Kernel.Run
import           Lips.Nix.Claims    (claimsFile)
import           Lips.Nix.Flake     (Rungs (..), SiteRung (..), flakeText, noRungs, substrateNixpkgsVar)
import           Lips.World         (World (..))
import           Lips.Report        (niceSubject, nixMissing, plural)
import           Lips.Schema        (lockFlakeRef)
import           Lips.Stage         (siteNameOf, stageBeside, withTempDir, writeCompiled,
                                     writeSite)

-- | The claim gate: every observable the program states must actually hold.
--
-- This is the ONE gate that observes a running thing rather than reading the
-- module text, so it is what holds minted behaviour -- and every future
-- re-mint -- to the author's own words.
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
claimGate :: World -> FilePath -> Realization -> IO ()
claimGate world file rl =
  clauseClaimGate world file rl >> commandClaimGate world file rl

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

commandClaimGate :: World -> FilePath -> Realization -> IO ()
commandClaimGate world file rl
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
        stageBeside file rl tmp
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
            ("\8594 the behaviour is minted, so rebuild it from the program as it"
              <> " stands: lips generate " <> T.pack file))
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
          artFails = checkArtifactValues base (rlGround rl) artExpects
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
      map snd (checkArtifactValues base (rlGround rl)
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
      -- The module may name things BESIDE it: the site its own clauses build.
      -- So the callback stages the neighbourhood; a module referencing ./site/build.nix
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

-- | The staged-path gate: every relative path the realized module names must
-- exist in what lips stages beside it (the site its clauses build). Without it
-- such a path reaches nix, which fails with @path '...' does not exist@ over a
-- store path, naming neither lips, the program nor a remedy. Checked against a
-- real staging into a temp dir, not against a guess at how a path maps to the
-- language folder, so the gate sees exactly what nix will see. No language
-- holds a source tree (model-written source is refused), so a path naming one
-- (@src ./artifacts/\<name\>@) is refused here too.
stagedGate :: (FilePath -> IO ()) -> FilePath -> Realization -> IO ()
stagedGate stage file rl
  | null staged = pure ()
  | otherwise = withTempDir $ \dir -> do
  stage dir
  missing <- filterM (fmap not . doesPathExist . (dir </>) . T.unpack . fst) staged
  case missing of
    [] -> pure ()
    ms -> die (report
      (T.pack file <> " names " <> plural (length ms) "file" <> " that lips never staged:")
      [ p <> " (named by " <> niceSubject (dSubject d) <> ")" | (p, d) <- ms ]
      ("→ lips stages only the site its clauses build, so the engine must not name"
        <> " another path; rebuild it: lips generate " <> T.pack file))
  where staged = rlStaged rl

-- | The build gate: every artifact the engine declares must BUILD, and every
-- path the output names inside one must really be there.
--
-- Why observation and not a static check: what a build CONTAINS is decided by
-- the builder and its arguments, never by anything lips reads. An engine
-- emitting @ExecStart = "${artifact.hello}\/bin\/hello"@ over a build that
-- installs @bin\/server@ was well-formed everywhere lips can read: it passed the
-- mint gate, @check@, and the artifact EVAL check, and shipped a unit that
-- cannot start -- twice. Knowing the answer requires looking inside the result,
-- and teaching lips what each builder names its output would be an open list
-- the kernel enumerates (the doctrine forbids it).
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
    -- The build reads the directory exactly as compile writes it.
    TIO.writeFile (dir </> "artifact.nix") body
    -- The whole neighbourhood, since an artifact's own argument may name the
    -- site: a wrapper renaming the program is exactly that shape.
    stage dir
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
        ("\8594 the name in that path is decided by the build's own arguments, so"
          <> " both are rebuilt together: lips generate " <> T.pack file))
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
        let (artBody, artNames) = rlArtifact rl
        TIO.writeFile (dir </> "artifact.nix") artBody
        case claimsFile (not (null artNames)) (rlSiteName rl) (rlClaims rl) of
          Nothing   -> pure ()   -- unreachable: the claim list is non-empty here
          Just body -> TIO.writeFile (dir </> "claims.nix") body
        note ("observing " <> T.intercalate ", " (map clId (rlClaims rl)))
        forM_ (rlClaims rl) (buildClaim nixpkgs file dir)

-- | The world's own gate: the build its @gate@ slot names must succeed over the
-- render, before the engine is written.
--
-- Why: a world's schema may be weak on purpose (nono's grounds only the
-- top-level sections), and then the only authority on the names below it is a
-- validator the world runs in its own build. Without this gate that validator
-- saw nothing until a human built the compiled directory, so an engine whose
-- render it refuses was accepted and committed. The world says which build is
-- its verdict; lips builds it and knows nothing about what it checks.
--
-- It builds @#gate@ of the very directory @compile@ writes ('writeCompiled'),
-- with @nixpkgs@ overridden by the locked pin, so the validator is the version
-- the mint was grounded against rather than whatever the ambient registry
-- resolves. Only @nixpkgs@ is overridden: a world input lips cannot pin (a
-- kubenix URL) would make the verdict drift, which is why such worlds declare
-- no gate yet.
--
-- A world with no @gate@ slot is untouched, and @check@ never runs this: it
-- stays nixpkgs-free, while the world's own package build still refuses an
-- invalid render where it is used.
worldGate :: Text -> World -> FilePath -> Realization -> IO ()
worldGate nixpkgs world file rl = case wGate world of
  Nothing -> pure ()
  Just _  -> step ("the " <> wName world <> " world's own gate") $ withTempDir $ \tmp -> do
    _ <- writeCompiled world file tmp rl
    res <- try (readProcessWithExitCode "nix"
      [ "build", "--no-link", "path:" <> tmp <> "#gate"
      , "--override-input", "nixpkgs", T.unpack nixpkgs ] "")
    case res of
      Left e -> die (nixMissing file "run the world's own gate over it" "generate"
                      (tshow (e :: IOException)))
      Right (ExitFailure _, _, err) -> die (report
        (T.pack file <> ": the " <> wName world <> " world refuses what lips rendered.")
        (T.lines (T.pack err))
        ("\8594 the rules are minted, so mint again: lips generate " <> T.pack file
          <> ". If the refusal is a fact about the world, state it in the world"
          <> " file's preamble first, so the next mint is told."))
      Right (ExitSuccess, _, _) -> pure ()

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
      ("\8594 the behaviour is minted, so it is rebuilt from the program:"
        <> " lips generate " <> T.pack file))
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
      ("\8594 the build's arguments are minted, so rebuild them:"
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
  mflake <- lookupEnv (T.unpack substrateNixpkgsVar)
  case mflake of
    Just ref -> lockFlakeRef ref remedy
    -- Deduce-or-fail: an artifact lips cannot build is an artifact lips cannot
    -- vouch for, and "not verified" must never ship as verified.
    Nothing  -> die (report
      "lips can't build the artifact it minted: no nixpkgs is pinned."
      [substrateNixpkgsVar <> " is unset, so there is no nixpkgs to build against."]
      ("\8594 run the packaged lips: nix run . -- " <> remedy <> " (it bakes the pinned flakes)."))


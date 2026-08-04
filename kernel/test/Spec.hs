{-# LANGUAGE OverloadedStrings #-}
-- Arbitrary Decision is a test-only orphan; it belongs with the suite, not the
-- library, so the orphan warning here is expected and suppressed.
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Conformance tests for the kernel calculus. Each block cites the spec
-- invariant it pins (spec v2, sections 2 and 4). This is the seed of the
-- conformance suite named as the source of truth in spec section 12.
module Main (main) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.IO    as TIO

import Test.Hspec
import Test.QuickCheck hiding (Confidence)

import Lips.Kernel.Base
import Lips.Kernel.Surface (valueTokens)
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader
import Lips.Kernel.Realize
import Lips.Kernel.Refine
import Lips.Kernel.Run
import Lips.Kernel.Engine.Answerable
import Lips.Kernel.Engine.Data
import Lips.Kernel.Engine.Gate (engineViolations)
import Lips.Generate.Draft (DraftTree (..), materializeDraft)
import Lips.Kernel.Engine.Overlap
import Lips.Kernel.Engine.Reach
import Lips.Kernel.Engine.Typing (wordTypes)
import Lips.Kernel.Engine.Value
import qualified Lips.Kernel.Sexp as Sx
import Lips.Kernel.Clause.Vocabulary
import Lips.Kernel.Clause.Gate
import Lips.Kernel.Clause.Catalogue
import Lips.Runtime (guileRuntime, schemeVocabulary)
import Lips.Kernel.Engine.Aggregate (mergeModeOf, assembleSubject, assembleWith)
import Lips.Kernel.OptionType
import Lips.Nix.Options
import Lips.Nix.Schema (schemaFor)
import Lips.Nix.Claims (claimsFile)
import Lips.Nix.Flake (flakeText, runCommands)
import Lips.Nix.Target
import Lips.Cli (GenerateOpts (..), CompileOpts (..), CheckOpts (..), OptionsOpts (..), generateOpts, compileOpts, checkOpts, optionsOpts, programCompleter)
import Options.Applicative (execParserPure, defaultPrefs, getParseResult, info, idm)
import Options.Applicative.Types (Completer (..))
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, getTemporaryDirectory)
import System.FilePath ((</>))
import Data.List (sort, sortOn)
import Lips.Generate.Harness
import Lips.Generate.Readme (renderReadme)
import Lips.Generate.Minting (parseEngineCandidates, assemble, expectsOf, sourcesOf, reportOf, gapsOf, carriesEngineMeaning, uncheckableExpects, claimlessBakedSource, unplaceableClaims, EngineItem (..), Gap (..), ItemCandidate (..), SourceFile (..), systemPrompt, systemPromptFor, promptWithDirection)
import Lips.Generate.PiJson (PiReply (..), parsePiReply, PiEvent (..), progressEvent, abbreviate, resultSummary)
import Lips.Cli.Output (Style (..), Verdict (..), runningText, verdictText, elapsedText, report, reportHead)
import Lips.Kernel.Claim
import Lips.Kernel.Expect
import Lips.Generate.Record (corpusText, genId, record, recordedProgram, recordedPrograms)
import Lips.Kernel.Lang.Pattern
import Lips.Kernel.Lang.Crystallize
import Lips.Kernel.Lang.Diagnose
import Lips.Kernel.Lang.Nest
import Lips.Kernel.Lang.Store
import Lips.Kernel.Source
import Lips.Lsp.Derive
import Lips.Lsp.Server (uriToPath)
import Lips.Identity

-- | A decision about subject @s@ asserting @a@, at strength @str@, id @i@.
mk :: Text -> Text -> Text -> Strength -> Decision
mk i s a str =
  Decision
    { dId        = DecisionId i
    , dSubject   = Subject [s]
    , dKind      = Fact
    , dAssertion = Assertion a
    , dStrength  = str
    , dProv      = FromSource (SourceLoc "ledger" 1)
    , dRationale = Nothing
    }

winnerAssertion :: Subject -> Map.Map Subject Decision -> Maybe Assertion
winnerAssertion s = fmap dAssertion . Map.lookup s

-- The all-Replace, no-assembly configuration: what most of this suite exercises
-- (aggregation has its own cases). Test helpers, not production functions --
-- they used to live in the kernel as four exported wrappers with no caller
-- outside these tests.
resolveReplace :: Base -> Either [Conflict] (Map.Map Subject Decision)
resolveReplace base = case resolve (const Replace) noAssembly base of
  Left errs -> Left [ c | REConflict c <- errs ]
  Right m   -> Right m

realizeReplace :: Base -> Either RealizeError Text
realizeReplace = realize (const Replace) noAssembly

runReplace :: Int -> [Rule] -> [Demand] -> Text -> Either RunError Text
runReplace budget rules demands =
  fmap rlModule . run (const Replace) noAssembly budget rules demands

runBaseReplace :: Int -> [Rule] -> [Demand] -> Base -> Either RunError Text
runBaseReplace budget rules demands =
  fmap rlModule . runBase (const Replace) noAssembly budget rules demands

noAssembly :: [Decision] -> Either Text Decision
noAssembly _ = Left "assemble unused"

main :: IO ()
main = hspec $ do
  describe "generate argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info (generateOpts 0.7) idm)
    it "defaults target to nixos, confidence to the default, renew/verbose off" $
      parseArgs ["ledger.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 False False Nothing "high" ["ledger.backup.lips"])
    it "reads --target home-manager in any position" $
      parseArgs ["--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts HomeManager Nothing 0.7 False False Nothing "high" ["a.backup.lips"])
    it "rejects an unknown target" $
      parseArgs ["--target", "darwin", "a.backup.lips"] `shouldBe` Nothing
    it "reads an explicit --model alongside multiple programs" $
      parseArgs ["--model", "anthropic/claude", "a.backup.lips", "b.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 False False (Just "anthropic/claude") "high" ["a.backup.lips", "b.backup.lips"])
    it "combines --target and --confidence" $
      parseArgs ["--confidence", "0.9", "--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts HomeManager Nothing 0.9 False False Nothing "high" ["a.backup.lips"])
    it "rejects an out-of-range confidence" $
      parseArgs ["--confidence", "1.5", "a.backup.lips"] `shouldBe` Nothing
    it "reads --renew in any position" $ do
      parseArgs ["--renew", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 True False Nothing "high" ["a.backup.lips"])
      parseArgs ["a.backup.lips", "--renew"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 True False Nothing "high" ["a.backup.lips"])
    it "reads -v/--verbose in any position" $ do
      parseArgs ["--verbose", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 False True Nothing "high" ["a.backup.lips"])
      parseArgs ["a.backup.lips", "-v"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 False True Nothing "high" ["a.backup.lips"])
    it "reads -m as the short alias for --model" $
      parseArgs ["-m", "anthropic/claude", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos Nothing 0.7 False False (Just "anthropic/claude") "high" ["a.backup.lips"])
    it "rejects a duplicate --model (fail loud, not last-wins)" $
      parseArgs ["--model", "a", "--model", "b", "a.backup.lips"] `shouldBe` Nothing
    -- The thinking level is always passed to pi and always recorded, so an
    -- ambient reasoning setting cannot steer a mint unrecorded (invariant 6).
    it "defaults --thinking to high and reads an override" $ do
      goThinking <$> parseArgs ["a.backup.lips"] `shouldBe` Just "high"
      goThinking <$> parseArgs ["--thinking", "max", "a.backup.lips"] `shouldBe` Just "max"
    -- The grounding schema defaults to the pin baked into this binary, so nobody
    -- has to author one; --schema is how a caller whose own world differs (a
    -- stable channel, a company nixpkgs) grounds the mint against it instead.
    it "defaults --schema to the baked pin and reads an override" $ do
      goSchema <$> parseArgs ["a.backup.lips"] `shouldBe` Just Nothing
      goSchema <$> parseArgs ["--schema", "github:NixOS/nixpkgs/nixos-24.11", "a.backup.lips"]
        `shouldBe` Just (Just "github:NixOS/nixpkgs/nixos-24.11")
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing

  describe "compile argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info compileOpts idm)
    it "defaults --out and --lang to Nothing, and gates on the contract" $
      parseArgs ["a.backup.lips"]
        `shouldBe` Just (CompileOpts Nothing Nothing False "a.backup.lips")
    it "reads --lang in any position, alongside --out" $ do
      parseArgs ["--lang", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CompileOpts Nothing (Just "services/a/backup") False "a.backup.lips")
      parseArgs ["--out", "dir", "--lang", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CompileOpts (Just "dir") (Just "services/a/backup") False "a.backup.lips")
    -- The gate needs nix to evaluate the realized module, which a compile
    -- INSIDE a nix build does not have; the flag states that skip.
    it "reads --no-contract, the stated skip for a compile inside a nix build" $
      parseArgs ["--no-contract", "a.backup.lips"]
        `shouldBe` Just (CompileOpts Nothing Nothing True "a.backup.lips")
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing

  describe "check argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info checkOpts idm)
    it "defaults --lang to Nothing" $
      parseArgs ["a.backup.lips"] `shouldBe` Just (CheckOpts Nothing False "a.backup.lips")
    it "reads --lang in any position" $ do
      parseArgs ["--lang", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CheckOpts (Just "services/a/backup") False "a.backup.lips")
      parseArgs ["a.backup.lips", "--lang", "services/a/backup"]
        `shouldBe` Just (CheckOpts (Just "services/a/backup") False "a.backup.lips")
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing
    it "defaults to reading the committed engine, not a draft" $
      fmap ceDraft (parseArgs ["prog.backup.lips"]) `shouldBe` Just False
    it "reads a draft engine from stdin when --draft is given" $
      fmap ceDraft (parseArgs ["--draft", "prog.backup.lips"]) `shouldBe` Just True
    -- Two different engines are named, so the invocation is ambiguous and lips
    -- refuses it rather than silently preferring one (invariant 2).
    it "refuses --draft together with --lang, in either order" $ do
      parseArgs ["--draft", "--lang", "backup", "prog.backup.lips"] `shouldBe` Nothing
      parseArgs ["--lang", "backup", "--draft", "prog.backup.lips"] `shouldBe` Nothing

  describe "options argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info optionsOpts idm)
    it "defaults to the default target and cap" $
      parseArgs ["services.restic"]
        `shouldBe` Just (OptionsOpts Nixos Nothing 40 "services.restic")
    it "takes a target, a limit and a query" $
      parseArgs ["--target", "home-manager", "--limit", "10", "services.restic"]
        `shouldBe` Just (OptionsOpts HomeManager Nothing 10 "services.restic")
    it "rejects an unknown target, like generate does" $
      parseArgs ["--target", "darwin", "services.restic"] `shouldBe` Nothing
    -- The lookup verb is the mint's own tool, so it must be able to read exactly
    -- the schema a mint would read -- including an overridden one.
    it "takes the same --schema override generate takes" $
      parseArgs ["--schema", "github:NixOS/nixpkgs/nixos-24.11", "services.restic"]
        `shouldBe` Just (OptionsOpts Nixos (Just "github:NixOS/nixpkgs/nixos-24.11") 40 "services.restic")
    it "fails with no query at all" $
      parseArgs [] `shouldBe` Nothing

  -- Tab completion must offer only what a human may pass: the .lips programs
  -- and directories to descend into, never the machine-written neighbours.
  describe "PROGRAM tab completion (Lips.Cli.programCompleter)" $ do
    -- The fixture mirrors the on-disk layout: programs at the top level, the
    -- machine's files inside <language>/.
    let withFixture act = do
          tmp <- getTemporaryDirectory
          let root = tmp </> "lips-completer-spec"
          createDirectoryIfMissing True (root </> "backup")
          mapM_ (\f -> writeFile (root </> f) "")
            [ "ledger.backup.lips", "photos.backup.lips", ".hidden.backup.lips" ]
          mapM_ (\f -> writeFile (root </> "backup" </> f) "")
            [ "backup.lang", "backup.expect" ]
          r <- act root
          removeDirectoryRecursive root
          pure r
            -- Completions come back as full paths; compare them root-relative.
        completeIn root w = sort . map (drop (length root + 1))
                            <$> runCompleter programCompleter (root <> "/" <> w)
    it "offers .lips programs and directories, hiding machine files" $
      withFixture (\root -> (,,) <$> completeIn root "" <*> completeIn root "led" <*> completeIn root "backup/")
        `shouldReturn`
          ( sort ["backup/", "ledger.backup.lips", "photos.backup.lips"]
          , ["ledger.backup.lips"]
          , [] )


  describe "realization target (Lips.Nix.Target)" $ do
    it "parses the world slugs and rejects others" $ do
      parseTarget "nixos" `shouldBe` Just Nixos
      parseTarget "home-manager" `shouldBe` Just HomeManager
      parseTarget "kubenix" `shouldBe` Just Kubenix
      parseTarget "terranix" `shouldBe` Just Terranix
      parseTarget "darwin" `shouldBe` Nothing
    it "slug round-trips through parse for every target" $
      mapM_ (\t -> parseTarget (T.unpack (targetSlug t)) `shouldBe` Just t)
            [minBound .. maxBound]
    it "defaults to nixos" $
      defaultTarget `shouldBe` Nixos

  describe "merge (spec 2.1: strength) " $ do
    it "delta-over-defaults: Stated overrides Default on the same subject" $ do
      let base = fromList [mk "d1" "cadence" "daily" Default, mk "d2" "cadence" "hourly" Stated]
      resolveReplace base `shouldSatisfy` \r -> case r of
        Right m -> winnerAssertion (Subject ["cadence"]) m == Just (Assertion "hourly")
        Left _  -> False

    it "Law overrides Stated" $ do
      let base = fromList [mk "d1" "x" "a" Stated, mk "d2" "x" "b" Law]
      case resolveReplace base of
        Right m -> winnerAssertion (Subject ["x"]) m `shouldBe` Just (Assertion "b")
        Left _  -> expectationFailure "expected a winner, got conflict"

    it "distinct subjects coexist without competing" $ do
      let base = fromList [mk "d1" "a" "1" Stated, mk "d2" "b" "2" Stated]
      case resolveReplace base of
        Right m -> Map.size m `shouldBe` 2
        Left _  -> expectationFailure "distinct subjects must not conflict"

  describe "agreement (spec 2: set semantics)" $
    it "equal strength, equal assertion: one winner, no conflict" $ do
      let base = fromList [mk "d1" "x" "same" Stated, mk "d2" "x" "same" Stated]
      case resolveReplace base of
        Right m -> Map.size m `shouldBe` 1
        Left _  -> expectationFailure "agreeing decisions must not conflict"

  describe "conflict (spec 2.2)" $ do
    it "equal strength, differing assertion: conflict carrying both provenances" $ do
      let d1 = mk "d1" "x" "a" Stated
          d2 = mk "d2" "x" "b" Stated
      case resolveReplace (fromList [d1, d2]) of
        Left [c] -> do
          conflictSubject c `shouldBe` Subject ["x"]
          -- both provenances are present, in deterministic (smallest-id) order
          map dId [conflictLeft c, conflictRight c] `shouldBe` [DecisionId "d1", DecisionId "d2"]
        Left cs  -> expectationFailure ("expected one conflict, got " ++ show (length cs))
        Right _  -> expectationFailure "expected a conflict"

  describe "resolve is deterministic (spec 2.4)" $
    it "result is independent of decision order" $ do
      let pool =
            [ mk "d1" "cadence" "daily" Default
            , mk "d2" "cadence" "hourly" Stated
            , mk "d3" "retention" "90d" Default
            , mk "d4" "name" "ledger" Stated
            , mk "d5" "name" "ledger" Stated
            ]
      property $ forAll (shuffle pool) $ \perm ->
        resolveReplace (fromList perm) === resolveReplace (fromList pool)

  describe "list aggregation (B: Append merge mode)" $ do
    let pkgs = Subject ["environment","systemPackages"]
        -- two Stated contributors, canonical VList assertions
        d1 = (mk "d1" "x" "[ \"htop\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
        d2 = (mk "d2" "x" "[ \"ripgrep\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
        rule = MapRule "r" Fact ["pkg"] [ Emit ["environment","systemPackages"] (VList [VStr [PHole "value"]]) ]

    it "mergeModeOf: a subject a rule emits a VList to is Append; else Replace" $ do
      mergeModeOf [rule] (Subject ["environment","systemPackages"]) `shouldBe` Append
      mergeModeOf [rule] (Subject ["pkg"]) `shouldBe` Replace
    it "mergeModeOf: a capture-bearing list emit path matches a concrete subject" $ do
      let r2 = MapRule "r2" Fact ["grp"] [ Emit ["g","<name>","items"] (VList [VStr [PHole "value"]]) ]
      mergeModeOf [r2] (Subject ["g","key1","items"]) `shouldBe` Append

    it "assembleSubject concatenates VList contributors in source-line order" $
      case assembleSubject [d2,d1] of          -- given out of order
        Right synth -> dAssertion synth `shouldBe` Assertion "[ \"ripgrep\" \"htop\" ]"
        Left e      -> expectationFailure ("assemble failed: " <> show e)
    it "assembleSubject preserves package refs across contributors" $ do
      let a = (mk "a" "x" "[ ${pkgs.curl} ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
          b = (mk "b" "x" "[ ${pkgs.htop} ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
      case assembleSubject [a,b] of
        Right synth -> dAssertion synth `shouldBe` Assertion "[ ${pkgs.curl} ${pkgs.htop} ]"
        Left e      -> expectationFailure ("assemble failed: " <> show e)
    it "assembleSubject fails loud on a non-VList contributor" $
      let bad = (mk "b" "x" "\"not-a-list\"" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
       in assembleSubject [bad] `shouldSatisfy` isLeft
    it "assembleSubject provenance links all contributors (walkable)" $
      case assembleSubject [d1,d2] of
        Right synth -> dProv synth `shouldBe` Derived [DecisionId "d2", DecisionId "d1"] (RuleId "append")
        Left e      -> expectationFailure ("assemble failed: " <> show e)

    it "resolve: two Append contributors aggregate, not conflict" $ do
      let base = fromList [d1,d2]
          modeOf _ = Append
      case resolve modeOf assembleSubject base of
        Right m -> Map.size m `shouldBe` 1
        Left _  -> expectationFailure "Append contributors must not conflict"
    it "resolve: a Replace subject still conflicts on equal-strength dissent" $ do
      -- A Replace subject (modeOf returns Replace) keeps today's semantics:
      -- two equal-strength differing assertions conflict, never silently pick.
      let base = fromList [ (mk "a" "x" "\"a\"" Stated) { dSubject = pkgs }
                          , (mk "b" "x" "\"b\"" Stated) { dSubject = pkgs } ]
          modeOf _ = Replace
      case resolve modeOf assembleSubject base of
        Left (REConflict _ : _) -> pure ()
        Left _                  -> expectationFailure "expected REConflict, got REAssemble"
        Right _                 -> expectationFailure "equal-strength dissent on a Replace subject must conflict"
    it "resolve: a single stronger decision on an Append subject wins as-is (no assembly)" $ do
      -- replace-across-strengths: a lone top-strength winner is taken verbatim,
      -- without assembling (the list-shape check is the option schema's job at
      -- generate, not resolve's; resolve never inspects element types).
      let base = fromList [ (mk "a" "x" "[ \"x\" ]" Stated) { dSubject = pkgs }
                          , (mk "b" "x" "[ \"y\" ]" Law) { dSubject = pkgs } ]
      case resolve (const Append) assembleSubject base of
        Right m -> winnerAssertion pkgs m `shouldBe` Just (Assertion "[ \"y\" ]")
        Left e  -> expectationFailure ("a single stronger list should replace, got " <> show e)
    it "resolve: replace-across-strengths -- Law list replaces the Stated list" $ do
      let stated = (mk "s" "x" "[ \"a\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
          law    = (mk "l" "x" "[ \"b\" ]" Law) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
      case resolve (const Append) assembleSubject (fromList [stated,law]) of
        Right m -> winnerAssertion pkgs m `shouldBe` Just (Assertion "[ \"b\" ]")
        Left e  -> expectationFailure ("expected the Law list to replace, got " <> show e)
    it "resolveReplace is today's behavior (no config)" $
      case resolveReplace (fromList [d1,d2]) of
        Left [_] -> pure ()   -- two equal-strength different assertions -> Conflict (today)
        _        -> expectationFailure "without Append, two list lines conflict"

    -- Completeness cases beyond ordered (pinned above) and
    -- replace-across-strengths (pinned above): the list elements need not be
    -- plain strings, and a capture-bearing list emit fans out per concrete key
    -- (an attrsOf-of-list), so siblings on the SAME key aggregate while
    -- different keys coexist.
    it "record-valued: listOf-submodule attrset elements aggregate as-is" $ do
      let u1 = (mk "a" "x" "[ { name = \"app\"; ensureDBOwnership = true; } ]" Stated)
                 { dSubject = Subject ["services","postgresql","ensureUsers"]
                 , dProv = FromSource (SourceLoc "f" 1) }
          u2 = (mk "b" "x" "[ { name = \"web\"; ensureDBOwnership = true; } ]" Stated)
                 { dSubject = Subject ["services","postgresql","ensureUsers"]
                 , dProv = FromSource (SourceLoc "f" 2) }
      case assembleSubject [u1,u2] of
        Right synth -> dAssertion synth `shouldBe`
          Assertion "[ { name = \"app\"; ensureDBOwnership = true; } { name = \"web\"; ensureDBOwnership = true; } ]"
        Left e      -> expectationFailure ("assemble failed: " <> show e)
    it "attrsOf-of-list (Q5): same-key contributors aggregate, distinct keys coexist" $ do
      let r    = MapRule "r" Fact ["grp"]
                   [ Emit ["g","<name>","items"] (VList [VStr [PHole "value"]]) ]
          modeOf = mergeModeOf [r]
      -- the capture path matches any concrete key, so each key is Append
      modeOf (Subject ["g","key1","items"]) `shouldBe` Append
      modeOf (Subject ["g","key2","items"]) `shouldBe` Append
      let k1a = (mk "a" "x" "[ \"x\" ]" Stated)
                  { dSubject = Subject ["g","key1","items"], dProv = FromSource (SourceLoc "f" 1) }
          k1b = (mk "b" "x" "[ \"y\" ]" Stated)
                  { dSubject = Subject ["g","key1","items"], dProv = FromSource (SourceLoc "f" 2) }
          k2  = (mk "c" "x" "[ \"z\" ]" Stated)
                  { dSubject = Subject ["g","key2","items"], dProv = FromSource (SourceLoc "f" 3) }
      case resolve modeOf assembleSubject (fromList [k1a,k1b,k2]) of
        Right m -> Map.size m `shouldBe` 2   -- key1 (assembled) + key2 (alone)
        Left e  -> expectationFailure ("resolve failed: " <> show e)

    it "end-to-end: two install lines aggregate into one systemPackages list" $ do
      -- Each line crystallizes to a DISTINCT captured subject (install.<pkg>),
      -- so the human base does not conflict; the rule emits a VList rhs to the
      -- COMMON environment.systemPackages, so resolve assembles both into one.
      let pat = patOne "p" [TLit "install", THole "pkg"] Fact
                  [SLit "install.", SHole "pkg"] [SHole "pkg"]
          installRule = MapRule "r" Fact ["install", "<pkg>"]
                   [ Emit ["environment","systemPackages"] (VList [VStr [PHole "value"]]) ]
          prog = T.unlines [ "install htop.", "install ripgrep." ]
          modeOf = mergeModeOf [installRule]
      case crystallize "f" [pat] prog of
        Left e  -> expectationFailure ("crystallize failed: " <> show e)
        Right base -> case runBase modeOf assembleSubject 100 (map toRule [installRule]) [] base of
          Left e     -> expectationFailure ("run failed: " <> show e)
          Right rl -> rlModule rl `shouldSatisfy`
            T.isInfixOf "environment.systemPackages = [ \"htop\" \"ripgrep\" ];"

    it "end-to-end C: one line with many packages -> one VList, aggregatable with B" $ do
      -- Capability C: a <name.tail> template hole binds the rest of a line, and
      -- a <value.tail> rhs fills to a VList of those tokens. Each line
      -- crystallizes to a DISTINCT subject (install.<n:index>, since a multi-word
      -- capture may not key a subject), so the
      -- human base does not conflict; the rule emits a VTail rhs to the COMMON
      -- environment.systemPackages, so resolve assembles both VLists into one.
      let pat = patOne "p" [TLit "install", TMulti "pkgs"] Fact
                  [SLit "install.", SHole "n:index"] [SHole "pkgs"]
          tailRule = MapRule "r" Fact ["install", "<pkg>"]
                   [ Emit ["environment","systemPackages"] (VTail Nothing "value") ]
          prog = T.unlines [ "install htop, ripgrep.", "install tmux." ]
          modeOf = mergeModeOf [tailRule]
      case crystallize "f" [pat] prog of
        Left e  -> expectationFailure ("crystallize failed: " <> show e)
        Right base -> case runBase modeOf assembleSubject 100 (map toRule [tailRule]) [] base of
          Left e     -> expectationFailure ("run failed: " <> show e)
          Right rl -> rlModule rl `shouldSatisfy`
            T.isInfixOf "environment.systemPackages = [ \"htop\" \"ripgrep\" \"tmux\" ];"

    it "end-to-end C+pkg: a line of package names realizes to a list of derivations" $ do
      -- The package-derivation tail: <value.tail:pkg> fills each token to a
      -- pkgs.<token> derivation, so one line of package names becomes one
      -- VList of derivations. Realize emits them bare (a Nix list holds
      -- derivations), so the module carries [ pkgs.htop pkgs.ripgrep pkgs.tmux ],
      -- the shape environment.systemPackages demands. This is the capability
      -- the string-tail form above could not express (it would emit strings).
      let pat = patOne "p" [TLit "install", TMulti "pkgs"] Fact
                  [SLit "install.", SHole "n:index"] [SHole "pkgs"]
          tailRule = MapRule "r" Fact ["install", "<pkg>"]
                   [ Emit ["environment","systemPackages"] (VTail (Just HPkg) "value") ]
          prog = T.unlines [ "install htop, ripgrep.", "install tmux." ]
          modeOf = mergeModeOf [tailRule]
      case crystallize "f" [pat] prog of
        Left e  -> expectationFailure ("crystallize failed: " <> show e)
        Right base -> case runBase modeOf assembleSubject 100 (map toRule [tailRule]) [] base of
          Left e     -> expectationFailure ("run failed: " <> show e)
          Right rl -> rlModule rl `shouldSatisfy`
            T.isInfixOf "environment.systemPackages = [ pkgs.htop pkgs.ripgrep pkgs.tmux ];"

    it "end-to-end: N separate bullet facts each contribute one package via a singleton-list rhs" $ do
      -- The "COMMON TRAP" case (Minting.hs): a heading followed by one bullet
      -- per package, each bullet crystallizing to its OWN fact subject
      -- (pkg.<name>). A rule mapping pkg.<name> must wrap its <value:pkg> hole
      -- in a one-element list -- "[ <value:pkg> ]" -- so each contributor's rhs
      -- is itself a VList (required both to pass the option schema's OTListOf
      -- check and to trigger Append aggregation); a bare, unwrapped hole here
      -- would satisfy neither, since its value shape is a single reference.
      let pat = patOne "p" [TLit "-", THole "name"] Fact
                  [SLit "pkg.", SHole "name"] [SHole "name"]
          pkgRule = MapRule "r" Fact ["pkg", "<name>"]
                   [ Emit ["environment","systemPackages"] (VList [VHole HPkg "value"]) ]
          prog = T.unlines [ "- npm", "- bun", "- scala" ]
          modeOf = mergeModeOf [pkgRule]
      case crystallize "f" [pat] prog of
        Left e  -> expectationFailure ("crystallize failed: " <> show e)
        Right base -> case runBase modeOf assembleSubject 100 (map toRule [pkgRule]) [] base of
          Left e     -> expectationFailure ("run failed: " <> show e)
          Right rl -> rlModule rl `shouldSatisfy`
            T.isInfixOf "environment.systemPackages = [ pkgs.npm pkgs.bun pkgs.scala ];"

  describe "refinement (spec 2.4, 4)" $ do
    let oblige = (mk "o1" "row" "row->txn" Stated) { dKind = Oblige }
        -- one rule: an Oblige expands into one Meta mechanism decision
        mechRule = Rule
          { rId      = RuleId "ingest"
          , rMatches = (== Oblige) . dKind
          , rRewrite = \_ -> Right [ (mk "ignored" "row" "upsert-keyed" Stated) { dKind = Meta } ]
          }

    it "a ground base is a fixpoint (unchanged)" $ do
      let base = fromList [mk "d1" "x" "a" Stated]
      refine 100 [mechRule] base `shouldBe` Right base

    it "one matching rule expands the decision to ground" $ do
      case refine 100 [mechRule] (fromList [oblige]) of
        Right b -> do
          let ds = toList b
          length ds `shouldBe` 1
          map dKind ds `shouldBe` [Meta]
        Left e  -> expectationFailure ("unexpected error: " ++ show e)

    it "the refiner stamps derived provenance linking parent and rule" $ do
      case refine 100 [mechRule] (fromList [oblige]) of
        Right b -> case toList b of
          [child] -> dProv child `shouldBe` Derived [DecisionId "o1"] (RuleId "ingest")
          _       -> expectationFailure "expected exactly one child"
        Left e  -> expectationFailure ("unexpected error: " ++ show e)

    it "a decision matched by two rules is an Overlap error (orthogonality)" $ do
      let r1 = mechRule { rId = RuleId "r1" }
          r2 = mechRule { rId = RuleId "r2" }
      refine 100 [r1, r2] (fromList [oblige])
        `shouldBe` Left (Overlap (DecisionId "o1") [RuleId "r1", RuleId "r2"])

    it "a non-terminating rule fails loud within the budget" $ do
      let loop = Rule
            { rId      = RuleId "loop"
            , rMatches = (== Oblige) . dKind
            , rRewrite = \_ -> Right [ (mk "again" "row" "x" Stated) { dKind = Oblige } ]
            }
      refine 10 [loop] (fromList [oblige]) `shouldBe` Left (Nonterminating 10)

    it "a rule whose <value.N> outruns the program value fails loud, never crashes" $ do
      -- Regression (kernel review): editing a program so a value loses a token
      -- must fail through the error channel on the deterministic print path,
      -- not throw a Haskell exception.
      let r = MapRule "r" Fact ["x"]
                [ Emit ["opt"] (VStr [PHole "value.2"]) ]
          matched = (mk "d" "x" "only-one-word" Stated) { dSubject = Subject ["x"] }
      case refine 100 [toRule r] (fromList [matched]) of
        Left (RewriteFailed (DecisionId "d") (RuleId "r") _) -> pure ()
        other -> expectationFailure ("expected RewriteFailed, got " ++ show other)

  describe "demands and open questions (spec 2.5)" $ do
    let hasSubject s b = any ((== Subject [s]) . dSubject) (toList b)
        needCurrency = Demand "currency" "what currency do amounts use?" (hasSubject "currency")

    it "an unmet demand is an open question; base is incomplete" $ do
      let base = fromList [mk "d1" "row" "a" Stated]
      map demId (openQuestions [needCurrency] base) `shouldBe` ["currency"]
      complete [needCurrency] base `shouldBe` False

    it "a met demand leaves no open question; base is complete" $ do
      let base = fromList [mk "d1" "currency" "EUR" Stated]
      map demId (openQuestions [needCurrency] base) `shouldBe` []
      complete [needCurrency] base `shouldBe` True

  describe "canonical form (spec 2: reader round-trips render)" $ do
    it "reads a well-formed line into the expected decision" $ do
      let line = "d1 invariant account.balance stated \"sum of transactions\" @ledger:4"
      readDecision line `shouldBe`
        Right Decision
          { dId        = DecisionId "d1"
          , dSubject   = Subject ["account", "balance"]
          , dKind      = Invariant
          , dAssertion = Assertion "sum of transactions"
          , dStrength  = Stated
          , dProv      = FromSource (SourceLoc "ledger" 4)
          , dRationale = Nothing
          }

    it "reads a derived provenance line" $ do
      let line = "m1 meta row stated \"upsert\" <-o1,d3 via ingest"
      (dProv <$> readDecision line) `shouldBe`
        Right (Derived [DecisionId "o1", DecisionId "d3"] (RuleId "ingest"))

    it "rejects an unknown kind (fail loud)" $
      readDecision "d1 whatever x stated \"a\"" `shouldSatisfy` isLeft

    it "skips comment and blank lines" $ do
      let src = "# concepts\n\nd1 fact currency stated \"EUR\" @ledger:6\n"
      (fmap (map dId . toList) (readBase src)) `shouldBe` Right [DecisionId "d1"]

    it "round-trips any base: readBase . renderBase == id" $
      property $ \ds ->
        let b = fromList ds in readBase (renderBase b) === Right b

  describe "realization (spec 10: base -> NixOS module)" $ do
    let ground =
          [ (mk "g1" "services" "true" Stated) { dSubject = Subject ["services", "ledger", "enable"], dProv = Derived [DecisionId "m31"] (RuleId "ingest") }
          , (mk "g2" "timer" "\"daily\"" Stated) { dSubject = Subject ["systemd", "timers", "ledger", "timerConfig", "OnCalendar"], dProv = FromSource (SourceLoc "ledger" 2) }
          ]

    it "emits a valid module with sorted, provenance-tagged assignments" $ do
      let expected = T.unlines
            [ "# lips-realized module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-m31 via ingest"
            , "  services.ledger.enable = true;"
            , "  # ledger:2"
            , "  systemd.timers.ledger.timerConfig.OnCalendar = \"daily\";"
            , "}"
            ]
      realizeReplace (fromList ground) `shouldBe` Right expected

    it "refuses to realize a base with a conflict" $ do
      let clash = [mk "a" "x" "true" Stated, mk "b" "x" "false" Stated]
      realizeReplace (fromList clash) `shouldSatisfy` isLeft

    -- An unfilled <value.tail> (VTail) must never silently render as the
    -- literal string "<value.tail>" into a module. In production fillValue
    -- always converts VTail -> VList before storage, and a non-firing rule
    -- stores nothing, so this path is unreachable today -- but "fail loud,
    -- never guess" is a kernel invariant enforced structurally, not trusted to
    -- "currently unreachable." If a future change lets an unfilled tail reach
    -- realize, it must fail through the error channel, not emit a bogus string.
    it "refuses to realize an unfilled <value.tail> (fail loud, not a literal)" $ do
      let g = (mk "g" "x" "<value.tail>" Stated)
                { dSubject = Subject ["environment", "systemPackages"] }
      realizeReplace (fromList [g]) `shouldSatisfy` isLeft

    -- A value-keyed segment (e.g. a route path) is often not a bare Nix
    -- identifier, so it must be string-quoted in the emitted attribute path;
    -- plain identifier segments stay unquoted (existing engines unchanged).
    it "quotes an option-path segment that is not a bare Nix identifier" $ do
      let g = (mk "g" "x" "\"world\"" Stated)
                { dSubject = Subject ["environment", "etc", "httpserver/hello", "text"] }
      case realizeReplace (fromList [g]) of
        Right out -> out `shouldSatisfy`
                       T.isInfixOf "environment.etc.\"httpserver/hello\".text = \"world\";"
        Left e    -> expectationFailure ("unexpected realize error: " ++ show e)

    it "is order-independent (deterministic output)" $
      property $ forAll (shuffle ground) $ \perm ->
        realizeReplace (fromList perm) === realizeReplace (fromList ground)

    it "gathers artifact.<name> groups into a let-bound derivation" $ do
      let arts =
            [ (mk "b" "x" "\"rustPlatform.buildRustPackage\"" Stated) { dSubject = Subject ["artifact","myserver","builder"] }
            , (mk "p" "x" "\"myserver\"" Stated) { dSubject = Subject ["artifact","myserver","args","pname"] }
            , (mk "s" "x" "./ledger.artifacts/myserver" Stated) { dSubject = Subject ["artifact","myserver","args","src"] }
            , (mk "e" "x" "\"${artifact.myserver}/bin/myserver\"" Stated) { dSubject = Subject ["systemd","services","myserver","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 1) }
            ]
          expected = T.unlines
            [ "# lips-realized module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "let"
            , "  artifact = {"
            , "    myserver = pkgs.rustPlatform.buildRustPackage {"
            , "      pname = \"myserver\";"
            , "      src = ./ledger.artifacts/myserver;"
            , "      meta.mainProgram = \"myserver\";"
            , "    };"
            , "  };"
            , "in"
            , "{"
            , "  # app:1"
            , "  systemd.services.myserver.serviceConfig.ExecStart = \"${artifact.myserver}/bin/myserver\";"
            , "}"
            ]
      realizeReplace (fromList arts) `shouldBe` Right expected

    it "extracts the same artifacts into a standalone artifact.nix (addressable for a flake)" $ do
      let arts =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","myserver","builder"] }
            , (mk "p" "x" "\"myserver\"" Stated) { dSubject = Subject ["artifact","myserver","args","pname"] }
            , (mk "s" "x" "./artifacts/myserver" Stated) { dSubject = Subject ["artifact","myserver","args","src"] }
            , (mk "e" "x" "\"${artifact.myserver}/bin/myserver\"" Stated) { dSubject = Subject ["systemd","services","myserver","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 1) }
            ]
          expected = T.unlines
            [ "# lips-realized artifact derivations. Generated; do not edit."
            , "{ pkgs }:"
            , "let"
            , "  artifact = {"
            , "    myserver = pkgs.buildGoModule {"
            , "      pname = \"myserver\";"
            , "      src = ./artifacts/myserver;"
            , "      meta.mainProgram = \"myserver\";"
            , "    };"
            , "  };"
            , "in"
            , "artifact"
            ]
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList arts)
        `shouldBe` Right (Just (expected, ["myserver"]))

    -- nix's default `nix run`/`nix develop` program lookup assumes
    -- bin/<pname>; a builder is free to name its output differently (a Go
    -- module's own name, a Cargo bin name), so the compiled binary can be
    -- called anything. realize already knows the true name wherever a
    -- program's own decisions spell it out, in a path like
    -- ${artifact.<name>}/bin/<x> (e.g. an ExecStart) -- so it stamps that name
    -- as meta.mainProgram, never a guessed or hardcoded convention, and only
    -- when the base names exactly one candidate (never when it names none, or
    -- more than one -- deduce-or-fail: an ambiguous base leaves nix's
    -- unchanged default in place, exactly as it does today).
    it "names meta.mainProgram from a bin/<x> path even when <x> differs from the artifact's own name" $ do
      let arts =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","website","builder"] }
            , (mk "p" "x" "\"website\"" Stated) { dSubject = Subject ["artifact","website","args","pname"] }
            , (mk "s" "x" "./artifacts/website" Stated) { dSubject = Subject ["artifact","website","args","src"] }
            , (mk "e" "x" "\"${artifact.website}/bin/site\"" Stated) { dSubject = Subject ["systemd","services","website","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 1) }
            ]
          expected = T.unlines
            [ "# lips-realized artifact derivations. Generated; do not edit."
            , "{ pkgs }:"
            , "let"
            , "  artifact = {"
            , "    website = pkgs.buildGoModule {"
            , "      pname = \"website\";"
            , "      src = ./artifacts/website;"
            , "      meta.mainProgram = \"site\";"
            , "    };"
            , "  };"
            , "in"
            , "artifact"
            ]
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList arts)
        `shouldBe` Right (Just (expected, ["website"]))

    -- Ambiguous evidence never becomes a guess: two ExecStarts inside one
    -- artifact naming two different bin/<x> paths leave meta.mainProgram unset
    -- rather than picking either arbitrarily.
    it "leaves meta.mainProgram unset when a base names more than one bin/<x> candidate" $ do
      let arts =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","website","builder"] }
            , (mk "p" "x" "\"website\"" Stated) { dSubject = Subject ["artifact","website","args","pname"] }
            , (mk "e1" "x" "\"${artifact.website}/bin/site\"" Stated) { dSubject = Subject ["systemd","services","website","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 1) }
            , (mk "e2" "x" "\"${artifact.website}/bin/other\"" Stated) { dSubject = Subject ["systemd","services","other","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 2) }
            ]
          expected = T.unlines
            [ "# lips-realized artifact derivations. Generated; do not edit."
            , "{ pkgs }:"
            , "let"
            , "  artifact = {"
            , "    website = pkgs.buildGoModule {"
            , "      pname = \"website\";"
            , "    };"
            , "  };"
            , "in"
            , "artifact"
            ]
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList arts)
        `shouldBe` Right (Just (expected, ["website"]))

    -- An artifact arg may name another artifact (the core-plus-wrapper shape:
    -- a wrapper's runtimeInputs holds ${artifact.core}). In the module the
    -- reference resolves because a Nix @let@ is recursive; the standalone file
    -- is an attrset, so it must say @rec@ or the reference is an undefined
    -- variable and the file evaluates only by accident of never being read.
    it "binds artifact.nix recursively so one artifact may reference another" $ do
      let arts =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","core","builder"] }
            , (mk "p" "x" "\"core\"" Stated) { dSubject = Subject ["artifact","core","args","pname"] }
            , (mk "wb" "x" "\"writeShellApplication\"" Stated) { dSubject = Subject ["artifact","wrap","builder"] }
            , (mk "wr" "x" "[ ${artifact.core} ]" Stated) { dSubject = Subject ["artifact","wrap","args","runtimeInputs"] }
            ]
          expected = T.unlines
            [ "# lips-realized artifact derivations. Generated; do not edit."
            , "{ pkgs }:"
            , "let"
            , "  artifact = {"
            , "    core = pkgs.buildGoModule {"
            , "      pname = \"core\";"
            , "    };"
            , "    wrap = pkgs.writeShellApplication {"
            , "      runtimeInputs = [ artifact.core ];"
            , "    };"
            , "  };"
            , "in"
            , "artifact"
            ]
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList arts)
        `shouldBe` Right (Just (expected, ["core","wrap"]))

    -- The dangling check used to scan option assignments only, so an artifact
    -- arg naming an unbuilt artifact reached the module and died inside nix as
    -- "attribute 'nosuch' missing" -- no lips, no program, no remedy.
    it "catches a dangling ${artifact.<name>} inside an artifact arg" $ do
      let dangling =
            [ (mk "wb" "x" "\"writeShellApplication\"" Stated) { dSubject = Subject ["artifact","wrap","builder"] }
            , (mk "wr" "x" "[ ${artifact.nosuch} ]" Stated) { dSubject = Subject ["artifact","wrap","args","runtimeInputs"] }
            ]
      realizeReplace (fromList dangling) `shouldBe` Left (RDangling ["nosuch"])
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList dangling)
        `shouldBe` Left (RDangling ["nosuch"])

    it "emits no artifact.nix for a program with no artifacts" $
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList ground)
        `shouldBe` Right Nothing

    -- A relative path literal names a file lips STAGED beside the module (an
    -- artifact's source tree). It is the one value a module cannot vouch for
    -- itself: nix resolves it against the module directory, so a path naming
    -- nothing dies inside nix, naming neither lips nor the program. realize
    -- therefore reports every relative path with the decision that named it,
    -- and the caller -- which owns the filesystem -- requires it to exist.
    -- An absolute path belongs to the host, so it is not lips's to check.
    it "reports the relative paths the realized base names (absolute ones are the host's)" $ do
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","myserver","builder"] }
            , (mk "s" "x" "./artifacts/myserver" Stated) { dSubject = Subject ["artifact","myserver","args","src"] }
            , (mk "f" "x" "./artifacts/myserver/motd" Stated) { dSubject = Subject ["environment","etc","motd","source"] }
            , (mk "a" "x" "/etc/hosts" Stated) { dSubject = Subject ["environment","etc","hosts","source"] }
            ]
      fmap (map fst) (realizeStagedPaths (const Replace) (\_ -> Left "unused") (fromList ps))
        `shouldBe` Right ["./artifacts/myserver", "./artifacts/myserver/motd"]

    -- Source fills: the engine declares them under the artifact, realize reports
    -- them, and the caller substitutes them into the tree it stages. Realize
    -- refuses a fill that could never be written into source, so the defect is
    -- named at the engine instead of appearing as Nix syntax inside a program.
    it "reports the source fills an artifact declares" $ do
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","tool","builder"] }
            , (mk "n" "x" "\"logscan\"" Stated) { dSubject = Subject ["artifact","tool","fill","name"] }
            , (mk "p" "x" "8080" Stated) { dSubject = Subject ["artifact","tool","fill","port"] }
            ]
      realizeArtifactFills (const Replace) (\_ -> Left "unused") (fromList ps)
        `shouldBe` Right [("tool","name","logscan"), ("tool","port","8080")]

    it "refuses a fill whose value has no source text (a derivation is not text)" $ do
      let ps = [ (mk "n" "x" "\"${artifact.other}\"" Stated) { dSubject = Subject ["artifact","tool","fill","name"] } ]
      realizeArtifactFills (const Replace) (\_ -> Left "unused") (fromList ps)
        `shouldSatisfy` \r -> case r of Left (RBadArtifact "tool" _) -> True; _ -> False

    it "refuses a fill whose marker no source file could ever name" $ do
      let ps = [ (mk "n" "x" "\"logscan\"" Stated) { dSubject = Subject ["artifact","tool","fill","2nd"] } ]
      realizeArtifactFills (const Replace) (\_ -> Left "unused") (fromList ps)
        `shouldSatisfy` \r -> case r of Left (RBadArtifact "tool" _) -> True; _ -> False

    it "refuses an artifact section the kernel does not know (it would be dropped)" $ do
      -- Before this guard, args/builder were selected and anything else silently
      -- ignored, so a mint's typo compiled to a derivation missing what it said.
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","tool","builder"] }
            , (mk "a" "x" "\"0.1.0\"" Stated) { dSubject = Subject ["artifact","tool","arg","version"] }
            ]
      realizeReplace (fromList ps)
        `shouldSatisfy` \r -> case r of Left (RBadArtifact "tool" _) -> True; _ -> False

    it "reports no staged path for a base that names none" $
      realizeStagedPaths (const Replace) (\_ -> Left "unused") (fromList ground)
        `shouldBe` Right []

    -- A path INSIDE a build (${artifact.<name>}/bin/hello) is decided by the
    -- SOURCE, not by the derivation, so no static gate can know it is there: an
    -- http mint that left `module server` in go.mod named /bin/hello and shipped
    -- a unit that cannot start. realize reports every such (artifact, path) pair
    -- with the decision that named it, so the caller -- which may build -- can
    -- look inside the result. Structural, from the parsed Value: the flake check
    -- that predates this regexed the module text instead.
    it "reports the paths the realized base names INSIDE an artifact" $ do
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","hello","builder"] }
            , (mk "p" "x" "\"hello\"" Stated) { dSubject = Subject ["artifact","hello","args","pname"] }
            , (mk "e" "x" "\"${artifact.hello}/bin/hello\"" Stated) { dSubject = Subject ["systemd","services","hello","serviceConfig","ExecStart"] }
            -- a bare reference names the whole build, so there is no path to look for
            , (mk "l" "x" "[ ${artifact.hello} ]" Stated) { dSubject = Subject ["environment","systemPackages"] }
            ]
      fmap (map (\(n, p, _) -> (n, p)))
           (realizeArtifactPaths (const Replace) (\_ -> Left "unused") (fromList ps))
        `shouldBe` Right [("hello", "/bin/hello")]

    it "stops an inside-artifact path at the first space (a command carries arguments)" $ do
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","hello","builder"] }
            , (mk "p" "x" "\"hello\"" Stated) { dSubject = Subject ["artifact","hello","args","pname"] }
            , (mk "e" "x" "\"${artifact.hello}/bin/hello --port 8080\"" Stated) { dSubject = Subject ["systemd","services","hello","serviceConfig","ExecStart"] }
            ]
      fmap (map (\(n, p, _) -> (n, p)))
           (realizeArtifactPaths (const Replace) (\_ -> Left "unused") (fromList ps))
        `shouldBe` Right [("hello", "/bin/hello")]

    it "reports a path inside an artifact referenced from another artifact's arg" $ do
      -- The core-plus-wrapper shape: writeShellApplication whose text execs the
      -- compiled core. The wrapper's own script is where the binary name is
      -- spelled, so this is exactly where the naming defect hides.
      let ps =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","tool-core","builder"] }
            , (mk "p" "x" "\"tool-core\"" Stated) { dSubject = Subject ["artifact","tool-core","args","pname"] }
            , (mk "w" "x" "\"writeShellApplication\"" Stated) { dSubject = Subject ["artifact","tool","builder"] }
            , (mk "t" "x" "\"exec ${artifact.tool-core}/bin/tool-core\"" Stated) { dSubject = Subject ["artifact","tool","args","text"] }
            ]
      fmap (map (\(n, p, _) -> (n, p)))
           (realizeArtifactPaths (const Replace) (\_ -> Left "unused") (fromList ps))
        `shouldBe` Right [("tool-core", "/bin/tool-core")]

    it "reports no inside-artifact path for a base that names none" $
      realizeArtifactPaths (const Replace) (\_ -> Left "unused") (fromList ground)
        `shouldBe` Right []

    it "fails loud (typed, not a crash) on a ${artifact.<name>} reference to an undefined artifact" $
      let dangling = [ (mk "e" "x" "\"${artifact.ghost}/bin/x\"" Stated) { dSubject = Subject ["systemd","services","x","serviceConfig","ExecStart"] } ]
       in realizeReplace (fromList dangling) `shouldBe` Left (RDangling ["ghost"])

    it "detects an artifact reference in a canonical list and flags it dangling if unbuilt" $ do
      -- systemPackages is a list of derivations; a list element references an
      -- artifact via the canonical ${artifact.<name>} form (stored by fillValue,
      -- detected structurally from the parsed Value, not text-scanned).
      let built =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","weather","builder"] }
            , (mk "p" "x" "\"weather\"" Stated) { dSubject = Subject ["artifact","weather","args","pname"] }
            , (mk "e" "x" "[ ${artifact.weather} ]" Stated) { dSubject = Subject ["environment","systemPackages"] }
            ]
      realizeReplace (fromList built) `shouldSatisfy` isRight
      -- a ref to an unbuilt artifact still fails loud
      let dangling = [ (mk "e" "x" "[ ${artifact.ghost} ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realizeReplace (fromList dangling) `shouldBe` Left (RDangling ["ghost"])
      -- the literal token "artifact." inside a string is NOT a reference: a
      -- VStr holds it as a PLit, so valueArtifactNames finds nothing.
      let litText = [ (mk "e" "x" "\"see artifact.ghost docs\"" Stated) { dSubject = Subject ["environment","variables","NOTE"] } ]
      realizeReplace (fromList litText) `shouldSatisfy` isRight
      -- a package whose OWN segment is 'artifact' is a package (RPkg), not an
      -- artifact (RArt): valueArtifactNames returns [] for RPkg.
      let pkgPath = [ (mk "e" "x" "${pkgs.foo.artifact.bar}" Stated) { dSubject = Subject ["services","x","package"] } ]
      realizeReplace (fromList pkgPath) `shouldSatisfy` isRight
      let pkgList = [ (mk "e" "x" "[ ${pkgs.foo.artifact.bar} ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realizeReplace (fromList pkgList) `shouldSatisfy` isRight

    -- A name that reached realize still carrying a <token> was never bound (a
    -- rule whose <self> or <capture> nothing filled). Nothing used to stop it:
    -- artifactEntries took any name segment verbatim, and the dangling check
    -- compares ref names to group names TEXTUALLY, so an unfilled ref and an
    -- unfilled group agreed and the literal "<self>-core = pkgs.buildGoModule"
    -- was written into the module. Fail loud instead, naming the name.
    it "fails loud on an artifact name that reached realize unfilled" $ do
      let unfilled =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","<self>-core","builder"] }
            , (mk "e" "x" "[ ${artifact.<self>-core} ]" Stated) { dSubject = Subject ["environment","systemPackages"] }
            ]
      realizeReplace (fromList unfilled) `shouldBe`
        Left (RBadArtifact "<self>-core" "artifact name reached realize with the token <self> unfilled; a <self> binds per instance and a <capture> per rule match, so this name was never bound")
      -- the same guard on the standalone artifact.nix path
      realizeArtifactFile (const Replace) (\_ -> Left "unused") (fromList unfilled)
        `shouldSatisfy` isLeft

    it "fails loud (typed) on a malformed artifact group (no builder)" $
      let noBuilder = [ (mk "p" "x" "\"srv\"" Stated) { dSubject = Subject ["artifact","srv","args","pname"] } ]
       in realizeReplace (fromList noBuilder) `shouldBe` Left (RBadArtifact "srv" "no builder")

  describe "run pipeline (spec 5: four outcomes)" $ do
    -- an engine: one rule mapping any Oblige to a ground option assignment
    let engine = [ Rule (RuleId "ingest") ((== Oblige) . dKind)
                     (\_ -> Right [ (mk "x" "x" "true" Stated) { dSubject = Subject ["services", "ledger", "enable"], dKind = Meta } ]) ]
        needs subj = [ Demand "q" ("need " <> T.intercalate "." subj) (any ((== Subject subj) . dSubject) . toList) ]
        prog = "o1 oblige feed.ingest stated \"row->txn\" @ledger:9\n"

    it "parse rejection: a malformed line re-enters generate" $
      runReplace 100 engine [] "this line has no quoted assertion"
        `shouldSatisfy` \r -> case r of Left (ParseRejected _) -> True; _ -> False

    it "open question: an unmet demand is surfaced verbatim" $
      runReplace 100 engine (needs ["currency"]) prog
        `shouldBe` Left (OpenQuestions ["need currency"])

    it "conflict: equal-strength contradiction stops the run" $
      runReplace 100 engine [] "d1 fact x stated \"1\" @f:1\nd2 fact x stated \"2\" @f:2\n"
        `shouldSatisfy` \r -> case r of Left (Conflicted _) -> True; _ -> False

    it "unmapped: an obligation no rule maps fails loud (anti-MDA guard)" $
      runReplace 100 engine (needs ["feed", "ingest"])
        "o1 oblige feed.ingest stated \"rows\" @l:9\nx1 invariant feed.dedup stated \"never twice\" @l:10\n"
        `shouldSatisfy` \r -> case r of Left (Unmapped ds) -> map dSubject ds == [Subject ["feed", "dedup"]]; _ -> False

    it "realization: a satisfied program refines and realizes to a module" $ do
      let expected = T.unlines
            [ "# lips-realized module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-o1 via ingest"
            , "  services.ledger.enable = true;"
            , "}"
            ]
      runReplace 100 engine (needs ["feed", "ingest"]) prog `shouldBe` Right expected

    it "a concept line is decorative: it neither fails Unmapped nor realizes" $ do
      -- A heading like "http routes:" crystallizes to a 'Concept': vocabulary
      -- that groups and explains the lines under it, with no obligation to
      -- realize. It must not trip the anti-MDA guard, and must not leak into
      -- the module as an option assignment.
      let withHeading = "h1 concept http.routes stated \"routes\" @prog:1\n" <> prog
          expected = T.unlines
            [ "# lips-realized module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-o1 via ingest"
            , "  services.ledger.enable = true;"
            , "}"
            ]
      runReplace 100 engine [] withHeading `shouldBe` Right expected

  describe "generate minting (engine-synthesis plan: whole-engine candidates)" $ do
    it "parses the three item forms and assembles an engine" $ do
      let reply = T.unlines
            [ "0.95 p1 pattern the bank drops files into <loc> => fact feed.source \"<loc>\""
            , "0.9 r1 match fact feed.source => systemd.services.i.environment.INBOX \"\\\"<value>\\\"\""
            , "0.85 q1 demand feed.source \"where do the files arrive?\""
            , "0.95 a1 expect systemd.services.i.environment.INBOX from feed.source"
            ]
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      map icConfidence cs `shouldBe` map Confidence [0.95, 0.9, 0.85, 0.95]
      let eng = assemble (map icItem cs)
      (length (edPatterns eng), length (edRules eng), length (edDemands eng)) `shouldBe` (1, 1, 1)
      length (expectsOf (map icItem cs)) `shouldBe` 1

    it "keeps a value escape (\\n) that only the transport layer would swallow" $ do
      -- Regression (api.web mint, 2026-07-30): a rule joining two words with a
      -- newline realized "200n404" -- valid output, wrong text, invisible to
      -- every gate. Only \" and \\ are transport escapes; anything else belongs
      -- to the value grammar inside, which reads \n as a newline.
      let reply = "0.9 r1 match fact p => environment.etc.pair.text \"\\\"<value.1>\\n<value.2>\\\"\""
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      case [ emRhs e | ItemRule r <- map icItem cs, e <- mrEmits r ] of
        [VStr [PHole "value.1", PLit "\n", PHole "value.2"]] -> pure ()
        other -> expectationFailure ("expected a newline between the two holes, got " ++ show other)

    it "a pattern template may begin with a dispatch keyword (no collision)" $ do
      -- Regression (kernel review): a loose line starting with a domain word
      -- like "match" must mint as a pattern, not be misrouted to the rule
      -- parser. The leading 'pattern' keyword makes the kind explicit.
      let reply = "0.95 p1 pattern match <a> to <b> => fact link.p \"<a> <b>\""
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      case map icItem cs of
        [ItemPattern _] -> pure ()
        other           -> expectationFailure ("expected one pattern, got " ++ show other)

    it "skips fences and comments, collects malformed lines as errors" $ do
      let reply = T.unlines
            [ "```", "# note", ""
            , "0.9 p1 pattern every bank row becomes one <e> => oblige feed.ingest \"<e>\""
            , "2.0 p2 pattern x => fact y \"z\""   -- confidence out of range
            , "0.9 r9 match fact feed.x => a.b \"<mystery>\""  -- unknown emit hole
            , "```"
            ]
          (errs, cs) = parseEngineCandidates reply
      length cs `shouldBe` 1
      length errs `shouldBe` 2

    it "collects a multi-line source block verbatim (artifacts plan)" $ do
      let reply = T.unlines
            [ "0.95 r1 match oblige srv.run => artifact.srv.builder \"\\\"writeShellApplication\\\"\""
            , "0.9 s1 source srv src/main.rs <<<lips"
            , "fn main() {"
            , "    # not a comment: real content"
            , ""
            , "    println!(\"hi\");"
            , "}"
            , "lips>>>"
            , "0.95 a1 expect systemd.services.srv.serviceConfig.ExecStart from srv.run"
            ]
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      case sourcesOf (map icItem cs) of
        [SourceFile a p c] -> do
          (a, p) `shouldBe` ("srv", "src/main.rs")
          c `shouldBe` "fn main() {\n    # not a comment: real content\n\n    println!(\"hi\");\n}"
        _ -> expectationFailure "expected exactly one source file"
      length cs `shouldBe` 3

    it "a report block carries the mint's prose verbatim" $ do
      let reply = "0.9 d1 report <<<lips\n# The backup language\n\nreads two shapes.\nlips>>>\n"
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      reportOf (map icItem cs) `shouldBe` Just "# The backup language\n\nreads two shapes."
      assemble (map icItem cs) `shouldBe` assemble []

    it "a gap block names a missing kernel capability and its repro" $ do
      let reply = T.unlines
            [ "0.4 g1 gap templated-source <<<lips"
            , "blocked line: - /hi => status 200"
            , "source heredocs have no holes, so a per-route body cannot reach the source."
            , "lips>>>"
            ]
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      map gapSlug (gapsOf (map icItem cs)) `shouldBe` ["templated-source"]

    it "exempts report and gap from the confidence gate, like a because-note" $ do
      -- A gap is honest at low confidence by nature, and prose is not engine
      -- meaning: neither may refuse a mint the engine itself is sure of.
      map carriesEngineMeaning [ItemReport "p", ItemGap (Gap "g" "b"), ItemNote "n"]
        `shouldBe` [False, False, False]

    it "the README warns it is generated, carries the prose and lists the gaps" $ do
      let out = renderReadme "backup" "reads three shapes."
                  [Gap "templated-source" "no holes in source blocks"]
      out `shouldSatisfy` T.isInfixOf "lips generate"
      out `shouldSatisfy` T.isInfixOf "reads three shapes."
      out `shouldSatisfy` T.isInfixOf "templated-source"
      renderReadme "backup" "prose" [] `shouldSatisfy` (not . T.isInfixOf "Known Gaps")

    it "reports an unterminated source block" $ do
      let reply = T.unlines [ "0.9 s1 source srv main.rs <<<lips", "content with no closer" ]
          (errs, _) = parseEngineCandidates reply
      length errs `shouldBe` 1

    it "parses a because-note (reason keyed to its item's id, no engine meaning)" $ do
      -- A because-note explains a low-confidence item; it shares that item's id
      -- and contributes nothing to the engine (dropped by assemble).
      let reply = T.unlines
            [ "0.4 r1 match fact art.hash => artifact.a.args.vendorHash \"\\\"<value>\\\"\""
            , "0.4 r1 because \"the program never states the vendor hash\""
            ]
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      [icId c | c <- cs] `shouldBe` ["r1", "r1"]
      [r | c <- cs, ItemNote r <- [icItem c]]
        `shouldBe` ["the program never states the vendor hash"]
      length (edRules (assemble (map icItem cs))) `shouldBe` 1

  describe "behavioral contract (ledger 13: .expect relational gate)" $ do
    let dec subj a = Decision (DecisionId "d") (Subject (T.splitOn "." subj)) Fact
                       (Assertion a) Stated (FromSource (SourceLoc "p" 1)) Nothing
        base = fromList [ dec "backup.job" "/var/lib/ledger /backup/ledger daily" ]
        opt  = Subject ["backup", "job"]

    it "parse/render round-trips" $ do
      let src = "a1 expect services.restic.backups.ledger.repository from backup.job#2\n"
      (renderExpect <$> readExpect src) `shouldBe` Right src

    -- The contract round-trips even when an option path carries a literal
    -- dotted key (environment.etc."my.route".text): the engine path split and
    -- the render must agree, or a dotted segment shreds and the check looks up
    -- the wrong option.
    it "expect round-trips with a dotted segment in the option path" $
      property $ forAll dottedSeg $ \seg ->
        let e = Expect "a" ["services","nginx",seg,"proxyPass"] (Subject ["proxy","upstream"]) Nothing
        in readExpect (renderExpect [e]) === Right [e]

    -- A model may write an attrsOf key in Nix-attr-path form, quoted
    -- (locations."/".proxyPass), or bare (locations./.proxyPass). Both must
    -- parse to the SAME segment, so a rule written bare and an expect written
    -- quoted (or vice versa) still agree and the check looks up the right key.
    it "parses a quoted attrsOf key in an option path to its bare segment" $ do
      parseExpectBody "a" "expect services.nginx.virtualHosts.app.locations.\"/\".proxyPass from proxy.upstream"
        `shouldBe` Right Expect
            { exId = "a"
            , exPath = ["services","nginx","virtualHosts","app","locations","/","proxyPass"]
            , exFrom = Subject ["proxy","upstream"]
            , exToken = Nothing
            }
      -- a quoted key with a dot inside stays one segment (no split on the dot)
      parseExpectBody "a" "expect a.\"file.txt\".b from x"
        `shouldBe` Right Expect
            { exId = "a"
            , exPath = ["a","file.txt","b"]
            , exFrom = Subject ["x"]
            , exToken = Nothing
            }

    it "rejects an unterminated quote in an option path" $
      parseExpectBody "a" "expect a.\"unterminated from x" `shouldSatisfy` isLeft

    it "binds <self> in the option path to the instance (contract is language-level)" $
      bindSelfExpect "ledger" (Expect "a" ["services", "restic", "backups", "<self>", "paths"] opt Nothing)
        `shouldBe` Expect "a" ["services", "restic", "backups", "ledger", "paths"] opt Nothing

    -- A segment is literal text with <token> OCCURRENCES (the same grammar an
    -- artifact name uses, where <self>-core is the core-plus-wrapper idiom), so
    -- <self> binds inside a segment too. Comparing the whole segment left
    -- <self>-core unbound and the assertion silently read null.
    it "binds <self> occurring inside a path segment, not only as a whole one" $
      bindSelfExpect "greet" (Expect "a" ["home", "packages", "<self>-core"] opt Nothing)
        `shouldBe` Expect "a" ["home", "packages", "greet-core"] opt Nothing

    it "resolves the whole assertion and the nth token" $ do
      expectedValue base (Expect "a" ["o"] opt Nothing)  `shouldBe` Right "/var/lib/ledger /backup/ledger daily"
      expectedValue base (Expect "a" ["o"] opt (Just 2)) `shouldBe` Right "/backup/ledger"

    it "fails loud on an out-of-range token or a missing subject" $ do
      expectedValue base (Expect "a" ["o"] opt (Just 9))              `shouldSatisfy` isLeft
      expectedValue base (Expect "a" ["o"] (Subject ["no","x"]) Nothing) `shouldSatisfy` isLeft

    -- Value-keyed contract: a family expect (from route.<path>.status) expands
    -- against the program's routes to one concrete expect per route, each with
    -- its <path> filled into the option path. Completes the capture capability
    -- on the expect side (rules already fan out the same way).
    it "expands a value-keyed family expect to one concrete expect per route" $ do
      let rbase = fromList [ (dec "route./hello.status" "200") { dId = DecisionId "d1" }
                           , (dec "route./bye.status"   "404") { dId = DecisionId "d2" } ]
          fam   = Expect "a" ["environment", "etc", "http-routes<path>", "text"]
                            (Subject ["route", "<path>", "status"]) Nothing
      case expandExpects rbase [fam] of
        Left e   -> expectationFailure ("expand failed: " ++ show e)
        Right xs -> map (\x -> (exFrom x, exPath x)) xs `shouldMatchList`
          [ (Subject ["route", "/hello", "status"], ["environment", "etc", "http-routes/hello", "text"])
          , (Subject ["route", "/bye",   "status"], ["environment", "etc", "http-routes/bye",   "text"]) ]

    it "a plain (captureless) expect passes through expansion unchanged" $
      expandExpects base [Expect "a" ["o"] opt Nothing] `shouldBe` Right [Expect "a" ["o"] opt Nothing]

    it "fails loud on a family expect no decision matches" $
      expandExpects base [Expect "a" ["o"] (Subject ["route", "<path>", "status"]) Nothing]
        `shouldSatisfy` isLeft

    it "containment: the program value must appear in the evaluated option" $ do
      let e = Expect "a1" ["p"] opt (Just 2)
      checkValues [e] [("/backup/ledger", "\"/backup/ledger\"")] `shouldBe` []          -- exact
      checkValues [e] [("hour", "\"hourly\"")]                   `shouldBe` []          -- substring
      length (checkValues [e] [("/backup/ledger", "\"/fixed/repo\"")]) `shouldBe` 1     -- value dropped
      length (checkValues [e] [("/backup/ledger", "null")])           `shouldBe` 1     -- option relocated

    it "rejects a check on a package/artifact-referencing option (would crash eval)" $ do
      -- Regression (kernel review): an expect naming an option a rule fills
      -- with ${pkgs...}/${artifact...} is uncheckable (the check evals with an
      -- empty pkgs stub) and must be flagged, not left to abort nix eval.
      let ruleStr = MapRule "r" Fact ["svc", "name"]
            [ Emit ["systemd","services","s","serviceConfig","ExecStart"] (VStr [PArt "srv", PLit "/bin/s"])
            , Emit ["systemd","services","s","environment","NAME"] (VStr [PHole "value"]) ]
          onDeriv = Expect "a1" ["systemd","services","s","serviceConfig","ExecStart"] (Subject ["svc","name"]) Nothing
          onValue = Expect "a2" ["systemd","services","s","environment","NAME"] (Subject ["svc","name"]) Nothing
      valueRefsDerivation (VStr [PArt "srv", PLit "/bin/s"]) `shouldBe` True
      valueRefsDerivation (VStr [PHole "value"])            `shouldBe` False
      map exId (uncheckableExpects [ruleStr] [onDeriv, onValue]) `shouldBe` ["a1"]

    -- An artifact-only program (its whole result is a built command) had NOTHING
    -- it could pin: an artifact arg is consumed by a builder, so it is no
    -- attribute of the module or of the resulting derivation, and the mint wrote
    -- an empty contract -- which passes trivially. Such an arg IS a literal in
    -- the ground base, so the kernel judges it there: no nix, no eval.
    it "judges an artifact arg against the ground base (what an artifact-only program pins)" $ do
      let ground = fromList
            [ (mk "b" "x" "\"writeShellApplication\"" Stated) { dSubject = Subject ["artifact","greet","builder"] }
            , (mk "t" "x" "\"echo \\\"hello from lips\\\"\"" Stated) { dSubject = Subject ["artifact","greet","args","text"] }
            ]
          onArg = Expect "a1" ["artifact","greet","args","text"] (Subject ["cmd","greet","msg"]) Nothing
      isGroundExpect onArg `shouldBe` True
      isGroundExpect (Expect "a2" ["home","packages"] (Subject ["x"]) Nothing) `shouldBe` False
      -- the program's value reached the arg
      checkArtifactValues ground [(onArg, "hello from lips")] `shouldBe` []
      -- a value that did NOT reach it fails, naming the slot
      length (checkArtifactValues ground [(onArg, "goodbye")]) `shouldBe` 1
      -- an assertion on a slot no rule fills fails loud instead of reading null
      let onNothing = Expect "a3" ["artifact","greet","args","name"] (Subject ["cmd","greet","msg"]) Nothing
      length (checkArtifactValues ground [(onNothing, "greet")]) `shouldBe` 1

    -- A claim slot is pinned by the SAME mechanism, which is what makes a
    -- re-mint that drops an author's example trip the existing gate rather than
    -- needing a new one.
    it "judges a claim slot against the ground base, with no eval" $ do
      let ground = fromList
            [ (mk "c1" "x" "\"${artifact.tool}/bin/tool\"" Stated)
                { dSubject = Subject ["claim","echo","run"] }
            , (mk "c2" "x" "\"hi\"" Stated)
                { dSubject = Subject ["claim","echo","stdout"] }
            ]
          onOut = Expect "e1" ["claim","echo","stdout"] (Subject ["witness","out"]) Nothing
      isGroundExpect onOut `shouldBe` True
      checkArtifactValues ground [(onOut, "hi")] `shouldBe` []
      length (checkArtifactValues ground [(onOut, "bye")]) `shouldBe` 1
      -- a claim the engine stopped emitting fails loud, which is the drop gate
      let dropped = Expect "e2" ["claim","gone","stdout"] (Subject ["witness","out"]) Nothing
      checkArtifactValues ground [(dropped, "hi")]
        `shouldSatisfy` any (T.isInfixOf "nothing realizes this slot")

    -- A slot holds a VALUE; the program states a value. They must be compared as
    -- values, never as transport encodings: the canonical form escapes a quote,
    -- so a stated value carrying one (a JSON witness) would never appear in it as
    -- text. Found by a real mint, whose author example was {"a":"1"}.
    it "compares a slot to the program value as values, not as encodings" $ do
      let ground = fromList
            [ (mk "c1" "x" "\"{\\\"a\\\":\\\"1\\\"}\"" Stated)
                { dSubject = Subject ["claim","echo","stdout"] }
            ]
          onOut = Expect "e1" ["claim","echo","stdout"] (Subject ["witness","out"]) Nothing
      checkArtifactValues ground [(onOut, "{\"a\":\"1\"}")] `shouldBe` []
      -- and a value that genuinely is not there still fails
      length (checkArtifactValues ground [(onOut, "{\"a\":\"2\"}")]) `shouldBe` 1

    -- A whole-value assertion on a SEVERAL-PART value can be unsatisfiable by
    -- construction (the rule joins the parts its own way), which reads exactly
    -- like a value that failed to arrive. Say which it is, and name the remedy.
    it "names the remedy when a several-part value is pinned as a whole" $ do
      let ground = fromList
            [ (mk "c3" "x" "\"{\\\"a\\\":\\\"1\\\"}\\n{\\\"a\\\":\\\"2\\\"}\"" Stated)
                { dSubject = Subject ["claim","echo","stdin"] }
            ]
          onIn = Expect "e3" ["claim","echo","stdin"] (Subject ["witness","in"]) Nothing
          -- the program side renders a two-part value space-joined
          fails = checkArtifactValues ground [(onIn, "{\"a\":\"1\"} {\"a\":\"2\"}")]
      fails `shouldSatisfy` any (T.isInfixOf "pin one part per assertion")
      -- a genuinely absent value gets no such hint, since it is a different fault
      checkArtifactValues ground [(onIn, "nowhere")]
        `shouldSatisfy` all (not . T.isInfixOf "pin one part per assertion")

    it "still judges a slot whose value has no text form" $ do
      let ground = fromList
            [ (mk "c2" "x" "[ ${artifact.tool} ]" Stated)
                { dSubject = Subject ["artifact","w","args","runtimeInputs"] }
            ]
          onArg = Expect "e2" ["artifact","w","args","runtimeInputs"] (Subject ["x"]) Nothing
      checkArtifactValues ground [(onArg, "artifact.tool")] `shouldBe` []

    it "keeps a claim expect out of the nix eval set" $ do
      -- A claim command references an artifact, so without the exemption the
      -- derivation-reference guard would call the author's own example
      -- uncheckable and refuse the engine.
      let ruleClaim = MapRule "r" Fact ["witness", "<k>"]
            [ Emit ["claim","echo","run"] (VStr [PArt "tool", PLit "/bin/tool"]) ]
          onRun = Expect "e1" ["claim","echo","run"] (Subject ["witness","out"]) Nothing
      uncheckableExpects [ruleClaim] [onRun] `shouldBe` []

    it "an artifact arg is checkable even when it references another artifact" $ do
      -- The derivation-reference exemption is about the nix eval's pkgs stub; an
      -- artifact assertion never evals, so it must not be swept up by it.
      let ruleArt = MapRule "r" Fact ["cmd", "<name>"]
            [ Emit ["artifact","wrap","args","runtimeInputs"] (VList [VRef (RArt "core")]) ]
          onArg = Expect "a1" ["artifact","wrap","args","runtimeInputs"] (Subject ["cmd","x"]) Nothing
      uncheckableExpects [ruleArt] [onArg] `shouldBe` []

  describe "pattern matching (crystallization plan: normalization, holes)" $ do
    it "normalizes case only: a symbol survives normalization" $ do
      -- Punctuation is part of the token; only a line's final terminator is
      -- shed, and that happens once per line, not once per token.
      normalizeToken "Files." `shouldBe` "files."
      stripTrailingPunct "inbox/." `shouldBe` "inbox/"
      stripTrailingPunct "inbox/" `shouldBe` "inbox/"

    it "matches a template, binding a hole to the surface token" $ do
      let tpl = [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
      matchTemplate tpl (tokenizeLine "the bank drops files into inbox/.")
        `shouldBe` Just (Map.fromList [("loc", "inbox/")])

    it "fails to match on length or literal mismatch" $ do
      matchTemplate [TLit "a", THole "x"] (tokenizeLine "a b c") `shouldBe` Nothing
      matchTemplate [TLit "a", THole "x"] (tokenizeLine "z b") `shouldBe` Nothing

    it "a repeated hole must bind consistently" $ do
      let tpl = [THole "x", TLit "is", THole "x"]
      matchTemplate tpl (tokenizeLine "foo is foo") `shouldBe` Just (Map.fromList [("x", "foo")])
      matchTemplate tpl (tokenizeLine "foo is bar") `shouldBe` Nothing

    it "applies bindings to build subject and assertion" $ do
      let p = patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                Fact [SLit "feed.source"] [SHole "loc"]
      applyPattern p (Map.fromList [("loc", "inbox/")])
        `shouldBe` [(Subject ["feed", "source"], Fact, Assertion "inbox/", Stated)]

    it "lexes a quoted value as one token, dropping the quotes (gap 2)" $
      tokenizeLine "returns text \"hello world\"" `shouldBe`
        [("returns", "returns"), ("text", "text"), ("hello world", "hello world")]

    it "a hole captures a quoted value, spaces preserved" $
      matchTemplate [TLit "text", THole "body"] (tokenizeLine "text \"hello world\"")
        `shouldBe` Just (Map.fromList [("body", "hello world")])

    it "a bullet is a literal token; the item value binds a hole" $
      matchTemplate [TLit "-", THole "path"] (tokenizeLine "- /hello")
        `shouldBe` Just (Map.fromList [("path", "/hello")])

  describe "punctuation is a symbol the engine claims, not kernel noise" $ do
    let patP body = case parsePatternBody "p" body of
          Right ok -> ok
          Left e   -> error (T.unpack e)
    it "a mid-line symbol stays on its token" $
      tokenizeLine "content: shows a painting" `shouldBe`
        [("content:", "content:"), ("shows", "shows"), ("a", "a"), ("painting", "painting")]
    it "only the LAST token sheds its terminator" $
      tokenizeLine "host shop.example.com:" `shouldBe`
        [("host", "host"), ("shop.example.com", "shop.example.com")]
    it "a template that writes a symbol requires it" $ do
      let p = patP "content: <what.words> => fact c \"<what>\""
      matchTemplate (pTemplate p) (tokenizeLine "content: shows a painting")
        `shouldBe` Just (Map.fromList [("what", "shows a painting")])
      matchTemplate (pTemplate p) (tokenizeLine "content shows a painting")
        `shouldBe` Nothing
    it "a template that omits the symbol does not match a line that writes it" $
      -- Two patterns differing only by a colon read disjoint lines, which is
      -- what makes a block heading sayable.
      matchTemplate (pTemplate (patP "content <what.words> => fact c \"<what>\""))
                    (tokenizeLine "content: shows a painting")
        `shouldBe` Nothing
    it "a hole binds its token verbatim, symbol included" $
      -- The value carries what the author wrote; a rule building a list splits
      -- and strips it ('Engine.Value' fillV), so nothing is dropped unseen.
      matchTemplate [TLit "install", THole "p", TLit "and", THole "q"]
                    (tokenizeLine "install htop, and ripgrep")
        `shouldBe` Just (Map.fromList [("p", "htop,"), ("q", "ripgrep")])

  describe "template multi-token hole (C: many words in one hole)" $ do
    -- A @<name.words>@ hole binds SEVERAL tokens (>= 1) of a line, so a value
    -- of several words needs no quotes and one line may carry many items. The
    -- kernel dictates no collection syntax: the hole is a generic "bind these
    -- words" capability; how items are separated is the minted pattern's
    -- affair (here, comma+space prose).
    it "a trailing <name.words> binds the rest of the tokens, joined by space" $ do
      let p   = patOne "p" [TLit "install", TMulti "pkgs"] Fact [SHole "pkgs"] [SHole "value"]
          toks = tokenizeLine "install htop, ripgrep, tmux."
      -- The separators the author wrote stay in the captured value (the final
      -- terminator does not); the list-building rule strips them per token.
      matchTemplate (pTemplate p) toks `shouldBe` Just (Map.fromList [("pkgs", "htop, ripgrep, tmux")])
    it "a multi-token hole matching zero tokens fails (deduce-or-fail, never guess)" $ do
      let p = patOne "p" [TLit "install", TMulti "pkgs"] Fact [SHole "pkgs"] [SHole "value"]
      matchTemplate (pTemplate p) (tokenizeLine "install") `shouldBe` Nothing
    it "a multi-token hole is still a binding a target hole may use" $ do
      -- holesOf must include the name, or a target <pkgs> bound only by a
      -- multi-token hole would be rejected as loose on read (applyPattern
      -- would be partial).
      let p = patOne "p" [TLit "install", TMulti "pkgs"] Fact [SHole "pkgs"] [SHole "value"]
      holesOf p `shouldBe` ["pkgs"]
    it "a <name.words> template token round-trips through the .lang store" $ do
      let p  = patOne "p" [TLit "install", TMulti "pkgs"] Fact [SLit "install"] [SHole "pkgs"]
          rt = decisionToPattern . patternToDecision
      rt p `shouldBe` Right p
    it "a multi-token hole bounded by a following literal binds the words between" $ do
      -- The bounded form: an unquoted value of several words mid-sentence, the
      -- capture the template grammar was missing (a human had to quote it).
      let p = patOne "p" [TLit "back", TLit "up", TMulti "src", TLit "to", THole "dst"]
                Fact [SLit "backup.source"] [SHole "src"]
      matchTemplate (pTemplate p) (tokenizeLine "back up my home folder to nas")
        `shouldBe` Just (Map.fromList [("src", "my home folder"), ("dst", "nas")])
    it "a bounded multi-token hole stretches past a literal the tail still needs" $ do
      -- Shortest-first with backtracking: binding <src> to "a" leaves "to c"
      -- unmatched, so the match must grow the capture until the whole template
      -- fits. Without backtracking this line would be reported as out of
      -- language, a grammar bug rather than a program defect.
      let p = patOne "p" [TLit "back", TLit "up", TMulti "src", TLit "to", THole "dst"]
                Fact [SLit "backup.source"] [SHole "src"]
      matchTemplate (pTemplate p) (tokenizeLine "back up a to b to c")
        `shouldBe` Just (Map.fromList [("src", "a to b"), ("dst", "c")])
    it "a multi-token hole may sit anywhere in a template" $
      -- The old grammar rejected this on read (the hole had to be last), which
      -- made a mid-sentence multi-word value inexpressible.
      parsePatternBody "p" "install <pkgs.words> on <host> => fact pkg.<host> \"<pkgs>\""
        `shouldSatisfy` isRight

  describe "template fused hole (a value fused to punctuation inside one token)" $ do
    -- The gap this closes: a language whose values sit inside a token --
    -- `println("hallo")`, `--port=8080`, `k=v` -- was unreadable, because a
    -- hole could only be a WHOLE whitespace token. Nothing here is
    -- per-language: the kernel learns no call syntax, it only stops requiring
    -- a space around a hole.
    let pat body = case parsePatternBody "p" body of
          Right ok -> ok
          Left e   -> error (T.unpack e)
    it "lexes a quoted span fused to a prefix as one token" $
      -- The quote is already the kernel's atomicity mark; it applies wherever
      -- the span starts, not only at the head of a token, or a call argument
      -- with a space would split into two tokens.
      lexTokens "println_to_stdout(\"hallo du\")"
        `shouldBe` ["println_to_stdout(\"hallo du\")"]
    it "a quoted value closing a sentence still hands over its inner text" $ do
      -- Once a quoted span may start mid-token, the sentence period lands on
      -- the SAME token as the value; stripping it before unquoting is what
      -- keeps `respond with "hi".` a value rather than a quoted-looking word.
      tokenizeLine "respond with \"hello from lips\"."
        `shouldBe` [("respond", "respond"), ("with", "with"), ("hello from lips", "hello from lips")]
      matchTemplate (pTemplate (pat "respond with \"<msg>\". => fact m \"<msg>\""))
                    (tokenizeLine "respond with \"hello from lips\".")
        `shouldBe` Just (Map.fromList [("msg", "hello from lips")])

    it "a hole inside a token binds the text between its literal pieces" $ do
      let p = pat "println_to_stdout(\"<text>\") => fact print.text \"<text>\""
      matchTemplate (pTemplate p) (tokenizeLine "println_to_stdout(\"hallo\")")
        `shouldBe` Just (Map.fromList [("text", "hallo")])
      matchTemplate (pTemplate p) (tokenizeLine "println_to_stdout(\"hallo du\")")
        `shouldBe` Just (Map.fromList [("text", "hallo du")])
    it "a fused hole is a binding the target may use" $
      holesOf (pat "println_to_stdout(\"<text>\") => fact print.text \"<text>\"")
        `shouldBe` ["text"]
    it "the literal pieces around a fused hole must match" $ do
      let p = pat "println_to_stdout(\"<text>\") => fact print.text \"<text>\""
      matchTemplate (pTemplate p) (tokenizeLine "eprintln_to_stdout(\"hallo\")")
        `shouldBe` Nothing
      matchTemplate (pTemplate p) (tokenizeLine "println_to_stdout(hallo)")
        `shouldBe` Nothing
    it "a fused hole binds at least one character (deduce-or-fail)" $
      matchTemplate (pTemplate (pat "println(<x>) => fact a \"<x>\""))
                    (tokenizeLine "println()")
        `shouldBe` Nothing
    it "reads a key=value shape, hole and literal in one token" $
      matchTemplate (pTemplate (pat "--port=<n> => fact port \"<n>\""))
                    (tokenizeLine "--port=8080")
        `shouldBe` Just (Map.fromList [("n", "8080")])
    it "reads two holes glued by literal text inside one token" $ do
      -- A declaration's parameter list, `<fname>(<param>: <ptype>)`: the token
      -- `<fname>(<param>:` starts with '<' and its ':' is a literal piece the
      -- program line must carry, so a naive whole-token reading would bind one hole named
      -- "fname>(<param" and leave the emit's <fname> and <param> unbound -- a
      -- refusal for a template that is plainly inside the grammar.
      let p = pat "function <fname>(<param>: <ptype>) => fact function.<fname>.signature \"<fname> <param> <ptype>\""
      holesOf p `shouldBe` ["fname", "param", "ptype"]
      matchTemplate (pTemplate p) (tokenizeLine "function println_to_stdout(x: String)")
        `shouldBe` Just (Map.fromList
          [("fname", "println_to_stdout"), ("param", "x"), ("ptype", "String")])
    it "captures the surface verbatim while literals compare case-insensitively" $
      matchTemplate (pTemplate (pat "Print(<x>) => fact a \"<x>\""))
                    (tokenizeLine "print(Hallo)")
        `shouldBe` Just (Map.fromList [("x", "Hallo")])
    it "a fused template token round-trips through the .lang store" $ do
      let p  = pat "println_to_stdout(\"<text>\") => fact print.text \"<text>\""
          rt = decisionToPattern . patternToDecision
      rt p `shouldBe` Right p
    it "refuses a multi-token hole inside a token instead of mis-binding it" $
      -- <x.words> spans whitespace, which a token cannot; saying so beats
      -- silently binding a hole named "x.words".
      parsePatternBody "p" "println(<x.words>) => fact a \"<x>\""
        `shouldSatisfy` isLeft
    it "the engine that exposed the gap now closes its nesting" $ do
      -- The failing mint: p2 emits <text>, bound only by a hole inside the
      -- call token. Before fused holes this was an UnboundInScope error the
      -- mint could not fix, i.e. a missing grammar case.
      let p1 = pat "function println_to_stdout(x: String) => glue runtime.stdout \"one line per call\""
          p2 = case parsePatternBody "p2.under.p"
                      "println_to_stdout(\"<text>\") => fact print.<n:index>.text \"<text>\"" of
                 Right ok -> ok
                 Left e   -> error (T.unpack e)
          src = T.unlines
            [ "function println_to_stdout(x: String)"
            , ""
            , "println_to_stdout(\"hallo\")"
            , "println_to_stdout(\"du\")"
            , "println_to_stdout(\"!\")"
            ]
      checkNesting [p1, p2] `shouldBe` []
      fmap (map (\d -> case dAssertion d of Assertion a -> a) . toList) (crystallize "function" [p1, p2] src)
        `shouldBe` Right ["one line per call", "hallo", "du", "!"]

  describe "source fills (a program word inside baked source)" $ do
    it "reads the markers a source text names, once each, in order" $
      sourceMarkers "module @name@\nfunc main() { print(\"@name@ @greeting@\") }"
        `shouldBe` ["name", "greeting"]
    it "reads no marker where an @ is ordinary source text" $
      -- A decorator, a Makefile prefix, an email: narrow marker syntax keeps
      -- them out, so a fill is never guessed into someone's code.
      sourceMarkers "@app.route('/')\n\t@echo hi\nme@example.com\n@ @\n@1x@"
        `shouldBe` []
    it "fills every marker in every file" $
      fillTree "tool" [("name", "logscan")]
        [("go.mod", "module @name@\n"), ("main.go", "// @name@ reads stdin\n")]
        `shouldBe` Right [ ("go.mod", "module logscan\n")
                         , ("main.go", "// logscan reads stdin\n") ]
    it "refuses a declared fill no source file names (the word would govern nothing)" $
      fillTree "tool" [("name", "logscan"), ("port", "8080")]
        [("go.mod", "module @name@\n")]
        `shouldBe` Left ["artifact tool declares fill port but no source file names @port@"]
    it "refuses a marker the engine never declares (it would ship verbatim)" $
      fillTree "tool" [("name", "logscan")]
        [("main.go", "// @name@\nconst greeting = \"@greting@\"\n")]
        `shouldBe` Left ["artifact tool: main.go names @greting@, which the engine never declares as a fill"]
    it "fills in one pass, so a fill's own text is never rescanned" $
      -- A program word that happens to read @name@ must land verbatim; a second
      -- pass would let a program value inject a marker.
      fillTree "tool" [("greeting", "@name@"), ("name", "x")]
        [("main.go", "@greeting@ @name@")]
        `shouldBe` Right [("main.go", "@name@ x")]

  describe "crystallize (crystallization plan: three outcomes)" $ do
    let sourceP = patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                    Fact [SLit "feed.source"] [SHole "loc"]
        obligeP = patOne "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
                    Oblige [SLit "feed.ingest"] [SLit "every bank row becomes one ", SHole "e"]

    it "a line matched by one pattern crystallizes to one decision" $ do
      case crystallize "prog" [sourceP, obligeP] "the bank drops files into inbox/." of
        Right b -> case toList b of
          [d] -> (dSubject d, dAssertion d, dProv d)
            `shouldBe` (Subject ["feed", "source"], Assertion "inbox/", FromSource (SourceLoc "prog" 1))
          ds  -> expectationFailure ("expected one decision, got " ++ show (length ds))
        Left e  -> expectationFailure ("unexpected error: " ++ show e)

    it "a line matched by no pattern is NoPattern (re-enters generate)" $
      crystallize "prog" [sourceP] "something entirely unknown here"
        `shouldSatisfy` \r -> case r of Left [NoPattern 1 _] -> True; _ -> False

    it "a line matched by two patterns is Overlapping (orthogonality)" $ do
      let a = patOne "a" [THole "x", TLit "hour"] Fact [SLit "feed.cadence"] [SHole "x"]
          b = patOne "b" [TLit "every", THole "y"] Fact [SLit "feed.cadence"] [SHole "y"]
      crystallize "prog" [a, b] "every hour"
        `shouldBe` Left [Overlapping 1 ["a", "b"]]

    it "names a line whose fact an earlier line already stated" $ do
      -- Two lines that crystallize to the SAME subject AND assertion merge into
      -- one decision (the base is keyed by subject), so the later line produces
      -- nothing and editing it changes no output -- with nothing saying so:
      -- diagInert works per kind, diagDropped per hole, and neither sees a whole
      -- absorbed line. Reported, never refused: duplicating a line is a pinned
      -- edit-tolerance promise (spec 5) and two statements of one fact are one
      -- fact (the merge doctrine).
      let stepP = patOne "s" [TLit "-", TMulti "step"]
                    Fact [SLit "step.", SHole "step", SLit ".command"] [SHole "step"]
          src = "- fetch.\n- publish.\n- fetch.\n"
      restatements (classifyLines "prog" [stepP] src)
        `shouldBe` [(3, 1, "step.fetch.command")]

    it "a restated line still crystallizes (duplication stays a no-op)" $ do
      -- One word per step, so the subject stays a readable canonical segment
      -- (a multi-word capture spliced into a subject is refused; see the
      -- crystallize round-trip block).
      let stepP = patOne "s" [TLit "-", TMulti "step"]
                    Fact [SLit "step.", SHole "step", SLit ".command"] [SHole "step"]
      crystallize "prog" [stepP] "- publish.\n- publish.\n" `shouldSatisfy` isRight

    it "reports nothing when two lines disagree (that is resolve's conflict)" $ do
      let setP = patOne "s" [TLit "set", THole "v"] Fact [SLit "cfg.k"] [SHole "v"]
      restatements (classifyLines "prog" [setP] "set a\nset b\n") `shouldBe` []

    it "skips comment and blank lines" $ do
      let src = "# a language\n\nthe bank drops files into inbox/.\n"
      fmap (map dId . toList) (crystallize "prog" [sourceP] src) `shouldBe` Right [DecisionId "d3"]

    it "hole re-instantiation always crystallizes (edit-tolerance by construction)" $ do
      let setP = patOne "set" [TLit "set", THole "k", TLit "to", THole "v"]
                   Fact [SLit "cfg.", SHole "k"] [SHole "v"]
      property $ forAll ((,) <$> safeToken <*> safeToken) $ \(k, v) ->
        let line = T.unwords ["set", k, "to", v]
         in case crystallize "p" [setP] line of
              Right b -> case toList b of
                [d] -> dSubject d == Subject ["cfg", k] && dAssertion d == Assertion v
                _   -> False
              Left _ -> False

    -- A captured value may contain a dot (an HTTP route key /file.json): it
    -- must stay ONE subject segment, not be split by the dot-joined path form.
    it "keeps a dot inside a captured value as one subject segment" $ do
      let routeP = patOne "pr" [TLit "-", THole "path", TLit "is", THole "body"]
                     Fact [SLit "route.", SHole "path", SLit ".body"] [SHole "body"]
      case crystallize "prog" [routeP] "- /file.json is x" of
        Right b -> map dSubject (toList b) `shouldBe` [Subject ["route", "/file.json", "body"]]
        Left e  -> expectationFailure ("unexpected crystallize error: " ++ show e)

    it "captures a quoted multi-word value into a bulleted route (gap 2)" $ do
      let routeP = patOne "pr" [TLit "-", THole "path", TLit "returns", TLit "text", THole "body"]
                     Fact [SLit "route.", SHole "path"] [SHole "body"]
      case crystallize "prog" [routeP] "- /hello returns text \"hello world\"" of
        Right b -> case toList b of
          [d] -> (dSubject d, dAssertion d) `shouldBe`
                   (Subject ["route", "/hello"], Assertion "hello world")
          ds  -> expectationFailure ("expected one decision, got " ++ show (length ds))
        Left e -> expectationFailure ("unexpected crystallize error: " ++ show e)

  describe "multi-fact patterns (a dense line states several facts)" $ do
    -- "http server in <lang> on port <port>" states BOTH language and port; the
    -- one pattern that matches the line must emit both, or a demand on the
    -- second could never be met (the bug that motivated this).
    let denseP = Pattern "p1" []
                   [ TLit "http", TLit "server", TLit "in", THole "lang"
                   , TLit "on", TLit "port", THole "port" ]
                   [ PatEmit Steer [SLit "server.language"] [SHole "lang"]
                   , PatEmit Fact [SLit "http.port"]       [SHole "port"] ]
        roundTrip = decisionToPattern . patternToDecision

    it "applyPattern yields one tuple per emit" $
      applyPattern denseP (Map.fromList [("lang", "go"), ("port", "8080")])
        `shouldBe` [ (Subject ["server", "language"], Steer, Assertion "go", Stated)
                   , (Subject ["http", "port"], Fact, Assertion "8080", Stated) ]

    it "crystallizes a dense line to several decisions with distinct ids" $
      case crystallize "prog" [denseP] "http server in go on port 8080" of
        Right b -> map (\d -> (dId d, dSubject d, dAssertion d)) (toList b)
          `shouldBe` [ (DecisionId "d1.1", Subject ["server", "language"], Assertion "go")
                     , (DecisionId "d1.2", Subject ["http", "port"], Assertion "8080") ]
        Left e  -> expectationFailure ("unexpected crystallize error: " ++ show e)

    it "a one-emit pattern keeps the bare per-line id (backward compatible)" $
      case crystallize "prog" [patOne "p" [TLit "port", THole "n"] Fact [SLit "http.port"] [SHole "n"]] "port 8080" of
        Right b -> map dId (toList b) `shouldBe` [DecisionId "d1"]
        Left e  -> expectationFailure ("unexpected crystallize error: " ++ show e)

    it "a multi-emit pattern round-trips through the .lang store" $
      roundTrip denseP `shouldBe` Right denseP

    it "an assertion containing '; ' is not mis-split into a second emit" $ do
      let p = patOne "p" [TLit "note", THole "x"] Fact [SLit "n"] [SLit "a ; b ", SHole "x"]
      roundTrip p `shouldBe` Right p

  describe "engine data (engine-synthesis plan: rules and demands as data)" $ do
    let rule = MapRule "r2" Fact ["feed", "cadence"]
                 [ Emit ["systemd", "timers", "t", "OnCalendar"] (VStr [PHole "value"]) ]

    it "rule body round-trips" $
      parseRuleBody "r2" (renderRuleBody rule) `shouldBe` Right rule

    -- The emit separator " ; " and the meta arrow " => " are ordinary text
    -- inside a shell line or a mapping, so a value may hold them. The pattern
    -- side always split outside quotes; the rule side split naively, which made
    -- such a value unwritable and blamed it as an unterminated string. One
    -- quote-aware rule now serves both (Lips.Kernel.Quoting).
    it "rule body round-trips with the emit separator inside a value" $ do
      let r = MapRule "r" Fact ["x"]
                [ Emit ["environment","etc","foo","text"] (VStr [PLit "cd /x ; ls"]) ]
      parseRuleBody "r" (renderRuleBody r) `shouldBe` Right r

    it "rule body round-trips with the meta arrow inside a value" $ do
      let r = MapRule "r" Fact ["x"]
                [ Emit ["environment","etc","foo","text"] (VStr [PLit "a => b"]) ]
      parseRuleBody "r" (renderRuleBody r) `shouldBe` Right r

    it "rule body round-trips over arbitrary string values (property)" $
      property $ \(chunks :: [Bool]) ->
        let txt = T.concat [ if b then " ; " else " => " | b <- chunks ]
            r   = MapRule "r" Fact ["x"]
                    [ Emit ["a","b"] (VStr [PLit ("cmd" <> txt <> "tail")]) ]
         in parseRuleBody "r" (renderRuleBody r) === Right r

    -- The storage round-trip must hold for ANY segment shape, including a
    -- literal dotted key (a model may write environment.etc."my.route".text).
    -- The base layer escapes \.; the engine layer must too, or parse . render
    -- shreds a dotted segment into two. This is the engine analogue of the
    -- base-layer readBase . renderBase == id property.
    it "rule body round-trips with a dotted segment in the emit path" $
      property $ forAll (dottedPathRule <$> dottedSeg) $ \r ->
        parseRuleBody "r" (renderRuleBody r) === Right r

    -- A quoted attrsOf key in an emit path normalizes to the same bare segment
    -- as the unquoted form (plan: align the engine path split with the base
    -- subject split), so a model writing locations."/".proxyPass emits the
    -- option slot / (not the wrong key "/"), matching a bare-keyed expect.
    it "parses a quoted attrsOf key in an emit path to its bare segment" $ do
      parseRuleBody "r" "match fact x => a.b.\"/\".c true"
        `shouldBe` Right (MapRule "r" Fact ["x"]
            [ Emit ["a","b","/","c"] (VBool True) ])
      parseRuleBody "r" "match fact x => a.b.\"file.txt\".c true"
        `shouldBe` Right (MapRule "r" Fact ["x"]
            [ Emit ["a","b","file.txt","c"] (VBool True) ])

    -- Language reuse (plan 2026-07-22): a shared grammar names the per-instance
    -- attrsOf key by the reserved <self> segment, bound to the solution's file
    -- basename, instead of baking one instance into the grammar.
    it "binds <self> in an option path to the instance name" $ do
      let selfRule = MapRule "r" Oblige ["backup", "job"]
            [ Emit ["services", "restic", "backups", "<self>", "paths"] (VStr [PHole "value"]) ]
          matched = (mk "d" "unused" "/var/lib/x" Stated)
                      { dSubject = Subject ["backup", "job"], dKind = Oblige }
      case refine 100 [toRule (bindSelf "ledger" selfRule)] (fromList [matched]) of
        Right b -> map dSubject (toList b) `shouldBe`
                     [Subject ["services", "restic", "backups", "ledger", "paths"]]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    -- <self> fills by OCCURRENCE in an emit path too, not only as a whole
    -- segment: a program that builds a compiled core and a wrapper needs the
    -- group artifact.<self>-core. Whole-segment equality let the path PARSE
    -- (segments are opaque text) and never fill, so the literal "<self>-core"
    -- travelled on toward realize -- a silent twin of the ref-name refusal.
    it "binds <self> EMBEDDED in an emit-path segment" $ do
      let selfRule = MapRule "r" Fact ["board", "command"]
            [ Emit ["artifact", "<self>-core", "builder"] (VStr [PLit "buildGoModule"])
            , Emit ["artifact", "<self>-core", "args", "src"] (VPath "./artifacts/<self>-core") ]
          matched = (mk "d" "unused" "hi" Stated)
                      { dSubject = Subject ["board", "command"], dKind = Fact }
      case refine 100 [toRule (bindSelf "board" selfRule)] (fromList [matched]) of
        Right b -> map (\x -> (dSubject x, dAssertion x)) (toList b) `shouldMatchList`
          [ (Subject ["artifact", "board-core", "builder"], Assertion "\"buildGoModule\"")
          , (Subject ["artifact", "board-core", "args", "src"], Assertion "./artifacts/board-core") ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "bindSelf leaves a rule without <self> untouched" $
      bindSelf "ledger" rule `shouldBe` rule

    -- <self> is the instance name everywhere it can appear, not only in an
    -- option path: a rhs string piece (<self>) and an artifact reference
    -- (${artifact.<self>}) both bind to the instance, so a rule can name the
    -- program's own build and app name without baking one instance in.
    it "binds <self> inside rhs values (string piece and artifact ref)" $ do
      let selfRule = MapRule "r" Fact ["cli", "output"]
            [ Emit ["artifact", "<self>", "args", "name"] (VStr [PSelf])
            , Emit ["environment", "systemPackages"] (VList [VRef (RArt "<self>")]) ]
          matched = (mk "d" "unused" "hi" Stated)
                      { dSubject = Subject ["cli", "output"], dKind = Fact }
      case refine 100 [toRule (bindSelf "hello" selfRule)] (fromList [matched]) of
        Right b -> map (\d -> (dSubject d, dAssertion d)) (toList b) `shouldMatchList`
          [ (Subject ["artifact", "hello", "args", "name"], Assertion "\"hello\"")
          , (Subject ["environment", "systemPackages"], Assertion "[ ${artifact.hello} ]") ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    -- Value-keyed options: one rule matches a subject FAMILY (a <capture>
    -- segment binds any concrete segment) and interpolates the captured key
    -- into the emit path, so N sibling decisions fan out to N distinct option
    -- slots that ride Nix's native attrsOf merge (routes keyed by path).
    it "matches a <capture> subject family and fills the key into the emit path" $ do
      let r = MapRule "r" Fact ["route", "<path>", "status"]
                [ Emit ["environment", "etc", "<path>", "text"] (VStr [PHole "value"]) ]
          d1 = (mk "d1" "unused" "200" Stated) { dSubject = Subject ["route", "hello", "status"] }
          d2 = (mk "d2" "unused" "404" Stated) { dSubject = Subject ["route", "bye", "status"] }
      case refine 100 [toRule r] (fromList [d1, d2]) of
        Right b -> map (\d -> (dSubject d, dAssertion d)) (toList b) `shouldMatchList`
                     [ (Subject ["environment", "etc", "hello", "text"], Assertion "\"200\"")
                     , (Subject ["environment", "etc", "bye", "text"], Assertion "\"404\"") ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "a rule with a <capture> subject round-trips through render/parse" $ do
      let r = MapRule "r" Fact ["route", "<path>", "status"]
                [ Emit ["environment", "etc", "<path>", "text"] (VStr [PHole "value"]) ]
      parseRuleBody "r" (renderRuleBody r) `shouldBe` Right r

    -- Captures are first-class, not path-only: the same binding that fills an
    -- emit PATH also fills a VALUE and an artifact-ref NAME. Without this a
    -- program that names the thing it builds ("install a command greet") has no
    -- expressible engine: the mint reaches for artifact.<cmd> / args.name
    -- "<cmd>" and both were rejected (docs/gaps/README.md, finding 2).
    it "fills a captured key into a rule's VALUE, not only its emit path" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["artifact", "<name>", "args", "name"] (VStr [PHole "name"]) ]
          d  = (mk "d1" "unused" "hello there" Stated)
                 { dSubject = Subject ["cmd", "greet", "msg"] }
      case refine 100 [toRule r] (fromList [d]) of
        Right b -> map (\x -> (dSubject x, dAssertion x)) (toList b) `shouldBe`
                     [ (Subject ["artifact", "greet", "args", "name"], Assertion "\"greet\"") ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "fills a captured key into an ${artifact.<name>} build reference" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["environment", "systemPackages"] (VList [VRef (RArt "<name>")]) ]
          d  = (mk "d1" "unused" "hi" Stated)
                 { dSubject = Subject ["cmd", "greet", "msg"] }
      case refine 100 [toRule r] (fromList [d]) of
        Right b -> map dAssertion (toList b) `shouldBe` [ Assertion "[ ${artifact.greet} ]" ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    -- Composed names fill by OCCURRENCE, the same way a capture fills an emit
    -- path segment: <self> per instance (bindSelf), a capture per rule match.
    -- A wrapper artifact referencing its own compiled core is the motivating
    -- shape (two artifacts, one program).
    it "fills <self> inside a COMPOSED artifact-ref name" $ do
      let r = MapRule "r" Fact ["cli", "output"]
                [ Emit ["environment", "systemPackages"] (VList [VRef (RArt "<self>-core")])
                , Emit ["artifact", "<self>", "args", "text"]
                       (VStr [PLit "exec ", PArt "<self>-core", PLit "/bin/core"]) ]
          d = (mk "d" "unused" "hi" Stated) { dSubject = Subject ["cli", "output"], dKind = Fact }
      case refine 100 [toRule (bindSelf "board" r)] (fromList [d]) of
        Right b -> map (\x -> (dSubject x, dAssertion x)) (toList b) `shouldMatchList`
          [ (Subject ["environment", "systemPackages"], Assertion "[ ${artifact.board-core} ]")
          , (Subject ["artifact", "board", "args", "text"]
            , Assertion "\"exec ${artifact.board-core}/bin/core\"") ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "fills a capture inside a COMPOSED artifact-ref name" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["environment", "systemPackages"] (VList [VRef (RArt "<name>-core")]) ]
          d = (mk "d" "unused" "hi" Stated) { dSubject = Subject ["cmd", "greet", "msg"] }
      case refine 100 [toRule r] (fromList [d]) of
        Right b -> map dAssertion (toList b) `shouldBe` [ Assertion "[ ${artifact.greet-core} ]" ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "rejects a COMPOSED artifact name whose capture the subject does not bind" $
      parseRuleBody "r" "match fact cmd.<name>.msg => environment.systemPackages \"[ ${artifact.<other>-core} ]\""
        `shouldSatisfy` isLeft

    it "a value hole naming no capture and no value fails loud at refine" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["environment", "etc", "x", "text"] (VStr [PHole "typo"]) ]
          d  = (mk "d1" "unused" "hi" Stated)
                 { dSubject = Subject ["cmd", "greet", "msg"] }
      refine 100 [toRule r] (fromList [d]) `shouldSatisfy` isLeft

    it "${artifact.<name>} and a value capture round-trip through render/parse" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["artifact", "<name>", "args", "name"] (VStr [PHole "name"])
                , Emit ["environment", "systemPackages"] (VList [VRef (RArt "<name>")]) ]
      parseRuleBody "r" (renderRuleBody r) `shouldBe` Right r

    -- The guard sits at the door every minted engine enters, where the subject
    -- is in hand: a capture the subject never binds is rejected at parse, not
    -- left to fire at refine on an author's machine.
    it "rejects a value capture the rule's subject does not bind" $
      parseRuleBody "r7" "match fact cmd.<name>.msg => artifact.x.args.name \"\\\"<other>\\\"\""
        `shouldSatisfy` isLeft

    -- <self> is <...>-shaped but is NOT a capture: it binds to the instance
    -- name at realize time, so no rule subject binds it and the unbound-capture
    -- check must skip it. Regression: the check rejected every
    -- ${artifact.<self>} rule, a form the ledger documents as supported and no
    -- committed example happened to use.
    it "accepts <self> in an artifact reference, which is not a capture" $ do
      let body = "match fact tool.command => artifact.<self>.args.pname \"\\\"<value>\\\"\""
                   <> " ; home.packages \"[ ${artifact.<self>} ]\""
      parseRuleBody "r5" body `shouldSatisfy` isRight

    -- An artifact's source dir is written ./artifacts/<name>. A path literal is
    -- opaque text, so the capture used to survive unfilled into the module as
    -- the literal "./artifacts/<name>", which Nix then rejected for a trailing
    -- slash: a silent-literal escape of exactly the kind the value grammar
    -- exists to prevent.
    it "fills a capture inside a path literal (an artifact's args.src)" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["artifact", "<name>", "args", "src"] (VPath "./artifacts/<name>") ]
          d = (mk "d1" "unused" "hi" Stated)
                { dSubject = Subject ["cmd", "logscan", "msg"] }
      case refine 100 [toRule r] (fromList [d]) of
        Right b -> map dAssertion (toList b) `shouldBe` [ Assertion "./artifacts/logscan" ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    it "rejects an unbound capture inside a path literal" $
      parseRuleBody "r" "match fact x => artifact.a.args.src ./artifacts/<name>"
        `shouldSatisfy` isLeft

    -- <value>/<value.N> are reserved for the rule's OWN matched value (the
    -- ground decision's assertion), never a subject capture -- but a subject
    -- capture may be named ANYTHING (captureName has no reserved words), so a
    -- mint that names a capture <value> (a natural word choice) got no error
    -- at all: 'pick' matches the literal "value" clause before ever consulting
    -- the capture map, so the rhs silently read the decision's assertion
    -- instead of the captured subject segment the mint clearly intended.
    -- Confirmed live: 'parseRuleBody' accepted
    -- "match fact cmd.<value>.msg => a.b \"<value>\"" with no error, and
    -- 'refine' filled it from the assertion, never the capture. Reject the
    -- name collision at the same door the unbound-capture check already uses.
    it "rejects a subject capture named <value>, reserved for the rule's own value" $
      parseRuleBody "r" "match fact cmd.<value>.msg => a.b \"\\\"<value>\\\"\""
        `shouldSatisfy` isLeft
    -- A dot inside a bare subject segment would split it (subject segments are
    -- dot-delimited), so the only way to write a single capture segment named
    -- "value.1" is quoted, the same escape hatch a real dotted key (a route
    -- "/file.json") already uses.
    it "rejects a quoted subject capture named <value.1>, reserved the same way" $
      parseRuleBody "r" "match fact cmd.\"<value.1>\".msg => a.b \"\\\"<value.1>\\\"\""
        `shouldSatisfy` isLeft
    it "still accepts an ordinarily-named capture used correctly" $
      parseRuleBody "r" "match fact cmd.<port>.msg => a.b \"\\\"<port>\\\"\""
        `shouldSatisfy` isRight

    it "accepts value, value.N and a bound capture in one rule's values" $ do
      let r = MapRule "r" Fact ["cmd", "<name>", "msg"]
                [ Emit ["artifact", "<name>", "args", "name"] (VStr [PHole "name"])
                , Emit ["artifact", "<name>", "args", "text"] (VStr [PHole "value"])
                , Emit ["artifact", "<name>", "args", "v2"] (VStr [PHole "value.2"])
                , Emit ["environment", "systemPackages"] (VList [VRef (RArt "<name>")]) ]
      parseRuleBody "r" (renderRuleBody r) `shouldBe` Right r

    -- End to end: two routes in one program, each keyed by its own path, flow
    -- through crystallize -> refine -> realize into two DISTINCT keyed options
    -- (the collision the value-keyed-options gap caused is gone).
    it "end to end: two routes fan out to two path-keyed options" $ do
      let routeP = Pattern "pr" []
                     [ TLit "-", THole "path", TLit "=>", TLit "status", THole "code" ]
                     [ PatEmit Fact [SLit "route.", SHole "path", SLit ".status"] [SHole "code"] ]
          routeRule = MapRule "r" Fact ["route", "<path>", "status"]
                   [ Emit ["environment", "etc", "<path>", "text"] (VStr [PHole "value"]) ]
          prog = "- /hello => status 200\n- /bye => status 404"
      case crystallize "prog" [routeP] prog of
        Left e     -> expectationFailure ("crystallize: " ++ show e)
        Right base -> case refine 100 [toRule routeRule] base of
          Left e       -> expectationFailure ("refine: " ++ show e)
          Right ground -> case realizeReplace ground of
            Left e    -> expectationFailure ("realize: " ++ show e)
            Right out -> do
              out `shouldSatisfy` T.isInfixOf "environment.etc.\"/hello\".text = \"200\";"
              out `shouldSatisfy` T.isInfixOf "environment.etc.\"/bye\".text = \"404\";"

    -- A capture may be EMBEDDED in a segment (a literal prefix the model
    -- composes, e.g. an etc filename http-routes<path>), not only fill a whole
    -- segment; each route must still get a distinct key (no collision).
    it "interpolates a <capture> embedded inside an emit-path segment" $ do
      let r = MapRule "r" Fact ["route", "<path>", "body"]
                [ Emit ["environment", "etc", "http-routes<path>", "text"] (VStr [PHole "value"]) ]
          d1 = (mk "d1" "unused" "world" Stated) { dSubject = Subject ["route", "hello", "body"] }
          d2 = (mk "d2" "unused" "nope"  Stated) { dSubject = Subject ["route", "bye", "body"] }
      case refine 100 [toRule r] (fromList [d1, d2]) of
        Right b -> map dSubject (toList b) `shouldMatchList`
                     [ Subject ["environment", "etc", "http-routeshello", "text"]
                     , Subject ["environment", "etc", "http-routesbye", "text"] ]
        Left e  -> expectationFailure ("unexpected refine error: " ++ show e)

    -- Failproof: a <name> in an emit path the subject never bound must fail
    -- loud (RewriteFailed), never emit a literal <name> that silently collides.
    it "fails loud on an emit-path capture the subject never bound" $ do
      let r = MapRule "r" Fact ["route", "<path>", "body"]
                [ Emit ["environment", "etc", "<missing>", "text"] (VStr [PHole "value"]) ]
          d1 = (mk "d1" "unused" "world" Stated) { dSubject = Subject ["route", "hello", "body"] }
      refine 100 [toRule r] (fromList [d1]) `shouldSatisfy` isLeft

    it "demand body round-trips" $ do
      let q = DemandSpec "q1" ["feed", "source"] "where do the files arrive?"
      parseDemandBody "q1" (renderDemandBody q) `shouldBe` Right q

    -- A family demand (route.<path>.status) is met by ANY concrete route; a
    -- plain demand still needs its exact subject present (backward compatible).
    it "a value-keyed family demand is satisfied by any matching route" $ do
      let famDem = toDemand (DemandSpec "q" ["route", "<path>", "status"] "?")
          hit    = fromList [ (mk "d1" "u" "200" Stated) { dSubject = Subject ["route", "/hello", "status"] } ]
          miss   = fromList [ (mk "d1" "u" "200" Stated) { dSubject = Subject ["other", "thing"] } ]
      demSatisfied famDem hit  `shouldBe` True
      demSatisfied famDem miss `shouldBe` False

    it "rejects an emit with an unknown hole" $
      parseRuleBody "r" "match fact x => a.b \"\\\"<mystery>\\\"\"" `shouldSatisfy` isLeft

    -- The design event of the first live backup run, made physics: computation
    -- in an rhs must be structurally rejected, not prompt-discouraged.
    it "rejects computation in an rhs (function application is not a value)" $
      parseRuleBody "r" "match fact x => a.b \"lib.splitString \\\" \\\" <value>\"" `shouldSatisfy` isLeft

    it "rejects non-pkgs interpolation inside rhs strings" $
      parseRuleBody "r" "match fact x => a.b \"\\\"${lib.getExe pkgs.restic}\\\"\"" `shouldSatisfy` isLeft

    -- A world can WANT a literal ${...} in a string: another tool's own
    -- reference syntax (Terraform's "${aws_s3_bucket.x.id}") is text as far as
    -- Nix and lips are concerned. The grammar already carries it as an escaped
    -- literal, so the refusal must NAME that remedy -- deduce-or-fail means the
    -- message says what to write instead, or the mint reads "impossible".
    it "a literal ${...} is an escaped literal, and the refusal says so" $ do
      parseValue "\"\\${aws_s3_bucket.assets.id}\""
        `shouldBe` Right (VStr [PLit "${aws_s3_bucket.assets.id}"])
      -- round-trips and realizes as an escaped literal, i.e. a Nix string whose
      -- value is the other tool's reference text
      fmap renderRealized (parseValue "\"\\${aws_s3_bucket.assets.id}\"")
        `shouldBe` Right "\"\\${aws_s3_bucket.assets.id}\""
      case parseValue "\"${aws_s3_bucket.assets.id}\"" of
        Right v -> expectationFailure ("expected a refusal, got " <> show v)
        Left why -> why `shouldSatisfy` T.isInfixOf "\\${"

    -- Models write non-string values bare (null, a path); the parser accepts
    -- both the bare and the transport-quoted form (artifacts live run).
    it "accepts a bare non-string rhs (null, path) as well as quoted" $ do
      parseRuleBody "r" "match steer x => a.vendorHash null ; a.src ./artifacts/x"
        `shouldBe` Right (MapRule "r" Steer ["x"]
          [ Emit ["a", "vendorHash"] VNull, Emit ["a", "src"] (VPath "./artifacts/x") ])

    it "parses the full value algebra: null, float, path, and typed holes" $ do
      parseValue "null"            `shouldBe` Right VNull
      parseValue "3.14"            `shouldBe` Right (VFloat 3.14)
      parseValue "/var/lib/ledger" `shouldBe` Right (VPath "/var/lib/ledger")
      parseValue "<value:int>"     `shouldBe` Right (VHole HInt "value")
      parseValue "<value.2:path>"  `shouldBe` Right (VHole HPath "value.2")

    it "rejects an untyped bare hole and an unknown hole type" $ do
      parseValue "<value>"         `shouldSatisfy` isLeft
      parseValue "<value:widget>"  `shouldSatisfy` isLeft

    it "an integer-typed option is filled as an INTEGER from a program value (nginx port gap)" $ do
      let r = MapRule "r" Fact ["server", "port"]
                [ Emit ["services", "nginx", "defaultHTTPListenPort"] (VHole HInt "value") ]
          matched = (mk "d" "unused" "8080" Stated) { dSubject = Subject ["server", "port"] }
      case refine 100 [toRule r] (fromList [matched]) of
        Right b -> case toList b of
          [d] -> (dSubject d, dAssertion d) `shouldBe`
                   (Subject ["services", "nginx", "defaultHTTPListenPort"], Assertion "8080")
          ds  -> expectationFailure ("expected one emitted decision, got " ++ show (length ds))
        Left e -> expectationFailure ("unexpected refine error: " ++ show e)

    it "a path hole emits an unquoted path; a bool hole emits a keyword" $ do
      fillValue (const (Right "/etc/ssl/cert.pem")) (VHole HPath "value") `shouldBe` Right "/etc/ssl/cert.pem"
      fillValue (const (Right "true"))              (VHole HBool "value") `shouldBe` Right "true"

    it "a typed hole fails with a Left (not a crash) when the program value is the wrong type" $ do
      fillValue (const (Right "not-a-number")) (VHole HInt "value") `shouldSatisfy` isLeft
      fillValue (const (Right "has space"))    (VHole HPath "value") `shouldSatisfy` isLeft

    it "accepts the closed value forms: string+pkgs-ref, list, bool, int" $ do
      parseValue "\"${pkgs.restic}/bin/restic backup <value.1>\"" `shouldBe`
        Right (VStr [PRef ["pkgs", "restic"], PLit "/bin/restic backup ", PHole "value.1"])
      parseValue "[ \"timers.target\" ]" `shouldBe` Right (VList [VStr [PLit "timers.target"]])
      parseValue "true" `shouldBe` Right (VBool True)
      parseValue "42" `shouldBe` Right (VInt 42)

    it "escapes filled program text: injection cannot leave the string" $
      fillValue (const (Right "a\" ; evil ${pkgs.hack}")) (VStr [PHole "value"]) `shouldBe`
        Right "\"a\\\" ; evil \\${pkgs.hack}\""

    it "reads and round-trips an ${artifact.<name>} reference (a name, not computation)" $ do
      parseValue "\"${artifact.myserver}/bin/myserver\"" `shouldBe`
        Right (VStr [PArt "myserver", PLit "/bin/myserver"])
      fmap renderValue (parseValue "\"${artifact.myserver}/bin/myserver\"")
        `shouldBe` Right "\"${artifact.myserver}/bin/myserver\""

    it "rejects a malformed artifact reference" $
      parseValue "\"${artifact.bad name}\"" `shouldSatisfy` isLeft

    -- The reserved <self> (the instance name) is a first-class value token, in
    -- a string and as an artifact reference, so a rule can name the program's
    -- own build/app. It stays literal in .lang (shared) and round-trips.
    it "parses and round-trips the reserved <self> in a value" $ do
      parseValue "\"<self>\""          `shouldBe` Right (VStr [PSelf])
      parseValue "\"echo <self>\""     `shouldBe` Right (VStr [PLit "echo ", PSelf])
      parseValue "${artifact.<self>}"  `shouldBe` Right (VRef (RArt "<self>"))
      parseValue "\"${artifact.<self>}/bin/x\"" `shouldBe`
        Right (VStr [PArt "<self>", PLit "/bin/x"])
      fmap renderValue (parseValue "\"<self>\"")          `shouldBe` Right "\"<self>\""
      fmap renderValue (parseValue "${artifact.<self>}")  `shouldBe` Right "${artifact.<self>}"

    -- An artifact NAME is one grammar everywhere: literal text with <self> and
    -- <capture> occurrences embedded, not a single whole token. A program that
    -- builds two artifacts (a compiled core, a wrapper around it) needs
    -- ${artifact.<self>-core}; the whole-token check refused it, so the shape
    -- was unwritable (docs/gaps board.lips, rule r4).
    it "parses and round-trips a COMPOSED artifact name (<self>/<capture> plus literal text)" $ do
      parseValue "${artifact.<self>-core}" `shouldBe` Right (VRef (RArt "<self>-core"))
      parseValue "${artifact.<name>-core}" `shouldBe` Right (VRef (RArt "<name>-core"))
      parseValue "\"${artifact.<self>-core}/bin/core\"" `shouldBe`
        Right (VStr [PArt "<self>-core", PLit "/bin/core"])
      fmap renderValue (parseValue "${artifact.<self>-core}")
        `shouldBe` Right "${artifact.<self>-core}"

    it "still rejects an artifact name that is not identifier text plus <token>s" $ do
      parseValue "${artifact.<self> core}"  `shouldSatisfy` isLeft
      parseValue "${artifact.<self}"        `shouldSatisfy` isLeft
      parseValue "${artifact.a<>b}"         `shouldSatisfy` isLeft
      parseValue "${artifact.}"             `shouldSatisfy` isLeft

    it "a bare ${pkgs}/${artifact} reference stands as a value (a list of derivations)" $ do
      -- honest Nix: runtimeInputs/systemPackages are lists of packages, not
      -- strings. The model writes ${...}; it round-trips in .lang form but
      -- realizes bare, since a Nix list holds derivations, not interpolations.
      parseValue "${pkgs.curl}"           `shouldBe` Right (VRef (RPkg ["pkgs", "curl"]))
      parseValue "[ ${pkgs.curl} ]"       `shouldBe` Right (VList [VRef (RPkg ["pkgs", "curl"])])
      parseValue "[ ${artifact.weather} ]" `shouldBe` Right (VList [VRef (RArt "weather")])
      renderValue    (VRef (RPkg ["pkgs", "curl"]))          `shouldBe` "${pkgs.curl}"
      renderRealized (VList [VRef (RPkg ["pkgs", "curl"])])  `shouldBe` "[ pkgs.curl ]"
      renderRealized (VList [VRef (RArt "weather")])         `shouldBe` "[ artifact.weather ]"
      -- R1: fillValue stores the CANONICAL form (round-trippable via parseValue,
      -- refs stay ${...}), so assembly can re-parse contributor assertions as
      -- Values; realize is the single canonical->Nix render point.
      fillValue (const (Right "x")) (VList [VRef (RArt "weather")]) `shouldBe` Right "[ ${artifact.weather} ]"
      -- the canonical stored form re-parses to the same Value (the round-trip)
      case fillValue (const (Right "x")) (VList [VRef (RArt "weather")]) of
        Right stored -> parseValue stored `shouldBe` Right (VList [VRef (RArt "weather")])
        Left e       -> expectationFailure ("fillValue failed: " <> show e)

    it "parses and round-trips an attrset (a listOf-submodule element, e.g. ensureUsers)" $ do
      parseValue "{ name = \"app\"; ensureDBOwnership = true; }"
        `shouldBe` Right (VAttr [("name", VStr [PLit "app"]), ("ensureDBOwnership", VBool True)])
      parseValue "[ { name = \"<value>\"; ensureDBOwnership = true; } ]"
        `shouldBe` Right (VList [VAttr [("name", VStr [PHole "value"]), ("ensureDBOwnership", VBool True)]])
      fmap renderValue (parseValue "{ name = \"app\"; ensureDBOwnership = true; }")
        `shouldBe` Right "{ name = \"app\"; ensureDBOwnership = true; }"

    it "parses an empty attrset and round-trips it" $ do
      parseValue "{}" `shouldBe` Right (VAttr [])
      fmap renderValue (parseValue "{}") `shouldBe` Right "{}"

    it "fills a hole inside an attrset element, escaping program text (no injection)" $
      fillValue (const (Right "app\" ; evil"))
        (VList [VAttr [("name", VStr [PHole "value"]), ("ensureDBOwnership", VBool True)]])
        `shouldBe` Right "[ { name = \"app\\\" ; evil\"; ensureDBOwnership = true; } ]"

    it "rejects a non-identifier attrset key (keys are closed, injection-safe)" $ do
      parseValue "{ \"bad key\" = 1; }" `shouldSatisfy` isLeft
      parseValue "{ 1bad = 1; }" `shouldSatisfy` isLeft

    it "rejects computation inside an attrset value" $
      parseValue "{ a = lib.foo 1; }" `shouldSatisfy` isLeft

    it "detects a derivation reference nested in an attrset" $ do
      valueRefsDerivation (VAttr [("src", VRef (RPkg ["pkgs", "curl"]))]) `shouldBe` True
      valueRefsDerivation (VAttr [("name", VStr [PHole "value"])]) `shouldBe` False

    it "a listOf-submodule option accepts a list of attrsets (grounding is unconstrained per element)" $
      valueMatches (OTListOf (OTOther "submodule")) (VList [VAttr [("name", VStr [PLit "app"])]])
        `shouldBe` True

    it "<value.N> picks the Nth token of the matched assertion" $ do
      let r = MapRule "r4" Fact ["backup", "job"]
                [ Emit ["src"] (VStr [PHole "value.1"])
                , Emit ["dst"] (VStr [PHole "value.2"])
                ]
          matched = (mk "d1" "unused" "/var/lib /backup" Stated) { dSubject = Subject ["backup", "job"] }
      case refine 100 [toRule r] (fromList [matched]) of
        Right b -> [ (dSubject d, dAssertion d) | d <- toList b ] `shouldMatchList`
          [ (Subject ["src"], Assertion "\"/var/lib\""), (Subject ["dst"], Assertion "\"/backup\"") ]
        Left e -> expectationFailure ("unexpected refine error: " ++ show e)

    it "an interpreted rule fires on its (kind, subject) and fills <value>" $ do
      let matched = (mk "d2" "unused" "hourly" Stated) { dSubject = Subject ["feed", "cadence"] }
      case refine 100 [toRule rule] (fromList [matched]) of
        Right b -> case toList b of
          [d] -> (dSubject d, dKind d, dAssertion d) `shouldBe`
                   (Subject ["systemd", "timers", "t", "OnCalendar"], Meta, Assertion "\"hourly\"")
          ds  -> expectationFailure ("expected one emitted decision, got " ++ show (length ds))
        Left e -> expectationFailure ("unexpected refine error: " ++ show e)

  describe "pattern nesting (blocks: a line's scope, Lang.Nest)" $ do
    let host  = patOne "p2" [TLit "host", THole "domain"]
                  Concept [SLit "host.", SHole "domain"] [SLit "a virtual host"]
        route = patUnder "p3" "p2" [TLit "-", THole "path", TLit "proxies", TLit "to", THole "up"]
                  [ PatEmit Fact
                      [SLit "host.", SHole "domain", SLit ".route.", SHole "path", SLit ".proxy"]
                      [SHole "up"] ]

    it "puts an ancestor's captures in a child's scope" $
      holesInScope [host, route] route `shouldMatchList` ["path", "up", "domain"]

    it "leaves a top-level pattern with only its own holes" $
      holesInScope [host, route] host `shouldMatchList` ["domain"]

    it "refuses a parent no pattern defines" $
      checkNesting [patUnder "p3" "nope" [TLit "x"] [PatEmit Concept [SLit "a"] [SLit "b"]]]
        `shouldBe` [UnknownParent "p3" "nope"]

    it "refuses a nesting cycle" $
      checkNesting [ patUnder "p3" "p4" [TLit "x"] [PatEmit Concept [SLit "a"] [SLit "b"]]
                   , patUnder "p4" "p3" [TLit "y"] [PatEmit Concept [SLit "c"] [SLit "d"]] ]
        `shouldBe` [NestCycle ["p3", "p4"]]

    it "allows a pattern nested under itself (unbounded depth)" $
      checkNesting [patUnder "p3" "p3" [TLit "-", THole "x"]
                      [PatEmit Concept [SLit "n.", SHole "x"] [SLit "a node"]]]
        `shouldBe` []

    it "refuses an emit hole no ancestor binds" $
      checkNesting [ patOne "p2" [TLit "host"] Concept [SLit "host"] []
                   , patUnder "p3" "p2" [TLit "-"]
                       [PatEmit Fact [SLit "r.", SHole "ghost"] []] ]
        `shouldBe` [UnboundInScope "p3" ["ghost"]]

    it "accepts the two-level engine whose child reads its parent's capture" $
      checkNesting [host, route] `shouldBe` []

    it "scopes two blocks so a repeated item key does not collide" $ do
      -- The failure this closes: both hosts state a "/" location, so both lines
      -- crystallized to route./.proxy and lips reported "sets the same thing two
      -- ways ... keep only one of those lines" -- about two correct lines, while
      -- calling the two host headers decoration.
      let src = T.unlines
            [ "host shop.example.com:"
            , "- / proxies to http://localhost:3000."
            , "host blog.example.com:"
            , "- / proxies to http://localhost:4000."
            ]
      fmap subjectsOf (crystallize "g" [host, route] src) `shouldBe` Right
        [ ["host", "shop.example.com"]
        , ["host", "shop.example.com", "route", "/", "proxy"]
        , ["host", "blog.example.com"]
        , ["host", "blog.example.com", "route", "/", "proxy"]
        ]

    it "numbers anonymous siblings per block, so their fields stay together" $ do
      -- Nothing in the program names a target, so position is the only identity
      -- there is; without it both records collapse onto one subject and the
      -- correlation between a job and its url is lost.
      let targets = patOne "t1" [TLit "targets"] Concept [SLit "targets"] [SLit "the scrape targets"]
          target  = patUnder "t2" "t1" [TLit "-", TLit "target"]
                      [PatEmit Concept [SLit "targets.", SHole "n:index"] [SLit "one target"]]
          field k = patUnder ("t" <> k) "t2" [TLit "-", TLit k, TLit "is", THole "v"]
                      [PatEmit Fact [SLit "targets.", SHole "n", SLit ".", SLit k] [SHole "v"]]
          src = T.unlines
            [ "targets:"
            , "- target:", "- job is web.", "- url is http://a/metrics."
            , "- target:", "- job is db.",  "- url is http://b/metrics."
            ]
      fmap subjectsOf (crystallize "m" [targets, target, field "job", field "url"] src)
        `shouldBe` Right
          [ ["targets"]
          , ["targets", "1"], ["targets", "1", "job"], ["targets", "1", "url"]
          , ["targets", "2"], ["targets", "2", "job"], ["targets", "2", "url"]
          ]

    it "keeps a repeated item distinct when it is index-keyed" $ do
      -- Four steps, the fourth repeating the second. Keyed by their own text they
      -- merged into three and the fourth line vanished at exit 0.
      let steps = patOne "s1" [TLit "steps"] Concept [SLit "steps"] [SLit "the steps"]
          step  = patUnder "s2" "s1" [TLit "-", TMulti "cmd"]
                    [PatEmit Fact [SLit "steps.", SHole "n:index"] [SHole "cmd"]]
          src = "steps:\n- fetch.\n- run tests.\n- publish.\n- run tests.\n"
      fmap subjectsOf (crystallize "r" [steps, step] src) `shouldBe` Right
        [["steps"], ["steps","1"], ["steps","2"], ["steps","3"], ["steps","4"]]

    it "fails loud on an item line with no block to sit in" $
      crystallize "g" [host, route] "- / proxies to http://localhost:3000.\n"
        `shouldBe` Left [NoParentBlock 1 "- / proxies to http://localhost:3000." ["p2"]]

    it "resolves depth by indentation for a pattern nested under itself" $ do
      -- Unbounded depth: an item sits inside the item above it when it is more
      -- indented, and roots in the header otherwise. The two parents are tried in
      -- the order the id declares them. This is the ONLY place leading whitespace
      -- means anything.
      let root = patOne "n0" [TLit "tree"] Concept [SLit "tree"] [SLit "a tree"]
          node = Pattern "n1" ["n1", "n0"] [TLit "-", THole "name"]
                   [PatEmit Fact [SHole "k:key", SLit ".", SHole "name"] [SLit "a node"]]
          src = T.unlines ["tree:", "- File", "  - New", "    - Item", "- Edit", "  - New"]
      fmap subjectsOf (crystallize "t" [root, node] src) `shouldBe` Right
        [ ["tree"]
        , ["tree","File"], ["tree","File","New"], ["tree","File","New","Item"]
        , ["tree","Edit"], ["tree","Edit","New"]
        ]

    it "names the block each line sits in, and stops calling a header decoration" $ do
      -- Before blocks, the two host headers were reported "decorative, realizing
      -- nothing -- editing these changes no output", which was false: their word
      -- keys every option their items realize.
      let eng = EngineData [host, route] [] [] []
          src = T.unlines
            [ "host shop.example.com:", "- / proxies to http://localhost:3000."
            , "host blog.example.com:", "- / proxies to http://localhost:4000." ]
          d = diagnose "g" eng src
      [ (n, par) | Matched n _ _ par _ <- diagLines d ]
        `shouldBe` [(1, Nothing), (2, Just 1), (3, Nothing), (4, Just 3)]
      diagHeads d `shouldBe` [(1, "host shop.example.com:", 1), (3, "host blog.example.com:", 1)]
      diagInert d `shouldBe` []

    it "names a program word coerced into a Nix path" $ do
      -- A bare Nix path means "copy this location into the store": pure eval
      -- refuses an absolute one, and a document root exists on the running
      -- machine, not in the store. Found by a flake check on the first engine to
      -- write <value:path>, so the gate now names it (invariant 4).
      valuePathHoles (VHole HPath "value") `shouldBe` ["value"]
      valuePathHoles (VStr [PHole "value"]) `shouldBe` []
      valuePathHoles (VList [VAttr [("root", VHole HPath "value")]]) `shouldBe` ["value"]
      valuePathHoles (VPath "./artifacts/x") `shouldBe` []

    it "refuses <key> in a pattern that heads no block" $
      checkNesting [patOne "p1" [TLit "x"] Concept [SHole "k:key", SLit ".a"] []]
        `shouldBe` [KeyWithoutBlock "p1"]

  describe "crystallize round-trip (every decision a line states must re-read)" $ do
    -- The defect this closes (examples/website, 2026-07-31): a two-word quoted
    -- label was spliced into a subject SEGMENT, so the emitted line read
    -- "d4 concept button.drück mich stated ..." -- whitespace is the decision
    -- line's own separator, and readDecision then choked on "mich" as a
    -- strength. Every gate was green while out/*.decisions had stopped being
    -- canonical text, which leaves the regeneration gate comparing against a
    -- document lips can no longer parse. Domain-blind and offline: render each
    -- decision, read it back, insist on the same decision.
    let button = patOne "p1" [TLit "button", THole "label"]
                   Concept [SLit "button.", SHole "label"] [SLit "a button"]
    it "refuses a captured value that breaks the decision line it lands in" $
      case crystallize "w" [button] "button \"drück mich\":\n" of
        Left [Unreadable 1 t why] -> do
          t `shouldBe` "button \"drück mich\":"
          why `shouldSatisfy` T.isInfixOf "unknown strength: mich"
        other -> expectationFailure ("expected one Unreadable, got " ++ show other)
    it "marks the offending line in the per-line report, never 'ok'" $
      -- The report and the verdict must agree: a reader saw "line 1  ok" from
      -- classifyLines and then the whole file failing on line 1, because the
      -- round trip lived in crystallize alone.
      case classifyLines "w" [button] "button \"dr\252ck mich\":\n" of
        [Illegible 1 t why] -> do
          t `shouldBe` "button \"dr\252ck mich\":"
          why `shouldSatisfy` T.isInfixOf "unknown strength: mich"
        other -> expectationFailure ("expected one Illegible, got " ++ show other)
    it "accepts a single-word capture in the same position" $
      fmap (map (\d -> case dSubject d of Subject ss -> ss) . toList)
           (crystallize "w" [button] "button \"go\":\n")
        `shouldBe` Right [["button", "go"]]
    it "leaves a multi-word value in an ASSERTION alone (it is quoted there)" $
      -- The gate must not over-refuse: the assertion is a quoted field, so
      -- spaces in it round-trip, and only the subject side is at risk.
      crystallize "w" [patOne "p1" [TLit "say", THole "m"] Fact [SLit "s"] [SHole "m"]]
                     "say \"hello world\"\n"
        `shouldSatisfy` isRight

  describe "a several-part value (<value.N> must read the part, not the word)" $ do
    -- The defect this closes (examples/website, 2026-07-31; filed by the web
    -- mint as gap multiword-route-body): a pattern stating two program words as
    -- one fact ("<label> <target>") lost the boundary between them, so a rule
    -- reading <value.1>/<value.2> got "drück" and "mich" and the real target
    -- "main" was dropped. Every gate stayed green, since every token WAS spent
    -- -- into the wrong hole. A several-part value now quotes its parts.
    let two = patOne "p" [TLit "button", THole "label", TLit "opens", THole "target"]
                Fact [SLit "button.click"] [SHole "label", SLit " ", SHole "target"]
        one = patOne "p" [TLit "install", TMulti "pkgs"]
                Fact [SLit "install.1"] [SHole "pkgs"]
        assn p binds = case applyPattern p (Map.fromList binds) of
          [(_, _, Assertion a, _)] -> a
          other                    -> error (show other)
    it "quotes every part of a several-part value" $
      assn two [("label", "drück mich"), ("target", "main")]
        `shouldBe` "\"drück mich\" \"main\""
    it "leaves a one-part value alone, so its own words stay its words" $
      assn one [("pkgs", "htop ripgrep tmux")] `shouldBe` "htop ripgrep tmux"
    it "reads back one part per hole, whatever a part contains" $ do
      valueTokens (assn two [("label", "drück mich"), ("target", "main")])
        `shouldBe` ["drück mich", "main"]
      -- A part carrying a quote must not close its own quoting.
      valueTokens (assn two [("label", "say \"hi\""), ("target", "main")])
        `shouldBe` ["say \"hi\"", "main"]
      valueTokens (assn one [("pkgs", "htop ripgrep tmux")])
        `shouldBe` ["htop", "ripgrep", "tmux"]
    it "hands a rule the part, and the whole value without the quoting" $ do
      -- End to end: the shape examples/website got wrong. <value.1> is the
      -- two-word label, <value.2> the target, <value> the parts joined.
      let rule = MapRule "r" Fact ["button", "click"]
            [ Emit ["services", "x", "label"] (VStr [PHole "value.1"])
            , Emit ["services", "x", "target"] (VStr [PHole "value.2"])
            , Emit ["services", "x", "both"] (VStr [PHole "value"]) ]
          prog = "button \"drück mich\" opens main\n"
      case crystallize "w" [two] prog of
        Left e -> expectationFailure ("crystallize failed: " <> show e)
        Right base -> case runBase (mergeModeOf [rule]) assembleSubject 100 (map toRule [rule]) [] base of
          Left e   -> expectationFailure ("run failed: " <> show e)
          Right rl -> do
            rlModule rl `shouldSatisfy` T.isInfixOf "services.x.label = \"drück mich\";"
            rlModule rl `shouldSatisfy` T.isInfixOf "services.x.target = \"main\";"
            rlModule rl `shouldSatisfy` T.isInfixOf "services.x.both = \"drück mich main\";"
    it "a contract on part #N reads the same part the rule does" $ do
      let base = case crystallize "w" [two] "button \"drück mich\" opens main\n" of
            Right b -> b
            Left e  -> error (show e)
          ex n = Expect "a1" ["services","x","label"] (Subject ["button","click"]) (Just n)
      expectedValue base (ex 1) `shouldBe` Right "drück mich"
      expectedValue base (ex 2) `shouldBe` Right "main"

  describe "language storage (crystallization plan: .lang round-trip)" $ do
    let engine = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                  Fact [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
                  Oblige [SLit "feed.ingest"] [SLit "every bank row becomes one ", SHole "e"]
              ]
          , edRules =
              [ MapRule "r1" Oblige ["feed", "ingest"]
                  [ Emit ["services", "x", "enable"] (VBool True) ] ]
          , edDemands = [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?" ]
          , edMerges  = [ MergeSpec "m1" ["environment", "systemPackages"] True ]
          }

    it "round-trips the whole engine: readLang . renderLang == Right" $
      readLang (renderLang (FromGeneration "cafe0123") engine) `shouldBe` Right engine

    it "declares a structure-bound hole in an emit subject" $
      -- An item with no key of its own (no word in the line identifies it) still
      -- needs an identity, or two such lines collapse onto one subject. <n:index>
      -- is filled from the line's position among its siblings, not from a token
      -- -- the same move as <value:pkg>, which fills from something other than a
      -- program word.
      structHoles (patOne "p1" [TLit "-", TMulti "s"] Fact
                     [SLit "step.", SHole "n:index"] [SHole "s"])
        `shouldBe` [("n", SIndex)]

    it "fills a struct hole and a plain reference to it from one binding" $
      -- The declaration is <n:index>; every reference (here, and in a descendant
      -- pattern) is the plain <n>, so nesting two anonymous levels needs no
      -- shadowing rule.
      applyPattern (patOne "p1" [TLit "-"] Fact [SLit "s.", SHole "n:index"] [SHole "n"])
                   (Map.fromList [("n", "2")])
        `shouldBe` [(Subject ["s", "2"], Fact, Assertion "2", Stated)]

    it "refuses a struct hole whose name a template hole already binds" $
      parsePatternBody "p1" "- <n> => fact s.<n:index> \"<n>\"" `shouldSatisfy` isLeft

    it "round-trips a struct hole through the .lang" $ do
      let ed = EngineData
            [patOne "p1" [TLit "-", TMulti "s"] Fact
               [SLit "step.", SHole "n:index", SLit ".command"] [SHole "s"]] [] [] []
      readLang (renderLang (FromGeneration "cafe0123") ed) `shouldBe` Right ed

    it "round-trips a pattern that names the pattern it nests under" $ do
      -- Nesting rides the pattern id, so the template grammar is untouched: a
      -- template may still begin with the word "under" (a body prefix could not
      -- be read out of free template text without refusing such a template,
      -- which invariant 3 calls a kernel bug).
      let host  = patOne "p2" [TLit "host", THole "domain"]
                    Concept [SLit "host.", SHole "domain"] [SLit "a virtual host"]
          route = patUnder "p3" "p2" [TLit "-", THole "path", TLit "proxies", TLit "to", THole "up"]
                    [ PatEmit Fact
                        [SLit "host.", SHole "domain", SLit ".route.", SHole "path", SLit ".proxy"]
                        [SHole "up"] ]
          ed = EngineData [host, route] [] [] []
      readLang (renderLang (FromGeneration "cafe0123") ed) `shouldBe` Right ed

    it "stores the parent in the pattern's subject path" $
      renderLang (FromGeneration "cafe0123")
        (EngineData [patUnder "p3" "p2" [TLit "x"] [PatEmit Concept [SLit "a"] [SLit "b"]]] [] [] [])
        `shouldSatisfy` T.isInfixOf "lang.pattern.p3.under.p2"

    it "reads a qualified pattern id at the mint door" $
      fmap pParents (parsePatternBody "p3.under.p2" "- <path> => concept a.<path> \"x\"")
        `shouldBe` Right ["p2"]

    it "leaves an unqualified pattern id parentless" $
      fmap pParents (parsePatternBody "p3" "- <path> => concept a.<path> \"x\"")
        `shouldBe` Right []

    it "keeps the bare id as the pattern's own id" $
      fmap pId (parsePatternBody "p3.under.p2" "- <path> => concept a.<path> \"x\"")
        `shouldBe` Right "p3"

    it "readLang refuses an engine whose nesting does not close" $ do
      -- One door: every verb reads a .lang through readLang, so generate,
      -- compile, check and lsp all inherit the nesting checks.
      let orphan = "p3 meta lang.pattern.p3.under.p2 stated \"- <x> => fact a.<x> \\\"<x>\\\"\"\n"
      readLang orphan `shouldSatisfy` isLeft

    it "readLang anchors a nesting error to the offending pattern's line" $ do
      let src = T.unlines
            [ "p1 meta lang.pattern.p1 stated \"host <d> => concept host.<d> \\\"h\\\"\""
            , "p3 meta lang.pattern.p3.under.p1 stated \"- <x> => fact a.<ghost> \\\"<x>\\\"\""
            ]
      case readLang src of
        Left es -> map peLine es `shouldBe` [2]
        Right _ -> expectationFailure "expected a nesting error"

    it "rejects an unrecognized engine line loudly (never silently dropped)" $ do
      -- Regression (kernel review): a mistyped group subject must fail, not be
      -- quietly ignored (which would lose a rule and mislead a later run).
      let bad = "r1 meta engine.rulez.r1 stated \"match oblige a => b.c \\\"true\\\"\" @gen:x\n"
      readLang bad `shouldSatisfy` isLeft

    it "anchors a body parse error to its real source line, not line 0" $ do
      -- Regression (kernel review): readLang lost the line number for body
      -- sub-grammar errors. Line 2 here carries a malformed rule body.
      let src = T.unlines
            [ "p1 meta lang.pattern.p1 stated \"x => fact y \\\"z\\\"\" @gen:x"
            , "r1 meta engine.rule.r1 stated \"not-a-rule-body\" @gen:x"
            ]
      case readLang src of
        Left es -> map peLine es `shouldBe` [2]
        Right _ -> expectationFailure "expected a body parse error"

    it "stamps every .lang line with the generation event" $
      let stamped = renderLang (FromGeneration "cafe0123") engine
       in [ l | l <- T.lines stamped, not (T.null l), not ("@gen:cafe0123" `T.isSuffixOf` l) ]
            `shouldBe` []

    it "generation ids are deterministic and content-sensitive" $ do
      let r  = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" "prog" "tt" "reply"
          r' = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" "prog" "tt" "reply2"
          rc = record "m" Nixos "github:o/r/aaa" "high" 0.5 "sp" "prog" "tt" "reply"
          rt = record "m" HomeManager "github:o/r/aaa" "high" 0.7 "sp" "prog" "tt" "reply"
          rl = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" "prog" "other lookup" "reply"
          rk = record "m" Nixos "github:o/r/aaa" "low" 0.7 "sp" "prog" "tt" "reply"
          rs = record "m" Nixos "github:o/r/bbb" "high" 0.7 "sp" "prog" "tt" "reply"
      genId r `shouldBe` genId r
      genId r `shouldNotBe` genId r'
      -- the confidence threshold is pinned: changing it changes the id
      genId r `shouldNotBe` genId rc
      -- the target world is pinned: changing it changes the id
      genId r `shouldNotBe` genId rt
      -- what the mint was TOLD is an input: changing it changes the id
      genId r `shouldNotBe` genId rl
      -- the reasoning level steers the reply, so it is pinned too
      genId r `shouldNotBe` genId rk
      -- the option schema decides which rules were admissible, so the pin that
      -- names it is an input of the event like every other
      genId r `shouldNotBe` genId rs
      T.length (genId r) `shouldBe` 16

    it "names the option schema the mint was grounded against" $
      -- A reader (and the re-mint that wants the same grounding) must be able to
      -- see WHICH schema admitted these rules, without re-deriving it from
      -- whichever lips binary happens to be installed.
      T.lines (record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" "prog" "tt" "reply")
        `shouldContain` ["schema: github:o/r/aaa"]
    -- The record stores the corpus verbatim, which makes it the one offline
    -- witness of what each program SAID when the language (and any baked
    -- artifact source) was minted. The source-specification gate reads it back.
    it "reads one program's text back out of the record it was minted from" $ do
      let progs = [("a/one.log.lips", "first line\nsecond line\n"), ("a/two.log.lips", "other\n")]
          r     = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" (corpusText progs) "tt" "reply"
      recordedProgram "a/one.log.lips" r `shouldBe` Just "first line\nsecond line\n"
      -- addressed by file NAME, so the same program under another directory reads
      recordedProgram "b/two.log.lips" r `shouldBe` Just "other\n"
      -- a program the record never saw has nothing to compare
      recordedProgram "a/three.log.lips" r `shouldBe` Nothing
      -- and the section stops before the next record block
      recordedProgram "a/two.log.lips" r `shouldSatisfy` maybe False (not . T.isInfixOf "transcript")

    -- The corpus reading, which the source-specification gate needs to judge a
    -- program the record holds no section for: its sentences must at least be
    -- sentences the mint saw somewhere in the language.
    it "reads every program section back out of the record" $ do
      let progs = [("a/one.log.lips", "first line\nsecond line\n"), ("a/two.log.lips", "other\n")]
          r     = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" (corpusText progs) "tt" "reply"
      recordedPrograms r `shouldBe`
        [("one.log.lips", "first line\nsecond line\n"), ("two.log.lips", "other\n")]
      -- a record with no corpus block at all yields no sections, never a crash
      recordedPrograms "nothing here" `shouldBe` []

    it "writes the target slug into the record text" $
      record "m" HomeManager "github:o/r/aaa" "high" 0.7 "sp" "prog" "tt" "reply"
        `shouldSatisfy` T.isInfixOf "target: home-manager"
    -- readRecordedTarget scans for the FIRST line starting with "target:", so
    -- the headers must stay above every section a lookup answer could pollute.
    it "keeps the headers above the tool transcript" $ do
      let r = record "m" Nixos "github:o/r/aaa" "high" 0.7 "sp" "prog" "<- query_options\ntarget: not-this" "reply"
      take 4 (T.lines r)
        `shouldBe` ["model: m", "target: nixos", "schema: github:o/r/aaa", "thinking: high"]
      r `shouldSatisfy` T.isInfixOf "--- tool transcript ---"

    it "emit grammar carries no strength: body parses and applies to a Stated fact" $
      -- A pattern reads a program line the human wrote, so the kernel fixes the
      -- emitted decision to Stated; there is no strength token to write or drop.
      case parsePatternBody "ps" "say <msg> => fact out \"<msg>\"" of
        Right p  -> applyPattern p (Map.fromList [("msg", "hi")])
                      `shouldBe` [(Subject ["out"], Fact, Assertion "hi", Stated)]
        Left e   -> expectationFailure (T.unpack e)

    it "a stray 'stated' token is read as the assertion, not a strength slot" $
      -- No lenient backward-compat: the old <kind> <subject> <strength>
      -- \"...\" form no longer has a strength slot, so 'stated' where a quoted
      -- assertion is expected fails loud rather than being silently absorbed.
      parsePatternBody "po" "say <msg> => fact out stated \"<msg>\""
        `shouldSatisfy` isLeft

    it "reads a hole with fused trailing punctuation: '<when>.' binds <when>" $
      case parsePatternBody "p9" "back up <src> every <when>. => fact backup.job \"<src> <when>\"" of
        Right p -> pTemplate p `shouldBe`
          [TLit "back", TLit "up", THole "src", TLit "every", THole "when"]
        Left e  -> expectationFailure (T.unpack e)

    it "reads a quoted hole \"<body>\" in a template as a capturing hole (gap 2)" $
      case parsePatternBody "pr" "- <path> returns text \"<body>\" => fact route.text \"<path> <body>\"" of
        Right p -> pTemplate p `shouldBe`
          [TLit "-", THole "path", TLit "returns", TLit "text", THole "body"]
        Left e  -> expectationFailure (T.unpack e)

    it "splits on the LAST unquoted => so a template may itself contain => (route arrow)" $
      case parsePatternBody "pr2" "- <path> => status <code> \"<body>\" => fact route.<path> \"<path> <code> <body>\"" of
        Right p -> do
          pTemplate p `shouldBe`
            [TLit "-", THole "path", TLit "=>", TLit "status", THole "code", THole "body"]
          pEmits p `shouldBe` [PatEmit Fact [SLit "route.", SHole "path"] [SHole "path", SLit " ", SHole "code", SLit " ", SHole "body"]]
        Left e  -> expectationFailure (T.unpack e)

    it "rejects a pattern whose target hole is not bound by the template" $ do
      let bad = (patternToDecision (patOne "p1" [THole "loc"] Fact [SLit "feed.source"] [SHole "loc"]))
                  { dAssertion = Assertion "<loc> => fact feed.source \"<missing>\"" }
      decisionToPattern bad `shouldSatisfy` isLeft

  -- Corpus pin (crystallization + engine-synthesis plans): a whole feed engine
  -- as data (patterns, rules, demands), the loose program, and edits of it,
  -- all crystallized and run with no model and no hand-written engine.
  describe "end-to-end feed corpus (engine as data, edit-tolerance)" $ do
    let svc seg = ["systemd", "services", "ledger-ingest"] ++ seg
        quotedValue = VStr [PHole "value"]
        feedEngine = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "csv", TLit "files", TLit "into", THole "loc"]
                  Fact [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
                  Fact [SLit "feed.cadence"] [SHole "sched"]
              , patOne "p3" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "exactly", TLit "one", THole "rec"]
                  Oblige [SLit "feed.ingest"] [SHole "rec"]
              ]
          , edRules =
              [ MapRule "r1" Oblige ["feed", "ingest"]
                  [ Emit (svc ["enable"]) (VBool True)
                  , Emit (svc ["wantedBy"]) (VList [VStr [PLit "multi-user.target"]])
                  ]
              , MapRule "r2" Fact ["feed", "cadence"]
                  [ Emit ["systemd", "timers", "ledger-ingest", "timerConfig", "OnCalendar"] quotedValue ]
              , MapRule "r3" Fact ["feed", "source"]
                  [ Emit (svc ["environment", "LEDGER_INBOX"]) quotedValue ]
              ]
          , edDemands =
              [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?"
              , DemandSpec "q2" ["feed", "cadence"] "how often does the feed deliver?"
              ]
          , edMerges = []
          }
        loose loc sched = T.unlines
          [ "the bank drops csv files into " <> loc <> "."
          , "the bank delivers new files every " <> sched <> "."
          , "every bank row becomes exactly one transaction."
          ]
        runLoose loc sched = do
          -- through storage deliberately: the on-disk form is what run uses
          eng  <- either (Left . show) Right (readLang (renderLang (FromGeneration "feedcafe") feedEngine))
          base <- either (Left . show) Right (crystallize "feed" (edPatterns eng) (loose loc sched))
          either (Left . show) Right
            (runBaseReplace 10000 (map toRule (edRules eng)) (map toDemand (edDemands eng)) base)
        moduleWith inbox oncal = T.unlines
          [ "# lips-realized module. Generated from a ground decision base; do not edit."
          , "{ config, lib, pkgs, ... }:"
          , "{"
          , "  # <-d3 via r1"
          , "  systemd.services.ledger-ingest.enable = true;"
          , "  # <-d1 via r3"
          , "  systemd.services.ledger-ingest.environment.LEDGER_INBOX = \"" <> inbox <> "\";"
          , "  # <-d3 via r1"
          , "  systemd.services.ledger-ingest.wantedBy = [ \"multi-user.target\" ];"
          , "  # <-d2 via r2"
          , "  systemd.timers.ledger-ingest.timerConfig.OnCalendar = \"" <> oncal <> "\";"
          , "}"
          ]

    it "crystallizes and realizes the original program (no model, no hand-written engine)" $
      runLoose "inbox/" "hour" `shouldBe` Right (moduleWith "inbox/" "hour")

    it "absorbs value edits with no model (edit-tolerance by construction)" $
      runLoose "dropzone/" "day" `shouldBe` Right (moduleWith "dropzone/" "day")

    it "an unmet minted demand is an open question" $ do
      let noSource = T.unlines
            [ "the bank delivers new files every hour."
            , "every bank row becomes exactly one transaction."
            ]
      case crystallize "feed" (edPatterns feedEngine) noSource of
        Left e -> expectationFailure ("unexpected crystallize error: " ++ show e)
        Right base ->
          runBaseReplace 10000 (map toRule (edRules feedEngine)) (map toDemand (edDemands feedEngine)) base
            `shouldBe` Left (OpenQuestions ["where do the files arrive?"])

  -- Authoring diagnostics: the pure (language, program) view a human/editor
  -- reads (editor-tooling milestone, first rung). One shared matcher with
  -- crystallize, so a diagnostic never disagrees with what run would do.
  describe "diagnose (authoring view over .lang, pure)" $ do
    let eng = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "csv", TLit "files", TLit "into", THole "loc"]
                  Fact [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
                  Fact [SLit "feed.cadence"] [SHole "sched"]
              ]
          , edRules = []
          , edDemands =
              [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?"
              , DemandSpec "q2" ["feed", "cadence"] "how often does the feed deliver?"
              ]
          , edMerges = []
          }

    it "reports a matched line with the pattern it used and the decision it yields" $ do
      let d = diagnose "f" eng "the bank drops csv files into inbox/."
      diagMatched d `shouldBe` 1
      diagTotal d `shouldBe` 1
      case diagLines d of
        [Matched 1 _ "p1" _ [dec]] -> dSubject dec `shouldBe` Subject ["feed", "source"]
        other                  -> expectationFailure ("unexpected: " ++ show other)

    it "flags a line that escapes the language as Unmatched" $ do
      let d = diagnose "f" eng "encrypt everything at rest."
      diagMatched d `shouldBe` 0
      case diagLines d of
        [Unmatched 1 _] -> pure ()
        other           -> expectationFailure ("unexpected: " ++ show other)

    it "lists demands left open by what the program states" $ do
      -- only the source is stated, so the cadence demand stays open
      let d = diagnose "f" eng "the bank drops csv files into inbox/."
      diagOpen d `shouldBe` ["how often does the feed deliver?"]

    it "skips blank and comment lines in the coverage count" $ do
      let d = diagnose "f" eng "# a note\n\nthe bank drops csv files into inbox/."
      diagTotal d `shouldBe` 1
      diagMatched d `shouldBe` 1

    -- A line the engine reads and then drops contributes NOTHING to the output,
    -- so editing it changes nothing. 'Concept' is the only kind realize drops,
    -- so a Concept-only line is exactly the inert case. Reporting it is what
    -- keeps a mint from silencing an inconvenient line unnoticed
    -- (docs/gaps/README.md, finding 1: silent concept demotion).
    -- A template hole binds program TEXT, so a redundant :type on it carries no
    -- information. Two independent mints wrote <path:path> and <days:int> and
    -- were rejected for a hole the emit could not find, so the grammar accepts
    -- and degrades it (the same move already made for a typed hole in a string).
    it "degrades a typed template hole to the plain hole" $ do
      let engT = EngineData
            { edPatterns = [ patOne "p2" [TLit "stored", TLit "in", THole "path"]
                               Fact [SLit "habit.log"] [SHole "path"] ]
            , edRules = [], edDemands = [], edMerges = [] }
          d = diagnose "f" engT "stored in /tmp/habits.tsv"
      diagMatched d `shouldBe` 1
      parseTplTok "<path:path>" `shouldBe` THole "path"
      parseTplTok "<days:int>"  `shouldBe` THole "days"
      -- a colon that is not a known type stays part of the name
      parseTplTok "<a:b>"       `shouldBe` THole "a:b"

    it "reports a decorative (Concept-only) line as contributing nothing" $ do
      let engC = eng { edPatterns = edPatterns eng ++
                        [ patOne "p3" [TLit "feed", TLit "notes"]
                            Concept [SLit "notes"] [SLit "feed notes"] ] }
          d = diagnose "f" engC "feed notes\nthe bank drops csv files into inbox/."
      map fst (diagInert d) `shouldBe` [1]

    -- The http engine's real shape: a steer whose rule emits a constant. The
    -- author needs the LINE named, not the pattern id the mint chose.
    it "names a line whose word the engine reads and discards" $ do
      let engD = EngineData
            { edPatterns =
                [ patOne "p3" [TLit "write", TLit "the", TLit "server", TLit "in", THole "lang"]
                    Steer [SLit "server.language"] [SHole "lang"] ]
            , edRules = [ MapRule "r3" Steer ["server", "language"]
                            [ Emit ["environment", "etc", "builder", "text"]
                                   (VStr [PLit "buildGoModule"]) ] ]
            , edDemands = []
            , edMerges = []
            }
      diagDropped (diagnose "f" engD "write the server in go")
        `shouldBe` [(1, "write the server in go", ["lang"])]

    it "reports no dropped word when the rule reads the value" $ do
      let engK = EngineData
            { edPatterns =
                [ patOne "p3" [TLit "write", TLit "the", TLit "server", TLit "in", THole "lang"]
                    Steer [SLit "server.language"] [SHole "lang"] ]
            , edRules = [ MapRule "r3" Steer ["server", "language"]
                            [ Emit ["environment", "etc", "builder", "text"]
                                   (VStr [PHole "value"]) ] ]
            , edDemands = []
            , edMerges = []
            }
      diagDropped (diagnose "f" engK "write the server in go") `shouldBe` []

    it "does not call a realizing line decorative" $ do
      let d = diagnose "f" eng "the bank drops csv files into inbox/."
      diagInert d `shouldBe` []

    -- The concept escape (review 2026-07-29, V6): a Concept realizes nothing, so
    -- DELETING such a line changes no output and every gate stays green -- while
    -- an artifact's minted source was written from exactly those lines. Rewording
    -- one is already caught (its pattern is all-literal, so the line goes
    -- unmatched); the silent case is retirement, which this names.
    it "names a concept the program stated at mint time and no longer states" $ do
      let engC = eng { edPatterns = edPatterns eng ++
                        [ patOne "p3" [TLit "feed", TLit "notes"]
                            Concept [SLit "notes"] [SLit "feed notes"] ] }
          crys src = case crystallize "f" (edPatterns engC) src of
            Right b -> b
            Left e  -> error ("fixture failed to crystallize: " <> show e)
          was = crys "feed notes\nthe bank drops csv files into inbox/."
          now = crys "the bank drops csv files into inbox/."
      map (dSubject) (retiredConcepts was now) `shouldBe` [Subject ["notes"]]
      retiredConcepts was was `shouldBe` []
      -- a program that only ADDS a concept has retired none
      retiredConcepts now was `shouldBe` []

    it "derives one completion snippet per pattern, holes as numbered tab-stops" $
      case completionItems eng of
        (i0 : i1 : _) -> do
          map ciLabel [i0, i1] `shouldBe`
            [ "the bank drops csv files into <loc>"
            , "the bank delivers new files every <sched>" ]
          ciSnippet i0 `shouldBe` "the bank drops csv files into ${1:loc}"
        _ -> expectationFailure "expected two completion items"

    -- Contextual completion: complete the sentence a line has already started.
    -- Already-typed holes become literals; only holes still to type become
    -- tab-stops; a fragment at the cursor completes the literal it prefixes.
    let at line col = completionItemsAt eng line col

    it "offers every whole sentence on an empty line" $
      at "" 0 `shouldBe` completionItems eng

    it "keeps the common prefix and completes both patterns at a branch" $ do
      let items = at "the bank " (T.length "the bank ")
      map ciLabel items `shouldBe`
        [ "the bank drops csv files into <loc>"
        , "the bank delivers new files every <sched>" ]
      map ciSnippet items `shouldBe`
        [ "the bank drops csv files into ${1:loc}"
        , "the bank delivers new files every ${1:sched}" ]

    it "fills an already-typed hole as a literal, completes the rest" $ do
      -- cursor right after the value, before the line is whole: loc still unfilled
      let items = at "the bank drops csv files into inbox/ and "
                     (T.length "the bank drops csv files into inbox/ and ")
      -- 'and' matches no literal after loc -> p1 is outgrown, so no candidates
      items `shouldBe` []

    it "offers nothing once the line already matches a pattern whole" $
      at "the bank drops csv files into inbox/" (T.length "the bank drops csv files into inbox/")
        `shouldBe` []

    it "completes a fragment of the next literal (cursor mid-word)" $ do
      let items = at "the bank dr" (T.length "the bank dr")
      map ciLabel items `shouldBe` [ "the bank drops csv files into <loc>" ]
      map ciSnippet items `shouldBe` [ "the bank drops csv files into ${1:loc}" ]

    it "prefers the literal a fragment prefixes over an unrelated branch" $ do
      -- 'dr' prefixes 'drops' but not 'delivers', so only p1 is offered
      length (at "the bank dr" (T.length "the bank dr")) `shouldBe` 1

    it "does not offer a pattern the prefix has outgrown" $ do
      -- extra tokens after a filled loc: the line exceeds p1
      at "the bank drops csv files into inbox/ more" (T.length "the bank drops csv files into inbox/ more")
        `shouldBe` []

    -- The type a hole has is the engine's own answer (Engine.Typing), so the
    -- editor states it instead of leaving the author to guess what a word must
    -- BE. Unknown stays silent: a wrong type reads as the author's mistake.
    describe "a completion states the type the engine gives each hole" $ do
      let engT = EngineData
            { edPatterns =
                [ patOne "p1" [TLit "serve", TLit "on", TLit "port", THole "port"]
                    Fact [SLit "http.port"] [SHole "port"]
                , patOne "p2" [TLit "alerts", TLit "go", TLit "to", THole "dest"]
                    Fact [SLit "alert.target"] [SHole "dest"]
                , patOne "p3" [TLit "run", TLit "it", TLit "in", THole "lang"]
                    Steer [SLit "server.language"] [SHole "lang"]
                , patOne "p4" [TLit "keep", THole "count", THole "period", TLit "snapshots"]
                    Fact [SLit "backup.retention"] [SHole "count", SLit " ", SHole "period"]
                ]
            , edRules =
                [ MapRule "r1" Fact ["http", "port"]
                    [ Emit ["services", "nginx", "listenPort"] (tval "<value:int>") ]
                , MapRule "r2" Fact ["alert", "target"]
                    [ Emit ["environment", "etc", "a", "text"] (tval "\"<value>\"") ]
                , MapRule "r3" Steer ["server", "language"]
                    [ Emit ["artifact", "s", "builder"] (tval "\"buildGoModule\"") ]
                , MapRule "r4" Fact ["backup", "retention"]
                    [ Emit ["services", "x", "pruneOpts"] (tval "[ <value.1:int> \"<value.2>\" ]") ]
                ]
            , edDemands = [], edMerges = []
            }

      it "names the type in the label and in the detail" $
        case completionItems engT of
          (i1 : i2 : i3 : _) -> do
            map ciLabel [i1, i2, i3] `shouldBe`
              [ "serve on port <port:int>"
              , "alerts go to <dest:text>"
              , "run it in <lang>" ]
            map ciDetail [i1, i2, i3] `shouldBe`
              [ Just "port: int", Just "dest: text", Nothing ]
          _ -> expectationFailure "expected three completion items"

      it "leaves the inserted snippet free of the type" $
        case completionItems engT of
          (i1 : _) -> ciSnippet i1 `shouldBe` "serve on port ${1:port}"
          _        -> expectationFailure "expected a completion item"

      it "types each hole of a several-part value by its own part" $
        case [ i | i <- completionItems engT, "keep" `T.isPrefixOf` ciLabel i ] of
          (i : _) -> do
            ciLabel i `shouldBe` "keep <count:int> <period:text> snapshots"
            ciDetail i `shouldBe` Just "count: int, period: text"
          _ -> expectationFailure "expected the retention item"

      it "leaves a hole the author already typed out of the detail" $
        case completionItemsAt engT "keep 7 " (T.length "keep 7 ") of
          (i : _) -> do
            ciLabel i `shouldBe` "keep 7 <period:text> snapshots"
            ciDetail i `shouldBe` Just "period: text"
          _ -> expectationFailure "expected the retention item"

    -- The map made visible: lips' whole claim is that a sentence becomes
    -- machinery, and until now an author could only read the machinery in the
    -- compiled module. Hover states it per line, offline, from the same rewrite
    -- step the build runs.
    describe "hover says what a line realizes" $ do
      let engH = EngineData
            { edPatterns =
                [ patOne "p1" [TLit "serve", TLit "http", TLit "on", TLit "port", THole "port"]
                    Fact [SLit "server.port"] [SHole "port"]
                , patOne "p2" [TLit "http", TLit "routes"]
                    Concept [SLit "routes"] [SLit "the http routes"]
                ]
            , edRules =
                [ MapRule "r1" Fact ["server", "port"]
                    [ Emit ["networking", "firewall", "allowedTCPPorts"] (tval "[ <value:int> ]")
                    , Emit ["artifact", "<self>", "fill", "port"] (tval "\"<value>\"") ] ]
            , edDemands = [], edMerges = []
            }
          hoverOn src n = hoverAt engH "hello" (diagnose "f" engH src) n

      it "names the pattern, the decision, and every option the line sets" $
        case hoverOn "serve http on port 8080." 0 of
          Just t -> do
            t `shouldSatisfy` T.isInfixOf "p1"
            t `shouldSatisfy` T.isInfixOf "server.port = 8080"
            t `shouldSatisfy` T.isInfixOf "networking.firewall.allowedTCPPorts = [ 8080 ]"
            -- <self> is the program's own instance, so the path is the real one
            t `shouldSatisfy` T.isInfixOf "artifact.hello.fill.port = \"8080\""
          Nothing -> expectationFailure "expected a hover"

      it "says a decorative line realizes nothing" $
        case hoverOn "http routes:" 0 of
          Just t  -> t `shouldSatisfy` T.isInfixOf "realizes nothing"
          Nothing -> expectationFailure "expected a hover"

      it "says so on a line no pattern reads" $
        case hoverOn "encrypt everything at rest." 0 of
          Just t  -> t `shouldSatisfy` T.isInfixOf "No pattern reads"
          Nothing -> expectationFailure "expected a hover"

      it "gives no hover for a blank or comment line" $ do
        hoverOn "# a note" 0 `shouldBe` Nothing
        hoverOn "" 0 `shouldBe` Nothing

      it "reports the complaint where the value does not fit" $
        case hoverOn "serve http on port eighty." 0 of
          Just t  -> t `shouldSatisfy` T.isInfixOf "not a int"
          Nothing -> expectationFailure "expected a hover"

    -- A word that does not FIT the rule spending it (an int hole fed a word)
    -- fails at refine, far from the line that stated it. The same fill runs here,
    -- one step, so the author is told which line and why while they type.
    describe "a value that does not fit the rule that spends it" $ do
      let engU = EngineData
            { edPatterns = [ patOne "p1" [TLit "serve", TLit "on", TLit "port", THole "port"]
                               Fact [SLit "http.port"] [SHole "port"] ]
            , edRules = [ MapRule "r1" Fact ["http", "port"]
                            [ Emit ["services", "nginx", "listenPort"] (tval "<value:int>") ] ]
            , edDemands = [], edMerges = []
            }

      it "names the line, the rule and the complaint" $
        case diagUnfit (diagnose "f" engU "serve on port eighty") of
          [(n, txt, whys)] -> do
            n `shouldBe` 1
            txt `shouldBe` "serve on port eighty"
            whys `shouldSatisfy` any ("int" `T.isInfixOf`)
          other -> expectationFailure ("unexpected: " ++ show other)

      it "stays silent on a value that fits" $
        diagUnfit (diagnose "f" engU "serve on port 8080") `shouldBe` []

      it "reaches the editor as an error on that line" $
        case [ x | x <- diagsOf (diagnose "f" engU "serve on port eighty")
                 , dgSeverity x == 1 ] of
          (x : _) -> dgLine x `shouldBe` 0
          []      -> expectationFailure "expected an error diagnostic"

    it "derives an error diagnostic on a line that escapes the language" $ do
      let ds = diagsOf (diagnose "f" eng "encrypt everything at rest.")
      case [x | x <- ds, dgSeverity x == 1] of
        (x : _) -> dgLine x `shouldBe` 0   -- 0-based line of the sole (bad) line
        []      -> expectationFailure "expected an error diagnostic"

    it "derives a warning diagnostic for each open question" $ do
      let ds = diagsOf (diagnose "f" eng "the bank drops csv files into inbox/.")
      map dgMessage [x | x <- ds, dgSeverity x == 2]
        `shouldBe` ["Open question: how often does the feed deliver?"]

  -- The whole verdict, purely: what a baked-source language's specification
  -- requires of ONE program. Two directions, because the source is shared by
  -- every program in the language -- a recorded program must still state what
  -- the mint saw, and an UNRECORDED sibling must state nothing the mint never
  -- saw (the escape the gate used to skip silently).
  describe "source-spec verdict (baked source keeps its specification)" $ do
    let concept subj txt = Decision
          { dId        = DecisionId subj
          , dSubject   = Subject [subj]
          , dKind      = Concept
          , dAssertion = Assertion txt
          , dStrength  = Stated
          , dProv      = FromSource (SourceLoc "p.x.lips" 1)
          , dRationale = Nothing
          }
        fact subj txt = (concept subj txt) { dKind = Fact }
        b = fromList

    it "holds when the recorded section is restated verbatim" $
      sourceSpecVerdict (Just (b [concept "io.filter" "keep every field"]))
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.filter" "keep every field"])
        `shouldBe` SpecHolds

    it "reports a deleted recorded concept as retired" $
      sourceSpecVerdict (Just (b [concept "io.filter" "keep every field"]))
                        [b [concept "io.filter" "keep every field"]]
                        (b [fact "cmd.logscan.name" "logscan"])
        `shouldBe` SpecRetired [concept "io.filter" "keep every field"]

    it "reports a reworded concept as retired (text is part of the spec)" $
      sourceSpecVerdict (Just (b [concept "io.filter" "every field equals it"]))
                        [b [concept "io.filter" "every field equals it"]]
                        (b [concept "io.filter" "every field differs from it"])
        `shouldBe` SpecRetired [concept "io.filter" "every field equals it"]

    it "lets an unrecorded sibling restate only recorded concepts" $
      sourceSpecVerdict Nothing
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.filter" "keep every field"])
        `shouldBe` SpecHolds

    it "refuses an unrecorded sibling stating a concept the record never saw" $
      sourceSpecVerdict Nothing
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.sort" "sort the output"])
        `shouldBe` SpecUnrecorded [concept "io.sort" "sort the output"]

  -- Claims: the one gate that observes a running thing. The grammar is closed
  -- (an engine fills it, never extends it) and the PLACE is derived from the
  -- command, so a CLI program never pays for a boot and no new syntax carries
  -- the distinction.
  describe "claims (an observable the author stated)" $ do
    let groundDec subj asrt = Decision
          { dId = DecisionId (T.intercalate "." subj), dSubject = Subject subj
          , dKind = Meta, dAssertion = Assertion asrt, dStrength = Stated
          , dProv = FromSource (SourceLoc "t.x.lips" 1), dRationale = Nothing }
        dec subj asrt = Decision
          { dId = DecisionId "x", dSubject = Subject subj, dKind = Meta
          , dAssertion = Assertion asrt, dStrength = Stated
          , dProv = FromSource (SourceLoc "p.x.lips" 1), dRationale = Nothing }
        pair subj asrt = (Subject subj, dec subj asrt)
        vstr t = case parseValue t of
          Right v -> v
          Left e  -> error (T.unpack e)

    it "reads the closed section set, defaulting exit to 0" $
      claimsFromDecisions
        [ pair ["claim","echo","run"]    "\"${artifact.logscan}/bin/logscan --a 1\""
        , pair ["claim","echo","stdin"]  "\"{\\\"a\\\":1}\""
        , pair ["claim","echo","stdout"] "\"{\\\"a\\\":1}\""
        ]
        `shouldBe` Right
          [ Claim { clId = "echo"
                  , clRun = vstr "\"${artifact.logscan}/bin/logscan --a 1\""
                  , clStdin = Just "{\"a\":1}"
                  , clStdout = Just "{\"a\":1}"
                  , clExit = 0
                  , clPlace = PlaceDerivation } ]

    it "reads a stated exit code" $
      fmap (map clExit) (claimsFromDecisions
        [ pair ["claim","bad","run"]  "\"${artifact.logscan}/bin/logscan --nope\""
        , pair ["claim","bad","exit"] "2" ])
        `shouldBe` Right [2]

    -- A mint's typo must not be dropped in silence: the claim would then pass by
    -- observing less than the author stated.
    it "refuses a section the grammar does not have" $
      claimsFromDecisions [ pair ["claim","echo","stderr"] "\"boom\"" ]
        `shouldBe` Left "claim echo: unknown section(s) stderr; a claim has run, stdin, stdout, exit"

    it "refuses a claim with no command" $
      claimsFromDecisions [ pair ["claim","echo","stdout"] "\"hi\"" ]
        `shouldBe` Left "claim echo: no run, so there is nothing to observe"

    it "refuses a subject that is not claim.<id>.<section>" $
      claimsFromDecisions [ pair ["claim","echo"] "\"hi\"" ]
        `shouldSatisfy` either (T.isInfixOf "a claim is claim.<id>.<section>") (const False)

    it "refuses a stdout no program could print" $
      claimsFromDecisions
        [ pair ["claim","echo","run"]    "\"${artifact.t}/bin/t\""
        , pair ["claim","echo","stdout"] "[ 1 2 ]" ]
        `shouldSatisfy` either (T.isInfixOf "stdout must be plain text") (const False)

    it "places an artifact-only command in the nix sandbox" $
      claimPlace (vstr "\"${artifact.logscan}/bin/logscan --a 1\"") `shouldBe` PlaceDerivation

    it "places anything else in a booted machine" $ do
      claimPlace (vstr "\"systemctl is-active api\"") `shouldBe` PlaceMachine
      claimPlace (vstr "\"${pkgs.curl}/bin/curl -s localhost\"") `shouldBe` PlaceMachine

    it "compares exactly, stripping one trailing newline from the observed bytes" $
      comparisonPy Claim { clId = "echo", clRun = vstr "\"x\"", clStdin = Nothing
                         , clStdout = Just "hi", clExit = 0, clPlace = PlaceDerivation }
        `shouldBe`
          [ "expected_exit = 0"
          , "if out.endswith('\\n'): out = out[:-1]"
          , "if code != expected_exit:"
          , "    raise SystemExit('claim echo: exit was %d, expected %d' % (code, expected_exit))"
          , "expected_out = 'hi'"
          , "if out != expected_out:"
          , "    raise SystemExit('claim echo: stdout was %r, expected %r' % (out, expected_out))"
          ]

    it "checks only the exit status when the author stated no output" $
      comparisonPy Claim { clId = "q", clRun = vstr "\"x\"", clStdin = Nothing
                         , clStdout = Nothing, clExit = 2, clPlace = PlaceDerivation }
        `shouldSatisfy` all (not . T.isInfixOf "expected_out")

    -- A value the author states cannot end the python literal it is rendered
    -- into: the escaping is the kernel's, not something a reader must trust.
    it "escapes a quote in a stated value" $
      comparisonPy Claim { clId = "q", clRun = vstr "\"x\"", clStdin = Nothing
                         , clStdout = Just "it's {\"a\":1}", clExit = 0
                         , clPlace = PlaceDerivation }
        `shouldSatisfy` elem "expected_out = 'it\\'s {\"a\":1}'"

    -- A claim is observed, not assigned: it must reach the realization and NOT
    -- the module, or the module would carry a path no target world declares.
    it "excludes claim decisions from the rendered module" $ do
      let ground = fromList
            [ groundDec ["claim","echo","run"] "\"${artifact.tool}/bin/tool\""
            , groundDec ["artifact","tool","builder"] "\"buildGoModule\""
            , groundDec ["environment","systemPackages"] "[ ${artifact.tool} ]"
            ]
      case realize (const Replace) assembleSubject ground of
        Left e    -> expectationFailure (show e)
        Right txt -> do
          txt `shouldNotSatisfy` T.isInfixOf "claim"
          txt `shouldSatisfy` T.isInfixOf "environment.systemPackages"

    it "projects the claim out of the same ground base" $ do
      let ground = fromList
            [ groundDec ["claim","echo","run"] "\"${artifact.tool}/bin/tool\""
            , groundDec ["claim","echo","stdout"] "\"hi\""
            , groundDec ["artifact","tool","builder"] "\"buildGoModule\""
            ]
      fmap (map clId) (realizeClaims (const Replace) assembleSubject ground)
        `shouldBe` Right ["echo"]

    it "reports a malformed claim as an engine defect, not as an option" $ do
      let ground = fromList [ groundDec ["claim","echo","stdout"] "\"hi\"" ]
      realizeClaims (const Replace) assembleSubject ground
        `shouldBe` Left (RBadClaim "claim echo: no run, so there is nothing to observe")

    -- The option schema never sees kernel vocabulary: no world declares these
    -- paths, so grounding them would refuse every engine that builds or observes.
    it "keeps a claim emit out of option admissibility" $ do
      let rule = MapRule "r1" Fact ["w"]
            [ Emit ["claim","echo","run"] (VStr [PLit "x"]) ]
      checkEmits (Map.fromList [(["services","x","enable"], OTBool)]) [rule] `shouldBe` []

  -- The obligation: where an engine bakes source, the author's words are held to
  -- something observable, or nothing holds them at all.
  describe "the mint prompt states the claim grammar" $ do
    it "names the head and its closed section set" $ do
      let p = systemPromptFor Nixos
      p `shouldSatisfy` T.isInfixOf "claim.<id>.run"
      p `shouldSatisfy` T.isInfixOf "claim.<id>.stdin"
      p `shouldSatisfy` T.isInfixOf "claim.<id>.stdout"
      p `shouldSatisfy` T.isInfixOf "claim.<id>.exit"

    it "forbids inventing a witness and asks for one where source is baked" $ do
      let p = systemPromptFor Nixos
      p `shouldSatisfy` T.isInfixOf "NEVER INVENT A WITNESS"
      p `shouldSatisfy` T.isInfixOf "STATE A CLAIM WHEREVER THE PROGRAM GIVES YOU ONE"

    it "states the exact-comparison rule" $
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "COMPARISON IS EXACT"

    it "states the world limit where there is no machine to boot" $ do
      systemPromptFor Kubenix `shouldSatisfy` T.isInfixOf "no machine to\nboot"
      systemPromptFor Terranix `shouldSatisfy` T.isInfixOf "no machine to\nboot"
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "no machine to\nboot"

    it "offers the booted machine only in the world that has one" $
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "MAY BE OBSERVED IN A BOOTED MACHINE"

  describe "the mint is asked for an observable where it bakes source" $ do
    let src = SourceFile { sfArtifact = "tool", sfPath = "main.go", sfContent = "package main" }
        vstr t = case parseValue t of
          Right v -> v
          Left e  -> error (T.unpack e)
        derivC = Claim "echo" (vstr "\"${artifact.tool}/bin/tool\"") Nothing (Just "hi") 0 PlaceDerivation
        machC  = Claim "alive" (vstr "\"systemctl is-active api\"") Nothing (Just "active") 0 PlaceMachine

    it "warns on baked source with no claim" $
      claimlessBakedSource [src] [] `shouldBe` True

    it "stays quiet on baked source with one claim" $
      claimlessBakedSource [src] [derivC] `shouldBe` False

    it "leaves a pure-configuration mint unaffected" $
      claimlessBakedSource [] [] `shouldBe` False

    it "refuses a machine claim in a world with no machine to boot" $ do
      unplaceableClaims Kubenix [machC] `shouldBe` ["alive"]
      unplaceableClaims Terranix [machC] `shouldBe` ["alive"]
      unplaceableClaims HomeManager [machC] `shouldBe` ["alive"]

    it "admits an artifact-only claim in every world" $ do
      unplaceableClaims Kubenix [derivC] `shouldBe` []
      unplaceableClaims Terranix [derivC] `shouldBe` []

    it "admits a machine claim where there IS a machine" $
      unplaceableClaims Nixos [machC] `shouldBe` []

  describe "the claims rung" $ do
    it "exposes one aggregate that runs every experiment" $ do
      let txt = flakeText Nixos True True
      txt `shouldSatisfy` T.isInfixOf "claims = (pkgsFor system).linkFarmFromDrvs \"claims\""
      txt `shouldSatisfy` T.isInfixOf "import ./claims.nix { pkgs = pkgsFor system; }"

    it "leaves a claim-free flake free of claim vocabulary" $
      flakeText Nixos True False `shouldNotSatisfy` T.isInfixOf "claims"

    -- A sandbox claim needs no machine, so the rung is world-neutral.
    it "offers the rung in a world with no machine to boot" $
      flakeText Kubenix False True `shouldSatisfy` T.isInfixOf "claims"

    it "prints the build command only when the program states claims" $ do
      runCommands Nixos [] True "/tmp/out" `shouldSatisfy` any (T.isInfixOf "#claims")
      runCommands Nixos [] False "/tmp/out" `shouldNotSatisfy` any (T.isInfixOf "#claims")

  describe "claims.nix (the experiments, as nix)" $ do
    let vstr t = case parseValue t of
          Right v -> v
          Left e  -> error (T.unpack e)
        derivClaim = Claim { clId = "echo"
                           , clRun = vstr "\"${artifact.tool}/bin/tool --a 1\""
                           , clStdin = Just "{\"a\":1}", clStdout = Just "{\"a\":1}"
                           , clExit = 0, clPlace = PlaceDerivation }
        machineClaim = Claim { clId = "alive", clRun = vstr "\"systemctl is-active api\""
                             , clStdin = Nothing, clStdout = Just "active"
                             , clExit = 0, clPlace = PlaceMachine }

    it "writes nothing for a program that states no claims" $
      claimsFile True [] `shouldBe` Nothing

    it "renders a sandbox claim as a derivation that runs the command" $ do
      let txt = maybe "" id (claimsFile True [derivClaim])
      txt `shouldSatisfy` T.isInfixOf "artifact = import ./artifact.nix { inherit pkgs; };"
      txt `shouldSatisfy` T.isInfixOf "\"echo\" = pkgs.runCommand \"claim-echo\""
      -- the artifact reference stays a LIVE nix interpolation
      txt `shouldSatisfy` T.isInfixOf "command = \"${artifact.tool}/bin/tool --a 1\";"
      txt `shouldSatisfy` T.isInfixOf "out = out[:-1]"
      -- the python escape is itself nix-escaped, so nix hands python a
      -- backslash-n rather than a real newline inside the literal
      txt `shouldSatisfy` T.isInfixOf "endswith('\\\\n')"
      txt `shouldNotSatisfy` T.isInfixOf "nixosTest"

    it "renders a machine claim as a nixosTest importing the module" $ do
      let txt = maybe "" id (claimsFile False [machineClaim])
      txt `shouldSatisfy` T.isInfixOf "pkgs.testers.nixosTest"
      txt `shouldSatisfy` T.isInfixOf "imports = [ ./default.nix ];"
      txt `shouldSatisfy` T.isInfixOf "machine.execute(cmd)"
      -- an artifact-free program must not import an artifact.nix nobody wrote
      txt `shouldNotSatisfy` T.isInfixOf "artifact.nix"

    -- A stated byte must never be read as nix: the one live interpolation in a
    -- rendered claim is the command's own artifact reference.
    it "escapes an interpolation a program states" $ do
      let sneaky = derivClaim { clStdout = Just "${pkgs.hello}" }
          txt    = maybe "" id (claimsFile True [sneaky])
      txt `shouldSatisfy` T.isInfixOf "\\${pkgs.hello}"

    it "is deterministic in claim order" $
      claimsFile True [machineClaim, derivClaim] `shouldBe` claimsFile True [derivClaim, machineClaim]

    -- A claim id comes from the engine, so it can be anything a subject segment
    -- can be -- including a number, which is not a nix identifier. Rendered
    -- bare it is a syntax error the author cannot act on, three layers down in
    -- a nix trace (observed: a minted engine keyed its claims by <n:index>).
    it "quotes a claim id, which need not be a nix identifier" $ do
      let numeric = derivClaim { clId = "1" }
          txt     = maybe "" id (claimsFile True [numeric])
      txt `shouldSatisfy` T.isInfixOf "\"1\" = pkgs.runCommand"
      let machineNumeric = machineClaim { clId = "2" }
          txt2           = maybe "" id (claimsFile False [machineNumeric])
      txt2 `shouldSatisfy` T.isInfixOf "\"2\" = pkgs.testers.nixosTest"

  -- The advisory half of the obligation: where behaviour lives in minted source
  -- and the program states no observable, say so in the editor. A warning, never
  -- an error: the remedy is an author writing an example.
  describe "the lsp says when a sentence is observed by nothing" $ do
    let engC = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "keep", TLit "every", TLit "field"]
                  Concept [SLit "io.filter"] [SLit "keep every field"]
              , patOne "p2" [TLit "install", TLit "it", TLit "as", THole "name"]
                  Fact [SLit "cmd", SHole "name"] [SHole "name"]
              ]
          , edRules = []
          , edDemands = []
          , edMerges = []
          }
        prog = "keep every field\ninstall it as tool"
        d = diagnose "f" engC prog

    it "warns on a concept-only line where the language bakes source and states no claim" $ do
      let ds = unobservedDiags True False d
      map dgLine ds `shouldBe` [0]
      map dgSeverity ds `shouldBe` [2]
      map dgMessage ds `shouldSatisfy` all (T.isInfixOf "Nothing observes this sentence")

    it "stays silent once the program states a claim" $
      unobservedDiags True True d `shouldBe` []

    it "stays silent for a language that bakes no source" $
      unobservedDiags False False d `shouldBe` []

    it "never warns about a line that realizes something" $
      map dgLine (unobservedDiags True False d) `shouldNotContain` [1]

  describe "lsp uri decoding (file:// scheme, percent-escapes)" $ do
    it "strips the file:// scheme" $
      uriToPath "file:///home/u/my.loose" `shouldBe` "/home/u/my.loose"
    it "percent-decodes a space" $
      uriToPath "file:///home/u/my%20file.loose" `shouldBe` "/home/u/my file.loose"
    it "percent-decodes a multi-byte UTF-8 sequence" $
      uriToPath "file:///home/u/caf%C3%A9.loose" `shouldBe` "/home/u/caf\233.loose"
    it "leaves a plain path untouched" $
      uriToPath "/home/u/my.loose" `shouldBe` "/home/u/my.loose"

  -- Laws over arbitrary bases, not just the two worked examples: the merge is
  -- the kernel's core physics, so it is pinned as algebraic properties.
  describe "merge algebra (laws over arbitrary bases, spec 2.1)" $ do
    it "union is idempotent: union b b == b" $
      property $ \ds -> let b = fromList ds in union b b === b

    it "union is associative" $
      property $ \xs ys zs ->
        let a = fromList xs; b = fromList ys; c = fromList zs
         in union a (union b c) === union (union a b) c

    it "union is right-biased on id clashes (solution laid over defaults wins)" $ do
      let def = mk "d" "x" "old" Default
          sol = mk "d" "x" "new" Stated
      toList (union (fromList [def]) (fromList [sol])) `shouldBe` [sol]

    it "every resolved winner has the maximum strength among its subject's decisions" $
      property $ \ds ->
        case resolveReplace (fromList ds) of
          Left _        -> property True  -- the law constrains winners, not conflicts
          Right winners ->
            let bds = toList (fromList ds)
             in conjoin
                  [ dStrength w === maximum [ dStrength d | d <- bds, dSubject d == s ]
                  | (s, w) <- Map.toList winners ]

    it "resolve never invents or drops a subject" $
      property $ \ds ->
        case resolveReplace (fromList ds) of
          Left _        -> property True
          Right winners ->
            let subjects = Map.keys (Map.fromList [ (dSubject d, ()) | d <- toList (fromList ds) ])
             in Map.keys winners === subjects

  -- Orthogonality (at most one rule fires per decision) makes rewriting a
  -- function, hence confluent: the ground result cannot depend on rule order.
  describe "refinement confluence (rule order independence, spec 4)" $ do
    let rA = MapRule "rA" Fact   ["a"] [ Emit ["x"] (VBool True) ]
        rB = MapRule "rB" Oblige ["b"] [ Emit ["y"] (VStr [PHole "value"]) ]
        rC = MapRule "rC" Fact   ["c"] [ Emit ["z"] (VInt 1) ]
        rules = map toRule [rA, rB, rC]
        base  = fromList
          [ (mk "a" "a" ""   Stated) { dKind = Fact }
          , (mk "b" "b" "vv" Stated) { dKind = Oblige }
          , (mk "c" "c" ""   Stated) { dKind = Fact }
          ]

    it "the ground result is independent of rule order" $
      property $ forAll (shuffle [0 .. length rules - 1]) $ \perm ->
        refine 1000 (map (rules !!) perm) base === refine 1000 rules base

    it "a decision no rule matches is ground; an emitted Meta decision is a fixpoint" $ do
      isGround rules (mk "z" "unmatched" "" Stated)              `shouldBe` True
      isGround rules ((mk "m" "a" "" Stated) { dKind = Meta })    `shouldBe` True

  -- Static orthogonality: two rule left-hand sides that COULD claim one subject
  -- are a defect even when no program witnesses it (survey F, seam 1). The
  -- refiner's dynamic 'Overlap' only fires when some decision hits both.
  describe "rule overlap (critical pairs over rule left-hand sides, spec 4)" $ do
    let emit = [ Emit ["x"] (VBool True) ]
        rule i k s = MapRule i k s emit

    -- The yes/no half of the same unification, shared with the dropped-value
    -- check so one implementation answers both questions.
    it "unifies a capture with a literal at the same position" $ do
      subjectsUnify ["tool", "<lang>"] ["tool", "go"] `shouldBe` True
      subjectsUnify ["tool", "<lang>"] ["tool", "language"] `shouldBe` True

    it "does not unify different literals or different lengths" $ do
      subjectsUnify ["tool", "go"] ["tool", "rust"] `shouldBe` False
      subjectsUnify ["tool"] ["tool", "<lang>"] `shouldBe` False

    it "keeps a repeated capture constraining" $ do
      subjectsUnify ["x", "<a>", "<a>"] ["x", "p", "q"] `shouldBe` False
      subjectsUnify ["x", "<a>", "<a>"] ["x", "p", "p"] `shouldBe` True

    it "two rules with the same kind and subject overlap" $
      ruleOverlaps [rule "r1" Fact ["a", "b"], rule "r2" Fact ["a", "b"]]
        `shouldBe` [RuleOverlap "r1" "r2" ["a", "b"]]

    it "a capture overlaps a literal at the same position, witnessed by the literal" $
      ruleOverlaps [rule "r1" Fact ["route", "<path>", "status"]
                   , rule "r2" Fact ["route", "home", "status"]]
        `shouldBe` [RuleOverlap "r1" "r2" ["route", "home", "status"]]

    it "two captures overlap, witnessed by the still-open family" $
      ruleOverlaps [rule "r1" Fact ["route", "<path>"], rule "r2" Fact ["route", "<key>"]]
        `shouldBe` [RuleOverlap "r1" "r2" ["route", "<path>"]]

    it "different kinds never overlap (the refiner matches kind first)" $
      ruleOverlaps [rule "r1" Fact ["a"], rule "r2" Oblige ["a"]] `shouldBe` []

    it "different lengths never overlap (a subject match is length-exact)" $
      ruleOverlaps [rule "r1" Fact ["a"], rule "r2" Fact ["a", "b"]] `shouldBe` []

    it "distinct literals at one position separate the rules" $
      ruleOverlaps [rule "r1" Fact ["a", "p"], rule "r2" Fact ["a", "q"]] `shouldBe` []

    -- A repeated capture constrains: <a>.<a> matches only equal segments, so
    -- pairing it with p.q is NOT an overlap. Reporting one would reject a
    -- legitimate engine, so the check unifies rather than compares positionwise.
    it "a repeated capture does not overlap a pair of distinct literals" $
      ruleOverlaps [rule "r1" Fact ["x", "<a>", "<a>"], rule "r2" Fact ["x", "p", "q"]]
        `shouldBe` []

    it "a repeated capture does overlap equal literals" $
      ruleOverlaps [rule "r1" Fact ["x", "<a>", "<a>"], rule "r2" Fact ["x", "p", "p"]]
        `shouldBe` [RuleOverlap "r1" "r2" ["x", "p", "p"]]

    it "a rule never overlaps itself, and each pair is reported once" $
      ruleOverlaps [rule "r1" Fact ["a"], rule "r2" Fact ["a"], rule "r3" Fact ["a"]]
        `shouldBe` [ RuleOverlap "r1" "r2" ["a"]
                   , RuleOverlap "r1" "r3" ["a"]
                   , RuleOverlap "r2" "r3" ["a"]
                   ]

    -- The point of a STATIC check: this pair is invisible to the refiner until
    -- a program happens to state a route, and then it fails at compile time on
    -- the author's machine instead of at mint time on the engine.
    it "catches an overlap no decision in the base witnesses" $ do
      let r1 = rule "r1" Fact ["route", "<path>", "status"]
          r2 = rule "r2" Fact ["route", "<name>", "status"]
      refine 100 (map toRule [r1, r2]) (fromList [mk "d1" "unrelated" "" Stated])
        `shouldBe` Right (fromList [mk "d1" "unrelated" "" Stated])
      map roLeft (ruleOverlaps [r1, r2]) `shouldBe` ["r1"]

  describe "set or list: how a list option aggregates repeats" $ do
    let contrib i line v = Decision (DecisionId i) (Subject ["environment","systemPackages"])
                             Meta (Assertion v) Stated (FromSource (SourceLoc "f" line)) Nothing
        elemsOf d = case parseValue (unAssertion' (dAssertion d)) of
          Right (VList vs) -> map renderValue vs
          other            -> [T.pack (show other)]
        unAssertion' (Assertion a) = a
    it "a set (the default) collapses an element two lines both state" $
      fmap elemsOf (assembleSubject [ contrib "d1" 1 "[ \"app\" ]", contrib "d2" 2 "[ \"app\" ]" ])
        `shouldBe` Right ["\"app\""]
    it "a list keeps every contribution, in source order" $
      fmap elemsOf (assembleWith (const True)
                      [ contrib "d1" 1 "[ \"app\" ]", contrib "d2" 2 "[ \"app\" ]" ])
        `shouldBe` Right ["\"app\"", "\"app\""]
    it "a set keeps distinct elements, in source order" $
      fmap elemsOf (assembleSubject [ contrib "d2" 2 "[ \"b\" ]", contrib "d1" 1 "[ \"a\" ]" ])
        `shouldBe` Right ["\"a\"", "\"b\""]
    -- Which reading an option takes is knowledge about that option, so it is
    -- engine data, capture-aware like every other option path.
    it "an engine declaration names the option, matching a value-keyed family" $ do
      let specs = [ MergeSpec "m1" ["services","x","<name>","args"] True ]
      keepsRepeats specs ["services","x","web","args"] `shouldBe` True
      keepsRepeats specs ["services","x","web","other"] `shouldBe` False
      keepsRepeats [] ["services","x","web","args"] `shouldBe` False
    it "round-trips a merge declaration through the .lang body grammar" $ do
      let m = MergeSpec "m1" ["environment","systemPackages"] True
      parseMergeBody "m1" (renderMergeBody m) `shouldBe` Right m
      parseMergeBody "m2" "merge environment.systemPackages set"
        `shouldBe` Right (MergeSpec "m2" ["environment","systemPackages"] False)
    it "refuses a mode that is neither set nor list (never guesses one)" $
      parseMergeBody "m1" "merge environment.systemPackages unique" `shouldSatisfy` isLeft

  describe "static pattern overlap (the pattern-layer sibling of rule overlap)" $ do
    let pat i toks = patOne i toks Fact [SLit "s"] [SLit "a"]
        ids os = [ (poLeft o, poRight o) | o <- os ]
    it "two identical templates overlap, witnessed by the line they both read" $
      patternOverlaps [pat "p1" [TLit "back", TLit "up"], pat "p2" [TLit "back", TLit "up"]]
        `shouldBe` [PatternOverlap "p1" "p2" ["back", "up"]]
    it "a hole overlaps a literal at the same position, witnessed by the literal" $
      patternOverlaps [pat "p1" [TLit "run", THole "when"], pat "p2" [TLit "run", TLit "daily"]]
        `shouldBe` [PatternOverlap "p1" "p2" ["run", "daily"]]
    it "different literals separate two templates" $
      patternOverlaps [pat "p1" [TLit "back", TLit "up"], pat "p2" [TLit "back", TLit "down"]]
        `shouldBe` []
    it "different lengths separate two hole-free templates" $
      patternOverlaps [pat "p1" [TLit "run", THole "a"], pat "p2" [TLit "run", THole "a2", THole "b"]]
        `shouldBe` []
    -- The form that makes the check worth having: a multi-token hole reads lines
    -- of every length, so it overlaps almost anything starting the same way.
    it "a multi-token hole overlaps a longer template with the same prefix" $
      ids (patternOverlaps [ pat "p1" [TLit "install", TMulti "pkgs"]
                           , pat "p2" [TLit "install", THole "pkg", TLit "on", THole "host"] ])
        `shouldBe` [("p1", "p2")]
    it "a multi-token hole still needs the literals to line up" $
      patternOverlaps [ pat "p1" [TLit "install", TMulti "pkgs", TLit "on", THole "host"]
                      , pat "p2" [TLit "install", THole "pkg", TLit "from", THole "repo"] ]
        `shouldBe` []
    it "reports each pair once and never a pattern against itself" $
      ids (patternOverlaps [pat "p1" [THole "a"], pat "p2" [THole "b"], pat "p3" [THole "c"]])
        `shouldBe` [("p1","p2"), ("p1","p3"), ("p2","p3")]
    -- A repeated hole constrains the two positions to one word, which the
    -- product walk does not track, so such a pattern is skipped rather than
    -- reported: a false rejection would refuse a sound engine.
    it "skips a template that repeats a hole name instead of guessing" $
      patternOverlaps [pat "p1" [THole "a", THole "a"], pat "p2" [TLit "p", TLit "q"]]
        `shouldBe` []
    it "two fused templates overlap only when a token could satisfy both" $ do
      let fused i lit = case parsePatternBody i (lit <> "(<x>) => fact s \"<x>\"") of
            Right ok -> ok
            Left e   -> error (T.unpack e)
      ids (patternOverlaps [fused "p1" "println", fused "p2" "println"])
        `shouldBe` [("p1", "p2")]
      patternOverlaps [fused "p1" "println", fused "p2" "eprintln"] `shouldBe` []
    it "a whole-token hole overlaps a fused template" $ do
      let fused = case parsePatternBody "p2" "println(<x>) => fact s \"<x>\"" of
            Right ok -> ok
            Left e   -> error (T.unpack e)
      ids (patternOverlaps [pat "p1" [THole "a"], fused]) `shouldBe` [("p1", "p2")]
    it "catches an overlap no program line in the corpus witnesses" $ do
      -- crystallize reports Overlapping only for a line that hits both; a corpus
      -- of one line that hits neither leaves the defect inside the engine.
      let p1 = pat "p1" [TLit "keep", THole "n", TLit "days"]
          p2 = pat "p2" [TLit "keep", TMulti "rest"]
      crystallize "f" [p1, p2] "keep 7 days\n" `shouldSatisfy` isLeft
      ids (patternOverlaps [p1, p2]) `shouldBe` [("p1","p2")]

  -- A word the language BINDS and then discards makes a program line look
  -- load-bearing while changing nothing (the http engine reads "go" into a
  -- steer and emits the literal buildGoModule, so it works only because nobody
  -- edits that word). Static, domain-blind, checked at the mint gate.
  describe "dropped program values (does every word the language reads reach output)" $ do
    let pat body = case parsePatternBody "p1" body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test pattern: " <> e))
        rul i body = case parseRuleBody i body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test rule: " <> e))

    -- The committed examples/http defect, verbatim in shape.
    let langPat = pat "write the server in <lang> using only the standard library \
                      \=> steer server.language \"<lang>\""
        constRule = rul "r3" "match steer server.language => artifact.helloserver.builder \"\\\"buildGoModule\\\"\""

    it "reports a captured word a matching rule replaces with a constant" $
      droppedValues [langPat] [constRule]
        `shouldBe` [DroppedValue "p1" "lang" (IgnoredBy ["server", "language"] ["r3"])]

    it "accepts the same rule once its rhs reads the value" $
      droppedValues [langPat]
        [ rul "r3" "match steer server.language => artifact.helloserver.builder \"\\\"build<value>Module\\\"\"" ]
        `shouldBe` []

    it "accepts a presence match: a pattern with no hole drops nothing" $
      droppedValues [pat "run a postgresql database server => fact postgres.enable \"true\""]
        [ rul "r1" "match fact postgres.enable => services.postgresql.enable true" ]
        `shouldBe` []

    it "accepts indexed value holes as reading the value" $
      droppedValues [pat "keep <count> <period> snapshots => fact backup.retention \"<count> <period>\""]
        [ rul "r4" "match fact backup.retention => services.restic.backups.<self>.pruneOpts \"[ \\\"--keep-<value.2> <value.1>\\\" ]\"" ]
        `shouldBe` []

    -- The greet engine: <name> reaches output through the emit PATH, <msg>
    -- through the value. Neither is dropped, and this is the shape most CLI
    -- engines take, so a false rejection here would be expensive.
    let greetPat = pat "install a command <name> that prints <msg> => fact cmd.<name>.msg \"<msg>\""

    it "accepts a subject capture the rule carries into an emit path" $
      droppedValues [greetPat]
        [ rul "r1" "match fact cmd.<name>.msg => artifact.<name>.args.text \"\\\"echo <value>\\\"\"" ]
        `shouldBe` []

    it "reports a subject capture no emit path or value mentions" $
      droppedValues [greetPat]
        [ rul "r1" "match fact cmd.<name>.msg => environment.etc.greet.text \"\\\"<value>\\\"\"" ]
        `shouldBe` [DroppedValue "p1" "name" (IgnoredBy ["cmd", "<name>", "msg"] ["r1"])]

    it "accepts a literal rule segment: the word selects the rule" $
      droppedValues [pat "write it in <lang> => fact tool.<lang> \"<lang>\""]
        [ rul "r1" "match fact tool.go => artifact.<self>.builder \"\\\"buildGoModule\\\"\"" ]
        `shouldBe` []

    it "reports a hole no emit mentions at all" $
      droppedValues [pat "write the tool in <lang> with no dependencies => fact tool.built \"true\""]
        [ rul "r1" "match fact tool.built => artifact.<self>.args.vendorHash null" ]
        `shouldBe` [DroppedValue "p1" "lang" EmittedNowhere]

    it "leaves a decorative hole to the inert-line report" $
      droppedValues [pat "show a kanban board in <place> => concept tool.intro \"<place>\""] []
        `shouldBe` []

    it "stays silent when no rule matches the decision at all" $
      droppedValues [langPat] [] `shouldBe` []

    it "names the defect in the words the rule author needs" $
      map renderDroppedValue (droppedValues [langPat] [constRule])
        `shouldBe`
          [ "pattern p1 binds <lang>, which reaches server.language, and rule r3 \
            \emits it nowhere: editing that word changes no output" ]

  -- A demand is judged against the crystallized base, so only a subject the
  -- language's own patterns emit can ever answer one. A demand outside every
  -- emitted family blocks every program in the language -- and reports it as the
  -- author's missing fact, which is why it is caught at the mint gate.
  describe "word types (what type does the engine give a word it reads)" $ do
    let pat i body = case parsePatternBody i body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test pattern: " <> e))
        rul i body = case parseRuleBody i body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test rule: " <> e))
        types ps rs = Map.toList (wordTypes ps rs (case ps of (q : _) -> q; [] -> error "no pattern"))

    it "types a word by the option value it lands in" $
      types [pat "p1" "serve http on port <port> => fact http.port \"<port>\""]
            [rul "r1" "match fact http.port => services.nginx.listenPort \"<value:int>\""]
        `shouldBe` [("port", WInt)]

    it "types a word landing in a string as text" $
      types [pat "p1" "alerts go to <dest> => fact alert.target \"<dest>\""]
            [rul "r1" "match fact alert.target => systemd.services.a.environment.T \"\\\"<value>\\\"\""]
        `shouldBe` [("dest", WText)]

    it "reads the part index of a several-part value" $
      types [pat "p1" "keep <count> <period> snapshots => fact backup.retention \"<count> <period>\""]
            [rul "r1" "match fact backup.retention => services.restic.backups.<self>.pruneOpts \"[ \\\"--keep-<value.2>\\\" <value.1:int> ]\""]
        `shouldBe` [("count", WInt), ("period", WText)]

    it "types a package word by the pkg hole that spends it" $
      types [pat "p1" "- <name> => fact pkg.<name> \"<name>\""]
            [rul "r1" "match fact pkg.<name> => environment.systemPackages \"[ <value:pkg> ]\""]
        `shouldBe` [("name", WPkg)]

    it "types a word the rule carries as an artifact name" $
      types [pat "p1" "install a command <cmd> that prints <msg> => fact cmd.<cmd>.msg \"<msg>\""]
            [rul "r1" "match fact cmd.<cmd>.msg => artifact.<cmd>.args.text \"\\\"echo <value>\\\"\""]
        `shouldBe` [("cmd", WName), ("msg", WText)]

    it "names the rule's own capture, not the pattern's" $
      types [pat "p1" "install a command <cmd> => fact cmd.<cmd>.msg \"hi\""]
            [rul "r1" "match fact cmd.<who>.msg => environment.etc.greet.text \"\\\"<who>\\\"\""]
        `shouldBe` [("cmd", WText)]

    it "types every token of a tail hole by its element type" $
      types [pat "p1" "install <pkgs.words> => fact install.list \"<pkgs>\""]
            [rul "r1" "match fact install.list => environment.systemPackages \"<value.tail:pkg>\""]
        `shouldBe` [("pkgs", WPkg)]

    -- A string position takes any text, so it does not contradict a coercion:
    -- the word must satisfy the narrower one. This is the committed http engine's
    -- shape, where the port is both written into Go source and opened in the
    -- firewall, and "text" there would be the less useful half of the truth.
    it "takes the narrower of a string and a typed position" $
      types [pat "p1" "serve on port <port> => fact http.port \"<port>\""]
            [rul "r1" "match fact http.port => artifact.s.fill.port \"\\\"<value>\\\"\" ; networking.firewall.allowedTCPPorts \"[ <value:int> ]\""]
        `shouldBe` [("port", WInt)]

    it "says nothing where two rules coerce the word differently" $
      types [pat "p1" "port <port> => fact a.port \"<port>\" ; fact b.port \"<port>\""]
            [ rul "r1" "match fact a.port => services.x.port \"<value:int>\""
            , rul "r2" "match fact b.port => services.y.debug \"<value:bool>\"" ]
        `shouldBe` []

    it "says nothing about a word no rule spends" $
      types [pat "p1" "write it in <lang> => steer server.language \"<lang>\""]
            [rul "r1" "match steer server.language => artifact.s.builder \"\\\"buildGoModule\\\"\""]
        `shouldBe` []

  describe "unanswerable demands (can a program ever meet it)" $ do
    let pat body = case parsePatternBody "p1" body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test pattern: " <> e))
        dem i subj = DemandSpec i subj "q?"
        namePat = pat "install the tool as the command <name> \
                      \=> fact command.<name> \"<name>\""

    -- The examples/habit mint (2026-07-29), verbatim in shape: two mints in a
    -- row demanded `command` beside a pattern emitting `command.<name>`, and
    -- generate reported the program as silent about a fact it states.
    it "reports a demand one segment short of the family its pattern emits" $
      unanswerableDemands [namePat] [dem "q3" ["command"]]
        `shouldBe` [UnanswerableDemand "q3" ["command"] [["command", "<name>"]]]

    it "accepts a demand naming the capture, since a program line fills it" $
      unanswerableDemands [namePat] [dem "q3" ["command", "<name>"]] `shouldBe` []

    it "accepts a demand on a plain subject a pattern emits" $
      unanswerableDemands
        [pat "the habit log is stored in <path> => fact habit.logpath \"<path>\""]
        [dem "q1" ["habit", "logpath"]] `shouldBe` []

    it "reports every demand of a language with no patterns at all" $
      map renderUnanswerableDemand (unanswerableDemands [] [dem "q1" ["habit", "logpath"]])
        `shouldBe` ["demand q1 asks for habit.logpath, which no pattern emits \
                    \(this language emits no subject at all)"]

    it "names the defect in the words the mint needs" $
      map renderUnanswerableDemand (unanswerableDemands [namePat] [dem "q3" ["command"]])
        `shouldBe` ["demand q3 asks for command, which no pattern emits; the \
                    \patterns emit command.<name>"]

  -- The value language's two guarantees, as properties over generated inputs:
  -- canonical round-trip, and injection made unrepresentable.
  -- A rhs either reads the matched decision's assertion or it does not; the
  -- dropped-value check ('Engine.Reach') turns that answer into a gate, so it
  -- is pinned here on its own.
  describe "valueUsesAssertion (does a rhs read the matched decision's value)" $ do
    let v t = case parseValue t of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test value: " <> e))

    it "sees <value> in a string" $
      valueUsesAssertion (v "\"echo <value>\"") `shouldBe` True

    it "sees an indexed <value.N>" $
      valueUsesAssertion (v "\"[ \\\"--keep-<value.2> <value.1>\\\" ]\"") `shouldBe` True

    it "sees a hole nested in a list" $
      valueUsesAssertion (v "[ \"<value>\" ]") `shouldBe` True

    it "does not see a constant" $
      valueUsesAssertion (v "\"buildGoModule\"") `shouldBe` False

    it "does not count a subject capture as reading the value" $
      valueUsesAssertion (v "\"<name>\"") `shouldBe` False

  describe "valueHoleTypes (what type does the rhs give the word it spends)" $ do
    let v t = case parseValue t of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test value: " <> e))
        types = Map.toList . valueHoleTypes

    it "types a hole inside a string as text" $
      types (v "\"echo <value>\"") `shouldBe` [("value", WText)]

    it "reads the type off a bare typed hole" $ do
      types (v "<value:int>") `shouldBe` [("value", WInt)]
      types (v "<value:bool>") `shouldBe` [("value", WBool)]
      types (v "<value:float>") `shouldBe` [("value", WFloat)]
      types (v "<value:pkg>") `shouldBe` [("value", WPkg)]

    it "types each part of a several-part value on its own" $
      types (v "\"<value.1>:<value.2>\"") `shouldBe` [("value.1", WText), ("value.2", WText)]

    it "gives a tail hole the type its elements coerce to" $ do
      types (v "<value.tail:pkg>") `shouldBe` [("value.tail", WPkg)]
      types (v "<value.tail>") `shouldBe` [("value.tail", WText)]

    it "types a capture the rhs names as a name, not a value" $
      types (v "[ ${artifact.<cmd>} ]") `shouldBe` [("cmd", WName)]

    -- A clause spends words too, so an editor must label them the same way. A
    -- typed hole in a clause fixes the type; a hole inside a Scheme string is
    -- text, exactly as inside a Nix string.
    it "reads the type off a typed hole inside a clause" $
      types (v "(define (limit) #<value:int>)") `shouldBe` [("value", WInt)]

    it "types a hole inside a clause's string as text" $
      types (v "(define (greet) \"hello #<who>\")") `shouldBe` [("who", WText)]

    it "reaches a hole nested in a list or an attrset" $ do
      types (v "[ <value:int> ]") `shouldBe` [("value", WInt)]
      types (v "{ port = <value:int>; }") `shouldBe` [("value", WInt)]

    it "says nothing about a constant rhs" $
      types (v "\"buildGoModule\"") `shouldBe` []

    it "keeps a path literal's capture a name" $
      types (v "./artifacts/<name>") `shouldBe` [("name", WName)]

  describe "value language (round-trip and injection safety, spec: closed rhs)" $ do
    it "parseValue . renderValue == id for canonical values" $
      property $ forAll genValue $ \v -> parseValue (renderValue v) === Right v

    -- Whatever a program value contains (quotes, backslashes, ${...}), filling
    -- a hole with it yields ONE inert literal: it cannot add structure, close
    -- the string, or open an interpolation. This is the Nix-injection guard.
    it "any filled program text collapses to a single inert literal" $
      property $ forAll fillText $ \t ->
        (fillValue (const (Right t)) (VStr [PHole "value"]) >>= parseValue)
          === Right (VStr [PLit t])

    it "a bare identifier rhs is rejected (only closed value forms parse)" $
      property $ forAll bareWord $ \w -> parseValue w `shouldSatisfy` isLeft

    -- Regression: a minted rule wrote a shell script's newline as the Nix
    -- textual escape \n (the two chars backslash, n). The old backslash
    -- handling in 'pString' treated ANY \<char> as "drop the backslash, keep
    -- the char", so \n became a bare, meaningless "n" -- a real
    -- writeShellApplication .text minted this way realized to a one-line
    -- script with the newline silently deleted ("...bashncurl..."). \n\/\t\/\r
    -- must instead store the actual control char and round-trip back through
    -- 'renderValue' as the same textual escape.
    it "backslash-n/t/r inside a string round-trip as real control chars, not a bare letter" $ do
      parseValue "\"a\\nb\"" `shouldBe` Right (VStr [PLit "a\nb"])
      parseValue "\"a\\tb\"" `shouldBe` Right (VStr [PLit "a\tb"])
      parseValue "\"a\\rb\"" `shouldBe` Right (VStr [PLit "a\rb"])
      renderValue (VStr [PLit "a\nb"]) `shouldBe` "\"a\\nb\""
      -- The exact failing shape: a shebang line then a command, one script.
      parseValue "\"#!/usr/bin/env bash\\ncurl -s wttr.in\\n\""
        `shouldBe` Right (VStr [PLit "#!/usr/bin/env bash\ncurl -s wttr.in\n"])

    -- Grammar completeness: inside a string the value is text, so a redundant
    -- :type on a hole is meaningless and degrades to the plain hole rather
    -- than being rejected (a form the mint writes naturally for a number).
    it "a typed hole inside a string degrades to its plain form" $ do
      parseValue "\"--keep-daily <value.2:int>\"" `shouldBe` parseValue "\"--keep-daily <value.2>\""
      parseValue "\"x <value:int> y\"" `shouldBe` parseValue "\"x <value> y\""
    -- 'parseValue' alone cannot judge a hole name: <cmd> is a legal capture
    -- when the rule's subject binds it, and parseValue never sees a subject.
    -- So an identifier hole parses here and 'parseRuleBody' rejects the unbound
    -- ones, where the subject is in hand (see the rule-parser tests above).
    it "an identifier hole parses as a capture; the rule parser judges it" $
      parseValue "\"x <bogus> y\"" `shouldBe` Right (VStr [PLit "x ", PHole "bogus", PLit " y"])
    it "a hole name that is not an identifier is still rejected" $
      parseValue "\"x <not a name> y\"" `shouldSatisfy` isLeft
    -- Capability C: a <value.tail> rhs fills to a VList of the program value's
    -- tokens (trailing sentence punctuation stripped). The whole rhs becomes
    -- one list, so a single line carrying many items is aggregatable with B.
    it "a <value.tail> rhs parses and renders canonically" $ do
      parseValue "<value.tail>" `shouldBe` Right (VTail Nothing "value")
      renderValue (VTail Nothing "value") `shouldBe` "<value.tail>"
    it "fillValue on a tail hole splits the program value into a VList of tokens" $
      fillValue (const (Right "htop, ripgrep, tmux.")) (VTail Nothing "value")
        `shouldBe` Right "[ \"htop\" \"ripgrep\" \"tmux\" ]"
    it "an empty program value for a tail hole fails loud" $
      fillValue (const (Right "")) (VTail Nothing "value") `shouldSatisfy` isLeft

    -- A package-derivation hole: a program token naming a package becomes a
    -- pkgs.<token> derivation, not a string. This is the bridge the value
    -- grammar was missing (a program-name token -> a derivation ref), so a
    -- line of package names realizes to a list of derivations for an option
    -- like environment.systemPackages. Injection-safe: each segment is gated
    -- by okSeg, so program text can never alter the pkgs path.
    it "a <value:pkg> hole parses, renders canonically, and round-trips" $ do
      parseValue "<value:pkg>"      `shouldBe` Right (VHole HPkg "value")
      parseValue "<value.2:pkg>"    `shouldBe` Right (VHole HPkg "value.2")
      renderValue (VHole HPkg "value") `shouldBe` "<value:pkg>"
      fmap renderValue (parseValue "<value:pkg>") `shouldBe` Right "<value:pkg>"
    it "a <value.tail:pkg> tail parses, renders canonically, and round-trips" $ do
      parseValue "<value.tail:pkg>" `shouldBe` Right (VTail (Just HPkg) "value")
      renderValue (VTail (Just HPkg) "value") `shouldBe` "<value.tail:pkg>"
      fmap renderValue (parseValue "<value.tail:pkg>") `shouldBe` Right "<value.tail:pkg>"
    it "a bare pkg hole fills one token to a pkgs.<token> derivation" $ do
      fillValue (const (Right "npm")) (VHole HPkg "value")
        `shouldBe` Right "${pkgs.npm}"
      fillValue (const (Right "python311Packages.requests")) (VHole HPkg "value")
        `shouldBe` Right "${pkgs.python311Packages.requests}"
    it "a pkg-tail fills a line of names to a VList of pkgs.<name> derivations" $ do
      fillValue (const (Right "npm yarn bun")) (VTail (Just HPkg) "value")
        `shouldBe` Right "[ ${pkgs.npm} ${pkgs.yarn} ${pkgs.bun} ]"
      renderRealized <$> parseValue "[ ${pkgs.npm} ${pkgs.yarn} ${pkgs.bun} ]"
        `shouldBe` Right "[ pkgs.npm pkgs.yarn pkgs.bun ]"
    it "a filled pkg hole realizes bare (a derivation in a list, not a string)" $ do
      case fillValue (const (Right "npm")) (VHole HPkg "value") of
        Right stored -> renderRealized <$> parseValue stored `shouldBe` Right "pkgs.npm"
        Left e       -> expectationFailure ("fillValue failed: " ++ show e)
    it "a pkg hole rejects a token that is not a valid package name" $ do
      fillValue (const (Right "ev;il"))     (VHole HPkg "value") `shouldSatisfy` isLeft
      fillValue (const (Right "../etc"))    (VHole HPkg "value") `shouldSatisfy` isLeft
      fillValue (const (Right "a${b"))      (VHole HPkg "value") `shouldSatisfy` isLeft
      fillValue (const (Right "npm ev;il")) (VTail (Just HPkg) "value") `shouldSatisfy` isLeft
    it "an empty token for a pkg hole fails loud" $
      fillValue (const (Right "")) (VHole HPkg "value") `shouldSatisfy` isLeft
    it "a pkg hole references a derivation (flagged by valueRefsDerivation)" $ do
      valueRefsDerivation (VHole HPkg "value")       `shouldBe` True
      valueRefsDerivation (VTail (Just HPkg) "value") `shouldBe` True
      valueRefsDerivation (VTail Nothing "value")    `shouldBe` False
      valueRefsDerivation (VHole HInt "value")        `shouldBe` False
    it "a list of pkgs refs grounds against a listOf-package option (kernel stays domain-blind)" $
      valueMatches (OTListOf (OTOther "package")) (VList [VRef (RPkg ["pkgs","npm"])])
        `shouldBe` True

  -- The system prompt is pinned into the generation id, so it is a versioned
  -- artifact; this guards its load-bearing clauses against silent drift.
  -- Rewritten alongside the 2026-07-26 mint-prompt rewrite: the wording moved
  -- (into assets/mint/body.md, organized as named sections below) but the
  -- doctrine did not, so most clauses are unchanged; three were rephrased
  -- in the rewrite (noted below) and are pinned to their new wording instead.
  describe "generate prompt is a pinned artifact (mint doctrine)" $
    it "states its load-bearing invariants" $
      mapM_ (\clause -> systemPrompt `shouldSatisfy` T.isInfixOf clause)
        [ "act exactly once"
        -- Both halves of the hole/literal split are load-bearing: a VALUE gets a
        -- hole so edits flow, a MECHANISM-selecting word stays a template
        -- literal so editing it demands a fresh language instead of governing
        -- nothing (TODO 1c, closed by design).
        , "replace every program VALUE with a hole"
        -- rephrased from "SELECTS A MECHANISM is not a value" (Where You Are)
        , "is not a value in this sense"
        -- An artifact's args are the whole builder call, so they must be able to
        -- produce a derivation name; a pname with no version ships a module that
        -- fails inside nix, past every lips gate (TODO 1e).
        , "BOTH pname and version"
        , "refusal beats invention"
        -- rephrased from "pure data" (Where You Are: the three artifacts named)
        , "data, never code"
        , "No functions"
        , "<value:int>"
        , "demand <subject>"
        -- A demand is met only by a subject a pattern emits, matched segment for
        -- segment; two habit mints in a row got this wrong (Engine.Answerable).
        , "must be one a PATTERN EMITS"
        , "expect <option.path> from <subject>"
        , "pattern|match|merge|demand|expect|because"
        -- A list option is a SET by default and a LIST only where the engine says
        -- so: the kernel cannot know which, so the mint must be told it can say.
        , "merge <option.path> set|list"
        -- A built program has an interface, and a program word reaches inside its
        -- source through a fill: both are universal physics, so they belong here
        -- and not in a per-language .direction file (docs/gaps/README.md,
        -- findings 1 and 4; TODO 1d for the fill).
        , "A built program has an INTERFACE"
        , "reach INSIDE the source, through a FILL"
        -- The capture forms are dead capability unless the prompt offers them.
        , "multi-token hole <name.words>"
        -- A decision line separates its subject by whitespace, so a subject
        -- segment built from a capture that may hold several words cannot be
        -- read back (crystallize refuses it). The mint cannot deduce that from
        -- the grammar, so the prompt names the remedy: key by <n:index>.
        , "A SUBJECT SEGMENT HOLDS NO SPACES"
        -- rephrased from "A MECHANISM is not a gap at all" (How You Work)
        , "None of this applies to a MECHANISM"
        , "or a <capture> the rule's subject binds"
        -- A composed name is kernel physics now, so the prompt must offer it:
        -- a capability the model is told nothing about is dead capability.
        , "A name may COMPOSE literal text with <self> or a <capture>"
        , "because-note"
        , "reserved segment <self>"
        , "PACKAGE NAMES"
        , "<value.tail:pkg>"
        , "NO EXPECT FOR A PACKAGE OR BUILD"
        , "ONLY the item's value"
        , "same line-shape appearing in different programs is a SINGLE"
        , "Rules must be orthogonal"
        , "query_options"
        , "look it up"
        , "grounds NAMES, never VALUES"
        -- Plan B's blocks, added by the rewrite: report is mandatory, gap files
        -- a kernel capability rather than working around it.
        , "report block is required"
        , "A gap is a bug report against lips"
        -- Every named section must actually be there, so a reviewer editing one
        -- cannot silently drop another (Task 3 of the mint-prompt rewrite).
        , "Where You Are"
        , "The Machine You Program"
        , "How You Work"
        , "What You May Say"
        , "Construct Reference"
        , "Designing a Good Language"
        , "Two Worked Examples"
        , "Self-Review Checklist"
        ]

  -- The body is the WORLD-NEUTRAL half of the prompt: the preamble names the
  -- world (and may contrast it with another), the body must not. A body that
  -- says "NixOS module" tells a kubenix or terranix mint it is writing
  -- something it is not -- the same leak already fixed in lips's own output.
  describe "mint prompt body names no world" $
    it "mentions no target world by name" $ do
      body <- TIO.readFile "../assets/mint/body.md"
      mapM_ (\w -> body `shouldNotSatisfy` T.isInfixOf w)
        [ "NixOS", "nixos", "home-manager", "kubenix", "terranix", "Kubernetes" ]

  -- The tool grounds option NAMES. The one thing it must not become is a
  -- licence to invent the VALUE that fills a name it just confirmed.
  describe "mint prompt states the lookup tool (and its limit)" $ do
    it "names the tool and when to reach for it, in every world" $
      mapM_ (\p -> mapM_ (\clause -> p `shouldSatisfy` T.isInfixOf clause)
              [ "query_options", "look it up", "grounds NAMES, never VALUES" ])
            [ systemPromptFor Nixos, systemPromptFor HomeManager, systemPromptFor Kubenix
            , systemPromptFor Terranix ]
    it "repeats that a confirmed option is not a licence to invent its value" $
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "refusal beats invention"

  -- The optional per-program .direction file steers mint taste. It must ride
  -- on top of the fixed prompt (so it enters genId) and carry the guard that
  -- keeps it advisory, never an obligation channel.
  describe "direction file (optional mint taste)" $ do
    it "absent or blank direction leaves the prompt untouched" $ do
      promptWithDirection Nothing Nixos `shouldBe` systemPrompt
      promptWithDirection (Just "   \n  ") Nixos `shouldBe` systemPrompt
    it "steers kubenix to the resource alias every kubenix example writes" $ do
      systemPromptFor Kubenix `shouldSatisfy` T.isInfixOf "kubernetes.resources."
      systemPromptFor Kubenix `shouldSatisfy` T.isInfixOf "kubenix"
    it "steers terranix to the terraform namespaces, and says grounding stops there" $ do
      let p = systemPromptFor Terranix
      mapM_ (\c -> p `shouldSatisfy` T.isInfixOf c)
        [ "terranix", "resource.<type>.<self>", "data.", "provider.", "output." ]
    it "steers home-manager to its namespaces, nixos to system options" $ do
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "home-manager"
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "systemd.user.services"
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "home.packages"
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "NixOS"
    it "present direction is appended verbatim atop the fixed prompt" $ do
      let p = promptWithDirection (Just "prefer restic, no docker") Nixos
      systemPrompt `shouldSatisfy` (`T.isInfixOf` p)
      p `shouldSatisfy` T.isInfixOf "prefer restic, no docker"
    it "states the advisory-not-obligation guard when direction is present" $ do
      let p = promptWithDirection (Just "prefer systemd timers") Nixos
      mapM_ (\clause -> p `shouldSatisfy` T.isInfixOf clause)
        [ "PREFERENCE, not requirement"
        , "never let it override a value the program states"
        ]

  -- Examples teach the grammar, so a stale one teaches a grammar that no longer
  -- exists. Extract every ```lips-engine block from the prompt and require the
  -- real parser to accept it: an example cannot outlive the syntax it shows.
  describe "prompt examples stay parseable" $ do
    -- A capability the model is never told about is dead, so the prompt must
    -- carry the block constructs, and the fenced-block guard below then checks
    -- that the taught spelling actually parses.
    it "teaches blocks and both structure holes" $
      mapM_ (\clause -> systemPrompt `shouldSatisfy` T.isInfixOf clause)
        [ "p5.under.p4", "<n:index>", "<k:key>"
        , "never by indentation" ]

    -- A symbol is a literal token now, so a template that omits one reads no
    -- line that writes it: the prompt must say so, or every mint ships an
    -- engine that cannot read its own example program.
    it "teaches that a template must write the symbols its line carries" $
      mapM_ (\clause -> systemPrompt `shouldSatisfy` T.isInfixOf clause)
        [ "A SYMBOL IS A TOKEN'S OWN TEXT", "TERMINATOR" ]

    it "every lips-engine block in the prompt parses" $ do
      let blocks = fencedBlocks "lips-engine" systemPrompt
      blocks `shouldSatisfy` (not . null)
      mapM_ (\b -> fst (parseEngineCandidates b) `shouldBe` []) blocks

  -- The model is not baked into lips: generate omits --model so pi's own
  -- default applies, then reads the model back from the json stream to keep
  -- .generation concrete. This pins that extraction.
  describe "pi json stream parsing (model read-back)" $ do
    let stream = T.unlines
          [ "{\"type\":\"message_start\",\"message\":{\"role\":\"assistant\",\"content\":[],\"model\":\"anthropic/claude-opus-4-8\"}}"
          , "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]},{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"line one\\nline two\"}],\"model\":\"anthropic/claude-opus-4-8\"}]}"
          ]
    it "recovers the assistant reply from agent_end" $
      prReply (parsePiReply stream) `shouldBe` "line one\nline two"
    it "recovers the model pi actually used" $
      prModel (parsePiReply stream) `shouldBe` "anthropic/claude-opus-4-8"
    it "empty stream yields empty fields (caller fails loud)" $
      parsePiReply "" `shouldBe` PiReply "" "" ""

  -- What the mint LOOKED UP is an input to the mint, so invariant 6 requires it
  -- in the record. The fixture is the shape pi really emits, captured from a
  -- --mode json run on 2026-07-27, not a sketch of it.
  describe "pi json stream parsing (tool transcript)" $ do
    let stream = T.unlines
          [ "{\"type\":\"agent_end\",\"messages\":[\
            \{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"mint it\"}]},\
            \{\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"toolCall\",\"id\":\"call_1\",\"name\":\"query_options\",\"arguments\":{\"query\":\"services.restic\"}}]},\
            \{\"role\":\"toolResult\",\"toolCallId\":\"call_1\",\"toolName\":\"query_options\",\"isError\":false,\"content\":[{\"type\":\"text\",\"text\":\"services.restic.backups.*.paths : list of string\"}]},\
            \{\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"text\",\"text\":\"pattern p 1.0\"}]}]}"
          ]
    it "records the query the mint asked and the answer it was given" $ do
      let t = prTranscript (parsePiReply stream)
      t `shouldSatisfy` T.isInfixOf "query_options"
      t `shouldSatisfy` T.isInfixOf "services.restic"
      t `shouldSatisfy` T.isInfixOf "list of string"
    -- Tools end the one-assistant-message world: a model that narrates before
    -- acting would otherwise get its narration fused in front of the engine.
    it "takes the reply after the tool call, not the narration before it" $
      prReply (parsePiReply stream) `shouldBe` "pattern p 1.0"
    it "a stream with no tool call has an empty transcript" $
      prTranscript (parsePiReply "") `shouldBe` ""

  describe "live mint progress (Lips.Generate.PiJson.progressEvent)" $ do
    it "a tool call shows the tool and what it was asked" $
      progressEvent "{\"type\":\"tool_execution_start\",\"toolName\":\"query_options\",\"args\":{\"query\":\"services.nginx\"}}"
        `shouldBe` Just (PiTool "query_options" "services.nginx")
    it "a tool answer carries its text and whether it failed" $
      progressEvent "{\"type\":\"tool_execution_end\",\"toolName\":\"check_draft\",\"isError\":true,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"nope\"}]}}"
        `shouldBe` Just (PiToolEnd "check_draft" True "nope")
    it "a turn beginning means lips is waiting on the model" $
      progressEvent "{\"type\":\"turn_start\"}" `shouldBe` Just (PiState "waiting for the model")
    it "the model's words come through as prose" $
      progressEvent "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"pattern p\"}}"
        `shouldBe` Just (PiProse "pattern p")
    it "reasoning shows as state, not as text" $
      progressEvent "{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"thinking_delta\",\"delta\":\"hm\"}}"
        `shouldBe` Just (PiState "thinking")
    it "an event with no progress in it shows nothing" $ do
      progressEvent "{\"type\":\"agent_start\"}" `shouldBe` Nothing
      progressEvent "not json" `shouldBe` Nothing
    it "a long argument is cut to one line, and says so" $ do
      abbreviate 8 "one\ntwo" `shouldBe` "one\8230"
      abbreviate 3 "abcdef" `shouldBe` "abc\8230"
      abbreviate 8 "short" `shouldBe` "short"
    it "an answer is summarized by size, a refusal by its first words" $ do
      resultSummary False "a\nb\nc" `shouldBe` "ok, 3 lines"
      resultSummary False "just this" `shouldBe` "just this"
      resultSummary False "" `shouldBe` "ok"
      resultSummary True "it broke\nbecause" `shouldBe` "failed: it broke\8230"

  describe "cli output vocabulary (Lips.Cli.Output)" $ do
    it "a running phase carries its label and the clock" $
      runningText Plain "mint" "" 1.25 `shouldBe` "· mint  1.2s"
    it "the state a phase reports rides beside the clock" $
      runningText Plain "mint" "looking up services.nginx" 3.0
        `shouldBe` "· mint  looking up services.nginx  3.0s"
    it "a held phase says so with its duration" $
      verdictText Plain "contract" (Held 0.5) `shouldBe` "✓ contract  (0.5s)"
    it "a failed phase uses the other glyph" $
      verdictText Plain "contract" (Failed 12.0) `shouldBe` "✗ contract  (12s)"
    it "styling is dropped entirely when the stream is not a terminal" $
      T.any (== '\ESC') (verdictText Plain "x" (Held 1)) `shouldBe` False
    it "a terminal gets styling, and the same words" $ do
      T.any (== '\ESC') (verdictText Fancy "x" (Held 1)) `shouldBe` True
      T.filter (/= '\ESC') (verdictText Fancy "x" (Held 1))
        `shouldSatisfy` T.isInfixOf "✓ x"
    it "durations read at a glance: tenths, seconds, then minutes" $ do
      elapsedText 0.04 `shouldBe` "0.0s"
      elapsedText 9.96 `shouldBe` "10.0s"
      elapsedText 12.4 `shouldBe` "12s"
      elapsedText 125 `shouldBe` "2m 05s"
    it "the report skeleton is headline, indented detail, then the action" $
      report "broke" ["a", "b"] "→ fix it"
        `shouldBe` "broke\n\n  a\n  b\n\n→ fix it"
    it "a detail-free report has no empty block" $
      report "broke" [] "→ fix it" `shouldBe` "broke\n\n→ fix it"
    it "a headline-only diagnosis leaves the action to its caller" $
      reportHead "broke" [] `shouldBe` "broke"

  describe "solution identity (plan 2026-07-22: <instance>.<language>.lips)" $ do
    let prog = "examples/ledger.backup.lips"
    it "reads the language before .lips and the instance before that" $ do
      languageName prog `shouldBe` "backup"
      instanceName prog `shouldBe` "ledger"
    it "the <language>.lips shorthand defaults the instance to the language" $ do
      languageName "examples/backup.lips" `shouldBe` "backup"
      instanceName "examples/backup.lips" `shouldBe` "backup"
    it "puts every machine-written file in one folder named by the language" $ do
      langPath       prog `shouldBe` "examples/backup/backup.lang"
      expectPath     prog `shouldBe` "examples/backup/backup.expect"
      generationPath prog `shouldBe` "examples/backup/backup.generation"
      artifactsPath  prog `shouldBe` "examples/backup/artifacts"
    it "the language's minted explanation is the folder's README.md" $ do
      readmePath prog          `shouldBe` "examples/backup/README.md"
      readmePath "examples/backup.lips" `shouldBe` "examples/backup/README.md"
    it "a refused mint's shippable artifact sits beside the other language-level files" $ do
      gapPath prog `shouldBe` "examples/backup/backup.gap"
      gapPath "examples/backup.lips" `shouldBe` "examples/backup/backup.gap"
    it "keeps the human-written direction at the top level, beside the programs" $ do
      directionPath prog `shouldBe` "examples/backup.direction"
      directionPath "examples/photos.backup.lips" `shouldBe` directionPath prog
      langPath "examples/photos.backup.lips" `shouldBe` langPath prog
    it "keeps derived output under out/, so one gitignore rule covers it" $ do
      decisionsPath prog `shouldBe` "examples/backup/out/ledger.decisions"
      compiledPath  prog `shouldBe` "examples/backup/out/ledger"
    it "never collides between instances of one language" $ do
      compiledPath "examples/photos.backup.lips"
        `shouldNotBe` compiledPath prog
    it "the shorthand puts the singleton under the language's own name" $
      compiledPath "examples/backup.lips" `shouldBe` "examples/backup/out/backup"

  -- Nothing used to check the marker, so every other function here read a
  -- non-program path as if it were one: x.backup.txt became language "backup"
  -- and the minted backup/backup.lang became a program in language "lang",
  -- each surfacing later as a confusing missing file.
  describe "the .lips marker is required (Lips.Identity.requireProgram)" $ do
    it "accepts both program shapes" $ do
      requireProgram "examples/ledger.backup.lips" `shouldBe` Right ()
      requireProgram "examples/backup.lips" `shouldBe` Right ()
    it "refuses a path with another extension, naming the marker" $
      case requireProgram "examples/x.backup.txt" of
        Right () -> expectationFailure "expected Left for x.backup.txt"
        Left msg -> msg `shouldSatisfy` T.isInfixOf ".lips"
    it "refuses a minted file passed as a program" $
      requireProgram "examples/backup/backup.lang" `shouldSatisfy` isLeft
    it "refuses a bare .lips, which names no language" $
      requireProgram "examples/.lips" `shouldSatisfy` isLeft

  describe "--lang resolution (Lips.Identity.resolveLangDir)" $ do
    let prog = "services/b/photos.backup.lips"
    it "with no override, resolves to the sibling langDir" $
      resolveLangDir prog Nothing `shouldBe` Right (langDir prog)
    it "accepts an override folder named after the program's language" $
      resolveLangDir prog (Just "services/a/backup")
        `shouldBe` Right "services/a/backup"
    it "tolerates a trailing slash on the override" $
      resolveLangDir prog (Just "services/a/backup/")
        `shouldBe` Right "services/a/backup"
    it "rejects an override folder named after a different language, naming both sides" $ do
      case resolveLangDir prog (Just "services/a/archival") of
        Right d  -> expectationFailure ("expected Left, got Right " ++ show d)
        Left msg -> do
          msg `shouldSatisfy` T.isInfixOf "backup"
          msg `shouldSatisfy` T.isInfixOf "archival"

  describe "explicit-directory path functions (Lips.Identity.*In)" $ do
    let prog = "services/b/photos.backup.lips"
        dir  = "services/a/backup"
    it "reads the four committed files from the given directory, not the sibling" $ do
      langPathIn       dir prog `shouldBe` "services/a/backup/backup.lang"
      expectPathIn     dir prog `shouldBe` "services/a/backup/backup.expect"
      generationPathIn dir prog `shouldBe` "services/a/backup/backup.generation"
      artifactsPathIn  dir prog `shouldBe` "services/a/backup/artifacts"

  describe "reader fails loud on malformed lines (spec: no silent parse)" $ do
    it "rejects an unknown strength" $
      readDecision "d1 fact x supreme \"a\"" `shouldSatisfy` isLeft
    it "rejects a line truncated before its assertion" $
      readDecision "d1 fact x stated" `shouldSatisfy` isLeft
    it "rejects an empty line" $
      readDecision "" `shouldSatisfy` isLeft

  -- The spec 5 edit-tolerance contract, as fuzzing: a program built from a
  -- language's own templates, with holes filled by arbitrary tokens, stays in
  -- the language and realizes. Edits are re-instantiations of holes; closure
  -- is a theorem of the crystallizer, exercised here over generated programs.
  describe "edit-tolerance fuzzing (spec 5: closure under edits)" $ do
    let p1t = [TLit "the", TLit "bank", TLit "drops", TLit "csv", TLit "files", TLit "into", THole "loc"]
        p2t = [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
        p3t = [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "exactly", TLit "one", THole "rec"]
        pats =
          [ patOne "p1" p1t Fact [SLit "feed.source"]  [SHole "loc"]
          , patOne "p2" p2t Fact [SLit "feed.cadence"] [SHole "sched"]
          , patOne "p3" p3t Oblige [SLit "feed.ingest"]  [SHole "rec"]
          ]
        svc seg = ["systemd", "services", "ledger-ingest"] ++ seg
        rules =
          [ MapRule "r1" Oblige ["feed", "ingest"]
              [ Emit (svc ["enable"]) (VBool True) ]
          , MapRule "r2" Fact ["feed", "cadence"]
              [ Emit ["systemd", "timers", "ledger-ingest", "timerConfig", "OnCalendar"] (VStr [PHole "value"]) ]
          , MapRule "r3" Fact ["feed", "source"]
              [ Emit (svc ["environment", "LEDGER_INBOX"]) (VStr [PHole "value"]) ]
          ]
        demands =
          [ DemandSpec "q1" ["feed", "source"]  "where do the files arrive?"
          , DemandSpec "q2" ["feed", "cadence"] "how often does the feed deliver?"
          ]
        -- reconstruct a surface line from a template, filling its single hole
        surface toks fill = T.unwords [ case t of TLit l -> l; TFused _ -> fill; THole _ -> fill; TMulti _ -> fill | t <- toks ]
        runProg prog = do
          base <- either (Left . show) Right (crystallize "feed" pats prog)
          either (Left . show) Right
            (runBaseReplace 10000 (map toRule rules) (map toDemand demands) base)
        -- the realized module minus provenance comments: the semantic content,
        -- which is what edits must preserve (comments track ids, not meaning)
        opts = filter (not . ("#" `T.isPrefixOf`) . T.stripStart) . T.lines
        tok  = safeToken
        anyLine = do
          t   <- tok
          tpl <- elements [p1t, p2t, p3t]
          dot <- elements ["", "."]
          pure (surface tpl t <> dot)

    it "crystallize accepts any in-language program (never NoPattern/Overlapping)" $
      property $ forAll (listOf1 anyLine) $ \ls ->
        case crystallize "feed" pats (T.unlines ls) of
          Right _ -> True
          Left _  -> False

    it "value edits realize: arbitrary source/cadence tokens build a module carrying them" $
      property $ forAll ((,) <$> tok <*> tok) $ \(loc, sched) ->
        case runProg (T.unlines [surface p1t loc, surface p2t sched]) of
          Right m -> loc `T.isInfixOf` m .&&. sched `T.isInfixOf` m
          Left e  -> counterexample e False

    it "recombination: reordering lines preserves the option assignments" $
      property $ forAll ((,,) <$> tok <*> tok <*> tok) $ \(loc, sched, rec) ->
        let ls = [surface p1t loc, surface p2t sched, surface p3t rec]
         in forAll (shuffle [0 .. length ls - 1]) $ \perm ->
              fmap opts (runProg (T.unlines (map (ls !!) perm)))
                === fmap opts (runProg (T.unlines ls))

    it "instance edit: duplicating an identical line changes nothing (agreement)" $
      property $ forAll ((,) <$> tok <*> tok) $ \(loc, sched) ->
        let orig = [surface p1t loc, surface p2t sched]
            dup  = orig ++ [surface p1t loc]
         in fmap opts (runProg (T.unlines dup)) === fmap opts (runProg (T.unlines orig))

  -- Option-schema grounding (steal #1): every minted rule must fill an option
  -- that exists in the target schema, with a value of a compatible type. The
  -- check is domain-blind (a typed OptionSchema); the NixOS specifics live in
  -- Lips.Nix.Options.
  describe "option-schema check (rules vs the target's typed options)" $ do
    let optRule rid pth rhs =
          MapRule { mrId = rid, mrKind = Fact, mrSubject = ["s"]
                  , mrEmits = [Emit { emPath = pth, emRhs = rhs }] }
        schema = Map.fromList
          [ (["services", "x", "port"], OTInt)
          , (["services", "x", "host"], OTString) ]

    it "accepts an int hole for an integer option" $
      valueMatches OTInt (VHole HInt "value") `shouldBe` True
    it "rejects a quoted string for an integer option" $
      valueMatches OTInt (VStr [PHole "value"]) `shouldBe` False
    it "accepts a string value for a string option" $
      valueMatches OTString (VStr [PHole "value"]) `shouldBe` True
    it "accepts a bool hole for a boolean option" $
      valueMatches OTBool (VHole HBool "value") `shouldBe` True
    it "checks the list element type" $ do
      valueMatches (OTListOf OTString) (VList [VStr [PLit "x"]]) `shouldBe` True
      valueMatches (OTListOf OTInt)    (VList [VStr [PHole "v"]]) `shouldBe` False
    it "accepts any value for an unmodelled type (OTOther is unconstrained)" $
      valueMatches (OTOther "submodule") (VBool True) `shouldBe` True

    -- H3: a listOf-submodule option (list of (submodule)) whose fields the
    -- schema lists as *-wildcard leaves is field-checked. The element type is
    -- OTOther "submodule" (an unconstrained catch-all by itself), but when the
    -- schema carries the submodule's fields, each VAttr element's fields are
    -- checked against their leaf types. A mistyped field (ensureDBOwnership =
    -- a STRING, not a bool) is flagged; a well-typed one passes. This is the
    -- one door minted engines enter, where the schema lives (generate); the
    -- run path stays schema-free (invariant 1).
    it "field-checks a listOf-submodule's attrset elements against the schema's wildcard leaves" $ do
      let sch = Map.fromList
            [ (["services","postgresql","ensureUsers"], OTListOf (OTOther "submodule"))
            , (["services","postgresql","ensureUsers","*","name"], OTString)
            , (["services","postgresql","ensureUsers","*","ensureDBOwnership"], OTBool)
            ]
          good = optRule "r1" ["services","postgresql","ensureUsers"]
                    (VList [VAttr [("name", VStr [PHole "value"])
                                  ,("ensureDBOwnership", VBool True)]])
          bad  = optRule "r2" ["services","postgresql","ensureUsers"]
                    (VList [VAttr [("name", VStr [PHole "value"])
                                  ,("ensureDBOwnership", VStr [PLit "true"])]])  -- string, not bool
      map renderOptionError (checkEmits sch [good]) `shouldBe` []
      -- Per-field TypeMismatch (no new variant): the error carries the field's
      -- leaf path + type + value, so the regenerate door names the exact
      -- offending field, not just the whole-element list.
      checkEmits sch [bad] `shouldBe`
        [ TypeMismatch "r2" ["services","postgresql","ensureUsers","ensureDBOwnership"] OTBool (VStr [PLit "true"]) ]
      map renderOptionError (checkEmits sch [bad])
        `shouldBe` ["rule r2: option services.postgresql.ensureUsers.ensureDBOwnership has type boolean but the rule fills it with an incompatible value"]

    it "a listOf-submodule with no listed field leaves degrades to unconstrained (the schema genuinely doesn't constrain; the kernel can't either)" $ do
      let sch = Map.fromList [ (["s","users"], OTListOf (OTOther "submodule")) ]
      checkEmits sch [ optRule "r" ["s","users"] (VList [VAttr [("anything", VStr [PLit "x"]),("goes", VBool True)]]) ]
        `shouldBe` []


    it "passes when every option exists and types match" $
      checkEmits schema
        [ optRule "r1" ["services", "x", "port"] (VHole HInt "value")
        , optRule "r2" ["services", "x", "host"] (VStr [PHole "value"]) ]
        `shouldBe` []
    it "flags an unknown option" $
      checkEmits schema [ optRule "r3" ["services", "x", "nope"] (VBool True) ]
        `shouldBe` [ UnknownOption "r3" ["services", "x", "nope"] ]
    it "flags a type mismatch" $
      checkEmits schema [ optRule "r4" ["services", "x", "port"] (VStr [PHole "value"]) ]
        `shouldBe` [ TypeMismatch "r4" ["services", "x", "port"] OTInt (VStr [PHole "value"]) ]
    -- Q2: the mismatch message prints the HUMAN type string (the wording the
    -- model and nixpkgs use), not the Haskell 'show' form, so a regenerate
    -- door reads "boolean" / "list of (submodule)", not "OTBool".
    it "renders option types as human strings in a mismatch message" $ do
      let port = optRule "r" ["services", "x", "port"] (VStr [PHole "value"])
          sch  = Map.fromList [ (["services","x","port"], OTInt)
                              , (["services","x","bool"], OTBool)
                              , (["services","x","users"], OTListOf (OTOther "(submodule)")) ]
      map renderOptionError (checkEmits sch [ port ])
        `shouldBe` ["rule r: option services.x.port has type integer but the rule fills it with an incompatible value"]
      map renderOptionError (checkEmits sch [ optRule "r" ["services","x","bool"] (VStr [PLit "x"]) ])
        `shouldBe` ["rule r: option services.x.bool has type boolean but the rule fills it with an incompatible value"]
      map renderOptionError (checkEmits sch [ optRule "r" ["services","x","users"] (VBool True) ])
        `shouldBe` ["rule r: option services.x.users has type list of (submodule) but the rule fills it with an incompatible value"]
    it "matches a wildcard schema segment (attrsOf-submodule instance name)" $ do
      let sch = Map.fromList [ (["services", "r", "*", "port"], OTInt) ]
      checkEmits sch [ optRule "r1" ["services", "r", "ledger", "port"] (VHole HInt "value") ]
        `shouldBe` []
      checkEmits sch [ optRule "r2" ["services", "r", "ledger", "port"] (VStr [PHole "v"]) ]
        `shouldBe` [ TypeMismatch "r2" ["services", "r", "ledger", "port"] OTInt (VStr [PHole "v"]) ]
    -- Value-keyed options: a <capture> emit-path segment must be admissible
    -- exactly where an instance name is (a schema "*"), and rejected in a
    -- literal slot -- so the mint can key ONLY a real attrsOf, deduced offline.
    it "accepts a <capture> segment in a wildcard slot and rejects it in a literal slot" $ do
      let sch = Map.fromList [ (["environment", "etc", "*", "text"], OTString) ]
      checkEmits sch [ optRule "r1" ["environment", "etc", "<path>", "text"] (VStr [PHole "value"]) ]
        `shouldBe` []
      checkEmits sch [ optRule "r2" ["environment", "<path>", "foo", "text"] (VStr [PHole "value"]) ]
        `shouldBe` [ UnknownOption "r2" ["environment", "<path>", "foo", "text"] ]

    it "accepts a path that descends into a declared free-form option" $ do
      let sch = Map.fromList [ (["services", "r", "*", "timerConfig"], OTOther "attribute set") ]
      checkEmits sch [ optRule "r3" ["services", "r", "ledger", "timerConfig", "OnCalendar"] (VStr [PHole "v"]) ]
        `shouldBe` []
    it "flags a path outside any declared option" $ do
      let sch = Map.fromList [ (["services", "r", "*", "port"], OTInt) ]
      checkEmits sch [ optRule "r4" ["services", "r", "ledger", "nonsuch"] (VBool True) ]
        `shouldBe` [ UnknownOption "r4" ["services", "r", "ledger", "nonsuch"] ]
    it "ignores artifact build-group emits (a derivation, not a target option)" $
      checkEmits Map.empty
        [ optRule "r" ["artifact", "srv", "builder"] (VStr [PLit "buildGoModule"]) ]
        `shouldBe` []
    -- Only an option whose type this layer does NOT model can have children the
    -- schema omits (a submodule, an attrset, a target's "anything"). A modelled
    -- scalar or list is a leaf by construction, so a path descending BELOW one
    -- names nothing in any world -- accepting it let a whole namespace of
    -- invented fields through under one real string option.
    it "refuses a path below a modelled leaf, and accepts one below an unmodelled option" $ do
      let sch = Map.fromList
            [ (["services","nginx","appendConfig"], OTString)
            , (["services","nginx","settings"], OTOther "attribute set of anything") ]
          under p = optRule "r1" p (VInt 1)
      checkEmits sch [under ["services","nginx","appendConfig","foo"]]
        `shouldBe` [UnknownOption "r1" ["services","nginx","appendConfig","foo"]]
      checkEmits sch [under ["services","nginx","settings","foo"]] `shouldBe` []
    it "echoes exactly the bogus option in a mixed rule set (deduce-or-fail)" $ do
      let sch  = Map.fromList [ (["services", "restic", "backups", "x", "paths"], OTListOf OTString) ]
          good = optRule "r1" ["services", "restic", "backups", "x", "paths"] (VList [VStr [PHole "value"]])
          bad  = optRule "r2" ["services", "restic", "backups", "x", "nonsuch"] (VStr [PHole "value"])
      map renderOptionError (checkEmits sch [good, bad])
        `shouldBe` ["rule r2: unknown option services.restic.backups.x.nonsuch"]

  describe "schema lookup (what the mint may ask)" $ do
    let sch = Map.fromList
          [ (["services","restic","backups","*","paths"], OTListOf OTString)
          , (["services","restic","backups","*","repository"], OTString)
          , (["services","nginx","enable"], OTBool)
          ]
    it "a dotted prefix with few matches answers with exact leaves and types" $
      answerQuery 40 "services.restic" sch `shouldBe` Leaves
        [ (["services","restic","backups","*","paths"], OTListOf OTString)
        , (["services","restic","backups","*","repository"], OTString) ]
    it "a bare word falls back to substring search" $
      answerQuery 40 "nginx" sch `shouldBe` Leaves [(["services","nginx","enable"], OTBool)]
    -- The load-bearing case: a large match set must NOT be an alphabetical
    -- slice, or the namespace the word is about disappears.
    it "too many matches answer with the namespaces, heaviest first" $
      answerQuery 2 "services" sch `shouldBe`
        Namespaces [ (["services","restic"], 2), (["services","nginx"], 1) ] 0
    it "an unmatched query says so rather than guessing" $
      answerQuery 40 "nosuchthing" sch `shouldBe` Nowhere
    -- The lookup and the grounding gate are two doors onto ONE schema, so they
    -- must answer alike: 'checkEmits' accepts any path descending into a
    -- declared free-form option, and the lookup has to say that instead of
    -- "no option matches" -- which would tell the mint its legal path is a
    -- typo. The answer must also state what it costs: nothing below is typed.
    it "a path inside a free-form option is answered as unchecked, not absent" $ do
      let freeSch = Map.insert ["services","x","settings"] (OTOther "attribute set of anything")
                      (Map.insert ["services","x","note"] OTString sch)
      answerQuery 40 "services.x.settings.compression.level" freeSch
        `shouldBe` Freeform ["services","x","settings"] (OTOther "attribute set of anything")
      -- and the gate agrees, which is the point of the case
      let r = MapRule "r1" Fact ["level"]
                [Emit ["services","x","settings","compression","level"] (VInt 9)]
      checkEmits freeSch [r] `shouldBe` []
      -- a modelled leaf is no such region: below it there is nothing to reach
      answerQuery 40 "services.x.note.deeper" freeSch `shouldBe` Nowhere
    it "the nearest declared ancestor wins, so the reader learns where typing stops" $ do
      let freeSch = Map.fromList
            [ (["resource"], OTOther "bool, int, float or str")
            , (["resource","aws_instance"], OTOther "attribute set of anything") ]
      answerQuery 40 "resource.aws_instance.web.ami" freeSch
        `shouldBe` Freeform ["resource","aws_instance"] (OTOther "attribute set of anything")
    it "a wrong leaf is answered with the real leaves beside it" $
      nearOptions 40 ["services","restic","backups","*","path"] sch `shouldBe` Leaves
        [ (["services","restic","backups","*","paths"], OTListOf OTString)
        , (["services","restic","backups","*","repository"], OTString) ]

  -- The NixOS-specific translation from optionsJSON's human type strings to the
  -- generic OptionType. Lives outside the kernel; the kernel never sees this
  -- wording.
  describe "NixOS optionsJSON parsing (Lips.Nix.Options)" $ do
    it "maps boolean"                $ classifyNixType "boolean" `shouldBe` OTBool
    it "maps any integer wording"    $ classifyNixType "16 bit unsigned integer; between 0 and 65535 (both inclusive)" `shouldBe` OTInt
    it "maps signed integer"         $ classifyNixType "signed integer" `shouldBe` OTInt
    it "maps floating point number"  $ classifyNixType "floating point number" `shouldBe` OTFloat
    it "maps string"                 $ classifyNixType "string" `shouldBe` OTString
    it "maps non-empty string"       $ classifyNixType "non-empty string" `shouldBe` OTString
    it "maps list of string"         $ classifyNixType "list of string" `shouldBe` OTListOf OTString
    it "keeps a union unmodelled"    $ classifyNixType "null or absolute path" `shouldBe` OTOther "null or absolute path"
    it "keeps an attrset unmodelled" $ classifyNixType "attribute set of anything" `shouldBe` OTOther "attribute set of anything"

    it "parses the fixture into a typed schema" $ do
      bytes <- BL.readFile "test/fixtures/options-mini.json"
      case parseNixOptionsJson bytes of
        Left e       -> expectationFailure (T.unpack e)
        Right schema -> do
          Map.lookup ["services", "x", "enable"]  schema `shouldBe` Just OTBool
          Map.lookup ["services", "x", "port"]    schema `shouldBe` Just OTInt
          Map.lookup ["services", "x", "host"]    schema `shouldBe` Just OTString
          Map.lookup ["services", "x", "paths"]   schema `shouldBe` Just (OTListOf OTString)
          Map.lookup ["services", "x", "envFile"] schema `shouldBe` Just (OTOther "null or absolute path")
          -- a <name> placeholder normalizes to the wildcard sentinel
          Map.lookup ["services", "y", "*", "port"] schema `shouldBe` Just OTInt

  -- The kubenix world's schema needs reshaping the other two do not: its typed
  -- tree sits behind an alias, and its inner nodes are free-form, which
  -- checkEmits would read as "anything below is fine".
  describe "kubenix optionsJSON reshaping (Lips.Nix.Kubenix)" $ do
    let kubeSchema = do
          bytes <- BL.readFile "test/fixtures/options-kubenix-mini.json"
          either (fail . T.unpack) pure (schemaFor Kubenix bytes)
    it "re-keys the typed tree onto the alias every program writes" $ do
      sch <- kubeSchema
      Map.lookup ["kubernetes","resources","deployments","*","spec","replicas"] sch
        `shouldBe` Just OTInt
      -- the group/version/kind spelling of the same alias
      Map.lookup ["kubernetes","resources","apps","v1","Deployment","*","spec","replicas"] sch
        `shouldBe` Just OTInt
      -- the typed path itself is MOVED, not copied: one spelling grounds
      Map.lookup ["kubernetes","api","resources","deployments","*","spec","replicas"] sch
        `shouldBe` Nothing
    it "unwraps a k8s optional so its scalar type still grounds" $ do
      sch <- kubeSchema
      Map.lookup ["kubernetes","resources","deployments","*","metadata","name"] sch
        `shouldBe` Just OTString
      Map.lookup ["kubernetes","resources","deployments","*","spec","paused"] sch
        `shouldBe` Just OTBool
    it "keeps an unmodelled optional's wording verbatim (it feeds the refusal)" $ do
      sch <- kubeSchema
      Map.lookup ["kubernetes","resources","deployments","*","metadata","labels"] sch
        `shouldBe` Just (OTOther "null or (attribute set of (string))")
    it "drops every inner node, which would swallow any path below it" $ do
      sch <- kubeSchema
      Map.lookup ["kubernetes","resources"] sch `shouldBe` Nothing
      Map.lookup ["kubernetes","api","resources"] sch `shouldBe` Nothing
      Map.lookup ["kubernetes","resources","deployments"] sch `shouldBe` Nothing
    it "keeps the world's own leaf options" $ do
      sch <- kubeSchema
      Map.lookup ["kubenix","project"] sch `shouldBe` Just OTString
      Map.lookup ["kubernetes","namespace"] sch `shouldBe` Just OTString
    it "grounds a real emit and refuses a misspelled field" $ do
      sch <- kubeSchema
      let emit p v = MapRule "r1" Fact ["replicas"] [Emit p v]
          good = emit ["kubernetes","resources","deployments","web","spec","replicas"] (VInt 3)
          bad  = emit ["kubernetes","resources","deployments","web","spec","replicaz"] (VInt 3)
          mist = emit ["kubernetes","resources","deployments","web","spec","replicas"] (VStr [PLit "three"])
      checkEmits sch [good] `shouldBe` []
      checkEmits sch [bad]  `shouldBe` [UnknownOption "r1" ["kubernetes","resources","deployments","web","spec","replicaz"]]
      checkEmits sch [mist] `shouldBe`
        [TypeMismatch "r1" ["kubernetes","resources","deployments","web","spec","replicas"] OTInt (VStr [PLit "three"])]

  -- terranix needs no reshaping (its document is plain nixosOptionsDoc output),
  -- but it grounds only the top-level terraform namespaces: they are declared
  -- free-form options, so every provider path below them is accepted unchecked.
  -- These cases pin that boundary, so a later provider-schema fix has a
  -- statement of the current, weaker guarantee to replace.
  describe "terranix optionsJSON grounding (Lips.Nix.Schema)" $ do
    let tnxSchema = do
          bytes <- BL.readFile "test/fixtures/options-terranix-mini.json"
          either (fail . T.unpack) pure (schemaFor Terranix bytes)
        emit p v = MapRule "r1" Fact ["ami"] [Emit p v]
    it "keeps the free-form namespace as a declared option" $ do
      sch <- tnxSchema
      Map.lookup ["resource"] sch `shouldBe` Just (OTOther "bool, int, float or str")
    it "accepts any provider path below a declared namespace" $ do
      sch <- tnxSchema
      checkEmits sch [emit ["resource","aws_instance","web","ami"] (VStr [PLit "ami-a1b2c3d4"])]
        `shouldBe` []
      checkEmits sch [emit ["output","ip","value"] (VStr [PLit "1.2.3.4"])] `shouldBe` []
    it "refuses a misspelled namespace, which is what grounding still buys here" $ do
      sch <- tnxSchema
      checkEmits sch [emit ["resourse","aws_instance","web","ami"] (VStr [PLit "x"])]
        `shouldBe` [UnknownOption "r1" ["resourse","aws_instance","web","ami"]]
    it "type-checks the core options that ARE typed" $ do
      sch <- tnxSchema
      Map.lookup ["backend","s3","bucket"] sch `shouldBe` Just OTString
      Map.lookup ["remote_state","s3","*","key"] sch `shouldBe` Just OTString
      checkEmits sch [emit ["backend","s3","bucket"] (VInt 7)] `shouldBe`
        [TypeMismatch "r1" ["backend","s3","bucket"] OTString (VInt 7)]

  -- Knob 3 of a target: what the compiled flake exposes, and the stock nix
  -- commands compile prints. A world with no machine must show no machine rung.
  describe "compiled flake per target (Lips.Nix.Flake)" $ do
    -- The bare artifact rungs run a binary with no init, so no service env.
    -- The shell rung closes that: one shell per unit the program ADDS to the
    -- config, carrying that unit's environment. Derived inside nix from the
    -- same evaluation, so lips knows no unit name.
    it "nixos exposes a shell per unit the program adds, holding its env" $ do
      let t = flakeText Nixos False False
      mapM_ (\c -> t `shouldSatisfy` T.isInfixOf c)
        [ "baseServices", "systemd.services", "genAttrs", "subtractLists"
        , "// b.serviceShells", "service-${u}", "env = cfg.systemd.services" ]
    it "nixos prints the per-unit shell, naming the unit as a placeholder" $ do
      let ls = T.unlines (runCommands Nixos [] False "/tmp/out")
      mapM_ (\c -> ls `shouldSatisfy` T.isInfixOf c)
        [ "nix develop path:/tmp/out#service-<unit>", "nix flake show" ]
    it "kubenix exposes the module and kubenix's own rendered outputs" $ do
      let t = flakeText Kubenix False False
      mapM_ (\c -> t `shouldSatisfy` T.isInfixOf c)
        [ "kubenixModules.default", "kubenix.evalModules", "kubenix.modules.k8s"
        , "config.kubernetes", "cfg.resultYAML", "cfg.result", "kubectl" ]
      mapM_ (\c -> t `shouldNotSatisfy` T.isInfixOf c)
        [ "nixosModules", "run-lips-vm", "eval-config.nix" ]
    it "kubenix prints how to write, check and shell the manifests" $ do
      let ls = T.unlines (runCommands Kubenix [] False "/tmp/out")
      mapM_ (\c -> ls `shouldSatisfy` T.isInfixOf c)
        [ "nix run", "path:/tmp/out#manifest", "manifests.yaml"
        , "nix build", "#manifest-json", "nix develop" ]
      ls `shouldNotSatisfy` T.isInfixOf "#vm"
    it "terranix exposes the module and terranix's own config.tf.json" $ do
      let t = flakeText Terranix False False
      mapM_ (\c -> t `shouldSatisfy` T.isInfixOf c)
        [ "terranixModules.default", "terranix.lib.terranixConfiguration"
        , "config = ", "opentofu" ]
      mapM_ (\c -> t `shouldNotSatisfy` T.isInfixOf c)
        [ "nixosModules", "run-lips-vm", "eval-config.nix", "kubenix" ]
    it "terranix prints how to write, check and shell the configuration" $ do
      let ls = T.unlines (runCommands Terranix [] False "/tmp/out")
      mapM_ (\c -> ls `shouldSatisfy` T.isInfixOf c)
        [ "nix run", "path:/tmp/out#config", "config.tf.json"
        , "nix build", "nix develop" ]
      mapM_ (\c -> ls `shouldNotSatisfy` T.isInfixOf c) [ "#vm", "#manifest" ]

  describe "engine gates are pure and reusable (Lips.Kernel.Engine.Gate)" $ do
    it "passes a sound engine" $ do
      let eng = engineFromLang
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.interval \"<secs>\""
            , "0.95 r1 match fact watch.interval => systemd.services.w.environment.S \"<value:int>\""
            ]
      engineViolations eng `shouldBe` []

    it "names two patterns that both read one line" $ do
      let eng = engineFromLang
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.a \"<secs>\""
            , "0.95 p2 pattern watch <n> seconds => fact watch.b \"<n>\""
            , "0.95 r1 match fact watch.a => systemd.services.w.environment.A \"<value:int>\""
            , "0.95 r2 match fact watch.b => systemd.services.w.environment.B \"<value:int>\""
            ]
      engineViolations eng `shouldNotBe` []

    -- The caller shows the FIRST entry, as dying on the first gate has always
    -- done, so the gate order decides which defect a refusal names: a later
    -- verdict is rarely meaningful once an earlier gate rejected the engine.
    it "keeps the gate order, so the first entry is the first rejecting gate" $ do
      let eng = engineFromLang
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.a \"<secs>\""
            , "0.95 p2 pattern watch <n> seconds => fact watch.b \"<n>\""
            , "0.95 r1 match fact watch.a => systemd.services.w.environment.A \"<value:int>\""
            , "0.95 r2 match fact watch.b => systemd.services.w.environment.B \"<value:int>\""
            , "0.95 q1 demand watch.nobody \"a fact no pattern emits\""
            ]
      case engineViolations eng of
        (v : _ : _) -> v `shouldSatisfy` T.isInfixOf "patterns read the same line"
        other       -> expectationFailure ("expected both gates to reject, got " ++ show (length other))

  describe "draft materialization (Lips.Generate.Draft)" $ do
    let reply = T.unlines
          [ "0.95 p1 pattern watch <secs> seconds => fact watch.interval \"<secs>\""
          , "0.95 r1 match fact watch.interval => systemd.services.w.environment.S \"<value:int>\""
          , "0.95 a1 expect systemd.services.w.environment.S from watch.interval"
          ]
    -- resolveLangDir refuses a folder whose basename is not the language, so a
    -- draft that landed in the temp root itself could never be checked.
    it "puts the draft in a folder named after the language" $
      case materializeDraft "/tmp/x" "one.watch.lips" reply Nothing of
        Left es -> expectationFailure ("draft did not materialize: " <> show es)
        Right t -> dtLangDir t `shouldBe` "/tmp/x/watch"

    it "renders the draft as a .lang the ordinary reader accepts" $
      case materializeDraft "/tmp/x" "one.watch.lips" reply Nothing of
        Left es -> expectationFailure ("draft did not materialize: " <> show es)
        Right t -> readLang (dtLang t) `shouldSatisfy` isRight

    -- On a regeneration the committed contract governs (invariant 5). Handing
    -- the model its own freshly written promises would always pass and the real
    -- gate would then refuse: a false green is worse than no tool.
    it "writes the governing contract, not the draft's own, when one is given" $
      case materializeDraft "/tmp/x" "one.watch.lips" reply (Just "the committed contract") of
        Left es -> expectationFailure ("draft did not materialize: " <> show es)
        Right t -> dtExpect t `shouldBe` "the committed contract"

    it "falls back to the draft's own expects, which is a first mint" $
      case materializeDraft "/tmp/x" "one.watch.lips" reply Nothing of
        Left es -> expectationFailure ("draft did not materialize: " <> show es)
        Right t -> dtExpect t `shouldSatisfy` T.isInfixOf "watch.interval"

    it "reports the parse errors of an unreadable draft rather than guessing" $
      case materializeDraft "/tmp/x" "one.watch.lips" "not an engine line" Nothing of
        Left es -> es `shouldNotBe` []
        Right _ -> expectationFailure "an unreadable draft must not materialize"

  -- The logic axis (decision doc 2026-08-02): behaviour is emitted as a small
  -- Scheme subset. The kernel owns the GRAMMAR and never evaluates it, exactly
  -- as it owns the Nix value grammar it never evaluates.
  describe "s-expressions (Lips.Kernel.Sexp: the closed clause grammar)" $ do
    it "round-trips a clause" $ do
      let t = "(define (keep? r s) (cond ((null? s) #t) (else #f)))"
      fmap Sx.renderSexp (Sx.parseSexp t) `shouldBe` Right t

    it "round-trips a character literal, which a clause needs to split on" $
      fmap Sx.renderSexp (Sx.parseSexp "(string-cut arg #\\=)")
        `shouldBe` Right "(string-cut arg #\\=)"

    it "reads a quoted empty list as data" $
      Sx.parseSexp "'()" `shouldBe` Right (Sx.SQuote (Sx.SList []))

    -- < and > are ordinary Scheme identifier characters, so the hole marker is
    -- #<...>, which Scheme reserves. Without this a clause could not compare.
    it "reads < as a symbol, not as the opening of a hole" $
      Sx.parseSexp "(< n 3)"
        `shouldBe` Right (Sx.SList [Sx.SSym "<", Sx.SSym "n", Sx.SInt 3])

    it "refuses text left over after the expression" $
      Sx.parseSexp "(a) (b)" `shouldSatisfy` isLeft

    it "refuses an unclosed list" $
      Sx.parseSexp "(define (f" `shouldSatisfy` isLeft

    it "fills a typed hole with a program value" $
      fmap Sx.renderSexp (Sx.fillSexp (const (Right "14")) (Sx.SHole HInt "value"))
        `shouldBe` Right "14"

    it "refuses a typed hole filled with something of the wrong type" $
      Sx.fillSexp (const (Right "daily")) (Sx.SHole HInt "value") `shouldSatisfy` isLeft

    it "escapes a program value landing in a string, so it cannot end the string" $
      fmap Sx.renderSexp (Sx.fillSexp (const (Right "a\"b")) (Sx.SStr [Sx.SPHole "value"]))
        `shouldBe` Right "\"a\\\"b\""

    it "has no way to splice a program value as code" $
      -- The only fillable positions are a typed hole and a string hole; a
      -- filled symbol has no constructor, so program text can never become a
      -- call. Pinned as a property of the grammar, not of a check.
      fmap Sx.renderSexp (Sx.fillSexp (const (Right "(system \"rm\")")) (Sx.SStr [Sx.SPHole "value"]))
        `shouldBe` Right "\"(system \\\"rm\\\")\""

    it "lists every symbol it mentions, in order" $
      fmap Sx.sexpSymbols (Sx.parseSexp "(f (g x) 1 \"s\")")
        `shouldBe` Right ["f", "g", "x"]

    it "does not list the symbols inside quoted data" $
      fmap Sx.sexpSymbols (Sx.parseSexp "(f '(g x))") `shouldBe` Right ["f"]

    -- A clause is a rule's rhs, so the value grammar must carry one. Without
    -- this a clause could only reach the module as opaque text, which is the
    -- one thing the logic axis exists to avoid (decision doc §12).
    it "parses an s-expression as a whole rhs value" $
      parseValue "(define (limit) #<value:int>)"
        `shouldSatisfy` either (const False) isSexpValue

    it "round-trips an s-expression rhs through the canonical form" $ do
      let t = "(define (limit) #<value:int>)"
      fmap renderValue (parseValue t) `shouldBe` Right t

    it "emits an s-expression rhs unchanged into the module" $
      fmap renderRealized (parseValue "(define (f x) x)")
        `shouldBe` Right "(define (f x) x)"

    it "reports the assertion hole inside an s-expression rhs" $
      fmap valueUsesAssertion (parseValue "(define (limit) #<value:int>)")
        `shouldBe` Right True

    it "reports a capture an s-expression rhs names" $
      fmap valueCaptures (parseValue "(define (greet) \"hello #<who>\")")
        `shouldBe` Right ["who"]

    it "fills a hole inside an s-expression rhs from the program value" $
      fmap (fillValue (const (Right "14"))) (parseValue "(define (limit) #<value:int>)")
        `shouldBe` Right (Right "(define (limit) 14)")

    it "has no plain text form, so it can never be written into source" $
      fmap sourceText (parseValue "(define (f x) x)") `shouldBe` Right Nothing

    it "still refuses a bare identifier as a whole rhs" $
      parseValue "pkgs.curl" `shouldSatisfy` isLeft

  -- What grounds a name in a clause is a vocabulary file, so the kernel
  -- enumerates nothing: it reads the forms, procedures and contracts a runtime
  -- declares, exactly as a rule reads an option path nixpkgs declares.
  describe "clause vocabulary (Lips.Kernel.Clause.Vocabulary: data, not a branch)" $ do
    it "reads a binder with its parameter position" $
      fmap vBinders (parseVocabulary "binder lambda params 1")
        `shouldBe` Right [Binder "lambda" (ParamsAt 1)]

    it "reads a binder whose bindings are a let list" $
      fmap vBinders (parseVocabulary "binder let bindings 1")
        `shouldBe` Right [Binder "let" (BindingsAt 1)]

    it "reads a special form" $
      fmap vForms (parseVocabulary "form cond") `shouldBe` Right ["cond"]

    it "reads a base procedure" $
      fmap vProcedures (parseVocabulary "procedure null?") `shouldBe` Right ["null?"]

    it "ignores comments and blank lines" $
      fmap vForms (parseVocabulary "# a comment\n\nform cond\n")
        `shouldBe` Right ["cond"]

    it "fails loud on an unknown declaration, naming the line" $
      parseVocabulary "wobble lambda"
        `shouldSatisfy` either (T.isInfixOf "wobble lambda") (const False)

    it "reads a contract with its kind, arity and meaning" $
      parseContracts "effect emit 1 \"line -> writes it\""
        `shouldBe` Right [Contract "emit" 1 Effect "line -> writes it"]

    it "reads a pure contract" $
      fmap (map cKind) (parseContracts "pure json-parse 1 \"text -> record\"")
        `shouldBe` Right [Pure]

    it "fails loud on a contract with no arity" $
      parseContracts "effect emit \"line -> writes it\"" `shouldSatisfy` isLeft

    -- The shipped vocabulary is an asset a human reviews, so the suite holds it
    -- to the same parser and pins that it covers the corpus the falsifier ran.
    it "ships a scheme vocabulary that parses" $
      schemeVocabulary `shouldSatisfy` \v ->
        "cond" `elem` vForms v && "equal?" `elem` vProcedures v

    it "ships contracts covering what the logscan core reaches" $
      map cName (vContracts schemeVocabulary)
        `shouldSatisfy` \ns -> all (`elem` ns)
          ["read-a-line", "end-of-input?", "emit", "die", "json-parse", "string-cut", "field-of"]

  -- The gate is the whole safety argument: a clause reaches the world only
  -- through a declared contract, and nothing else can slip in. Ported from
  -- experiments/logscan-clauses/gate.scm, which proved the walk by hand.
  describe "the subset gate (Lips.Kernel.Clause.Gate)" $ do
    it "passes the logscan core the falsifier ran" $
      gate schemeVocabulary logscanClauses `shouldBe` []

    it "names an identifier no vocabulary grounds" $
      gate schemeVocabulary [clauseOf "sneaky" "(define (sneaky p) (system p))"]
        `shouldBe` [Ungrounded "sneaky" "system"]

    it "does not report a lambda parameter as ungrounded" $
      gate schemeVocabulary [clauseOf "f" "(define (f xs) ((lambda (y) y) xs))"]
        `shouldBe` []

    it "does not report a let binding as ungrounded" $
      gate schemeVocabulary [clauseOf "f" "(define (f xs) (let ((y xs)) y))"]
        `shouldBe` []

    it "does not look inside quoted data" $
      gate schemeVocabulary [clauseOf "f" "(define (f) '(system))"] `shouldBe` []

    it "sees a clause calling another clause as grounded" $
      gate schemeVocabulary [ clauseOf "a" "(define (a x) (b x))"
                            , clauseOf "b" "(define (b x) x)" ] `shouldBe` []

    it "accepts a constant clause, which is what a stated number becomes" $
      gate schemeVocabulary [clauseOf "daily-limit" "(define daily-limit 14)"]
        `shouldBe` []

    it "refuses a body that is not a definition" $
      gate schemeVocabulary [clauseOf "f" "(emit \"now\")"]
        `shouldSatisfy` any isNotADefinition

    it "refuses a definition whose name is not the clause's own" $
      gate schemeVocabulary [clauseOf "f" "(define (g x) x)"]
        `shouldSatisfy` any isNotADefinition

    it "refuses an internal definition, so one clause is one definition" $
      gate schemeVocabulary [clauseOf "f" "(define (f x) (define y x) y)"]
        `shouldSatisfy` (/= [])

    it "reports a clause no program line caused" $
      gate schemeVocabulary [clauseNowhere "f" "(define (f x) x)"]
        `shouldBe` [Unprovenanced "f"]

    it "reports the contracts the core reaches, and nothing more" $
      map cName (reachedContracts schemeVocabulary logscanClauses)
        `shouldBe` ["die", "emit", "end-of-input?", "field-name", "field-of", "field-value", "json-parse", "read-a-line", "string-cut"]

    it "reports four effect contracts: the whole reach of logscan into the world" $
      map cName (filter ((== Effect) . cKind) (reachedContracts schemeVocabulary logscanClauses))
        `shouldBe` ["die", "emit", "end-of-input?", "read-a-line"]

  -- A clause is a decision, so realize assembles the core the same way it
  -- assembles a module: resolve, then project. Order is the program's own and
  -- every definition names the line that caused it.
  describe "realize clauses (a clause is a decision, not baked source)" $ do
    it "assembles clause decisions in source-line order, with provenance" $
      realizeClausesOf
        [ clauseDecision "c2" "keep" "(define (keep x) x)" (FromSource (SourceLoc "p.lips" 2))
        , clauseDecision "c1" "main" "(define (main a) (keep a))" (FromSource (SourceLoc "p.lips" 1))
        ]
        `shouldBe` Right (Just (T.concat
          [ ";; @from p.lips:1\n(define (main a) (keep a))\n"
          , "\n;; @from p.lips:2\n(define (keep x) x)\n" ]))

    it "returns nothing for a program that states no clauses" $
      realizeClausesOf [(mk "g1" "services" "true" Stated)] `shouldBe` Right Nothing

    -- A minted clause is DERIVED (a rule emitted it), so its own provenance
    -- names a rule. The program lines are its parents', which is what makes the
    -- chain a proof tree over sentences rather than over rules.
    it "walks a derived clause back to the program line behind it" $
      realizeClausesOf
        [ (mk "p1" "filter.logic" "keep matching lines" Stated)
            { dProv = FromSource (SourceLoc "logscan.lips" 2) }
        , clauseDecision "c1" "keep" "(define (keep x) x)"
            (Derived [DecisionId "p1"] (RuleId "r1"))
        ]
        `shouldBe` Right (Just ";; @from logscan.lips:2\n(define (keep x) x)\n")

    it "refuses a core whose clause reaches a name no contract grounds" $
      realizeClausesOf
        [ clauseDecision "c1" "sneaky" "(define (sneaky p) (system p))"
            (FromSource (SourceLoc "p.lips" 1)) ]
        `shouldSatisfy` either (const True) (const False)

    it "refuses an assertion that is not an s-expression at all" $
      realizeClausesOf
        [ clauseDecision "c1" "keep" "\"just a string\"" (FromSource (SourceLoc "p.lips" 1)) ]
        `shouldSatisfy` either (const True) (const False)

  -- Which runtime a clause set runs on is a computation over data, never a
  -- choice a model makes: the contracts are derived from the clauses, the
  -- properties are stated by the author, and the catalogue says who covers both.
  describe "runtime covering (Lips.Kernel.Clause.Catalogue)" $ do
    let guile = Runtime "guile" ["native", "fast-start"]
                        ["emit", "json-parse", "read-a-line"] ["guile", "guile-json"]
                        ["adapter-pure.scm"] ["adapter-effects-memory.scm"]
        hoot = Runtime "hoot" ["browser"] ["emit", "json-parse"] ["guile-hoot"]
                       ["adapter-pure.scm"] []

    it "reads a runtime declaration" $
      parseRuntime "guile" (T.unlines
        [ "property native", "provides emit json-parse", "package guile"
        , "file adapter-pure.scm", "claim-file adapter-effects-memory.scm" ])
        `shouldBe` Right (Runtime "guile" ["native"] ["emit", "json-parse"] ["guile"]
                                  ["adapter-pure.scm"] ["adapter-effects-memory.scm"])

    it "picks the one runtime covering the contracts and the properties" $
      coveringRuntime [guile, hoot] ["emit", "json-parse"] ["native"] `shouldBe` Right guile

    it "fails naming the contract nothing provides" $
      coveringRuntime [guile, hoot] ["talk-to-serial-port"] []
        `shouldSatisfy` either (T.isInfixOf "talk-to-serial-port") (const False)

    it "fails naming the property nothing has" $
      coveringRuntime [guile] ["emit"] ["browser"]
        `shouldSatisfy` either (T.isInfixOf "browser") (const False)

    -- Deduce-or-fail: an author adding one requirement is cheaper than lips
    -- choosing wrong and nobody noticing which runtime they got.
    it "fails listing the candidates when several cover, rather than choosing" $
      coveringRuntime [guile, hoot] ["emit"] []
        `shouldSatisfy` either (\e -> T.isInfixOf "guile" e && T.isInfixOf "hoot" e)
                               (const False)

    it "ships a guile runtime that covers what the logscan core reaches" $
      coveringRuntime [guileRuntime] (map cName (reachedContracts schemeVocabulary logscanClauses)) []
        `shouldBe` Right guileRuntime

-- | The subjects a crystallized base holds, in SOURCE-LINE order (the base is a
-- set keyed by id, so its own order is not the program's).
subjectsOf :: Base -> [[Text]]
subjectsOf b = [ segs | d <- sortOn lineOf (toList b), let Subject segs = dSubject d ]
  where
    lineOf d = case dProv d of
      FromSource (SourceLoc _ n) -> n
      _                          -> 0

isLeft :: Either a b -> Bool
isLeft = either (const True) (const False)

isRight :: Either a b -> Bool
isRight = either (const False) (const True)

-- Generators for the round-trip property. Tokens avoid the delimiters of the
-- canonical form; assertions deliberately include quotes and backslashes to
-- exercise escaping.
instance Arbitrary Decision where
  arbitrary = do
    i    <- safeToken
    -- Segments may carry a dot (a value-keyed key like a route path), so the
    -- reader/renderer round-trip is exercised on the escaping codec, not just
    -- dot-free idents.
    segs <- resize 3 (listOf1 subjSeg)
    k    <- elements [minBound .. maxBound]
    a    <- assertionText
    s    <- elements [minBound .. maxBound]
    p    <- genProv
    r    <- oneof [pure Nothing, Just <$> rationaleText]
    pure (Decision (DecisionId i) (Subject segs) k (Assertion a) s p r)

safeToken :: Gen Text
safeToken = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_"))

-- | A subject segment: a plain token, sometimes carrying a dot or slash (a
-- value-keyed key), so the canonical dotted-path codec is tested for real.
subjSeg :: Gen Text
subjSeg = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_./"))

assertionText :: Gen Text
assertionText = T.pack <$> listOf (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ " .,\"\\/()@:!"))

rationaleText :: Gen Text
rationaleText = T.unwords <$> listOf1 safeToken

-- A canonical value: no empty or adjacent literal pieces, literal text over a
-- Nix-safe alphabet that still exercises escaping (quotes, backslashes, ${).
genValue :: Gen Value
genValue = sized go
  where
    go n = frequency
      [ (3, VStr  <$> (canon <$> resize n (listOf genPiece)))
      , (1, VList <$> resize (n `div` 3) (listOf (go (n `div` 3))))
      , (2, VBool <$> arbitrary)
      , (2, VInt  <$> arbitrary)
      , (1, pure VNull)
      , (1, VFloat <$> elements [0.0, 1.5, 3.14, -2.5, 100.0, 0.25])
      , (1, VPath  <$> genPath)
      , (2, VHole  <$> elements [HInt, HBool, HFloat, HPath, HPkg] <*> genHole)
      , (1, VRef   <$> oneof [ RPkg . ("pkgs" :) <$> listOf1 refSeg, RArt <$> refSeg ])
      , (2, VAttr  <$> resize (n `div` 3) (listOf1 ((,) <$> genAttrKey <*> go (n `div` 3))))
      , (1, pure (VTail Nothing "value"))
      , (1, VTail <$> pure (Just HPkg) <*> pure "value")
      ]
    genPath = do
      pre  <- elements ["/", "./", "../"]
      segs <- listOf1 (T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_-")))
      pure (pre <> T.intercalate "/" segs)
    genPiece = oneof [ PLit <$> litText, PRef <$> genRef, PHole <$> genHole ]
    litText  = T.pack <$> listOf1 (elements litAlphabet)
    litAlphabet = ['a' .. 'z'] ++ ['0' .. '9'] ++ " \"\\${}.:/-_"
    genRef   = ("pkgs" :) <$> listOf1 refSeg
    refSeg   = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "-_"))
    genHole  = oneof [ pure "value", (\i -> "value." <> T.pack (show i)) <$> choose (1 :: Int, 9) ]
    -- A bare Nix attribute name: starts with a letter or '_', then the ident
    -- alphabet (incl. '-' and "'"), matching Realize's isBareIdent so an
    -- attrset key and a path segment accept the SAME key shapes.
    genAttrKey = do
      h <- elements (['a' .. 'z'] ++ "_")
      t <- listOf (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_-'-"))
      pure (T.pack (h : t))

-- Canonicalize a piece list the way parseValue would read it back: drop empty
-- literals and merge adjacent ones.
canon :: [Piece] -> [Piece]
canon = merge . filter notEmpty
  where
    notEmpty (PLit t) = not (T.null t)
    notEmpty _        = True
    merge (PLit a : PLit b : rest) = merge (PLit (a <> b) : rest)
    merge (p : rest)               = p : merge rest
    merge []                       = []

-- A segment containing a literal '.', the shape that breaks a naive dot
-- split. Includes a hyphen and a slash so the round-trip covers the attr-of
-- keys a model realistically writes (a route path, a dotted filename).
dottedSeg :: Gen Text
dottedSeg = do
  a <- listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_-"))
  b <- listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_-"))
  pure (T.pack (a ++ "." ++ b))

-- A one-emit rule whose path carries a dotted segment, to drive the storage
-- round-trip parseRuleBody . renderRuleBody == id over the failing shape.
dottedPathRule :: Text -> MapRule
dottedPathRule seg =
  MapRule "r" Fact ["x"] [ Emit ["services", "nginx", seg, "proxyPass"] (VStr [PHole "value"]) ]

-- Program text that fills a hole: includes exactly the characters the escape
-- must neutralize. Excludes '<', whose re-parse asymmetry is a known,
-- Nix-harmless value-language quirk (see the report to the maintainer).
fillText :: Gen Text
fillText = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ " \"\\${}();.:/-_"))

-- A lowercase word that is neither a value keyword nor a number: not a value.
bareWord :: Gen Text
bareWord = suchThat (T.pack <$> listOf1 (elements ['a' .. 'z']))
                    (`notElem` ["true", "false"])

genProv :: Gen Provenance
genProv = oneof
  [ FromSource <$> (SourceLoc <$> safeFile <*> (getNonNegative <$> arbitrary))
  , Derived <$> listOf1 (DecisionId <$> safeToken) <*> (RuleId <$> safeToken)
  , FromGeneration <$> hexId
  ]
  where
    -- "gen" is the reserved source name behind the @gen: stamp, so the
    -- generator must not mint it as a file.
    safeFile = suchThat (T.pack <$> listOf (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "/._"))) (/= "gen")
    hexId = T.pack <$> listOf1 (elements (['a' .. 'f'] ++ ['0' .. '9']))

-- | An engine written the way a mint answers, so a gate test states the case in
-- the surface syntax instead of assembling records by hand. Reply format, not
-- .lang format: it is what a draft arrives in, and it is far shorter to read.
engineFromLang :: [Text] -> EngineData
engineFromLang ls = case parseEngineCandidates (T.unlines ls) of
  (errs@(_ : _), _) -> error ("test engine does not parse: " <> show errs)
  ([], cands)       -> assemble (map icItem cands)

-- | The bodies of ```<tag> … ``` fenced blocks, in order. Used to pull every
-- teaching example out of the mint prompt so the parser guard above can hold
-- it to the real grammar (Task 2 of the mint-prompt rewrite).
fencedBlocks :: Text -> Text -> [Text]
fencedBlocks tag = go . T.lines
  where
    go ls = case break (== "```" <> tag) ls of
      (_, [])        -> []
      (_, _ : rest)  -> let (body, rest') = break (== "```") rest
                        in T.unlines body : go (drop 1 rest')

-- | A rhs written the way a rule states it, for a test that cares about the
-- value's shape rather than about parsing it.
tval :: Text -> Value
tval t = case parseValue t of
  Right v -> v
  Left e  -> error (T.unpack ("test value does not parse: " <> e))

-- | Is this value an s-expression (a clause)? Stated as a helper so the test
-- reads as the property it pins rather than as a pattern match.
isSexpValue :: Value -> Bool
isSexpValue (VSexp _) = True
isSexpValue _         = False

-- | The logscan core exactly as the falsifier ran it
-- (experiments/logscan-clauses/clauses.scm), stated here so the suite pins the
-- corpus rather than a paraphrase of it.
logscanClauses :: [Clause]
logscanClauses = zipWith line [1 :: Int ..]
  [ ("main",          "(define (main args) (scan (parse-spec args)))")
  , ("parse-spec",    "(define (parse-spec args) (cond ((null? args) '()) (else (cons (parse-pair (car args)) (parse-spec (cdr args))))))")
  , ("parse-pair",    "(define (parse-pair arg) (or (string-cut arg #\\=) (die \"argument is not field=value:\" arg)))")
  , ("scan",          "(define (scan spec) (scan-line (read-a-line) spec))")
  , ("scan-line",     "(define (scan-line line spec) (cond ((end-of-input? line) 'done) ((keep? (record-of line) spec) (emit line) (scan spec)) (else (scan spec))))")
  , ("record-of",     "(define (record-of line) (or (json-parse line) (die \"line is not JSON:\" line)))")
  , ("keep?",         "(define (keep? record spec) (cond ((null? spec) #t) ((field-equals? record (field-name (car spec)) (field-value (car spec))) (keep? record (cdr spec))) (else #f)))")
  , ("field-equals?", "(define (field-equals? record name value) (equal? (field-of record name) value))")
  ]
  where line n (nm, body) = (clauseOf nm body) { clFrom = [SourceLoc "logscan.lips" n] }

-- | A clause with provenance, as realize builds one from a decision.
clauseOf :: Text -> Text -> Clause
clauseOf name body = case Sx.parseSexp body of
  Left e  -> error ("test clause does not parse: " <> T.unpack e)
  Right x -> Clause name x [SourceLoc "test.lips" 1]

-- | A clause no program line caused: what the gate must refuse.
clauseNowhere :: Text -> Text -> Clause
clauseNowhere name body = (clauseOf name body) { clFrom = [] }

isNotADefinition :: GateFault -> Bool
isNotADefinition (NotADefinition _ _) = True
isNotADefinition _                    = False

-- | A decision a rule emitted to clause.<name>, as realize sees it.
clauseDecision :: Text -> Text -> Text -> Provenance -> Decision
clauseDecision i name body prov =
  (mk i "clause" body Stated)
    { dSubject = Subject ["clause", name], dKind = Meta, dProv = prov }

realizeClausesOf :: [Decision] -> Either RealizeError (Maybe Text)
realizeClausesOf = realizeClauses (const Replace) noAssembly schemeVocabulary . fromList

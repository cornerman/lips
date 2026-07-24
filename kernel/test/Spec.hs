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

import Test.Hspec
import Test.QuickCheck hiding (Confidence)

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader
import Lips.Kernel.Realize
import Lips.Kernel.Refine
import Lips.Kernel.Run
import Lips.Kernel.Engine.Data
import Lips.Kernel.Engine.Value
import Lips.Kernel.OptionType
import Lips.Nix.Options
import Lips.Nix.Target
import Lips.Generate.Args (parseGenerate)
import Lips.Generate.Harness
import Lips.Generate.Minting (parseEngineCandidates, assemble, expectsOf, sourcesOf, uncheckableExpects, EngineItem (..), ItemCandidate (..), SourceFile (..), systemPrompt, systemPromptFor, promptWithDirection)
import Lips.Generate.PiJson (PiReply (..), parsePiReply)
import Lips.Kernel.Expect
import Lips.Generate.Record (genId, record)
import Lips.Kernel.Lang.Pattern
import Lips.Kernel.Lang.Crystallize
import Lips.Kernel.Lang.Diagnose
import Lips.Kernel.Lang.Store
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

main :: IO ()
main = hspec $ do
  describe "generate argument parsing (--target, --confidence, model)" $ do
    it "defaults target to nixos, confidence to the default, renew off" $
      parseGenerate 0.7 ["ledger.backup.lips"]
        `shouldBe` Just (Nixos, 0.7, False, Nothing, ["ledger.backup.lips"])
    it "reads --target home-manager in any position" $
      parseGenerate 0.7 ["--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (HomeManager, 0.7, False, Nothing, ["a.backup.lips"])
    it "rejects an unknown target" $
      parseGenerate 0.7 ["--target", "darwin", "a.backup.lips"] `shouldBe` Nothing
    it "keeps model detection and multiple programs" $
      parseGenerate 0.7 ["anthropic/claude", "a.backup.lips", "b.backup.lips"]
        `shouldBe` Just (Nixos, 0.7, False, Just "anthropic/claude", ["a.backup.lips", "b.backup.lips"])
    it "combines --target and --confidence" $
      parseGenerate 0.7 ["--confidence", "0.9", "--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (HomeManager, 0.9, False, Nothing, ["a.backup.lips"])
    it "reads --renew in any position" $ do
      parseGenerate 0.7 ["--renew", "a.backup.lips"]
        `shouldBe` Just (Nixos, 0.7, True, Nothing, ["a.backup.lips"])
      parseGenerate 0.7 ["a.backup.lips", "--renew"]
        `shouldBe` Just (Nixos, 0.7, True, Nothing, ["a.backup.lips"])

  describe "realization target (Lips.Nix.Target)" $ do
    it "parses the two world slugs and rejects others" $ do
      parseTarget "nixos" `shouldBe` Just Nixos
      parseTarget "home-manager" `shouldBe` Just HomeManager
      parseTarget "darwin" `shouldBe` Nothing
    it "slug round-trips through parse for every target" $
      mapM_ (\t -> parseTarget (T.unpack (targetSlug t)) `shouldBe` Just t)
            [minBound .. maxBound]
    it "defaults to nixos" $
      defaultTarget `shouldBe` Nixos

  describe "merge (spec 2.1: strength) " $ do
    it "delta-over-defaults: Stated overrides Default on the same subject" $ do
      let base = fromList [mk "d1" "cadence" "daily" Default, mk "d2" "cadence" "hourly" Stated]
      resolve base `shouldSatisfy` \r -> case r of
        Right m -> winnerAssertion (Subject ["cadence"]) m == Just (Assertion "hourly")
        Left _  -> False

    it "Law overrides Stated" $ do
      let base = fromList [mk "d1" "x" "a" Stated, mk "d2" "x" "b" Law]
      case resolve base of
        Right m -> winnerAssertion (Subject ["x"]) m `shouldBe` Just (Assertion "b")
        Left _  -> expectationFailure "expected a winner, got conflict"

    it "distinct subjects coexist without competing" $ do
      let base = fromList [mk "d1" "a" "1" Stated, mk "d2" "b" "2" Stated]
      case resolve base of
        Right m -> Map.size m `shouldBe` 2
        Left _  -> expectationFailure "distinct subjects must not conflict"

  describe "agreement (spec 2: set semantics)" $
    it "equal strength, equal assertion: one winner, no conflict" $ do
      let base = fromList [mk "d1" "x" "same" Stated, mk "d2" "x" "same" Stated]
      case resolve base of
        Right m -> Map.size m `shouldBe` 1
        Left _  -> expectationFailure "agreeing decisions must not conflict"

  describe "conflict (spec 2.2)" $ do
    it "equal strength, differing assertion: conflict carrying both provenances" $ do
      let d1 = mk "d1" "x" "a" Stated
          d2 = mk "d2" "x" "b" Stated
      case resolve (fromList [d1, d2]) of
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
        resolve (fromList perm) === resolve (fromList pool)

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
            [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-m31 via ingest"
            , "  services.ledger.enable = true;"
            , "  # ledger:2"
            , "  systemd.timers.ledger.timerConfig.OnCalendar = \"daily\";"
            , "}"
            ]
      realize (fromList ground) `shouldBe` Right expected

    it "refuses to realize a base with a conflict" $ do
      let clash = [mk "a" "x" "true" Stated, mk "b" "x" "false" Stated]
      realize (fromList clash) `shouldSatisfy` isLeft

    -- A value-keyed segment (e.g. a route path) is often not a bare Nix
    -- identifier, so it must be string-quoted in the emitted attribute path;
    -- plain identifier segments stay unquoted (existing engines unchanged).
    it "quotes an option-path segment that is not a bare Nix identifier" $ do
      let g = (mk "g" "x" "\"world\"" Stated)
                { dSubject = Subject ["environment", "etc", "httpserver/hello", "text"] }
      case realize (fromList [g]) of
        Right out -> out `shouldSatisfy`
                       T.isInfixOf "environment.etc.\"httpserver/hello\".text = \"world\";"
        Left e    -> expectationFailure ("unexpected realize error: " ++ show e)

    it "is order-independent (deterministic output)" $
      property $ forAll (shuffle ground) $ \perm ->
        realize (fromList perm) === realize (fromList ground)

    it "gathers artifact.<name> groups into a let-bound derivation" $ do
      let arts =
            [ (mk "b" "x" "\"rustPlatform.buildRustPackage\"" Stated) { dSubject = Subject ["artifact","myserver","builder"] }
            , (mk "p" "x" "\"myserver\"" Stated) { dSubject = Subject ["artifact","myserver","args","pname"] }
            , (mk "s" "x" "./ledger.artifacts/myserver" Stated) { dSubject = Subject ["artifact","myserver","args","src"] }
            , (mk "e" "x" "\"${artifact.myserver}/bin/myserver\"" Stated) { dSubject = Subject ["systemd","services","myserver","serviceConfig","ExecStart"], dProv = FromSource (SourceLoc "app" 1) }
            ]
          expected = T.unlines
            [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "let"
            , "  artifact = {"
            , "    myserver = pkgs.rustPlatform.buildRustPackage {"
            , "      pname = \"myserver\";"
            , "      src = ./ledger.artifacts/myserver;"
            , "    };"
            , "  };"
            , "in"
            , "{"
            , "  # app:1"
            , "  systemd.services.myserver.serviceConfig.ExecStart = \"${artifact.myserver}/bin/myserver\";"
            , "}"
            ]
      realize (fromList arts) `shouldBe` Right expected

    it "fails loud (typed, not a crash) on a ${artifact.<name>} reference to an undefined artifact" $
      let dangling = [ (mk "e" "x" "\"${artifact.ghost}/bin/x\"" Stated) { dSubject = Subject ["systemd","services","x","serviceConfig","ExecStart"] } ]
       in realize (fromList dangling) `shouldBe` Left (RDangling ["ghost"])

    it "detects a bare artifact.<name> reference used as a list element" $ do
      -- systemPackages is a list of derivations; a bare `artifact.weather`
      -- element must be found (built, not dangling) even without ${...}.
      let built =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","weather","builder"] }
            , (mk "p" "x" "\"weather\"" Stated) { dSubject = Subject ["artifact","weather","args","pname"] }
            , (mk "e" "x" "[ artifact.weather ]" Stated) { dSubject = Subject ["environment","systemPackages"] }
            ]
      realize (fromList built) `shouldSatisfy` isRight
      -- a bare ref to an unbuilt artifact still fails loud
      let dangling = [ (mk "e" "x" "[ artifact.ghost ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realize (fromList dangling) `shouldBe` Left (RDangling ["ghost"])
      -- the literal token "artifact." inside a string is NOT a reference
      let litText = [ (mk "e" "x" "\"see artifact.ghost docs\"" Stated) { dSubject = Subject ["environment","variables","NOTE"] } ]
      realize (fromList litText) `shouldSatisfy` isRight
      -- a package path whose OWN segment is `artifact` is not a reference:
      -- `artifact.` must match only at a token boundary, never mid-path.
      let pkgPath = [ (mk "e" "x" "pkgs.foo.artifact.bar" Stated) { dSubject = Subject ["services","x","package"] } ]
      realize (fromList pkgPath) `shouldSatisfy` isRight
      let pkgList = [ (mk "e" "x" "[ pkgs.foo.artifact.bar ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realize (fromList pkgList) `shouldSatisfy` isRight

    it "fails loud (typed) on a malformed artifact group (no builder)" $
      let noBuilder = [ (mk "p" "x" "\"srv\"" Stated) { dSubject = Subject ["artifact","srv","args","pname"] } ]
       in realize (fromList noBuilder) `shouldBe` Left (RBadArtifact "srv" "no builder")

  describe "run pipeline (spec 5: four outcomes)" $ do
    -- an engine: one rule mapping any Oblige to a ground option assignment
    let engine = [ Rule (RuleId "ingest") ((== Oblige) . dKind)
                     (\_ -> Right [ (mk "x" "x" "true" Stated) { dSubject = Subject ["services", "ledger", "enable"], dKind = Meta } ]) ]
        needs subj = [ Demand "q" ("need " <> T.intercalate "." subj) (any ((== Subject subj) . dSubject) . toList) ]
        prog = "o1 oblige feed.ingest stated \"row->txn\" @ledger:9\n"

    it "parse rejection: a malformed line re-enters generate" $
      run 100 engine [] "this line has no quoted assertion"
        `shouldSatisfy` \r -> case r of Left (ParseRejected _) -> True; _ -> False

    it "open question: an unmet demand is surfaced verbatim" $
      run 100 engine (needs ["currency"]) prog
        `shouldBe` Left (OpenQuestions ["need currency"])

    it "conflict: equal-strength contradiction stops the run" $
      run 100 engine [] "d1 fact x stated \"1\" @f:1\nd2 fact x stated \"2\" @f:2\n"
        `shouldSatisfy` \r -> case r of Left (Conflicted _) -> True; _ -> False

    it "unmapped: an obligation no rule maps fails loud (anti-MDA guard)" $
      run 100 engine (needs ["feed", "ingest"])
        "o1 oblige feed.ingest stated \"rows\" @l:9\nx1 invariant feed.dedup stated \"never twice\" @l:10\n"
        `shouldSatisfy` \r -> case r of Left (Unmapped ds) -> map dSubject ds == [Subject ["feed", "dedup"]]; _ -> False

    it "realization: a satisfied program refines and realizes to a module" $ do
      let expected = T.unlines
            [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-o1 via ingest"
            , "  services.ledger.enable = true;"
            , "}"
            ]
      run 100 engine (needs ["feed", "ingest"]) prog `shouldBe` Right expected

    it "a concept line is decorative: it neither fails Unmapped nor realizes" $ do
      -- A heading like "http routes:" crystallizes to a 'Concept': vocabulary
      -- that groups and explains the lines under it, with no obligation to
      -- realize. It must not trip the anti-MDA guard, and must not leak into
      -- the module as an option assignment.
      let withHeading = "h1 concept http.routes stated \"routes\" @prog:1\n" <> prog
          expected = T.unlines
            [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            , "{"
            , "  # <-o1 via ingest"
            , "  services.ledger.enable = true;"
            , "}"
            ]
      run 100 engine [] withHeading `shouldBe` Right expected

  describe "generate minting (engine-synthesis plan: whole-engine candidates)" $ do
    it "parses the three item forms and assembles an engine" $ do
      let reply = T.unlines
            [ "0.95 p1 pattern the bank drops files into <loc> => fact feed.source stated \"<loc>\""
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

    it "a pattern template may begin with a dispatch keyword (no collision)" $ do
      -- Regression (kernel review): a loose line starting with a domain word
      -- like "match" must mint as a pattern, not be misrouted to the rule
      -- parser. The leading 'pattern' keyword makes the kind explicit.
      let reply = "0.95 p1 pattern match <a> to <b> => fact link.p stated \"<a> <b>\""
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      case map icItem cs of
        [ItemPattern _] -> pure ()
        other           -> expectationFailure ("expected one pattern, got " ++ show other)

    it "skips fences and comments, collects malformed lines as errors" $ do
      let reply = T.unlines
            [ "```", "# note", ""
            , "0.9 p1 pattern every bank row becomes one <e> => oblige feed.ingest stated \"<e>\""
            , "2.0 p2 pattern x => fact y stated \"z\""   -- confidence out of range
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

  describe "pattern matching (crystallization plan: normalization, holes)" $ do
    it "normalizes case and strips trailing sentence punctuation" $ do
      normalizeToken "Files." `shouldBe` "files"
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
                Fact Stated [SLit "feed.source"] [SHole "loc"]
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

  describe "crystallize (crystallization plan: three outcomes)" $ do
    let sourceP = patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                    Fact Stated [SLit "feed.source"] [SHole "loc"]
        obligeP = patOne "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
                    Oblige Stated [SLit "feed.ingest"] [SLit "every bank row becomes one ", SHole "e"]

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
      let a = patOne "a" [THole "x", TLit "hour"] Fact Stated [SLit "feed.cadence"] [SHole "x"]
          b = patOne "b" [TLit "every", THole "y"] Fact Stated [SLit "feed.cadence"] [SHole "y"]
      crystallize "prog" [a, b] "every hour"
        `shouldBe` Left [Overlapping 1 ["a", "b"]]

    it "skips comment and blank lines" $ do
      let src = "# a language\n\nthe bank drops files into inbox/.\n"
      fmap (map dId . toList) (crystallize "prog" [sourceP] src) `shouldBe` Right [DecisionId "d3"]

    it "hole re-instantiation always crystallizes (edit-tolerance by construction)" $ do
      let setP = patOne "set" [TLit "set", THole "k", TLit "to", THole "v"]
                   Fact Stated [SLit "cfg.", SHole "k"] [SHole "v"]
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
                     Fact Stated [SLit "route.", SHole "path", SLit ".body"] [SHole "body"]
      case crystallize "prog" [routeP] "- /file.json is x" of
        Right b -> map dSubject (toList b) `shouldBe` [Subject ["route", "/file.json", "body"]]
        Left e  -> expectationFailure ("unexpected crystallize error: " ++ show e)

    it "captures a quoted multi-word value into a bulleted route (gap 2)" $ do
      let routeP = patOne "pr" [TLit "-", THole "path", TLit "returns", TLit "text", THole "body"]
                     Fact Stated [SLit "route.", SHole "path"] [SHole "body"]
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
    let denseP = Pattern "p1"
                   [ TLit "http", TLit "server", TLit "in", THole "lang"
                   , TLit "on", TLit "port", THole "port" ]
                   [ PatEmit Steer Stated [SLit "server.language"] [SHole "lang"]
                   , PatEmit Fact  Stated [SLit "http.port"]       [SHole "port"] ]
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
      case crystallize "prog" [patOne "p" [TLit "port", THole "n"] Fact Stated [SLit "http.port"] [SHole "n"]] "port 8080" of
        Right b -> map dId (toList b) `shouldBe` [DecisionId "d1"]
        Left e  -> expectationFailure ("unexpected crystallize error: " ++ show e)

    it "a multi-emit pattern round-trips through the .lang store" $
      roundTrip denseP `shouldBe` Right denseP

    it "an assertion containing '; ' is not mis-split into a second emit" $ do
      let p = patOne "p" [TLit "note", THole "x"] Fact Stated [SLit "n"] [SLit "a ; b ", SHole "x"]
      roundTrip p `shouldBe` Right p

  describe "engine data (engine-synthesis plan: rules and demands as data)" $ do
    let rule = MapRule "r2" Fact ["feed", "cadence"]
                 [ Emit ["systemd", "timers", "t", "OnCalendar"] (VStr [PHole "value"]) ]

    it "rule body round-trips" $
      parseRuleBody "r2" (renderRuleBody rule) `shouldBe` Right rule

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

    it "bindSelf leaves a rule without <self> untouched" $
      bindSelf "ledger" rule `shouldBe` rule

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

    -- End to end: two routes in one program, each keyed by its own path, flow
    -- through crystallize -> refine -> realize into two DISTINCT keyed options
    -- (the collision the value-keyed-options gap caused is gone).
    it "end to end: two routes fan out to two path-keyed options" $ do
      let routeP = Pattern "pr"
                     [ TLit "-", THole "path", TLit "=>", TLit "status", THole "code" ]
                     [ PatEmit Fact Stated [SLit "route.", SHole "path", SLit ".status"] [SHole "code"] ]
          routeRule = MapRule "r" Fact ["route", "<path>", "status"]
                   [ Emit ["environment", "etc", "<path>", "text"] (VStr [PHole "value"]) ]
          prog = "- /hello => status 200\n- /bye => status 404"
      case crystallize "prog" [routeP] prog of
        Left e     -> expectationFailure ("crystallize: " ++ show e)
        Right base -> case refine 100 [toRule routeRule] base of
          Left e       -> expectationFailure ("refine: " ++ show e)
          Right ground -> case realize ground of
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
      fillValue (const (Right "x")) (VList [VRef (RArt "weather")]) `shouldBe` Right "[ artifact.weather ]"

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

  describe "language storage (crystallization plan: .lang round-trip)" $ do
    let engine = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                  Fact Stated [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
                  Oblige Stated [SLit "feed.ingest"] [SLit "every bank row becomes one ", SHole "e"]
              ]
          , edRules =
              [ MapRule "r1" Oblige ["feed", "ingest"]
                  [ Emit ["services", "x", "enable"] (VBool True) ] ]
          , edDemands = [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?" ]
          }

    it "round-trips the whole engine: readLang . renderLang == Right" $
      readLang (renderLang (FromGeneration "cafe0123") engine) `shouldBe` Right engine

    it "rejects an unrecognized engine line loudly (never silently dropped)" $ do
      -- Regression (kernel review): a mistyped group subject must fail, not be
      -- quietly ignored (which would lose a rule and mislead a later run).
      let bad = "r1 meta engine.rulez.r1 stated \"match oblige a => b.c \\\"true\\\"\" @gen:x\n"
      readLang bad `shouldSatisfy` isLeft

    it "anchors a body parse error to its real source line, not line 0" $ do
      -- Regression (kernel review): readLang lost the line number for body
      -- sub-grammar errors. Line 2 here carries a malformed rule body.
      let src = T.unlines
            [ "p1 meta lang.pattern.p1 stated \"x => fact y stated \\\"z\\\"\" @gen:x"
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
      let r  = record "m" Nixos 0.7 "sp" "prog" "reply"
          r' = record "m" Nixos 0.7 "sp" "prog" "reply2"
          rc = record "m" Nixos 0.5 "sp" "prog" "reply"
          rt = record "m" HomeManager 0.7 "sp" "prog" "reply"
      genId r `shouldBe` genId r
      genId r `shouldNotBe` genId r'
      -- the confidence threshold is pinned: changing it changes the id
      genId r `shouldNotBe` genId rc
      -- the target world is pinned: changing it changes the id
      genId r `shouldNotBe` genId rt
      T.length (genId r) `shouldBe` 16
    it "writes the target slug into the record text" $
      record "m" HomeManager 0.7 "sp" "prog" "reply"
        `shouldSatisfy` T.isInfixOf "target: home-manager"

    it "reads a hole with glued trailing punctuation: '<when>.' binds <when>" $
      case parsePatternBody "p9" "back up <src> every <when>. => fact backup.job stated \"<src> <when>\"" of
        Right p -> pTemplate p `shouldBe`
          [TLit "back", TLit "up", THole "src", TLit "every", THole "when"]
        Left e  -> expectationFailure (T.unpack e)

    it "reads a quoted hole \"<body>\" in a template as a capturing hole (gap 2)" $
      case parsePatternBody "pr" "- <path> returns text \"<body>\" => fact route.text stated \"<path> <body>\"" of
        Right p -> pTemplate p `shouldBe`
          [TLit "-", THole "path", TLit "returns", TLit "text", THole "body"]
        Left e  -> expectationFailure (T.unpack e)

    it "splits on the LAST unquoted => so a template may itself contain => (route arrow)" $
      case parsePatternBody "pr2" "- <path> => status <code> \"<body>\" => fact route.<path> stated \"<path> <code> <body>\"" of
        Right p -> do
          pTemplate p `shouldBe`
            [TLit "-", THole "path", TLit "=>", TLit "status", THole "code", THole "body"]
          pEmits p `shouldBe` [PatEmit Fact Stated [SLit "route.", SHole "path"] [SHole "path", SLit " ", SHole "code", SLit " ", SHole "body"]]
        Left e  -> expectationFailure (T.unpack e)

    it "rejects a pattern whose target hole is not bound by the template" $ do
      let bad = (patternToDecision (patOne "p1" [THole "loc"] Fact Stated [SLit "feed.source"] [SHole "loc"]))
                  { dAssertion = Assertion "<loc> => fact feed.source stated \"<missing>\"" }
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
                  Fact Stated [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
                  Fact Stated [SLit "feed.cadence"] [SHole "sched"]
              , patOne "p3" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "exactly", TLit "one", THole "rec"]
                  Oblige Stated [SLit "feed.ingest"] [SHole "rec"]
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
            (runBase 10000 (map toRule (edRules eng)) (map toDemand (edDemands eng)) base)
        moduleWith inbox oncal = T.unlines
          [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
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
          runBase 10000 (map toRule (edRules feedEngine)) (map toDemand (edDemands feedEngine)) base
            `shouldBe` Left (OpenQuestions ["where do the files arrive?"])

  -- Authoring diagnostics: the pure (language, program) view a human/editor
  -- reads (editor-tooling milestone, first rung). One shared matcher with
  -- crystallize, so a diagnostic never disagrees with what run would do.
  describe "diagnose (authoring view over .lang, pure)" $ do
    let eng = EngineData
          { edPatterns =
              [ patOne "p1" [TLit "the", TLit "bank", TLit "drops", TLit "csv", TLit "files", TLit "into", THole "loc"]
                  Fact Stated [SLit "feed.source"] [SHole "loc"]
              , patOne "p2" [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
                  Fact Stated [SLit "feed.cadence"] [SHole "sched"]
              ]
          , edRules = []
          , edDemands =
              [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?"
              , DemandSpec "q2" ["feed", "cadence"] "how often does the feed deliver?"
              ]
          }

    it "reports a matched line with the pattern it used and the decision it yields" $ do
      let d = diagnose "f" eng "the bank drops csv files into inbox/."
      diagMatched d `shouldBe` 1
      diagTotal d `shouldBe` 1
      case diagLines d of
        [Matched 1 _ "p1" [dec]] -> dSubject dec `shouldBe` Subject ["feed", "source"]
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

    it "derives one completion snippet per pattern, holes as numbered tab-stops" $
      case completionItems (edPatterns eng) of
        (i0 : i1 : _) -> do
          map ciLabel [i0, i1] `shouldBe`
            [ "the bank drops csv files into <loc>"
            , "the bank delivers new files every <sched>" ]
          ciSnippet i0 `shouldBe` "the bank drops csv files into ${1:loc}"
        _ -> expectationFailure "expected two completion items"

    it "derives an error diagnostic on a line that escapes the language" $ do
      let ds = diagsOf (diagnose "f" eng "encrypt everything at rest.")
      case [x | x <- ds, dgSeverity x == 1] of
        (x : _) -> dgLine x `shouldBe` 0   -- 0-based line of the sole (bad) line
        []      -> expectationFailure "expected an error diagnostic"

    it "derives a warning diagnostic for each open question" $ do
      let ds = diagsOf (diagnose "f" eng "the bank drops csv files into inbox/.")
      map dgMessage [x | x <- ds, dgSeverity x == 2]
        `shouldBe` ["Open question: how often does the feed deliver?"]

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
        case resolve (fromList ds) of
          Left _        -> property True  -- the law constrains winners, not conflicts
          Right winners ->
            let bds = toList (fromList ds)
             in conjoin
                  [ dStrength w === maximum [ dStrength d | d <- bds, dSubject d == s ]
                  | (s, w) <- Map.toList winners ]

    it "resolve never invents or drops a subject" $
      property $ \ds ->
        case resolve (fromList ds) of
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

  -- The value language's two guarantees, as properties over generated inputs:
  -- canonical round-trip, and injection made unrepresentable.
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

    -- Grammar completeness: inside a string the value is text, so a redundant
    -- :type on a hole is meaningless and degrades to the plain hole rather
    -- than being rejected (a form the mint writes naturally for a number).
    it "a typed hole inside a string degrades to its plain form" $ do
      parseValue "\"--keep-daily <value.2:int>\"" `shouldBe` parseValue "\"--keep-daily <value.2>\""
      parseValue "\"x <value:int> y\"" `shouldBe` parseValue "\"x <value> y\""
    it "a genuinely unknown hole inside a string is still rejected" $
      parseValue "\"x <bogus> y\"" `shouldSatisfy` isLeft

  -- The system prompt is pinned into the generation id, so it is a versioned
  -- artifact; this guards its load-bearing clauses against silent drift.
  describe "generate prompt is a pinned artifact (mint doctrine)" $
    it "states its load-bearing invariants" $
      mapM_ (\clause -> systemPrompt `shouldSatisfy` T.isInfixOf clause)
        [ "act exactly once"
        , "replace EVERY program value with a hole"
        , "refusal beats invention"
        , "pure data"
        , "No functions"
        , "<value:int>"
        , "demand <subject>"
        , "expect <option.path> from <subject>"
        , "pattern|match|demand|expect|because"
        , "because-note"
        , "reserved segment <self>"
        , "same line-shape appearing in different programs is a SINGLE"
        ]

  -- The optional per-program .direction file steers mint taste. It must ride
  -- on top of the fixed prompt (so it enters genId) and carry the guard that
  -- keeps it advisory, never an obligation channel.
  describe "direction file (optional mint taste)" $ do
    it "absent or blank direction leaves the prompt untouched" $ do
      promptWithDirection Nothing Nixos `shouldBe` systemPrompt
      promptWithDirection (Just "   \n  ") Nixos `shouldBe` systemPrompt
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
      parsePiReply "" `shouldBe` PiReply "" ""

  describe "solution identity (plan 2026-07-22: <instance>.<language>.lips)" $ do
    let prog = "examples/ledger.backup.lips"
    it "reads the language before .lips and the instance before that" $ do
      languageName prog `shouldBe` "backup"
      instanceName prog `shouldBe` "ledger"
    it "the <language>.lips shorthand defaults the instance to the language" $ do
      languageName "examples/backup.lips" `shouldBe` "backup"
      instanceName "examples/backup.lips" `shouldBe` "backup"
    it "names language-level sidecars by the language, shared across instances" $ do
      langPath       prog `shouldBe` "examples/backup.lang"
      expectPath     prog `shouldBe` "examples/backup.expect"
      generationPath prog `shouldBe` "examples/backup.generation"
      langPath "examples/photos.backup.lips" `shouldBe` langPath prog
    it "names the crystal witness per instance (never collides)" $
      decisionsPath prog `shouldBe` "examples/ledger.backup.lips.decisions"

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
          [ patOne "p1" p1t Fact   Stated [SLit "feed.source"]  [SHole "loc"]
          , patOne "p2" p2t Fact   Stated [SLit "feed.cadence"] [SHole "sched"]
          , patOne "p3" p3t Oblige Stated [SLit "feed.ingest"]  [SHole "rec"]
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
        surface toks fill = T.unwords [ case t of TLit l -> l; THole _ -> fill | t <- toks ]
        runProg prog = do
          base <- either (Left . show) Right (crystallize "feed" pats prog)
          either (Left . show) Right
            (runBase 10000 (map toRule rules) (map toDemand demands) base)
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
    it "echoes exactly the bogus option in a mixed rule set (deduce-or-fail)" $ do
      let sch  = Map.fromList [ (["services", "restic", "backups", "x", "paths"], OTListOf OTString) ]
          good = optRule "r1" ["services", "restic", "backups", "x", "paths"] (VList [VStr [PHole "value"]])
          bad  = optRule "r2" ["services", "restic", "backups", "x", "nonsuch"] (VStr [PHole "value"])
      map renderOptionError (checkEmits sch [good, bad])
        `shouldBe` ["rule r2: unknown NixOS option services.restic.backups.x.nonsuch"]

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
      , (2, VHole  <$> elements [HInt, HBool, HFloat, HPath] <*> genHole)
      , (1, VRef   <$> oneof [ RPkg . ("pkgs" :) <$> listOf1 refSeg, RArt <$> refSeg ])
      , (2, VAttr  <$> resize (n `div` 3) (listOf1 ((,) <$> genAttrKey <*> go (n `div` 3))))
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

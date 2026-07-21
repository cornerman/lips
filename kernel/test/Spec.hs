{-# LANGUAGE OverloadedStrings #-}
-- Arbitrary Decision is a test-only orphan; it belongs with the suite, not the
-- library, so the orphan warning here is expected and suppressed.
{-# OPTIONS_GHC -Wno-orphans #-}

-- | Conformance tests for the kernel calculus. Each block cites the spec
-- invariant it pins (spec v2, sections 2 and 4). This is the seed of the
-- conformance suite named as the source of truth in spec section 12.
module Main (main) where

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Control.Exception (evaluate)

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
import Lips.Generate.Harness
import Lips.Generate.Minting (parseEngineCandidates, assemble, expectsOf, ItemCandidate (..), systemPrompt)
import Lips.Kernel.Expect
import Lips.Generate.Record (genId, record)
import Lips.Kernel.Lang.Pattern
import Lips.Kernel.Lang.Crystallize
import Lips.Kernel.Lang.Lang

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
          , rRewrite = \_ -> [ (mk "ignored" "row" "upsert-keyed" Stated) { dKind = Meta } ]
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
            , rRewrite = \_ -> [ (mk "again" "row" "x" Stated) { dKind = Oblige } ]
            }
      refine 10 [loop] (fromList [oblige]) `shouldBe` Left (Nonterminating 10)

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

  describe "run pipeline (spec 5: four outcomes)" $ do
    -- an engine: one rule mapping any Oblige to a ground option assignment
    let engine = [ Rule (RuleId "ingest") ((== Oblige) . dKind)
                     (\_ -> [ (mk "x" "x" "true" Stated) { dSubject = Subject ["services", "ledger", "enable"], dKind = Meta } ]) ]
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

  describe "generate harness (spec 5: deduce-or-fail, resampling)" $ do
    let cand s a conf = Candidate ((mk (s <> "-id") s a Stated)) (Confidence conf)

    it "admit: at/above threshold accepted, below demoted to open questions" $ do
      let (yes, qs) = admit (Confidence 0.9)
            [cand "a" "1" 0.95, cand "b" "2" 0.5, cand "c" "3" 0.9]
      map (\d -> case dSubject d of Subject xs -> xs) yes `shouldBe` [["a"], ["c"]]
      map (\q -> case dSubject (oqCandidate q) of Subject xs -> xs) qs `shouldBe` [["b"]]

    it "admit: a demoted candidate is phrased as a confirmable question" $
      case admit (Confidence 0.9) [cand "currency" "EUR" 0.4] of
        (_, [q]) -> renderOpenQuestion q `shouldBe` "I believe currency = EUR; confirm or correct."
        other    -> expectationFailure ("expected exactly one open question, got " ++ show other)

    it "unanimous: identical deductions across samples are forced" $ do
      let s = [mk "i1" "a" "1" Stated, mk "i2" "b" "2" Stated]
      fmap (map coreOf) (unanimous [s, s, s]) `shouldBe` Right (map coreOf s)

    it "unanimous: a deduction missing from a sample is detected ambiguity" $ do
      let s1 = [mk "i1" "a" "1" Stated, mk "i2" "b" "2" Stated]
          s2 = [mk "i1" "a" "1" Stated]
      unanimous [s1, s2]
        `shouldBe` Left [Divergence (Subject ["b"], Fact, Assertion "2", Stated)]

    it "unanimous: an empty batch forces nothing (fail loud)" $
      unanimous [] `shouldBe` (Left [] :: Either [Divergence] [Decision])

  describe "generate minting (engine-synthesis plan: whole-engine candidates)" $ do
    it "parses the three item forms and assembles an engine" $ do
      let reply = T.unlines
            [ "0.95 p1 the bank drops files into <loc> => fact feed.source stated \"<loc>\""
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

    it "skips fences and comments, collects malformed lines as errors" $ do
      let reply = T.unlines
            [ "```", "# note", ""
            , "0.9 p1 every bank row becomes one <e> => oblige feed.ingest stated \"<e>\""
            , "2.0 p2 x => fact y stated \"z\""   -- confidence out of range
            , "0.9 r9 match fact feed.x => a.b \"<mystery>\""  -- unknown emit hole
            , "```"
            ]
          (errs, cs) = parseEngineCandidates reply
      length cs `shouldBe` 1
      length errs `shouldBe` 2

  describe "behavioral contract (ledger 13: .expect relational gate)" $ do
    let dec subj a = Decision (DecisionId "d") (Subject (T.splitOn "." subj)) Fact
                       (Assertion a) Stated (FromSource (SourceLoc "p" 1)) Nothing
        base = fromList [ dec "backup.job" "/var/lib/ledger /backup/ledger daily" ]
        opt  = Subject ["backup", "job"]

    it "parse/render round-trips" $ do
      let src = "a1 expect services.restic.backups.ledger.repository from backup.job#2\n"
      (renderExpect <$> readExpect src) `shouldBe` Right src

    it "resolves the whole assertion and the nth token" $ do
      expectedValue base (Expect "a" ["o"] opt Nothing)  `shouldBe` Right "/var/lib/ledger /backup/ledger daily"
      expectedValue base (Expect "a" ["o"] opt (Just 2)) `shouldBe` Right "/backup/ledger"

    it "fails loud on an out-of-range token or a missing subject" $ do
      expectedValue base (Expect "a" ["o"] opt (Just 9))              `shouldSatisfy` isLeft
      expectedValue base (Expect "a" ["o"] (Subject ["no","x"]) Nothing) `shouldSatisfy` isLeft

    it "containment: the program value must appear in the evaluated option" $ do
      let e = Expect "a1" ["p"] opt (Just 2)
      checkValues [e] [("/backup/ledger", "\"/backup/ledger\"")] `shouldBe` []          -- exact
      checkValues [e] [("hour", "\"hourly\"")]                   `shouldBe` []          -- substring
      length (checkValues [e] [("/backup/ledger", "\"/fixed/repo\"")]) `shouldBe` 1     -- value dropped
      length (checkValues [e] [("/backup/ledger", "null")])           `shouldBe` 1     -- option relocated

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
      let p = Pattern "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                Fact Stated [SLit "feed.source"] [SHole "loc"]
      applyPattern p (Map.fromList [("loc", "inbox/")])
        `shouldBe` (Subject ["feed", "source"], Fact, Assertion "inbox/", Stated)

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
    let sourceP = Pattern "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                    Fact Stated [SLit "feed.source"] [SHole "loc"]
        obligeP = Pattern "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
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
      let a = Pattern "a" [THole "x", TLit "hour"] Fact Stated [SLit "feed.cadence"] [SHole "x"]
          b = Pattern "b" [TLit "every", THole "y"] Fact Stated [SLit "feed.cadence"] [SHole "y"]
      crystallize "prog" [a, b] "every hour"
        `shouldBe` Left [Overlapping 1 ["a", "b"]]

    it "skips comment and blank lines" $ do
      let src = "# a language\n\nthe bank drops files into inbox/.\n"
      fmap (map dId . toList) (crystallize "prog" [sourceP] src) `shouldBe` Right [DecisionId "d3"]

    it "hole re-instantiation always crystallizes (edit-tolerance by construction)" $ do
      let setP = Pattern "set" [TLit "set", THole "k", TLit "to", THole "v"]
                   Fact Stated [SLit "cfg.", SHole "k"] [SHole "v"]
      property $ forAll ((,) <$> safeToken <*> safeToken) $ \(k, v) ->
        let line = T.unwords ["set", k, "to", v]
         in case crystallize "p" [setP] line of
              Right b -> case toList b of
                [d] -> dSubject d == Subject ["cfg", k] && dAssertion d == Assertion v
                _   -> False
              Left _ -> False

    it "captures a quoted multi-word value into a bulleted route (gap 2)" $ do
      let routeP = Pattern "pr" [TLit "-", THole "path", TLit "returns", TLit "text", THole "body"]
                     Fact Stated [SLit "route.", SHole "path"] [SHole "body"]
      case crystallize "prog" [routeP] "- /hello returns text \"hello world\"" of
        Right b -> case toList b of
          [d] -> (dSubject d, dAssertion d) `shouldBe`
                   (Subject ["route", "/hello"], Assertion "hello world")
          ds  -> expectationFailure ("expected one decision, got " ++ show (length ds))
        Left e -> expectationFailure ("unexpected crystallize error: " ++ show e)

  describe "engine data (engine-synthesis plan: rules and demands as data)" $ do
    let rule = MapRule "r2" Fact ["feed", "cadence"]
                 [ Emit ["systemd", "timers", "t", "OnCalendar"] (VStr [PHole "value"]) ]

    it "rule body round-trips" $
      parseRuleBody "r2" (renderRuleBody rule) `shouldBe` Right rule

    it "demand body round-trips" $ do
      let q = DemandSpec "q1" ["feed", "source"] "where do the files arrive?"
      parseDemandBody "q1" (renderDemandBody q) `shouldBe` Right q

    it "rejects an emit with an unknown hole" $
      parseRuleBody "r" "match fact x => a.b \"\\\"<mystery>\\\"\"" `shouldSatisfy` isLeft

    -- The design event of the first live backup run, made physics: computation
    -- in an rhs must be structurally rejected, not prompt-discouraged.
    it "rejects computation in an rhs (function application is not a value)" $
      parseRuleBody "r" "match fact x => a.b \"lib.splitString \\\" \\\" <value>\"" `shouldSatisfy` isLeft

    it "rejects non-pkgs interpolation inside rhs strings" $
      parseRuleBody "r" "match fact x => a.b \"\\\"${lib.getExe pkgs.restic}\\\"\"" `shouldSatisfy` isLeft

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
      fillValue (const "/etc/ssl/cert.pem") (VHole HPath "value") `shouldBe` "/etc/ssl/cert.pem"
      fillValue (const "true")              (VHole HBool "value") `shouldBe` "true"

    it "a typed hole fails loud when the program value is the wrong type" $ do
      evaluate (T.length (fillValue (const "not-a-number") (VHole HInt "value")))
        `shouldThrow` anyErrorCall
      evaluate (T.length (fillValue (const "has space") (VHole HPath "value")))
        `shouldThrow` anyErrorCall

    it "accepts the closed value forms: string+pkgs-ref, list, bool, int" $ do
      parseValue "\"${pkgs.restic}/bin/restic backup <value.1>\"" `shouldBe`
        Right (VStr [PRef ["pkgs", "restic"], PLit "/bin/restic backup ", PHole "value.1"])
      parseValue "[ \"timers.target\" ]" `shouldBe` Right (VList [VStr [PLit "timers.target"]])
      parseValue "true" `shouldBe` Right (VBool True)
      parseValue "42" `shouldBe` Right (VInt 42)

    it "escapes filled program text: injection cannot leave the string" $
      fillValue (const "a\" ; evil ${pkgs.hack}") (VStr [PHole "value"]) `shouldBe`
        "\"a\\\" ; evil \\${pkgs.hack}\""

    it "reads and round-trips an ${artifact.<name>} reference (a name, not computation)" $ do
      parseValue "\"${artifact.myserver}/bin/myserver\"" `shouldBe`
        Right (VStr [PArt "myserver", PLit "/bin/myserver"])
      fmap renderValue (parseValue "\"${artifact.myserver}/bin/myserver\"")
        `shouldBe` Right "\"${artifact.myserver}/bin/myserver\""

    it "rejects a malformed artifact reference" $
      parseValue "\"${artifact.bad name}\"" `shouldSatisfy` isLeft

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
              [ Pattern "p1" [TLit "the", TLit "bank", TLit "drops", TLit "files", TLit "into", THole "loc"]
                  Fact Stated [SLit "feed.source"] [SHole "loc"]
              , Pattern "p2" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "one", THole "e"]
                  Oblige Stated [SLit "feed.ingest"] [SLit "every bank row becomes one ", SHole "e"]
              ]
          , edRules =
              [ MapRule "r1" Oblige ["feed", "ingest"]
                  [ Emit ["services", "x", "enable"] (VBool True) ] ]
          , edDemands = [ DemandSpec "q1" ["feed", "source"] "where do the files arrive?" ]
          }

    it "round-trips the whole engine: readLang . renderLang == Right" $
      readLang (renderLang (FromGeneration "cafe0123") engine) `shouldBe` Right engine

    it "stamps every .lang line with the generation event" $
      let stamped = renderLang (FromGeneration "cafe0123") engine
       in [ l | l <- T.lines stamped, not (T.null l), not ("@gen:cafe0123" `T.isSuffixOf` l) ]
            `shouldBe` []

    it "generation ids are deterministic and content-sensitive" $ do
      let r  = record "m" 0.7 "sp" "prog" "reply"
          r' = record "m" 0.7 "sp" "prog" "reply2"
          rc = record "m" 0.5 "sp" "prog" "reply"
      genId r `shouldBe` genId r
      genId r `shouldNotBe` genId r'
      -- the confidence threshold is pinned: changing it changes the id
      genId r `shouldNotBe` genId rc
      T.length (genId r) `shouldBe` 16

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

    it "rejects a pattern whose target hole is not bound by the template" $ do
      let bad = (patternToDecision (Pattern "p1" [THole "loc"] Fact Stated [SLit "feed.source"] [SHole "loc"]))
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
              [ Pattern "p1" [TLit "the", TLit "bank", TLit "drops", TLit "csv", TLit "files", TLit "into", THole "loc"]
                  Fact Stated [SLit "feed.source"] [SHole "loc"]
              , Pattern "p2" [TLit "the", TLit "bank", TLit "delivers", TLit "new", TLit "files", TLit "every", THole "sched"]
                  Fact Stated [SLit "feed.cadence"] [SHole "sched"]
              , Pattern "p3" [TLit "every", TLit "bank", TLit "row", TLit "becomes", TLit "exactly", TLit "one", THole "rec"]
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
        parseValue (fillValue (const t) (VStr [PHole "value"])) === Right (VStr [PLit t])

    it "a bare identifier rhs is rejected (only closed value forms parse)" $
      property $ forAll bareWord $ \w -> parseValue w `shouldSatisfy` isLeft

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
        ]

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
          [ Pattern "p1" p1t Fact   Stated [SLit "feed.source"]  [SHole "loc"]
          , Pattern "p2" p2t Fact   Stated [SLit "feed.cadence"] [SHole "sched"]
          , Pattern "p3" p3t Oblige Stated [SLit "feed.ingest"]  [SHole "rec"]
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

isLeft :: Either a b -> Bool
isLeft = either (const True) (const False)

-- Generators for the round-trip property. Tokens avoid the delimiters of the
-- canonical form; assertions deliberately include quotes and backslashes to
-- exercise escaping.
instance Arbitrary Decision where
  arbitrary = do
    i    <- safeToken
    segs <- resize 3 (listOf1 safeToken)
    k    <- elements [minBound .. maxBound]
    a    <- assertionText
    s    <- elements [minBound .. maxBound]
    p    <- genProv
    r    <- oneof [pure Nothing, Just <$> rationaleText]
    pure (Decision (DecisionId i) (Subject segs) k (Assertion a) s p r)

safeToken :: Gen Text
safeToken = T.pack <$> listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "_"))

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

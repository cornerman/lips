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

import Test.Hspec
import Test.QuickCheck hiding (Confidence)

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader
import Lips.Kernel.Realize
import Lips.Kernel.Refine
import Lips.Kernel.Run
import Lips.Engine.Data
import Lips.Engine.Value
import Lips.Generate.Harness
import Lips.Generate.Minting (parseEngineCandidates, assemble, ItemCandidate (..))
import Lips.Generate.Record (genId, record)
import Lips.Lang.Pattern
import Lips.Lang.Crystallize
import Lips.Lang.Lang

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
            ]
          (errs, cs) = parseEngineCandidates reply
      errs `shouldBe` []
      map icConfidence cs `shouldBe` map Confidence [0.95, 0.9, 0.85]
      let eng = assemble (map icItem cs)
      (length (edPatterns eng), length (edRules eng), length (edDemands eng)) `shouldBe` (1, 1, 1)

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

    it "accepts the closed value forms: string+pkgs-ref, list, bool, int" $ do
      parseValue "\"${pkgs.restic}/bin/restic backup <value.1>\"" `shouldBe`
        Right (VStr [PRef ["pkgs", "restic"], PLit "/bin/restic backup ", PHole "value.1"])
      parseValue "[ \"timers.target\" ]" `shouldBe` Right (VList [VStr [PLit "timers.target"]])
      parseValue "true" `shouldBe` Right (VBool True)
      parseValue "42" `shouldBe` Right (VInt 42)

    it "escapes filled program text: injection cannot leave the string" $
      fillValue (const "a\" ; evil ${pkgs.hack}") (VStr [PHole "value"]) `shouldBe`
        "\"a\\\" ; evil \\${pkgs.hack}\""

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

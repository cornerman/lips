{-# LANGUAGE OverloadedStrings #-}

-- | Conformance tests for the kernel calculus. Each block cites the spec
-- invariant it pins (spec v2, sections 2 and 4). This is the seed of the
-- conformance suite named as the source of truth in spec section 12.
module Main (main) where

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)

import Test.Hspec
import Test.QuickCheck

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Refine

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

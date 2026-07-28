{-# LANGUAGE OverloadedStrings #-}

-- | Static orthogonality: do two minted rules claim the same decision?
--
-- 'Lips.Kernel.Refine' already answers this dynamically -- a decision matched
-- by several rules is an 'Lips.Kernel.Refine.Overlap' error -- but only for an
-- overlap some concrete decision witnesses. Two rules whose subjects are
-- @route.\<path\>.status@ and @route.\<name\>.status@ are indistinguishable
-- for every route that could ever exist, yet a program stating no route at all
-- refines clean and the defect ships inside the engine. It then surfaces on
-- the author's machine, at compile time, in a program that did nothing wrong.
--
-- So the check belongs at the mint gate, where an engine is still rejectable,
-- and it must be static: not "did any decision hit both rules" but "could
-- any". That is the classical critical-pair question of term rewriting -- a
-- rewrite system that is non-overlapping is confluent (Rosen, /Tree-Manipulating
-- Systems and Church-Rosser Theorems/, JACM 1973) -- specialized to the shape
-- lips actually has: a rule's left-hand side is a flat, fixed-length subject
-- pattern over literals and @\<name\>@ captures, plus a kind. Two left-hand
-- sides overlap exactly when they unify.
--
-- Unification, not a position-by-position comparison, because a repeated
-- capture constrains: @x.\<a\>.\<a\>@ matches only subjects whose last two
-- segments are equal, so it does NOT overlap @x.p.q@. A positionwise check
-- would call that an overlap and reject a legitimate engine -- a false
-- rejection is as bad as a missed defect, since the mint gate must let every
-- sound engine through (deduce-or-fail cuts both ways).
--
-- The witness is the unified subject family: the most general subject both
-- rules claim, rendered with any still-open capture left as @\<name\>@. It
-- names what is actually ambiguous, which is what the model needs to fix the
-- rule it wrote.
module Lips.Kernel.Engine.Overlap
  ( RuleOverlap (..)
  , ruleOverlaps
  , subjectsUnify
  , renderRuleOverlap
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe      (isJust)
import           Data.Text       (Text)

import Lips.Kernel.Capture      (captureName)
import Lips.Kernel.Engine.Data  (MapRule (..), renderAttrPath)

-- | Two rules that could claim one decision, with the subject family that
-- witnesses it (still-open captures rendered as @\<name\>@).
data RuleOverlap = RuleOverlap
  { roLeft    :: Text
  , roRight   :: Text
  , roWitness :: [Text]
  }
  deriving (Eq, Show)

-- | Every overlapping pair of rules, each pair once, in rule order. Empty
-- means the rule set is orthogonal, hence its refinement is a function.
ruleOverlaps :: [MapRule] -> [RuleOverlap]
ruleOverlaps rules =
  [ o
  | (l : rest) <- tails' rules
  , r <- rest
  , Just o <- [overlapOf l r]
  ]
  where
    tails' []       = []
    tails' t@(_:xs) = t : tails' xs

-- | Do these two rules overlap? Kind first (the refiner matches kind before
-- subject), then unification of the two subject patterns.
overlapOf :: MapRule -> MapRule -> Maybe RuleOverlap
overlapOf l r
  | mrKind l /= mrKind r = Nothing
  | otherwise = do
      let lhs = terms "l" (mrSubject l)
          rhs = terms "r" (mrSubject r)
      subst <- unify lhs rhs
      pure (RuleOverlap (mrId l) (mrId r) (map (render . resolve subst) lhs))

-- | Could one concrete subject match both of these subject patterns? The
-- yes/no half of 'overlapOf', without the witness -- shared so the
-- dropped-value check ('Lips.Kernel.Engine.Reach') asks the SAME question about
-- a pattern's emitted subject family and a rule's left-hand side. Two copies of
-- unification would be two places for the answer to drift.
subjectsUnify :: [Text] -> [Text] -> Bool
subjectsUnify l r = isJust (unify (terms "l" l) (terms "r" r))

-- | A subject segment is either a literal or a capture variable. Variables are
-- tagged by side, so the two rules' capture names cannot collide: @\<path\>@ in
-- one rule and @\<path\>@ in the other are independent.
data Term = Lit Text | Var Text Text
  deriving (Eq, Show)

terms :: Text -> [Text] -> [Term]
terms side = map term
  where
    term s = maybe (Lit s) (Var side) (captureName s)

-- | Unify two flat, equal-length term lists. No occurs check is needed: terms
-- have no structure, so a variable can only ever bind to a literal or another
-- variable and no cycle can form.
unify :: [Term] -> [Term] -> Maybe (Map Text Term)
unify as bs
  | length as /= length bs = Nothing
  | otherwise              = foldl step (Just Map.empty) (zip as bs)
  where
    step Nothing _ = Nothing
    step (Just s) (a, b) = case (resolve s a, resolve s b) of
      (Lit x, Lit y)
        | x == y                -> Just s
        | otherwise             -> Nothing
      -- Two captures: bind the right one to the left, so the witness (which
      -- resolves the LEFT rule's segments) reports the family under the name
      -- the first-named rule gave it.
      (Var ls lv, Var rs rv)
        | key ls lv == key rs rv -> Just s
        | otherwise              -> Just (Map.insert (key rs rv) (Var ls lv) s)
      (Var side v, t)           -> Just (Map.insert (key side v) t s)
      (t, Var side w)           -> Just (Map.insert (key side w) t s)

-- | Follow a variable's binding chain to the term that actually stands there.
resolve :: Map Text Term -> Term -> Term
resolve s t@(Var side v) = maybe t (resolve s) (Map.lookup (key side v) s)
resolve _ t              = t

key :: Text -> Text -> Text
key side v = side <> ":" <> v

-- | A witness segment: a literal as itself, an unbound capture as @\<name\>@.
render :: Term -> Text
render (Lit t)    = t
render (Var _ v)  = "<" <> v <> ">"

-- | One overlap in the words a rule author (the model, at the mint gate) needs:
-- which two rules, and the subject family they both claim.
renderRuleOverlap :: RuleOverlap -> Text
renderRuleOverlap o =
  "rules " <> roLeft o <> " and " <> roRight o
    <> " both match " <> renderAttrPath (roWitness o)

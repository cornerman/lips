{-# LANGUAGE OverloadedStrings #-}

-- | Refinement: the lips analogue of eval (spec v2, section 2, item 4).
--
-- Realization applies a language's rules to a base, producing another base,
-- repeatedly, until only ground decisions remain (matched by no rule). Two
-- properties are guaranteed by construction here:
--
--   * /Orthogonality/ (spec section 4). A decision matched by more than one
--     rule is an 'Overlap' error. Because at most one rule ever fires per
--     decision, rewriting is a function, hence confluent for free: same base,
--     same result, always.
--   * /Provenance/. The refiner stamps every derived decision with
--     @'Derived' [parent] rule@. A rule author cannot forge or omit the chain.
--
-- Termination is not decidable in general, so a step budget turns a runaway
-- rule into a loud 'Nonterminating' error rather than a hang (fail fast).
module Lips.Kernel.Refine
  ( Rule (..)
  , RefineError (..)
  , isGround
  , refine
  ) where

import qualified Data.Text       as T

import Lips.Kernel.Base     (Base, fromList, toList)
import Lips.Kernel.Decision

-- | A mapping from one language's engine. 'rRewrite' returns the decisions a
-- matched decision expands into; the refiner stamps their provenance, so the
-- rule need only supply subject, kind, assertion, strength, and rationale (the
-- returned ids and provenance are overwritten).
data Rule = Rule
  { rId      :: RuleId
  , rMatches :: Decision -> Bool
  , rRewrite :: Decision -> [Decision]
  }

data RefineError
  = -- | A decision matched several rules: an orthogonality violation. Carries
    -- the offending decision's id and every rule that claimed it.
    Overlap DecisionId [RuleId]
  | -- | The step budget was exceeded, signalling a non-terminating rule set.
    Nonterminating Int
  deriving (Eq, Show)

-- | A decision is ground when no rule matches it: refinement stops there.
isGround :: [Rule] -> Decision -> Bool
isGround rules d = not (any (`rMatches` d) rules)

-- | Refine a base to its fixpoint (all decisions ground) or the first error.
-- The budget bounds total rewrite steps.
refine :: Int -> [Rule] -> Base -> Either RefineError Base
refine budget rules = go budget . toList
  where
    go n ds
      | n < 0 = Left (Nonterminating budget)
      | otherwise =
          case span (isGround rules) ds of
            (_, [])              -> Right (fromList ds) -- everything ground
            (grounded, d : rest) ->
              -- 'span' guarantees d is non-ground, so it matches >= 1 rule.
              case filter (`rMatches` d) rules of
                [rule] -> go (n - 1) (grounded ++ stamp rule d ++ rest)
                []     -> error "refine: non-ground decision matched no rule"
                many   -> Left (Overlap (dId d) (map rId many))

-- | Rewrite one decision and stamp each product with a derived provenance and
-- a fresh, deterministic id built from the parent id, the rule, and the index.
stamp :: Rule -> Decision -> [Decision]
stamp rule parent =
  [ child
      { dId   = DecisionId (parentTxt <> "/" <> ruleTxt <> "#" <> T.pack (show i))
      , dProv = Derived [dId parent] (rId rule)
      }
  | (i, child) <- zip [0 :: Int ..] (rRewrite rule parent)
  ]
  where
    DecisionId parentTxt = dId parent
    RuleId ruleTxt = rId rule

-- | A decision base and its merge semantics (spec v2, section 2, items 1-2).
{-# LANGUAGE OverloadedStrings #-}
--
-- A base is a set of decisions keyed by id. Merging /resolves/ the base:
-- decisions grouped by subject compete by strength. The strongest assertion
-- wins (delta-over-defaults falls out of this, not a special feature); an
-- equal-strength disagreement is a conflict carrying both provenances, never
-- a silent choice.
module Lips.Kernel.Base
  ( Base
  , empty
  , fromList
  , toList
  , insert
  , union
  , Conflict (..)
  , MergeMode (..)
  , ResolveErr (..)
  , resolve
  ) where

import           Data.List  (sortOn)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text (Text)

import Lips.Kernel.Decision

-- | A set of decisions, keyed by their id so the base is a true set.
newtype Base = Base (Map DecisionId Decision)
  deriving (Eq, Show)

empty :: Base
empty = Base Map.empty

-- | Build a base. A repeated id keeps the last occurrence; ids are meant to be
-- unique, so callers should not rely on this.
fromList :: [Decision] -> Base
fromList = Base . Map.fromList . map (\d -> (dId d, d))

toList :: Base -> [Decision]
toList (Base m) = Map.elems m

insert :: Decision -> Base -> Base
insert d (Base m) = Base (Map.insert (dId d) d m)

-- | Set union. Used to lay a Solution over the System's defaults before
-- resolving: @union defaults solution@.
union :: Base -> Base -> Base
union (Base a) (Base b) = Base (Map.union b a) -- b (solution) wins id clashes

-- | An unresolvable disagreement: two decisions about one subject, at the same
-- top strength, asserting different things. Both provenances travel with it so
-- the error is never silent (spec section 2, item 2).
data Conflict = Conflict
  { conflictSubject :: Subject
  , conflictLeft    :: Decision
  , conflictRight   :: Decision
  }
  deriving (Eq, Show)

-- | How a subject's decisions merge at resolve time. 'Replace' is the scalar
-- default: the top-strength decision wins, equal-strength dissent conflicts.
-- 'Append' is the list-aggregation mode: the top-strength decisions all
-- CONTRIBUTE their elements to one assembled list (same-strength aggregation,
-- not conflict); a stronger decision still REPLACES the whole list. Which mode
-- a subject uses is derived from the engine (rule emits / option schema), never
-- carried on the decision, so the kernel stays domain-blind (spec section 2,
-- merge; list-aggregation design, Closure B).
data MergeMode = Replace | Append
  deriving (Eq, Show)

-- | Why a subject could not be resolved. An equal-strength disagreement on
-- a 'Replace' subject is a 'REConflict'; an 'Append' subject whose list could
-- not be assembled (a contributor was not a VList) is a 'REAssemble'. Both
-- carry the subject so the report is never silent.
data ResolveErr
  = REConflict Conflict
  | REAssemble Subject Text
  deriving (Eq, Show)

-- | Resolve a base with merge modes. 'Replace' subjects use today's
-- strength logic; 'Append' subjects assemble their top-strength contributors
-- (the assemble function is injected, so Base needs no Value dependency and no
-- import cycle). Deterministic: a single winner per subject, or every error.
resolve :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
        -> Base -> Either [ResolveErr] (Map Subject Decision)
resolve modeOf assemble base =
  let bySubject = groupBySubject (toList base)
      results   = map (resolveGroup modeOf assemble) (Map.toList bySubject)
      errs      = concat [es | Left es <- results]
      winners   = [(s, d) | Right (s, d) <- results]
   in if null errs then Right (Map.fromList winners) else Left errs

groupBySubject :: [Decision] -> Map Subject [Decision]
groupBySubject = Map.fromListWith (++) . map (\d -> (dSubject d, [d]))

resolveGroup :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
             -> (Subject, [Decision]) -> Either [ResolveErr] (Subject, Decision)
resolveGroup modeOf assemble (subj, ds) =
  case modeOf subj of
    Replace -> case replaceGroup subj ds of
      Left cs        -> Left (map REConflict cs)
      Right (s, d)   -> Right (s, d)
    Append -> case sortOn dId (filter ((== top) . dStrength) ds) of
      []     -> error "resolveGroup: empty subject group"  -- impossible: ds non-empty
      [one]  -> Right (subj, one)
      tops   -> case assemble tops of
        Right synth -> Right (subj, synth)
        Left e      -> Left [REAssemble subj e]
  where top = maximum (map dStrength ds)

-- | Today's replace-by-strength logic, factored out: the top-strength
-- decisions compete; agreement keeps the smallest-id one, dissent conflicts.
replaceGroup :: Subject -> [Decision] -> Either [Conflict] (Subject, Decision)
replaceGroup subj ds =
  case sortOn dId (filter ((== top) . dStrength) ds) of
    [] -> error "replaceGroup: empty subject group"  -- impossible: ds non-empty
    (chosen : rest) ->
      let dissent = filter ((/= dAssertion chosen) . dAssertion) rest
       in case dissent of
            [] -> Right (subj, chosen)
            _  -> Left [Conflict subj chosen d | d <- dissent]
  where top = maximum (map dStrength ds)


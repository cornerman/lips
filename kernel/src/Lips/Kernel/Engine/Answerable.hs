{-# LANGUAGE OverloadedStrings #-}

-- | Can a demand ever be answered?
--
-- A demand names the subject a program must decide, and 'openQuestions' judges
-- it against the crystallized base -- so the only decisions that can ever
-- satisfy it are the ones the language's own patterns emit. If no pattern emits
-- a subject in the demanded family, the demand stands open for EVERY program in
-- the language: the engine is dead on arrival, and no program the author writes
-- can revive it.
--
-- That failure blames the wrong side, which is why it is caught here. A mint of
-- @examples\/habit.lips@ (2026-07-29) wrote @demand command@ beside a pattern
-- emitting @command.\<name\>@; subject matching is segment-for-segment
-- ('Lips.Kernel.Capture.matchSubject'), so a one-segment demand can never see a
-- two-segment subject. The program did say @install the tool as the command
-- habit.@, yet lips reported "your program does not state this" and told the
-- author to state it -- a mint defect wearing an author's error message. Twice
-- in a row, so a prompt plea is not the fix (invariant 4: a structural guard).
--
-- Static and domain-blind: the check never asks what a subject MEANS, only
-- whether the engine's own shape could ever produce it. Subject unification
-- ('Lips.Kernel.Engine.Overlap.subjectsUnify') answers that, so a demand may
-- name captures (@command.\<name\>@) and a pattern may fill them.
module Lips.Kernel.Engine.Answerable
  ( UnanswerableDemand (..)
  , unanswerableDemands
  , renderUnanswerableDemand
  ) where

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision       (Subject (..))
import Lips.Kernel.Engine.Data    (DemandSpec (..), renderAttrPath)
import Lips.Kernel.Engine.Overlap (subjectsUnify)
import Lips.Kernel.Lang.Nest      (holesInScope)
import Lips.Kernel.Lang.Pattern   (Pattern (..), applyPattern)

-- | A demand no program can answer: the demand, and every subject family the
-- language's patterns do emit (the report names them, since the fix is almost
-- always one of them).
data UnanswerableDemand = UnanswerableDemand
  { udDemand   :: Text
  , udSubject  :: [Text]
  , udEmitted  :: [[Text]]
  }
  deriving (Eq, Show)

-- | Every demand no pattern can satisfy, in demand order. Empty means each
-- demand names a subject some program line could decide.
unanswerableDemands :: [Pattern] -> [DemandSpec] -> [UnanswerableDemand]
unanswerableDemands pats demands =
  [ UnanswerableDemand (dsId d) (dsSubject d) families
  | d <- demands
  , not (any (subjectsUnify (dsSubject d)) families)
  ]
  where families = concatMap (emittedFamilies pats) pats

-- | The subject families one pattern emits, with each hole standing as its own
-- capture. Derived by running the pattern's own substitution ('applyPattern'),
-- so the families are exactly the subjects crystallize will build -- the same
-- move 'Lips.Kernel.Engine.Reach' makes, rather than re-deriving how a subject
-- splits into segments.
emittedFamilies :: [Pattern] -> Pattern -> [[Text]]
emittedFamilies pats p =
  [ segs | (Subject segs, _, _, _) <- applyPattern p bound ]
  -- Every hole IN SCOPE: a nested pattern's subject may carry an ancestor's
  -- capture, and that segment is a capture in the family too.
  where bound = Map.fromList [(h, "<" <> h <> ">") | h <- holesInScope pats p]

-- | One unanswerable demand in the words its author (the model, at the mint
-- gate) needs: which demand, the subject nothing emits, and what is on offer.
renderUnanswerableDemand :: UnanswerableDemand -> Text
renderUnanswerableDemand ud =
  "demand " <> udDemand ud <> " asks for " <> renderAttrPath (udSubject ud)
    <> ", which no pattern emits" <> offer
  where
    offer
      | null (udEmitted ud) = " (this language emits no subject at all)"
      | otherwise = "; the patterns emit "
          <> T.intercalate ", " (map renderAttrPath (udEmitted ud))

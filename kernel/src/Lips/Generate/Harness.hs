{-# LANGUAGE OverloadedStrings #-}

-- | The deterministic core of @generate@ (spec v2, section 5, layer 2: \"in the
-- harness\"). @generate@ is the one step where a model runs, but the model's
-- output is not trusted directly: this harness decides, by fixed rules, what
-- may become a decision and what must become an open question. The model call
-- itself is the imperative shell and is not here; it plugs in as a producer of
-- 'Candidate's and of resample batches.
--
-- Two guards, both pure and both testable without a model:
--
--   * 'admit' enforces deduce-or-fail: a candidate at or above the confidence
--     threshold is admitted; anything below is demoted to an open question that
--     carries its candidate answer (\"I believe X; confirm or correct\"), never
--     auto-applied.
--   * 'unanimous' is the resampling check: a deduction genuinely forced by the
--     inputs comes back identical across samples. Any deduction not present in
--     every sample is detected ambiguity, reported as a 'Divergence'.
module Lips.Generate.Harness
  ( Confidence (..)
  , Candidate (..)
  , OpenQuestion (..)
  , admit
  , renderOpenQuestion
  , DeductionCore
  , Divergence (..)
  , coreOf
  , unanimous
  ) where

import           Data.List  (nub, sortOn)
import           Data.Text  (Text)
import qualified Data.Text  as T

import Lips.Kernel.Decision

-- | A model's self-reported certainty, in [0, 1].
newtype Confidence = Confidence Double
  deriving (Eq, Ord, Show)

-- | A decision the model proposes, with the confidence it attaches to it.
data Candidate = Candidate
  { candDecision   :: Decision
  , candConfidence :: Confidence
  }
  deriving (Eq, Show)

-- | An unresolved gap. It carries the model's candidate answer so the human can
-- confirm or correct, but the candidate is never silently applied.
data OpenQuestion = OpenQuestion
  { oqCandidate :: Decision
  }
  deriving (Eq, Show)

-- | Admit only certainty. Returns the admitted decisions and the open questions
-- for everything below the threshold, in the input order.
admit :: Confidence -> [Candidate] -> ([Decision], [OpenQuestion])
admit threshold = foldr step ([], [])
  where
    step c (yes, qs)
      | candConfidence c >= threshold = (candDecision c : yes, qs)
      | otherwise                     = (yes, OpenQuestion (candDecision c) : qs)

-- | Phrase a demoted candidate as a confirmable question.
renderOpenQuestion :: OpenQuestion -> Text
renderOpenQuestion (OpenQuestion d) =
  "I believe " <> subj (dSubject d) <> " = " <> assn (dAssertion d) <> "; confirm or correct."
  where
    subj (Subject segs) = T.intercalate "." segs
    assn (Assertion a)  = a

-- | The identity of a deduction for agreement purposes: its meaning, ignoring
-- generation artifacts (id and provenance) that legitimately vary per sample.
type DeductionCore = (Subject, Kind, Assertion, Strength)

coreOf :: Decision -> DeductionCore
coreOf d = (dSubject d, dKind d, dAssertion d, dStrength d)

-- | A deduction that did not appear in every sample: detected ambiguity.
newtype Divergence = Divergence DeductionCore
  deriving (Eq, Show)

-- | The resampling unanimity check. Given one deduction set per sample, return
-- the deductions forced by the inputs (present in every sample) or, if any
-- deduction is not unanimous, report every diverging core. An empty batch is
-- treated as no agreement to force (fail loud rather than vacuously succeed).
unanimous :: [[Decision]] -> Either [Divergence] [Decision]
unanimous [] = Left []
unanimous samples =
  let coreSets   = map (nub . map coreOf) samples
      everywhere = filter (\c -> all (c `elem`) coreSets) allCores
      allCores   = nub (concat coreSets)
      diverging  = filter (`notElem` everywhere) allCores
   in if null diverging
        then Right (dedupeByCore (concat samples))
        else Left (map Divergence (sortOn showCore diverging))

-- | Keep one decision per core, deterministically (smallest id), so the agreed
-- result is a clean set.
dedupeByCore :: [Decision] -> [Decision]
dedupeByCore = go [] . sortOn dId
  where
    go seen [] = reverse seen
    go seen (d : ds)
      | coreOf d `elem` map coreOf seen = go seen ds
      | otherwise                       = go (d : seen) ds

showCore :: DeductionCore -> Text
showCore (Subject s, k, Assertion a, str) =
  T.intercalate "." s <> "|" <> T.pack (show k) <> "|" <> a <> "|" <> T.pack (show str)

{-# LANGUAGE OverloadedStrings #-}

-- | Authoring diagnostics: a pure function of (language, program) that reports
-- how a program sits in its language, without any AI, Nix, or @.expect@. It is
-- the crystallize outcome made visible -- the same material a future editor
-- would paint as squiggles -- and the first rung of the editor-tooling
-- milestone (design section 13).
--
-- Three per-line outcomes (from 'classifyLines', the one shared matcher):
-- matched (which pattern, which decision), unmatched (the line escapes the
-- language), ambiguous (several patterns match). Then the open questions: the
-- language's demands not yet answered by the matched decisions. Then coverage.
--
-- Plus the INERT lines: a line the language reads and then drops, so it
-- contributes nothing to the realized output and editing it changes nothing.
-- Reading a line and silently ignoring it is the one failure lips cannot
-- otherwise catch (an unmapped non-'Concept' decision fails the build loud, and
-- an unreadable line is 'Unmatched'), so it is surfaced here rather than left
-- for an author to discover by editing a sentence and seeing no effect.
module Lips.Kernel.Lang.Diagnose
  ( Diagnosis (..)
  , diagnose
  ) where

import           Data.Text (Text)

import Lips.Kernel.Base            (fromList)
import Lips.Kernel.Decision        (Decision (..), Kind (..))
import Lips.Kernel.Demand          (Demand (..), openQuestions)
import Lips.Kernel.Engine.Data     (toDemand)
import Lips.Kernel.Lang.Crystallize (LineOutcome (..), classifyLines)
import Lips.Kernel.Lang.Store       (EngineData (..))

-- | A whole-program authoring report.
data Diagnosis = Diagnosis
  { diagLines   :: [LineOutcome] -- ^ per-line, in source order
  , diagOpen    :: [Text]        -- ^ unmet demands, verbatim questions
  , diagTotal   :: Int           -- ^ non-skipped lines considered
  , diagMatched :: Int           -- ^ how many lines crystallized (one line may yield several decisions)
  , diagInert   :: [(Int, Text)] -- ^ lines that realize nothing: line no and source text
  }
  deriving (Eq, Show)

-- | Diagnose a program against its language. Demands are checked against the
-- decisions that did crystallize, so an incomplete program still reports which
-- questions remain open given what it already states.
diagnose :: FilePath -> EngineData -> Text -> Diagnosis
diagnose file eng src =
  let outcomes = classifyLines file (edPatterns eng) src
      decided  = [d | Matched _ _ _ dsn <- outcomes, d <- dsn]
      base     = fromList decided
      open     = map demQuestion (openQuestions (map toDemand (edDemands eng)) base)
   in Diagnosis
        { diagLines   = outcomes
        , diagOpen    = open
        , diagTotal   = length outcomes
        , diagMatched = length [() | Matched{} <- outcomes]
        , diagInert   = inertLines outcomes
        }

-- | The lines that realize nothing. 'Concept' is the only kind realize drops
-- ('Lips.Kernel.Run' filters it before the anti-MDA guard), so a line whose
-- every decision is a 'Concept' is exactly the inert case. A line mixing a
-- 'Concept' with a realizing decision is NOT inert: part of it reaches output.
inertLines :: [LineOutcome] -> [(Int, Text)]
inertLines outcomes =
  [ (n, txt)
  | Matched n txt _ decs <- outcomes
  , not (null decs)
  , all ((== Concept) . dKind) decs
  ]

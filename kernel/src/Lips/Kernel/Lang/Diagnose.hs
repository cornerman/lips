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
--
-- Plus the RESTATED lines: a line whose decision an earlier line already made
-- ('Lips.Kernel.Lang.Crystallize.restatements'). It merges away, so editing it
-- changes nothing either -- the same harm as an inert line, from the other
-- direction, and reported the same way rather than refused (duplicating a line
-- is a pinned edit-tolerance promise, DESIGN section 5).
--
-- Plus the DISCARDED words: a line the language reads as an assertion whose word
-- no rule carries onward ('Lips.Kernel.Engine.Reach'). @generate@ refuses such
-- an engine at the gate, so what this reports are the engines committed before
-- the gate existed -- and the report is per LINE, since that is what the author
-- can act on.
module Lips.Kernel.Lang.Diagnose
  ( Diagnosis (..)
  , diagnose
  , retiredConcepts
  ) where

import           Data.Text (Text)

import Lips.Kernel.Base            (Base, fromList, toList)
import Lips.Kernel.Decision        (Decision (..), Kind (..))
import Lips.Kernel.Demand          (Demand (..), openQuestions)
import Lips.Kernel.Engine.Data     (toDemand)
import Lips.Kernel.Engine.Reach    (DroppedValue (..), droppedValues)
import Lips.Kernel.Lang.Crystallize (LineOutcome (..), classifyLines, restatements)
import Lips.Kernel.Lang.Store       (EngineData (..))

-- | A whole-program authoring report.
data Diagnosis = Diagnosis
  { diagLines   :: [LineOutcome] -- ^ per-line, in source order
  , diagOpen    :: [Text]        -- ^ unmet demands, verbatim questions
  , diagTotal   :: Int           -- ^ non-skipped lines considered
  , diagMatched :: Int           -- ^ how many lines crystallized (one line may yield several decisions)
  , diagInert   :: [(Int, Text)] -- ^ lines that realize nothing: line no and source text
  , diagDropped :: [(Int, Text, [Text])] -- ^ lines whose bound words reach no output: line no, source text, hole names
  , diagRestated :: [(Int, Int, Text)]   -- ^ lines absorbed by an earlier one: line no, that earlier line, the shared subject
  }
  deriving (Eq, Show)

-- | Diagnose a program against its language. Demands are checked against the
-- decisions that did crystallize, so an incomplete program still reports which
-- questions remain open given what it already states.
diagnose :: FilePath -> EngineData -> Text -> Diagnosis
diagnose file eng src =
  let outcomes = classifyLines file (edPatterns eng) src
      decided  = [d | Matched _ _ _ _ dsn <- outcomes, d <- dsn]
      base     = fromList decided
      open     = map demQuestion (openQuestions (map toDemand (edDemands eng)) base)
   in Diagnosis
        { diagLines   = outcomes
        , diagOpen    = open
        , diagTotal   = length outcomes
        , diagMatched = length [() | Matched{} <- outcomes]
        , diagInert   = inertLines outcomes
        , diagDropped = droppedLines (droppedValues (edPatterns eng) (edRules eng)) outcomes
        , diagRestated = restatements outcomes
        }

-- | The lines that realize nothing. 'Concept' is the only kind realize drops
-- ('Lips.Kernel.Run' filters it before the anti-MDA guard), so a line whose
-- every decision is a 'Concept' is exactly the inert case. A line mixing a
-- 'Concept' with a realizing decision is NOT inert: part of it reaches output.
inertLines :: [LineOutcome] -> [(Int, Text)]
inertLines outcomes =
  [ (n, txt)
  | Matched n txt _ _ decs <- outcomes
  , not (null decs)
  , all ((== Concept) . dKind) decs
  ]

-- | Join the engine's dropped words onto the program lines that produced them.
-- The engine names the defect by pattern id; the author needs the LINE they
-- wrote, so the report is keyed by line and lists the holes whose word governs
-- nothing. A line whose pattern drops no word never appears.
droppedLines :: [DroppedValue] -> [LineOutcome] -> [(Int, Text, [Text])]
droppedLines dvs outcomes =
  [ (n, txt, hs)
  | Matched n txt pid _ _ <- outcomes
  , let hs = [dvHole dv | dv <- dvs, dvPattern dv == pid]
  , not (null hs)
  ]

-- | The concepts a program stated when its language was minted and no longer
-- states: present in @was@, absent from @now@ (compared by subject AND text, so
-- a reworded one counts as gone).
--
-- Why it matters: a 'Concept' realizes nothing, so DELETING such a line changes
-- no output and every gate stays green -- while an artifact\'s minted source was
-- written from exactly those lines. That is the one way a program can stop being
-- the source of truth without anything failing: rewording a concept line breaks
-- its (all-literal) pattern and is reported as unmatched, and adding one is
-- unmatched too, but a deletion is silent. The caller applies this only where a
-- language bakes source, since a language whose concepts are mere headings must
-- stay freely editable.
retiredConcepts :: Base -> Base -> [Decision]
retiredConcepts was now =
  [ d | d <- concepts was, (dSubject d, dAssertion d) `notElem` stated ]
  where
    stated   = [ (dSubject d, dAssertion d) | d <- concepts now ]
    concepts b = [ d | d <- toList b, dKind d == Concept ]

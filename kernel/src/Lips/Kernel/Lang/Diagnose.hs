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
module Lips.Kernel.Lang.Diagnose
  ( Diagnosis (..)
  , diagnose
  ) where

import           Data.Text (Text)

import Lips.Kernel.Base            (fromList)
import Lips.Kernel.Demand          (Demand (..), openQuestions)
import Lips.Kernel.Engine.Data     (toDemand)
import Lips.Kernel.Lang.Crystallize (LineOutcome (..), classifyLines)
import Lips.Kernel.Lang.Store       (EngineData (..))

-- | A whole-program authoring report.
data Diagnosis = Diagnosis
  { diagLines   :: [LineOutcome] -- ^ per-line, in source order
  , diagOpen    :: [Text]        -- ^ unmet demands, verbatim questions
  , diagTotal   :: Int           -- ^ non-skipped lines considered
  , diagMatched :: Int           -- ^ how many crystallized to a decision
  }
  deriving (Eq, Show)

-- | Diagnose a program against its language. Demands are checked against the
-- decisions that did crystallize, so an incomplete program still reports which
-- questions remain open given what it already states.
diagnose :: FilePath -> EngineData -> Text -> Diagnosis
diagnose file eng src =
  let outcomes = classifyLines file (edPatterns eng) src
      decided  = [d | Matched _ _ _ d <- outcomes]
      base     = fromList decided
      open     = map demQuestion (openQuestions (map toDemand (edDemands eng)) base)
   in Diagnosis
        { diagLines   = outcomes
        , diagOpen    = open
        , diagTotal   = length outcomes
        , diagMatched = length decided
        }

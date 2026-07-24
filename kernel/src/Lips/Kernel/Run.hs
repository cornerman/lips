{-# LANGUAGE OverloadedStrings #-}

-- | @run@: the whole deterministic pipeline, no AI (spec v2, section 5). It
-- reads a program in canonical form, resolves it, checks its demands, refines
-- it with a language's rules, and realizes the result to a NixOS module.
--
-- 'RunError' is exactly the spec's four run outcomes: a parse rejection (a line
-- no pattern reads), an open question (an unmet demand), a conflict
-- (equal-strength contradiction), or a refinement failure. Success is the
-- realized module. Only minting new rules needs a model; everything here is a
-- pure function of (program, engine).
module Lips.Kernel.Run
  ( RunError (..)
  , run
  , runBase
  ) where

import           Data.Bifunctor  (first)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader   (ParseError, readBase)
import Lips.Kernel.Realize  (RealizeError (..), realize)
import Lips.Kernel.Refine

-- | The four run outcomes other than success (spec section 5).
data RunError
  = -- | A line no pattern reads. The only outcome that re-enters @generate@.
    ParseRejected [ParseError]
  | -- | Unmet demands, surfaced verbatim; answered by adding lines, no AI.
    OpenQuestions [Text]
  | -- | An equal-strength contradiction, both provenances cited.
    Conflicted [Conflict]
  | -- | A refinement failure: rule overlap or non-termination.
    RefineFailed RefineError
  | -- | Ground decisions no rule mapped to a mechanism: the program escaped the
    -- engine (spec section 3, the anti-MDA guard). Never realized as a guess;
    -- re-enters generate so the engine grows a mapping.
    Unmapped [Decision]
  | -- | Realization refused a ground base for an engine defect (a dangling
    -- @${artifact}@ reference or a malformed artifact group), each reason in
    -- plain words. A conflict is reported as 'Conflicted', not here.
    Unrealizable [Text]
  deriving (Eq, Show)

-- | Run a program (canonical-form text) against an engine (its rules and
-- demands). The budget bounds refinement steps.
run :: Int -> [Rule] -> [Demand] -> Text -> Either RunError Text
run budget rules demands src = do
  base0 <- first ParseRejected (readBase src)
  runBase budget rules demands base0

-- | The pipeline from a decision base onward (resolve, demands, refine,
-- realize), shared by canonical @run@ and the loose path where @crystallize@
-- produces the base. Pure in (base, engine).
runBase :: Int -> [Rule] -> [Demand] -> Base -> Either RunError Text
runBase budget rules demands base0 = do
  winners <- first Conflicted (resolve base0)
  -- Refine the resolved winners, so overridden defaults never realize.
  let base1 = fromList (Map.elems winners)
  case map demQuestion (openQuestions demands base1) of
    []        -> Right ()
    questions -> Left (OpenQuestions questions)
  ground  <- first RefineFailed (refine budget rules base1)
  -- A Concept is decorative vocabulary: a heading or label ("http routes:")
  -- that groups and explains the lines under it, carrying no obligation to
  -- realize. It is dropped here, so it neither trips the anti-MDA guard nor
  -- leaks into the module as an option. Only mapped mechanisms (kind Meta) may
  -- realize; any OTHER surviving decision is an unmapped obligation and must
  -- fail loud, not emit garbage.
  let realizable = filter ((/= Concept) . dKind) (toList ground)
  case filter ((/= Meta) . dKind) realizable of
    []      -> case realize (fromList realizable) of
                 Right nixMod          -> Right nixMod
                 Left (RConflicts cs)  -> Left (Conflicted cs)
                 Left (RDangling ns)   -> Left (Unrealizable
                   ["references artifact(s) nothing builds: " <> T.intercalate ", " ns])
                 Left (RBadArtifact n why) -> Left (Unrealizable ["artifact " <> n <> ": " <> why])
                 Left (RMalformed s e)    -> Left (Unrealizable
                   ["option " <> subjText s <> ": " <> e])
    leftovers -> Left (Unmapped leftovers)

-- | Render a subject as a dotted path for a plain-language error.
subjText :: Subject -> Text
subjText (Subject ss) = T.intercalate "." ss

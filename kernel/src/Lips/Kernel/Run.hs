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
  ) where

import           Data.Bifunctor  (first)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)

import Lips.Kernel.Base
import Lips.Kernel.Demand
import Lips.Kernel.Reader   (ParseError, readBase)
import Lips.Kernel.Realize  (realize)
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
  deriving (Eq, Show)

-- | Run a program (canonical-form text) against an engine (its rules and
-- demands). The budget bounds refinement steps.
run :: Int -> [Rule] -> [Demand] -> Text -> Either RunError Text
run budget rules demands src = do
  base0   <- first ParseRejected (readBase src)
  winners <- first Conflicted (resolve base0)
  -- Refine the resolved winners, so overridden defaults never realize.
  let base1 = fromList (Map.elems winners)
  case map demQuestion (openQuestions demands base1) of
    []        -> Right ()
    questions -> Left (OpenQuestions questions)
  ground  <- first RefineFailed (refine budget rules base1)
  first Conflicted (realize ground)

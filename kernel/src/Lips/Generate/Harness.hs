-- | The deduce-or-fail threshold type for @generate@ (spec v2, section 5).
--
-- @generate@ runs the model once and admits its minted engine only if every
-- item is at least this certain; anything below aborts the write (the CLI's
-- 'main' applies the filter and reports what was refused). 'Confidence' is the
-- unit that gate speaks in -- a model's self-reported certainty in [0, 1],
-- carried on each minted candidate and pinned into the generation record.
module Lips.Generate.Harness
  ( Confidence (..)
  ) where

-- | A model's self-reported certainty, in [0, 1].
newtype Confidence = Confidence Double
  deriving (Eq, Ord, Show)

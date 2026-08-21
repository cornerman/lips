{-# LANGUAGE OverloadedStrings #-}

-- | What one mint COST, as opposed to what it was made of.
--
-- The inputs of a generation event live in @.generation@, whose bytes hash to
-- the id every minted line is stamped with (invariant 6). A duration cannot go
-- there: two identical mints would then produce different ids and no stamp would
-- re-hash. So the cost gets its own unsealed file beside the record, and the
-- split is the point -- sealed inputs in the record, observed costs next to it.
--
-- It is committed like every other machine-written file in a world folder,
-- because the cost of a mint is a fact about the engine that was committed, and
-- comparing two mints is a diff. Before it, DESIGN 13's per-mint datapoints were
-- written by hand from whatever a terminal happened to still show.
module Lips.Generate.Stats
  ( MintStats (..)
  , verdictOf
  , renderStats
  ) where

import           Data.Text            (Text)
import qualified Data.Text            as T
import           Lips.Cli.Output      (Phase (..))
import           Lips.Generate.PiJson (Usage (..))

data MintStats = MintStats
  { mtVerdict  :: Text
  , mtModel    :: Text
  , mtThinking :: Text
  , mtWall     :: Double
  , mtPhases   :: [Phase]
  , mtTurns    :: Int
  , mtTools    :: [(Text, Int)]
  , mtUsage    :: Maybe Usage
  }
  deriving (Eq, Show)

-- | Accepted, or the name of the phase that failed. Derived from the phase log
-- rather than passed in, so the file cannot disagree with the verdict the
-- terminal printed.
verdictOf :: [Phase] -> Text
verdictOf ps = case [ phLabel p | p <- ps, not (phOk p) ] of
  (l : _) -> "refused at " <> l
  []      -> "accepted"

-- | One fact per line, @key: value@: the shape @.generation@ already uses, so
-- the two read alike and either can be grepped without a parser.
renderStats :: MintStats -> Text
renderStats s = T.unlines $
  [ "format: 1"
  , "verdict: " <> mtVerdict s
  , "model: " <> mtModel s
  , "thinking: " <> mtThinking s
  , "wall: " <> secs (mtWall s) ]
  ++ [ "phase " <> phLabel p <> ": " <> secs (phSecs p) | p <- mtPhases s ]
  ++ [ "turns: " <> T.pack (show (mtTurns s)) ]
  ++ [ "tool " <> n <> ": " <> T.pack (show c) | (n, c) <- mtTools s ]
  ++ tokens (mtUsage s)
  where
    -- One decimal: a mint is minutes, so tenths of a second are the finest
    -- figure that means anything, and a fixed shape keeps two files diffable.
    secs x = T.pack (show (fromIntegral (round (x * 10) :: Integer) / 10 :: Double))
    -- Absence is stated, never rendered as zero: a zero would read as a mint
    -- that cost nothing.
    tokens Nothing  = [ "tokens: not reported" ]
    tokens (Just u) =
      [ "tokens input: " <> T.pack (show (usInput u))
      , "tokens output: " <> T.pack (show (usOutput u))
      , "tokens cache-read: " <> T.pack (show (usCacheRead u))
      , "tokens cache-write: " <> T.pack (show (usCacheWrite u))
      -- pi's own figure, in dollars; lips never multiplies tokens by a price it
      -- would then have to keep true as somebody else's rates move.
      , "cost-usd: " <> T.pack (show (usCost u)) ]

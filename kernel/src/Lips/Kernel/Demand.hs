-- | Demands and open questions (spec v2, section 2, item 5).
--
-- A language's meta-decision may demand that some decision exist in a base
-- (\"an application of kind service must decide persistence\"). An unmet demand
-- is an open question: a first-class gap, surfaced verbatim, never guessed. A
-- Solution is complete when no demand is open.
module Lips.Kernel.Demand
  ( Demand (..)
  , openQuestions
  , complete
  ) where

import Data.Text (Text)

import Lips.Kernel.Base     (Base)

-- | A requirement that the base contain some decision. 'demSatisfied' inspects
-- the whole base; 'demQuestion' is the exact wording asked when it is unmet.
data Demand = Demand
  { demId        :: Text
  , demQuestion  :: Text
  , demSatisfied :: Base -> Bool
  }

-- | Every demand not satisfied by the base, in the order given. These are the
-- open questions a Solution author must answer before it can realize.
openQuestions :: [Demand] -> Base -> [Demand]
openQuestions demands base = filter (not . ($ base) . demSatisfied) demands

-- | A base is complete when it leaves no demand open.
complete :: [Demand] -> Base -> Bool
complete demands = null . openQuestions demands

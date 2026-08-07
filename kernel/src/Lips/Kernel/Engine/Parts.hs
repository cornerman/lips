{-# LANGUAGE OverloadedStrings #-}

-- | Does a rule read parts the value it matches actually has?
--
-- A value built from several program words at once stores ONE quoted part per
-- hole ('Lips.Kernel.Lang.Pattern.applyPattern'), so the number of parts a
-- pattern's emit produces is fixed by the pattern, known at mint time, and the
-- same for every program line that matches it. Two rule shapes are therefore
-- wrong for the whole language rather than for one program:
--
--   * @\<value.N\>@ with N past the last part. The executor fails loud
--     ('Lips.Kernel.Engine.Data', an out-of-range 'Left'), but only once some
--     program states such a line -- so the defect ships inside the engine and
--     surfaces on the author's machine.
--   * @\<value.tail\>@ over a several-part value. The tail reads the parts
--     JOINED and splits them on whitespace again ('Engine.Value.fillValue'
--     sees the text @pick@ returns, not the parts), so a two-word part becomes
--     two list elements. Silent, and wrong output every time.
--
-- Static and domain-blind, like its neighbours: it never asks what a part
-- MEANS, only how many there are. A ONE-part value is left alone, because its
-- word count is the program's, not the pattern's -- a rule reading a word of
-- it by position is the honest way to take a many-word value apart.
module Lips.Kernel.Engine.Parts
  ( PartFault (..)
  , PartWhy (..)
  , partFaults
  , renderPartFault
  ) where

import           Data.List (nub)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Decision       (Kind (Concept))
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..), renderAttrPath)
import Lips.Kernel.Engine.Landing (EmitView (..), emitViews)
import Lips.Kernel.Engine.Overlap (subjectsUnify)
import Lips.Kernel.Engine.Value   (AssertionUse (..), assertionUses)
import Lips.Kernel.Lang.Pattern   (Pattern)

-- | Why a rule cannot read the value it matches.
data PartWhy
  = -- | It reads part N, and the value has fewer.
    OutOfRange Int
  | -- | It spreads the value's tail over a value whose parts are already
    --   separate, which splits each part into words again.
    TailOverParts
  deriving (Eq, Show)

-- | One rule reading a part that is not there: the rule, the subject family it
-- matches, how many parts that family's value has, and which way it is wrong.
data PartFault = PartFault
  { pfRule   :: Text
  , pfFamily :: [Text]
  , pfParts  :: Int
  , pfWhy    :: PartWhy
  }
  deriving (Eq, Show)

-- | Every rule reading a part of a several-part value that does not exist, in
-- pattern then rule order. Empty means every part index a rule names is filled
-- by the pattern it matches.
partFaults :: [Pattern] -> [MapRule] -> [PartFault]
partFaults pats rules = nub
  [ PartFault (mrId r) (evFamily ev) n why
  | p <- pats
  , ev <- emitViews pats p
  -- A concept is dropped before realize ('Lips.Kernel.Run'), so no rule ever
  -- reads its value.
  , evKind ev /= Concept
  , let n = length (evParts ev)
  -- Only a value with SEVERAL quoted parts has a count the pattern fixes.
  , n > 1
  , r <- rules
  , mrKind r == evKind ev
  , subjectsUnify (evFamily ev) (mrSubject r)
  , why <- faultsOf n (concatMap (assertionUses . emRhs) (mrEmits r))
  ]
  where
    faultsOf n uses =
      nub ([OutOfRange m | UsePart m <- uses, m > n] ++ [TailOverParts | UseTail `elem` uses])

-- | One fault in the words its author (the model, at the mint gate) needs:
-- which rule, which value, how many parts it has, and what to write instead.
renderPartFault :: PartFault -> Text
renderPartFault pf = case pfWhy pf of
  OutOfRange n ->
    "rule " <> pfRule pf <> " reads <value." <> T.pack (show n) <> "> of "
      <> renderAttrPath (pfFamily pf) <> ", whose value has " <> parts
      <> ": no program line can fill it"
  TailOverParts ->
    "rule " <> pfRule pf <> " spreads <value.tail> over "
      <> renderAttrPath (pfFamily pf) <> ", whose value has " <> parts
      <> ": the tail splits each part into words again, so the parts are lost"
  where
    parts = T.pack (show (pfParts pf)) <> " parts"

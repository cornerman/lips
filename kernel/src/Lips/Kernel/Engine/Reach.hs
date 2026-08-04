{-# LANGUAGE OverloadedStrings #-}

-- | Does every word the language READS reach the realized output?
--
-- Deduce-or-fail covers the line lips cannot read (it fails loud, naming the
-- remedy). It does not cover the line lips reads, admits as a fact, and then
-- throws away: a rule may match that fact and emit only constants, so the
-- program's word governs nothing. The author then reads a sentence that looks
-- load-bearing, edits it, and the realized output does not move. A mint filed
-- exactly this against itself while minting a CLI tool -- "the same rule would
-- wrongly still emit buildGoModule ... the existing example works only because
-- nobody edits that word" -- and named this check as the honest fix.
--
-- The check is static and domain-blind: it never asks what a word MEANS, only
-- whether the engine's own shape carries it. A hole reaches output when some
-- rule matching the decision it feeds either reads that decision's value
-- (@\<value\>@ / @\<value.N\>@) or names the aligned subject capture in an emit
-- path or an emit value. It reaches nothing when no emit mentions it at all.
--
-- Two neighbours own the cases this one does not. A hole reaching only a
-- 'Concept' is decoration the mint DECLARED, and whole inert lines are named by
-- 'Lips.Kernel.Lang.Diagnose'. A decision no rule maps at all already fails the
-- build loud.
--
-- Where alignment is not statically decidable the answer is "carried", because
-- the mint gate must pass every sound engine (the stance
-- 'Lips.Kernel.Engine.Overlap' takes: a false rejection costs as much as a
-- missed defect). Three such cases: a rule whose aligned subject segment is a
-- LITERAL (only programs saying that word match it, so the word selects the
-- rule and is load-bearing), an emit no rule matches, and a segment mixing
-- literal text with a hole (treated as a plain variable, so at worst the report
-- names an extra rule).
module Lips.Kernel.Engine.Reach
  ( DroppedValue (..)
  , DropWhy (..)
  , droppedValues
  , renderDroppedValue
  ) where

import           Data.Maybe      (isJust)
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..), renderAttrPath)
import Lips.Kernel.Engine.Landing (Landing (..), wordDecorates, wordLandings)
import Lips.Kernel.Engine.Value   (valueCaptures, valueUsesAssertion)
import Lips.Kernel.Lang.Pattern   (Pattern (..), holesOf)

-- | Why a word reaches no output.
data DropWhy
  = -- | No emit of its own pattern mentions it: the word dies at crystallize.
    EmittedNowhere
  | -- | It reaches this subject family, and these rules match it and carry it
    -- nowhere.
    IgnoredBy [Text] [Text]
  deriving (Eq, Show)

-- | One word the language binds and the engine discards: the pattern that binds
-- it, the hole that names it, and why it goes nowhere.
data DroppedValue = DroppedValue
  { dvPattern :: Text
  , dvHole    :: Text
  , dvWhy     :: DropWhy
  }
  deriving (Eq, Show)

-- | Every dropped word, in pattern then template order. Empty means every word
-- the language reads governs something in the realized output.
droppedValues :: [Pattern] -> [MapRule] -> [DroppedValue]
droppedValues pats rules =
  [ DroppedValue (pId p) h why
  | p <- pats
  -- A word is judged where it is BOUND: an ancestor's capture is the ancestor
  -- line's own word, judged when that pattern is judged.
  , h <- holesOf p
  , Just why <- [dropOf pats rules p h]
  ]

-- | Where a hole's word lands is 'Lips.Kernel.Engine.Landing''s answer; this
-- module only judges what the rules there DO with it.
dropOf :: [Pattern] -> [MapRule] -> Pattern -> Text -> Maybe DropWhy
dropOf pats rules p h
  | null landings = if wordDecorates pats p h then Nothing else Just EmittedNowhere
  | any carriedBy landings = Nothing
  | otherwise = case [ l | l <- landings, not (null (lgRules l)) ] of
      []      -> Nothing
      (l : _) -> Just (IgnoredBy (lgFamily l) (map mrId (lgRules l)))
  where
    landings = wordLandings pats rules p h
    carriedBy l = any (carries l) (lgRules l)
    -- The rule carries the word if it reads the decision's value, or if it names
    -- the capture standing where the word lands. A LITERAL there means the rule
    -- only fires for that word, so the word already governs the choice of rule.
    carries l r =
      (isJust (lgPart l) && any (valueUsesAssertion . emRhs) (mrEmits r))
        || or [ maybe True (usesCapture r) (captureName s)
              | (i, s) <- zip [0 :: Int ..] (mrSubject r)
              , i `elem` lgSegments l
              ]

-- | Does the rule name this capture anywhere its output can see: an emit path
-- segment (whole or embedded, hence 'nameTokens') or an emit value (a string
-- hole, an artifact name, a path)?
usesCapture :: MapRule -> Text -> Bool
usesCapture r c = any inEmit (mrEmits r)
  where
    inEmit e = c `elem` concatMap nameTokens (emPath e)
                 || c `elem` valueCaptures (emRhs e)

-- | One dropped word in the words its author (the model, at the mint gate)
-- needs: which pattern binds it, where it lands, and who ignores it.
renderDroppedValue :: DroppedValue -> Text
renderDroppedValue dv = case dvWhy dv of
  EmittedNowhere ->
    "pattern " <> dvPattern dv <> " binds <" <> dvHole dv
      <> "> and emits it nowhere: the word it reads reaches no decision"
  IgnoredBy fam ids ->
    "pattern " <> dvPattern dv <> " binds <" <> dvHole dv <> ">, which reaches "
      <> renderAttrPath fam <> ", and " <> named
      <> " emits it nowhere: editing that word changes no output"
    where
      named = (if length ids == 1 then "rule " else "rules ") <> T.intercalate ", " ids

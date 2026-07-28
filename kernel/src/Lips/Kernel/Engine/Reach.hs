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

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Decision       (Assertion (..), Kind (Concept), Subject (..))
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..), renderAttrPath)
import Lips.Kernel.Engine.Overlap (subjectsUnify)
import Lips.Kernel.Engine.Value   (valueCaptures, valueUsesAssertion)
import Lips.Kernel.Lang.Pattern   (Pattern (..), applyPattern, holesOf)

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
  , h <- holesOf p
  , Just why <- [dropOf rules p h]
  ]

-- | Where a hole's word lands, decided by running the pattern's own
-- substitution with each hole bound to a unique marker. Reusing 'applyPattern'
-- (rather than re-deriving how a subject splits into segments) keeps this check
-- honest: it sees exactly the subjects and assertions crystallize will build.
dropOf :: [MapRule] -> Pattern -> Text -> Maybe DropWhy
dropOf rules p h
  | null carrying = if decorative then Nothing else Just EmittedNowhere
  | any reached judged = Nothing
  | otherwise = case [(fam, ids) | (fam, ids, _) <- judged, not (null ids)] of
      []               -> Nothing
      ((fam, ids) : _) -> Just (IgnoredBy fam ids)
  where
    holes  = holesOf p
    marks  = Map.fromList [(x, marker x) | x <- holes]
    filled = [(segs, k, a) | (Subject segs, k, Assertion a, _) <- applyPattern p marks]
    mentions (segs, _, a) = any hit segs || hit a
    hit t = marker h `T.isInfixOf` t
    -- Only a realizing emit can carry a word to output; a Concept is dropped by
    -- realize, so a hole reaching one is decoration, reported elsewhere.
    carrying   = [e | e@(_, k, _) <- filled, k /= Concept, mentions e]
    decorative = any mentions [e | e@(_, Concept, _) <- filled]
    judged     = map judge carrying
    reached (_, _, ok) = ok
    judge (segs, k, a) =
      let fam      = map famSeg segs
          idx      = [i | (i, s) <- zip [0 :: Int ..] segs, hit s]
          matching = [r | r <- rules, mrKind r == k, subjectsUnify fam (mrSubject r)]
       in (fam, map mrId matching, any (carries a idx) matching)
    -- A segment holding any marker becomes a capture named after the holes in
    -- it, so the rule side unifies against a variable -- and a hole repeated in
    -- two segments still constrains, since it yields the same variable twice.
    famSeg s = case [x | x <- holes, marker x `T.isInfixOf` s] of
      [] -> s
      hs -> "<" <> T.intercalate "+" hs <> ">"
    -- The rule carries the word if it reads the decision's value, or if it names
    -- the capture standing where the word lands. A LITERAL there means the rule
    -- only fires for that word, so the word already governs the choice of rule.
    carries a idx r =
      (hit a && any (valueUsesAssertion . emRhs) (mrEmits r))
        || or [ maybe True (usesCapture r) (captureName s)
              | (i, s) <- zip [0 :: Int ..] (mrSubject r)
              , i `elem` idx
              ]

-- | A marker no program text can collide with, since it is built here and only
-- ever compared against text this module substituted.
marker :: Text -> Text
marker h = "\SOH" <> h <> "\SOH"

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

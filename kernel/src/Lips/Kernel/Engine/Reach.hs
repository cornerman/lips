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
  , DecorativeValue (..)
  , decorativeValues
  , renderDecorativeValue
  ) where

import           Data.Maybe      (isNothing)
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..), renderAttrPath)
import Lips.Kernel.Engine.Landing (Landing (..), Part (..), wordDecorates, wordLandings)
import Lips.Kernel.Lang.Nest      (ancestorsOf)
import Lips.Kernel.Engine.Value   (AssertionUse (..), assertionUses, valueCaptures)
import Lips.Kernel.Lang.Pattern   (Pattern (..), holesOf)

-- | Why a word reaches no output.
data DropWhy
  = -- | No emit of its own pattern mentions it: the word dies at crystallize.
    EmittedNowhere
  | -- | It reaches this subject family, and these rules match it and carry it
    -- nowhere.
    IgnoredBy [Text] [Text]
  deriving (Eq, Show)

-- | One word whose only landing is a concept: the pattern that binds it and the
-- hole that names it.
data DecorativeValue = DecorativeValue
  { dcPattern :: Text
  , dcHole    :: Text
  }
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

-- | Does any rule matching this landing carry the word onward? The rule does if
-- it reads the part of the value the word sits in, or if it names the capture
-- standing where the word lands. A LITERAL there means the rule only fires for
-- that word, so the word already governs the choice of rule.
carriedBy :: Landing -> Bool
carriedBy l = any carries (lgRules l)
  where
    carries r =
      readsWord (lgPart l) (concatMap (assertionUses . emRhs) (mrEmits r))
        || or [ maybe True (usesCapture r) (captureName s)
              | (i, s) <- zip [0 :: Int ..] (mrSubject r)
              , i `elem` lgSegments l
              ]

-- | Every word whose only reading is DECORATIVE: it reaches a 'Concept' the
-- mint declared, and nothing else carries it, so realize drops it and editing
-- that word changes no output.
--
-- Reported rather than refused, and separate from 'droppedValues': a concept is
-- a legitimate reading the mint chose deliberately (a heading, a specification
-- for baked source), so this is an author-facing observation, not an engine
-- defect. It is invisible everywhere else -- the whole LINE is not inert
-- ('Lips.Kernel.Lang.Diagnose.diagInert' works per line, and such a line
-- usually realizes something through its other holes), and the drop gate
-- deliberately excuses a hole reaching a concept.
decorativeValues :: [Pattern] -> [MapRule] -> [DecorativeValue]
decorativeValues pats rules =
  [ DecorativeValue (pId p) h
  | p <- pats
  , h <- holesOf p
  , wordDecorates pats p h
  -- Not already named by the drop gate, and carried by no rule anywhere.
  , isNothing (dropOf pats rules p h)
  , not (any carriedBy (landingsBelow pats rules p h))
  ]

-- | Every landing of a word, in the pattern that binds it AND in every pattern
-- nested under that one. A block HEAD's word is in scope inside the block, so a
-- child keys its own subject by it (@host.\<domain\>.location.\<path\>.proxy@,
-- or @\<k:key\>@ carrying the head's whole subject): the head may emit nothing
-- but a concept and the word still governs every line inside it. Judging the
-- head alone called three correct @examples\/vhost@ lines decoration.
landingsBelow :: [Pattern] -> [MapRule] -> Pattern -> Text -> [Landing]
landingsBelow pats rules p h =
  concat [ wordLandings pats rules q h | q <- p : inside ]
  where
    inside = [ q | q <- pats, pId p `elem` map pId (ancestorsOf pats q) ]

-- | One decorative word in the words its author needs: which pattern binds it
-- and which hole names it. The caller joins it onto the program LINE, which is
-- what an author can act on ('Lips.Kernel.Lang.Diagnose').
renderDecorativeValue :: DecorativeValue -> Text
renderDecorativeValue dc =
  "pattern " <> dcPattern dc <> " binds <" <> dcHole dc
    <> "> into a concept only: the word is read and then dropped by realize"

-- | Does a rule reading the assertion these ways carry the word sitting at this
-- position in it? A one-part value IS the word, so any read of the assertion
-- carries it. A several-part value quotes one part per hole, so only a read of
-- THAT part does -- plus the two reads that take the value entire (@\<value\>@
-- joins the parts, @\<value.tail\>@ spreads them). Without the position, a rule
-- reading @\<value.1\>@ of a two-word value counted as carrying both, and the
-- second word was dropped with every gate green.
readsWord :: Maybe Part -> [AssertionUse] -> Bool
readsWord Nothing         _    = False
readsWord (Just Whole)    uses = not (null uses)
readsWord (Just (Part n)) uses = any entire uses
  where
    entire (UsePart m) = m == n
    entire _           = True   -- <value> and <value.tail> take every part

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

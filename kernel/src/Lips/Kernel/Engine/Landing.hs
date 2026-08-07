{-# LANGUAGE OverloadedStrings #-}

-- | Where a word the language READS lands in the engine.
--
-- One question, asked by two callers. 'Lips.Kernel.Engine.Reach' asks whether
-- the landing site carries the word to output at all (a mint gate), and
-- 'Lips.Kernel.Engine.Typing' asks what TYPE that site gives it (an editor
-- label, a live value check). Both need the same join, and it is the delicate
-- part: a pattern's hole becomes a subject segment or a part of an assertion,
-- and only then does a rule match it.
--
-- The join is run by SUBSTITUTION, not by re-deriving how a subject splits:
-- every hole is bound to a unique marker and the pattern's own 'applyPattern'
-- builds the emits, so this module sees exactly the subjects and assertions
-- crystallize will build. Nothing here asks what a word means; it reads the
-- engine's own shape, so the kernel stays domain-blind.
module Lips.Kernel.Engine.Landing
  ( Landing (..)
  , Part (..)
  , wordLandings
  , wordDecorates
  ) where

import           Data.Maybe      (isJust, listToMaybe)
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision       (Assertion (..), Kind (Concept), Subject (..))
import Lips.Kernel.Engine.Data    (MapRule (..))
import Lips.Kernel.Engine.Overlap (subjectsUnify)
import Lips.Kernel.Lang.Nest      (holesInScope, scopedBindings)
import Lips.Kernel.Lang.Pattern   (Pattern (..), applyPattern)
import Lips.Kernel.Surface        (valueTokens)

-- | Where a word sits in the assertion of the decision it reaches. A
-- several-part assertion quotes its parts (so a rule reads one by position),
-- while a one-part assertion IS the word, whatever it captured.
data Part
  = -- | The assertion is this one word: a rule reads it with @\<value\>@, or a
    --   word of it with @\<value.N\>@ \/ @\<value.tail\>@.
    Whole
  | -- | Part n (1-based) of a several-part assertion: @\<value.n\>@ reads
    --   exactly this word.
    Part Int
  deriving (Eq, Show)

-- | One landing of one word: the emit that carries it, and the rules matching
-- that emit. A word may land several times (a dense pattern emits several
-- decisions), and may sit in the subject AND the assertion of one of them.
data Landing = Landing
  { lgFamily   :: [Text]
    -- ^ the emit's subject, with every hole-bearing segment turned into a
    --   capture, which is what a rule's subject unifies against.
  , lgPart     :: Maybe Part
    -- ^ where the word sits in the assertion, if it does at all.
  , lgSegments :: [Int]
    -- ^ the indexes of the subject segments holding the word.
  , lgRules    :: [MapRule]
    -- ^ the rules matching this emit, by kind and unifying subject.
  }
  deriving (Eq, Show)

-- | Every landing of one word of one pattern. A 'Concept' emit is not a
-- landing: realize drops it, so a word reaching only a concept reaches no
-- output ('wordDecorates' answers for that case).
wordLandings :: [Pattern] -> [MapRule] -> Pattern -> Text -> [Landing]
wordLandings pats rules p h =
  [ Landing { lgFamily = fam, lgPart = partOf a, lgSegments = idx
            , lgRules = [ r | r <- rules, mrKind r == k, subjectsUnify fam (mrSubject r) ] }
  | (segs, k, a) <- emitsOf pats p
  , k /= Concept
  , let idx = [i | (i, s) <- zip [0 :: Int ..] segs, hit h s]
  , let fam = map (famSeg (holesInScope pats p)) segs
  , not (null idx) || isJust (partOf a)
  ]
  where
    -- A one-part assertion is the word itself; a several-part one quotes its
    -- parts, and 'valueTokens' takes exactly that quoting apart again, so the
    -- part index a rule reads with <value.N> is read off here the same way.
    partOf a
      | not (hit h a) = Nothing
      | otherwise = case toks of
          [_] -> Just Whole
          _   -> fmap Part (listToMaybe [ i | (i, t) <- zip [1 ..] toks, hit h t ])
      where toks = valueTokens a

-- | Does the word reach a 'Concept' emit? Decoration the mint DECLARED, so the
-- word governing nothing is expected rather than a defect.
wordDecorates :: [Pattern] -> Pattern -> Text -> Bool
wordDecorates pats p h =
  or [ any (hit h) segs || hit h a | (segs, Concept, a) <- emitsOf pats p ]

-- | The pattern's emits with every hole bound to its marker.
--
-- The bindings come from 'scopedBindings', not from this template alone: a
-- nested pattern's emits may name an ancestor's capture (so applyPattern is
-- total only over the whole scope), and its @\<k:key\>@ carries the block
-- head's WHOLE subject, which is what makes the family as long as the subjects
-- a rule matches. One emit set per head the line may sit under.
emitsOf :: [Pattern] -> Pattern -> [([Text], Kind, Text)]
emitsOf pats p =
  [ (segs, k, a)
  | marks <- scopedBindings marker pats p
  , (Subject segs, k, Assertion a, _) <- applyPattern p marks
  ]

-- | A segment holding any marker becomes a capture named after the holes in it,
-- so the rule side unifies against a variable -- and a hole repeated in two
-- segments still constrains, since it yields the same variable twice.
famSeg :: [Text] -> Text -> Text
famSeg holes s = case [x | x <- holes, marker x `T.isInfixOf` s] of
  [] -> s
  hs -> "<" <> T.intercalate "+" hs <> ">"

hit :: Text -> Text -> Bool
hit h t = marker h `T.isInfixOf` t

-- | A marker no program text can collide with, since it is built here and only
-- ever compared against text this module substituted.
marker :: Text -> Text
marker h = "\SOH" <> h <> "\SOH"

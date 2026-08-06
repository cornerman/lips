{-# LANGUAGE OverloadedStrings #-}

-- | What vouches for each thing a program asserts, counted.
--
-- Every assertion lips emits is grounded by something outside lips, or by
-- nothing. A target option is vouched by the world's schema, which defines its
-- meaning and type. A clause is vouched by the contract set and the subset gate.
-- A claim is vouched by the author, who stated the observable. An ARTIFACT
-- ARGUMENT is vouched by nothing lips can check: no schema declares
-- @args.text@, so a shell script minted into one is foreign text that only the
-- builder's own conventions govern. A STAGED SOURCE TREE is the same defect at
-- file scale.
--
-- This module counts those four classes and names the members of the two
-- unvouched ones. It judges nothing and classifies nothing by shape, because
-- guessing which strings are "really programs" is exactly the invention lips
-- refuses; it reports where the grounding runs out and lets a human read.
--
-- Why counting matters. A number nobody watches is how seventy lines of Go
-- arrive in a five-line program (§13, "A re-mint rewrites behavior the program
-- never mentions"). A number printed on every check is how it stays at one.
module Lips.Kernel.Grounding
  ( Grounding (..)
  , Unvouched (..)
  , grounding
  , groundingReport
  ) where

import           Data.List (nubBy, sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Decision

-- | One assertion nothing outside lips vouches for.
data Unvouched = Unvouched
  { uSubject :: Subject
  , uWords   :: Int          -- ^ how much foreign text it carries, in words
  , uFrom    :: Provenance
  }
  deriving (Eq, Show)

data Grounding = Grounding
  { gOptions  :: Int         -- ^ vouched by the target world's schema
  , gClauses  :: Int         -- ^ vouched by the contract set and the gate
  , gClaims   :: Int         -- ^ vouched by the author, who stated the observable
  , gGlue     :: [Unvouched] -- ^ artifact arguments: foreign text, vouched by nothing
  , gStaged   :: [Unvouched] -- ^ staged source trees: the same defect at file scale
  }
  deriving (Eq, Show)

-- | Classify every winner of a resolved base by what vouches for it. Subject
-- shape decides, so this is structural and domain-blind: @clause.@ and @claim.@
-- are kernel vocabulary, @artifact.\<n\>.args.@ is an argument to somebody
-- else's builder, and everything else names an option of the target world.
grounding :: [(Subject, Decision)] -> Grounding
grounding winners = foldr add (Grounding 0 0 0 [] []) (nubBy sameSubject winners)
  where
    -- One SUBJECT is one assertion, however many agreeing decisions carry it.
    -- Several program lines may state the same artifact argument (three lines
    -- naming one build), and counting those separately would report a program
    -- as three times more unvouched than it is.
    sameSubject (a, _) (b, _) = a == b

    add (s, d) g = case segments s of
      ("clause" : _) -> g { gClauses = gClauses g + 1 }
      ("claim" : _)  -> g { gClaims = gClaims g + 1 }
      -- Where the behaviour runs and what to call it: kernel vocabulary, so no
      -- schema vouches for it and counting it as an option overstates what does.
      ("site" : _)   -> g
      ["artifact", _, "args", "src"] -> g { gStaged = unvouchedOf s d : gStaged g }
      ("artifact" : _ : "args" : _)  -> g { gGlue = unvouchedOf s d : gGlue g }
      -- An artifact's builder and its fills name things; only its arguments
      -- carry text, so the rest is not counted as unvouched.
      ("artifact" : _) -> g
      _ -> g { gOptions = gOptions g + 1 }

    segments (Subject ss) = ss

    unvouchedOf s d = Unvouched
      { uSubject = s
      , uWords = length (T.words (assertionOf d))
      , uFrom = dProv d
      }

    assertionOf d = case dAssertion d of Assertion a -> a

-- | How much foreign text a program carries, in words. One monotone number, so
-- growth is visible at a glance: a five-line program that acquires seventy lines
-- of Go moves it by hundreds.
unvouchedWords :: Grounding -> Int
unvouchedWords g = sum (map uWords (gGlue g <> gStaged g))

-- | The report, one line per fact, ready to print. Ordered so the two unvouched
-- classes come last and largest-first: what a reviewer should look at, in the
-- order they should look at it.
groundingReport :: Grounding -> [Text]
groundingReport g =
  [ "grounding: " <> T.intercalate ", "
      [ count (gOptions g) "option assignment" <> " (schema)"
      , count (gClauses g) "clause" <> " (contracts)"
      , count (gClaims g) "claim" <> " (stated)"
      , count (length (gGlue g) + length (gStaged g)) "unvouched assertion"
          <> " (nothing), " <> count (unvouchedWords g) "word"
      ]
  ]
    <> map (line "glue") (sortOn (negate . uWords) (gGlue g))
    <> map (line "staged") (sortOn (negate . uWords) (gStaged g))
  where
    count 1 what = "1 " <> what
    count n what = T.pack (show n) <> " " <> what <> "s"
    line label u =
      "  " <> label <> ": " <> subjectText (uSubject u)
        <> " (" <> count (uWords u) "word" <> ") " <> provText (uFrom u)
    subjectText (Subject ss) = T.intercalate "." ss
    provText (FromSource (SourceLoc f n)) = "<- " <> f <> ":" <> T.pack (show n)
    provText (Derived ids (RuleId r)) =
      "<- " <> T.intercalate "," [ i | DecisionId i <- ids ] <> " via " <> r
    provText (FromGeneration h) = "<- gen:" <> h

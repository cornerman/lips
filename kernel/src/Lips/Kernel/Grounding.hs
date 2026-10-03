{-# LANGUAGE OverloadedStrings #-}

-- | What vouches for each thing a program asserts, counted.
--
-- Every assertion lips emits is grounded by something outside lips, or by
-- nothing. A target option is vouched by the world's schema, which defines its
-- meaning and type. A clause is vouched by the contract set and the subset gate.
-- A claim is vouched by the author, who stated the observable. GLUE -- an
-- argument to somebody else's builder, marked kind 'Glue' when the rule emits
-- it -- is foreign text only the builder's conventions govern, and comes in two
-- grades. AUTHOR glue carries only the program's words, so the author vouches
-- for it. MINT glue carries text the mint wrote (a shell line in @args.text@),
-- vouched by nothing lips can read, so it must at least be RUN by a claim. (A
-- source tree, the same defect at file scale, is refused at generate.)
--
-- A schema vouches for a NAME and a TYPE, never for the text inside a string. So
-- there is a fifth number beside the four classes: how many words of literal text
-- the mint wrote into string values that no program word reaches. A live mint put
-- a whole shell pipeline into @systemd.services.x.script@ and the four classes
-- called it a vouched option assignment, which is true of the option and false of
-- the pipeline.
--
-- This module counts, names the members of the unvouched classes and the mint
-- glue no claim runs, and measures mint-written text. It judges nothing and classifies nothing by shape,
-- because guessing which strings are "really programs" is exactly the invention
-- lips refuses; it reports where the grounding runs out and lets a human read.
--
-- Why counting matters. A number nobody watches is how seventy lines of Go
-- arrive in a five-line program (§13, "A re-mint rewrites behavior the program
-- never mentions"). A number printed on every check is how it stays at one.
module Lips.Kernel.Grounding
  ( Grounding (..)
  , Unvouched (..)
  , grounding
  , claimCount
  , groundingReport
  ) where

import           Data.List (nub, nubBy, sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Decision
import Lips.Kernel.Engine.Value (Piece (..), Value (..), parseValue, valueArtifactNames)

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
  , gClaimIds :: [Text]
    -- ^ The observables the author stated, by id. IDS, not decisions: one claim
    -- is stated in several sections (a call, what it equals, what it is fed), and
    -- counting those separately reported logscan's single claim as four.
  , gMintGlue :: [Unvouched]
    -- ^ MINT glue: builder arguments ('Glue' decisions) whose template holds
    -- literal text the mint wrote. Vouched by nothing, and exactly what a re-mint
    -- rewrites, so each must be pinned by a claim. Words are the mint's own.
  , gAuthorGlue :: [Unvouched]
    -- ^ AUTHOR glue: builder arguments filled only with the program's words. The
    -- foreign text is the author's, stated in the program, so it is legitimate
    -- without qualification and counted apart from what nothing vouches for.
  , gUnpinned :: [Unvouched]
    -- ^ The mint glue no claim reaches: no @claim.\<id\>.run@ names its artifact,
    -- directly or through another artifact's arguments. @generate@ refuses these.
  , gWritten  :: [Unvouched]
    -- ^ String option values carrying literal words no program word reaches: text
    -- the mint wrote and a schema cannot vouch for. Not a defect by itself (a
    -- unit description is prose, and prose is fine); a number to watch, because
    -- behaviour hiding in an option string is behaviour no gate reads.
  }
  deriving (Eq, Show)

-- | How many observables the author stated: distinct claim ids.
claimCount :: Grounding -> Int
claimCount = length . nub . gClaimIds

-- | Classify every winner of a resolved base by what vouches for it. Structural
-- and domain-blind: @clause.@ and @claim.@ are kernel vocabulary, a 'Glue'
-- decision is a builder argument the rule was marked for when it emitted it, and
-- everything else names an option of the target world.
--
-- @templateOf@ gives the rhs template a decision was filled from
-- ('Lips.Kernel.Engine.Data.emitTemplate'). Mint-written words are counted in
-- the TEMPLATE, because by the time a decision is ground its holes are filled
-- and a program word inside the string is indistinguishable from the mint's.
grounding :: (Decision -> Maybe Value) -> [(Subject, Decision)] -> Grounding
grounding templateOf winners = pin (foldr add (Grounding 0 0 [] [] [] [] []) unique)
  where
    -- One SUBJECT is one assertion, however many agreeing decisions carry it.
    -- Several program lines may state the same artifact argument (three lines
    -- naming one build), and counting those separately would report a program
    -- as three times more unvouched than it is.
    sameSubject (a, _) (b, _) = a == b
    unique = nubBy sameSubject winners

    add (s, d) g = case segments s of
      ("clause" : _) -> g { gClauses = gClauses g + 1 }
      ("claim" : cid : _) -> g { gClaimIds = cid : gClaimIds g }
      -- Where the behaviour runs and what to call it: kernel vocabulary, so no
      -- schema vouches for it and counting it as an option overstates what does.
      ("site" : _)   -> g
      _ | dKind d == Glue -> case templateOf d of
            -- Only the program's words went in: the author's glue.
            Just t | wordsIn t == 0 -> g { gAuthorGlue = unvouchedOf s d : gAuthorGlue g }
            Just t -> g { gMintGlue = (unvouchedOf s d) { uWords = wordsIn t } : gMintGlue g }
            -- No template to tell whose words these are: graded as the mint's,
            -- the grade that asks for a claim, rather than waved through.
            Nothing -> g { gMintGlue = unvouchedOf s d : gMintGlue g }
      -- An artifact's builder and its fills name things; only its arguments
      -- carry text, so the rest is not counted as unvouched.
      ("artifact" : _) -> g
      _ -> let g' = g { gOptions = gOptions g + 1 }
            in case mintWords d of
                 0 -> g'
                 n -> g' { gWritten = (unvouchedOf s d) { uWords = n } : gWritten g' }

    segments (Subject ss) = ss

    -- A claim pins glue by RUNNING its artifact. Its command names artifacts,
    -- and an artifact whose arguments name another (a wrapper exec'ing a core)
    -- runs that one too, so the reach is closed over artifact references.
    pin g = g { gUnpinned = [ u | u <- gMintGlue g, artifactOf (uSubject u) `notElem` map Just reached ] }
    reached = close (concat [ refsIn d | (Subject ["claim", _, "run"], d) <- unique ]) []
    close [] seen = seen
    close (n : ns) seen
      | n `elem` seen = close ns seen
      | otherwise = close (ns <> concat [ refsIn d | (Subject ("artifact" : m : _), d) <- unique, m == n ])
                          (n : seen)
    refsIn d = either (const []) valueArtifactNames (parseValue (assertionOf d))
    artifactOf (Subject ("artifact" : n : _)) = Just n
    artifactOf _                              = Nothing

    unvouchedOf s d = Unvouched
      { uSubject = s
      , uWords = length (T.words (assertionOf d))
      , uFrom = dProv d
      }

    assertionOf d = case dAssertion d of Assertion a -> a

    -- The literal words inside a string value, with the holes removed: what the
    -- mint wrote rather than what the program said. A non-string value (a
    -- boolean, a number, a path, a package reference) is not prose and counts
    -- zero, so this measures text and never mistakes a typed value for it.
    --
    -- Without a template (a decision no minted rule emitted) the filled value is
    -- counted instead. That over-counts, by the program words in it, which is
    -- the safe direction for a number that exists to be watched.
    mintWords d = case templateOf d of
      Just t  -> wordsIn t
      Nothing -> either (const 0) wordsIn (parseValue (assertionOf d))
    wordsIn v = length (concatMap T.words (literals v))

    literals (VStr ps)  = [ t | PLit t <- ps ]
    literals (VList vs) = concatMap literals vs
    literals (VAttr fs) = concatMap (literals . snd) fs
    literals _          = []

-- | How much foreign text a program carries, in words. One monotone number, so
-- growth is visible at a glance: a five-line program that acquires seventy lines
-- of Go moves it by hundreds.
unvouchedWords :: Grounding -> Int
unvouchedWords g = sum (map uWords (gMintGlue g))

-- | The report, one line per fact, ready to print. Ordered so the two unvouched
-- classes come last and largest-first: what a reviewer should look at, in the
-- order they should look at it.
groundingReport :: Grounding -> [Text]
groundingReport g =
  [ "grounding: " <> T.intercalate ", "
      [ count (gOptions g) "option assignment" <> " (schema)"
      , count (gClauses g) "clause" <> " (contracts)"
      , count (claimCount g) "claim" <> " (stated)"
      , count (length (gAuthorGlue g)) "glue assertion" <> " by the author (stated)"
      , count (length (gMintGlue g)) "unvouched assertion"
          <> " (nothing), " <> count (unvouchedWords g) "word"
      , count (sum (map uWords (gWritten g))) "mint-written word"
          <> " inside option strings"
      ]
  ]
    <> map (line "glue (mint, unpinned)") (largest (gUnpinned g))
    <> map (line "glue (mint)") (largest (filter (`notElem` gUnpinned g) (gMintGlue g)))
    <> map (line "glue (author)") (largest (gAuthorGlue g))
    -- Only the wordiest few: prose in a description is normal, and a list of
    -- every one-word string would bury the number that matters.
    <> map (line "mint wrote")
           (take 3 (filter ((> 3) . uWords) (sortOn (negate . uWords) (gWritten g))))
  where
    largest = sortOn (negate . uWords)
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

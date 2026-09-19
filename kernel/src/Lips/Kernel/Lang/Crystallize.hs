{-# LANGUAGE OverloadedStrings #-}

-- | @crystallize@: loose text x language -> decision base, deterministically
-- (spec v2, section 5; crystallization plan). This is the AI-free stage of
-- @run@. The language (a set of 'Pattern's) is the seed crystal that
-- @generate@ minted; here the program crystallizes around it.
--
-- Three outcomes per loose line, mirroring the run pipeline's fail-loud
-- discipline:
--
--   * matched by exactly one pattern: it crystallizes to one decision;
--   * matched by no pattern: 'NoPattern', the only outcome that re-enters
--     @generate@ (the program escaped the language);
--   * matched by more than one pattern: 'Overlapping', an orthogonality
--     violation, the same guard 'Lips.Kernel.Refine' enforces for rules.
--
-- A fourth outcome the plan lists, ambiguous hole binding, cannot arise: with
-- no morphology, normalization is a total function, so a token binds one way.
--
-- Line identity: a decision's id is its 1-based source line (@d\<n\>@) and its
-- provenance is that line, so any decision walks straight back to the text a
-- human wrote.
module Lips.Kernel.Lang.Crystallize
  ( CrystError (..)
  , LineOutcome (..)
  , classifyLines
  , crystallize
  , restatements
  ) where

import           Data.Char       (isSpace)
import           Data.List       (sortOn)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base     (Base, fromList)
import Lips.Kernel.Decision
import Lips.Kernel.Lang.Nest    (noFrames, recordLine, scopeLine)
import Lips.Kernel.Lang.Pattern
import Lips.Kernel.Reader   (ParseError (..), commentOrBlank, joinSubject, readDecision, render)

-- | A crystallization failure, anchored to the 1-based loose line.
data CrystError
  = -- | No pattern matched this line: the program escaped the language.
    NoPattern Int Text
  | -- | Several patterns matched: an orthogonality violation, all named.
    Overlapping Int [Text]
  | -- | The line reads as an item of a block, and no line heading such a block
    -- precedes it: the line, its text, and the parent pattern(s) it wanted.
    NoParentBlock Int Text [Text]
  | -- | The line reads, but a decision it states cannot be written down and read
    -- back: the line, its text, and what the reader complained about. A captured
    -- value carrying a character the canonical decision line reserves
    -- (whitespace separates its fields) lands here.
    Unreadable Int Text Text
  deriving (Eq, Show)

-- | The outcome of matching one loose line against the language: what a human
-- (or an editor) needs to see per line. 'crystallize' folds these into a base
-- or a list of errors; diagnostics render them directly.
data LineOutcome
  = -- | Exactly one pattern matched: line no, source text, the pattern id it
    -- matched, the line heading its block (if it sits in one), and the
    -- decision(s) it produces (a dense line yields several).
    Matched Int Text Text (Maybe Int) [Decision]
  | -- | No pattern matched: the line escapes the language.
    Unmatched Int Text
  | -- | Several patterns matched (orthogonality violation), all named.
    Ambiguous Int Text [Text]
  | -- | The line is an item of a block that no preceding line heads.
    Orphan Int Text [Text]
  | -- | The line matched and produced decisions, and one of them cannot be
    -- written down and read back: line no, source text, and the reader's
    -- complaint. Kept apart from 'Matched' so the per-line report marks the
    -- line instead of printing @ok@ next to the line the file then fails on.
    Illegible Int Text Text
  deriving (Eq, Show)

-- | Classify every non-skipped loose line against the language. The single
-- matcher shared by 'crystallize' and diagnostics, so the two never diverge.
classifyLines :: FilePath -> [Pattern] -> Text -> [LineOutcome]
classifyLines file patterns src =
  let numbered   = zip [1 ..] (T.lines src)
      candidates = [ (n, indentOf l, t)
                   | (n, l) <- numbered, let t = T.strip l, not (skip t) ]
   in reverse (snd (foldl' classify (noFrames, []) candidates))
  where
    skip = commentOrBlank
    -- Leading whitespace is read but weightless: only a pattern that nests under
    -- ITSELF consults it ('Lips.Kernel.Lang.Nest.scopeLine'), so every existing
    -- program means exactly what it meant.
    indentOf l = T.length (T.takeWhile isSpace l)
    classify (frames, acc) (n, indent, t) =
      let toks = tokenizeLine t
       in case [(p, m) | p <- patterns, Just m <- [matchTemplate (pTemplate p) toks]] of
            []           -> (frames, Unmatched n t : acc)
            [(p, m)] -> case scopeLine frames p indent (mBinds m) of
              Left qs -> (frames, Orphan n t qs : acc)
              Right (par, env) ->
                let decs = decisionsAt file n p (Match env (mItems m))
                    -- A line's block key is the subject of its first emit: what
                    -- a child's <k:key> resolves to, so keys compose downward.
                    key = case decs of
                      (d : _) -> joinSubject (segsOf (dSubject d))
                      []      -> ""
                    -- Frames are recorded either way: an illegible head is one
                    -- defect, and dropping its block would report every child
                    -- as an orphan on top of it.
                    frames' = recordLine frames p n indent par env key
                    outcome = case [why | d <- decs, Left why <- [rereads d]] of
                      (why : _) -> Illegible n t why
                      []        -> Matched n t (pId p) par decs
                 in (frames', outcome : acc)
            many         -> (frames, Ambiguous n t [pId p | (p, _) <- many] : acc)
    segsOf (Subject ss) = ss

-- | Crystallize a loose program against a language. Comment (@#@) and blank
-- lines are ignored. Collects every line error, so one report names all gaps.
crystallize :: FilePath -> [Pattern] -> Text -> Either [CrystError] Base
crystallize file patterns src =
  let outcomes = classifyLines file patterns src
      errs     = [toErr o | o <- outcomes, isErr o]
      ds       = [d | Matched _ _ _ _ dsn <- outcomes, d <- dsn]
   in if null errs then Right (fromList ds) else Left errs
  where
    isErr Matched{}   = False
    isErr _           = True
    toErr (Unmatched n t)     = NoPattern n t
    toErr (Ambiguous n _ ids) = Overlapping n ids
    toErr (Orphan n t qs)     = NoParentBlock n t qs
    toErr (Illegible n t why) = Unreadable n t why
    toErr Matched{}           = error "crystallize: Matched is not an error"

-- | The lines that state what an earlier line already stated: same subject, same
-- assertion. A base is keyed by subject, so such a line merges into the earlier
-- one and produces no decision of its own -- the author edits it and nothing
-- changes, with nothing anywhere saying so ('diagInert' works per kind,
-- 'diagDropped' per hole, and neither can see a whole absorbed line).
--
-- Reported, never refused. Two statements of one fact ARE one fact (the merge
-- doctrine the @set@ default rests on), and DESIGN section 5 pins duplicating a
-- line as an edit that must keep working, so making this an error would break a
-- promise. Visibility is the whole remedy, exactly as for an inert line: the
-- author is told, and decides.
--
-- Disagreement is a different case and stays where it is: an equal-strength
-- conflict at resolve, which already names both sides.
--
-- Keyed by line, since a line is what an author can delete. Comparison is by
-- source LINE, so a dense line emitting one fact twice (an engine defect, not a
-- program one) is never reported as restating itself.
restatements :: [LineOutcome] -> [(Int, Int, Text)]
restatements outcomes = sortOn (\(n, _, _) -> n) (concatMap report (Map.toList byFact))
  where
    byFact = Map.fromListWith (++)
      [ ((dSubject d, dAssertion d), [n])
      | Matched n _ _ _ dsn <- outcomes, d <- dsn ]
    report ((subj, _), ns) = case dedup ns of
      (first : laters) -> [(n, first, joinSubject (segsOf subj)) | n <- laters]
      []               -> []
    dedup = Map.keys . Map.fromList . map (\n -> (n, ()))
    segsOf (Subject ss) = ss

-- | Whether a decision survives being written down and read back. A decision
-- base IS its canonical text: the regeneration gate compares against a
-- committed .decisions document, so a decision that renders to a line the
-- reader cannot take back is not a decision at all. The check is the round trip
-- itself -- no list of forbidden characters, so it closes over the whole
-- grammar and over every future field.
rereads :: Decision -> Either Text ()
rereads d = case readDecision (render d) of
  Left e               -> Left (peMessage e <> ", reading back: " <> render d)
  Right d' | d' /= d   -> Left ("reads back as a different decision: " <> render d')
           | otherwise -> Right ()

-- | Build the decision(s) a matched pattern produces at a given line. A line
-- may state several facts, so the pattern emits several decisions; the base is
-- keyed by id, so each needs a distinct id or a fact would silently vanish. A
-- sole emit keeps the bare per-line id @d\<n\>@ (the common case); several get a
-- @d\<n\>.\<k\>@ suffix, 1-based, stable and line-anchored.
decisionsAt :: FilePath -> Int -> Pattern -> Match -> [Decision]
decisionsAt file n p m =
  let emits = applyMatch p m
   in zipWith build (idsAt n (length emits)) emits
  where
    build did (subj, kind, assn, str) =
      Decision
        { dId        = DecisionId did
        , dSubject   = subj
        , dKind      = kind
        , dAssertion = assn
        , dStrength  = str
        , dProv      = FromSource (SourceLoc (T.pack file) n)
        , dRationale = Nothing
        }

-- | The decision ids for a line producing @k@ decisions.
idsAt :: Int -> Int -> [Text]
idsAt n 1 = ["d" <> T.pack (show n)]
idsAt n k = ["d" <> T.pack (show n) <> "." <> T.pack (show i) | i <- [1 .. k]]

-- | Hole bindings from a template match (surface tokens keyed by hole name).
type Bindings = Map Text Text

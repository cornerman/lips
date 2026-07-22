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
  ) where

import           Data.Map.Strict (Map)
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base     (Base, fromList)
import Lips.Kernel.Decision
import Lips.Kernel.Lang.Pattern

-- | A crystallization failure, anchored to the 1-based loose line.
data CrystError
  = -- | No pattern matched this line: the program escaped the language.
    NoPattern Int Text
  | -- | Several patterns matched: an orthogonality violation, all named.
    Overlapping Int [Text]
  deriving (Eq, Show)

-- | The outcome of matching one loose line against the language: what a human
-- (or an editor) needs to see per line. 'crystallize' folds these into a base
-- or a list of errors; diagnostics render them directly.
data LineOutcome
  = -- | Exactly one pattern matched: line no, source text, the pattern id it
    -- matched, and the decision(s) it produces (a dense line yields several).
    Matched Int Text Text [Decision]
  | -- | No pattern matched: the line escapes the language.
    Unmatched Int Text
  | -- | Several patterns matched (orthogonality violation), all named.
    Ambiguous Int Text [Text]
  deriving (Eq, Show)

-- | Classify every non-skipped loose line against the language. The single
-- matcher shared by 'crystallize' and diagnostics, so the two never diverge.
classifyLines :: FilePath -> [Pattern] -> Text -> [LineOutcome]
classifyLines file patterns src =
  let numbered   = zip [1 ..] (T.lines src)
      candidates = [(n, t) | (n, l) <- numbered, let t = T.strip l, not (skip t)]
   in map (uncurry classify) candidates
  where
    skip t = T.null t || "#" `T.isPrefixOf` t
    classify n t =
      let toks = tokenizeLine t
       in case [(p, binds) | p <- patterns, Just binds <- [matchTemplate (pTemplate p) toks]] of
            []            -> Unmatched n t
            [(p, binds)]  -> Matched n t (pId p) (decisionsAt file n p binds)
            many          -> Ambiguous n t [pId p | (p, _) <- many]

-- | Crystallize a loose program against a language. Comment (@#@) and blank
-- lines are ignored. Collects every line error, so one report names all gaps.
crystallize :: FilePath -> [Pattern] -> Text -> Either [CrystError] Base
crystallize file patterns src =
  let outcomes = classifyLines file patterns src
      errs     = [toErr o | o <- outcomes, isErr o]
      ds       = [d | Matched _ _ _ dsn <- outcomes, d <- dsn]
   in if null errs then Right (fromList ds) else Left errs
  where
    isErr Matched{}   = False
    isErr _           = True
    toErr (Unmatched n t)     = NoPattern n t
    toErr (Ambiguous n _ ids) = Overlapping n ids
    toErr Matched{}           = error "crystallize: Matched is not an error"

-- | Build the decision(s) a matched pattern produces at a given line. A line
-- may state several facts, so the pattern emits several decisions; the base is
-- keyed by id, so each needs a distinct id or a fact would silently vanish. A
-- sole emit keeps the bare per-line id @d\<n\>@ (the common case); several get a
-- @d\<n\>.\<k\>@ suffix, 1-based, stable and line-anchored.
decisionsAt :: FilePath -> Int -> Pattern -> Bindings -> [Decision]
decisionsAt file n p binds =
  let emits = applyPattern p binds
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

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

-- | Crystallize a loose program against a language. Comment (@#@) and blank
-- lines are ignored. Collects every line error, so one report names all gaps.
crystallize :: FilePath -> [Pattern] -> Text -> Either [CrystError] Base
crystallize file patterns src =
  let numbered   = zip [1 ..] (T.lines src)
      candidates = [(n, t) | (n, l) <- numbered, let t = T.strip l, not (skip t)]
      results    = map (uncurry readLine) candidates
      errs       = [e | Left e <- results]
      ds         = [d | Right d <- results]
   in if null errs then Right (fromList ds) else Left errs
  where
    skip t = T.null t || "#" `T.isPrefixOf` t

    readLine n t =
      let toks = tokenizeLine t
       in case [(p, binds) | p <- patterns, Just binds <- [matchTemplate (pTemplate p) toks]] of
            []            -> Left (NoPattern n t)
            [(p, binds)]  -> Right (decisionAt file n p binds)
            many          -> Left (Overlapping n [pId p | (p, _) <- many])

-- | Build the decision a matched pattern produces at a given line.
decisionAt :: FilePath -> Int -> Pattern -> Bindings -> Decision
decisionAt file n p binds =
  let (subj, kind, assn, str) = applyPattern p binds
   in Decision
        { dId        = DecisionId ("d" <> T.pack (show n))
        , dSubject   = subj
        , dKind      = kind
        , dAssertion = assn
        , dStrength  = str
        , dProv      = FromSource (SourceLoc (T.pack file) n)
        , dRationale = Nothing
        }

-- | Hole bindings from a template match (surface tokens keyed by hole name).
type Bindings = Map Text Text

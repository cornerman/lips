{-# LANGUAGE OverloadedStrings #-}

-- | The unit of a crystallized language: a pattern (spec v2, section 5;
-- crystallization plan). A pattern is a linear token template with named holes
-- that maps one class of loose lines to one canonical decision. The model
-- mints patterns during @generate@; the kernel applies them during
-- @crystallize@, deterministically, with no AI.
--
-- Two token vocabularies meet here:
--
--   * The /template/ matches a loose line token by token. A literal token must
--     match (after normalization: lowercase, trailing punctuation stripped); a
--     hole binds exactly one token, capturing its surface form verbatim so
--     values are never corrupted.
--   * The /target/ (subject and assertion) is a holey string: literal text
--     with @\<hole\>@ placeholders that the captured surface forms fill.
--
-- Design limits, deliberate for the prototype (crystallization plan,
-- \"settled\"): holes bind a single token; a pattern yields a single decision;
-- holes may appear only in subject and assertion, never replacing a template
-- literal's meaning. These keep matching total and closure-under-hole-edits a
-- property by construction. Multi-token holes and morphology are future work.
module Lips.Lang.Pattern
  ( TplTok (..)
  , StrPart (..)
  , Pattern (..)
  , normalizeToken
  , stripTrailingPunct
  , tokenizeLine
  , matchTemplate
  , applyPattern
  , holesOf
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision (Assertion (..), Kind, Strength, Subject (..))

-- | A template token: a literal to match (stored already normalized) or a hole
-- that binds one loose token's surface form.
data TplTok = TLit Text | THole Text
  deriving (Eq, Show)

-- | A piece of a target (subject or assertion) string: literal text or a hole
-- reference filled from the template's bindings.
data StrPart = SLit Text | SHole Text
  deriving (Eq, Show)

-- | A crystallization pattern. Applying it to a matching loose line yields one
-- decision with this kind and strength, its subject and assertion built by
-- filling holes with captured surface tokens.
data Pattern = Pattern
  { pId        :: Text
  , pTemplate  :: [TplTok]
  , pKind      :: Kind
  , pStrength  :: Strength
  , pSubject   :: [StrPart] -- substituted, then split on \".\" into a path
  , pAssertion :: [StrPart]
  }
  deriving (Eq, Show)

-- | The hole names a pattern binds, in template order.
holesOf :: Pattern -> [Text]
holesOf p = [h | THole h <- pTemplate p]

-- | Strip trailing sentence punctuation, so @inbox\/.@ captures as @inbox\/@
-- and a template literal @files.@ matches @files@. Internal punctuation (the
-- slash in @inbox\/@) is preserved: only the tail is sentence noise.
stripTrailingPunct :: Text -> Text
stripTrailingPunct = T.dropWhileEnd (`elem` (".,;:!?" :: String))

-- | Normalize a token for literal comparison: lowercase after stripping
-- trailing punctuation. Total and deterministic (no morphology yet).
normalizeToken :: Text -> Text
normalizeToken = T.toLower . stripTrailingPunct

-- | Tokenize a loose line into (surface, normalized) pairs. The surface form
-- (trailing punctuation removed) is what a hole captures; the normalized form
-- is what a literal template token is compared against.
tokenizeLine :: Text -> [(Text, Text)]
tokenizeLine = map (\w -> (stripTrailingPunct w, normalizeToken w)) . T.words

-- | Match a template against a tokenized line. Succeeds only on equal length
-- (single-token holes): each literal must equal the normalized token, each hole
-- binds the surface token. Returns the hole bindings, or Nothing on any
-- mismatch. A repeated hole must bind consistently.
matchTemplate :: [TplTok] -> [(Text, Text)] -> Maybe (Map Text Text)
matchTemplate toks line
  | length toks /= length line = Nothing
  | otherwise = foldl' step (Just Map.empty) (zip toks line)
  where
    step Nothing _ = Nothing
    step (Just binds) (TLit lit, (_, norm))
      | lit == norm = Just binds
      | otherwise   = Nothing
    step (Just binds) (THole h, (surface, _)) =
      case Map.lookup h binds of
        Nothing               -> Just (Map.insert h surface binds)
        Just prev | prev == surface -> Just binds
                  | otherwise       -> Nothing

-- | Apply a matched pattern's bindings to produce the decision's subject,
-- kind, assertion, and strength. Bindings are complete by construction: every
-- target hole also appears in the template (validated when a pattern is read),
-- so substitution is total.
applyPattern :: Pattern -> Map Text Text -> (Subject, Kind, Assertion, Strength)
applyPattern p binds =
  ( Subject (T.splitOn "." (subst (pSubject p)))
  , pKind p
  , Assertion (subst (pAssertion p))
  , pStrength p
  )
  where
    subst parts = T.concat (map fill parts)
    fill (SLit t)  = t
    fill (SHole h) = Map.findWithDefault (missing h) h binds
    -- A missing hole is a pattern the reader should have rejected; make it loud.
    missing h = error ("applyPattern: unbound hole <" <> T.unpack h <> "> in pattern " <> T.unpack (pId p))

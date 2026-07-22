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
-- \"settled\"): holes bind a single token; holes may appear only in subject and
-- assertion, never replacing a template literal's meaning. These keep matching
-- total and closure-under-hole-edits a property by construction. Multi-token
-- holes and morphology are future work.
--
-- A pattern yields ONE OR MORE decisions from a matched line: a single loose
-- line often states several facts at once (\"http server in go on port 8080\"
-- fixes both language and port), and a line matches exactly one pattern, so the
-- pattern must emit every fact that line carries -- otherwise a demand on the
-- second fact could never be met. Each emit is a 'PatEmit'; a one-emit pattern
-- is the common case ('patOne').
module Lips.Kernel.Lang.Pattern
  ( TplTok (..)
  , StrPart (..)
  , PatEmit (..)
  , Pattern (..)
  , patOne
  , normalizeToken
  , stripTrailingPunct
  , lexTokens
  , unquote
  , tokenizeLine
  , matchTemplate
  , applyPattern
  , holesOf
  ) where

import           Data.Char       (isSpace)
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

-- | One decision a pattern emits: its kind and strength, plus subject and
-- assertion as holey strings filled from the matched line's captured tokens.
data PatEmit = PatEmit
  { peKind      :: Kind
  , peStrength  :: Strength
  , peSubject   :: [StrPart] -- substituted, then split on \".\" into a path
  , peAssertion :: [StrPart]
  }
  deriving (Eq, Show)

-- | A crystallization pattern: one token template and the decisions a matching
-- loose line produces. Each 'PatEmit' becomes one decision, its subject and
-- assertion built by filling holes with captured surface tokens.
data Pattern = Pattern
  { pId       :: Text
  , pTemplate :: [TplTok]
  , pEmits    :: [PatEmit]
  }
  deriving (Eq, Show)

-- | The common single-emit pattern (one loose line to one decision), spelled
-- out so call sites and tests stay readable.
patOne :: Text -> [TplTok] -> Kind -> Strength -> [StrPart] -> [StrPart] -> Pattern
patOne i tpl k s subj assn = Pattern i tpl [PatEmit k s subj assn]

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

-- | Whitespace-split a line, but keep a double-quoted @"..."@ span as ONE
-- token (quotes included), so a quoted value may contain spaces. Shared by the
-- line tokenizer and the template parser, so quoting is treated identically on
-- both sides: a quoted hole @"<body>"@ in a template and a quoted value in a
-- line lex to single tokens that line up.
lexTokens :: Text -> [Text]
lexTokens = go . T.stripStart
  where
    go t
      | T.null t       = []
      | T.head t == '"' =
          let (inner, after) = T.breakOn "\"" (T.tail t)
           in ("\"" <> inner <> "\"") : go (T.stripStart (T.drop 1 after))
      | otherwise =
          let (w, rest) = T.break isSpace t
           in w : go (T.stripStart rest)

-- | If a token is a @"..."@ quoted span, its inner text; else Nothing.
unquote :: Text -> Maybe Text
unquote w
  | T.length w >= 2, T.head w == '"', T.last w == '"' = Just (T.init (T.drop 1 w))
  | otherwise = Nothing

-- | Tokenize a loose line into (surface, normalized) pairs. A quoted span is
-- one token whose surface is its inner text (quotes stripped, verbatim, so a
-- captured value keeps its case and spaces); a bare word strips trailing
-- sentence punctuation, and its normalized form is what a literal template
-- token is compared against.
tokenizeLine :: Text -> [(Text, Text)]
tokenizeLine = filter (not . T.null . snd) . map tok . lexTokens
  where
    tok w = case unquote w of
      Just inner -> (inner, T.toLower inner)
      Nothing    -> (stripTrailingPunct w, normalizeToken w)
    -- A token that normalizes to empty is pure sentence punctuation (a lone
    -- "." left when a period is glued to a quoted value). It carries no
    -- meaning and is dropped, symmetric with the template side, so trailing
    -- punctuation never changes the token count a match depends on.

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

-- | Apply a matched pattern's bindings to produce one (subject, kind,
-- assertion, strength) tuple per emit. Bindings are complete by construction:
-- every target hole also appears in the template (validated when a pattern is
-- read), so substitution is total.
applyPattern :: Pattern -> Map Text Text -> [(Subject, Kind, Assertion, Strength)]
applyPattern p binds = map one (pEmits p)
  where
    one e =
      ( Subject (T.splitOn "." (subst (peSubject e)))
      , peKind e
      , Assertion (subst (peAssertion e))
      , peStrength e
      )
    subst parts = T.concat (map fill parts)
    fill (SLit t)  = t
    fill (SHole h) = Map.findWithDefault (missing h) h binds
    -- A missing hole is a pattern the reader should have rejected; make it loud.
    missing h = error ("applyPattern: unbound hole <" <> T.unpack h <> "> in pattern " <> T.unpack (pId p))

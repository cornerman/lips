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
-- \"settled\"): holes may appear only in subject and assertion, never replacing a
-- template literal's meaning. This keeps matching total and
-- closure-under-hole-edits a property by construction. Morphology is future
-- work.
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
import           Data.Maybe      (listToMaybe)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision (Assertion (..), Kind, Strength (Stated), Subject (..))
import Lips.Kernel.Surface  (stripTrailingPunct)

-- | A template token: a literal to match (stored already normalized), a hole
-- that binds one loose token's surface form, or a multi-token hole that binds
-- SEVERAL tokens (>= 1) as one space-joined capture. The multi-token hole is
-- the capture form for a value of several words: written @\<name.words>@, it
-- may sit anywhere in the template and ends where the template's next literal
-- matches (at the end of the template it binds the rest of the line, so one
-- line may carry many items without the kernel dictating any collection
-- syntax).
data TplTok = TLit Text | THole Text | TMulti Text
  deriving (Eq, Show)

-- | A piece of a target (subject or assertion) string: literal text or a hole
-- reference filled from the template's bindings.
data StrPart = SLit Text | SHole Text
  deriving (Eq, Show)

-- | One decision a pattern emits: its kind, plus subject and assertion as
-- holey strings filled from the matched line's captured tokens. A pattern
-- reads a program line the human wrote, so its emit is always a 'Stated' fact;
-- strength is not part of the emit grammar and 'applyPattern' fixes it.
data PatEmit = PatEmit
  { peKind      :: Kind
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
patOne :: Text -> [TplTok] -> Kind -> [StrPart] -> [StrPart] -> Pattern
patOne i tpl k subj assn = Pattern i tpl [PatEmit k subj assn]

-- | The hole names a pattern binds, in template order. A multi-token hole binds
-- a name too, so a target @<name>@ may be filled from such a capture (otherwise
-- 'applyPattern' could be partial and the reader would reject a target hole
-- bound only by a multi-token hole).
holesOf :: Pattern -> [Text]
holesOf p = [h | tok <- pTemplate p, h <- tokHoles tok]
  where
    tokHoles (THole h) = [h]
    tokHoles (TMulti h) = [h]
    tokHoles _         = []

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

-- | Match a template against a tokenized line. A literal must equal the
-- normalized token; a hole binds one surface token; a @TMulti@ binds one or
-- more tokens, space-joined. A repeated hole must bind consistently.
--
-- Search order makes the result deterministic: a multi-token hole takes the
-- FEWEST tokens it can, and the rest of the template decides. When the rest
-- then fails, the hole grows -- @back up \<src.words> to \<dst>@ must read
-- @back up a to b to c@ as src=\"a to b\", since src=\"a\" leaves \"to c\"
-- unmatched. Without that backtracking a line inside the language would be
-- reported as outside it, which is a grammar bug, not a program defect. The
-- search is over the line's tokens (a handful), and laziness stops it at the
-- first success.
matchTemplate :: [TplTok] -> [(Text, Text)] -> Maybe (Map Text Text)
matchTemplate toks line = listToMaybe (go toks line Map.empty)
  where
    go :: [TplTok] -> [(Text, Text)] -> Map Text Text -> [Map Text Text]
    go [] [] binds = [binds]
    go [] _  _     = []
    go (TLit lit : ts) ((_, norm) : rs) binds
      | lit == norm = go ts rs binds
      | otherwise   = []
    go (TLit _ : _) [] _ = []
    go (THole h : ts) ((surface, _) : rs) binds =
      [ b' | b <- bind h surface binds, b' <- go ts rs b ]
    go (THole _ : _) [] _ = []
    -- Never guess: a multi-token hole binds at least one token, so `splits`
    -- starts at one and an empty rest yields no match at all.
    go (TMulti h : ts) rest binds =
      [ b'
      | (taken, rs) <- splits rest
      , b  <- bind h (T.unwords (map fst taken)) binds
      , b' <- go ts rs b
      ]
    splits xs = [ splitAt n xs | n <- [1 .. length xs] ]
    -- A repeated hole must bind the same surface text at every occurrence.
    bind h v binds = case Map.lookup h binds of
      Nothing                    -> [Map.insert h v binds]
      Just prev | prev == v      -> [binds]
                | otherwise      -> []

-- | Apply a matched pattern's bindings to produce one (subject, kind,
-- assertion, strength) tuple per emit. Bindings are complete by construction:
-- every target hole also appears in the template (validated when a pattern is
-- read), so substitution is total.
applyPattern :: Pattern -> Map Text Text -> [(Subject, Kind, Assertion, Strength)]
applyPattern p binds = map one (pEmits p)
  where
    one e =
      ( Subject (segsOf (peSubject e))
      , peKind e
      , Assertion (subst (peAssertion e))
      , Stated  -- a pattern reads a program line: its emit is always a stated fact
      )
    subst parts = T.concat (map fill parts)
    fill (SLit t)  = t
    fill (SHole h) = Map.findWithDefault (missing h) h binds
    -- A missing hole is a pattern the reader should have rejected; make it loud.
    missing h = error ("applyPattern: unbound hole <" <> T.unpack h <> "> in pattern " <> T.unpack (pId p))
    -- Build the subject segments from the template structure, NOT by filling to
    -- a flat string and splitting on ".": only a LITERAL dot separates segments,
    -- while a captured value is atomic and keeps any dots it carries (an HTTP
    -- route @\/file.json@ stays one key segment, not two). A literal's dots
    -- still split, so a plain subject like @backup.source@ is unchanged.
    segsOf = foldr step [""] . map fill'
      where
        fill' (SLit t)  = Left t                     -- separator-bearing literal
        fill' (SHole h) = Right (Map.findWithDefault (missing h) h binds)
        step (Right v) (seg : rest) = (v <> seg) : rest
        step (Right _) []           = []             -- unreachable: acc always non-empty
        step (Left t)  acc          = prepend (T.splitOn "." t) acc
        -- Join the last literal piece onto the first accumulated segment; the
        -- earlier pieces become their own segments (the dots that separate them).
        prepend pieces (seg : rest) =
          init pieces ++ [(last pieces <> seg)] ++ rest
        prepend pieces []           = pieces

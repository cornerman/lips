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
  , FusedSeg (..)
  , matchFused
  , StrPart (..)
  , PatEmit (..)
  , StructType (..)
  , structHole
  , structHoles
  , refName
  , Pattern (..)
  , patOne
  , patUnder
  , parsePatternId
  , renderPatternId
  , normalizeToken
  , stripTrailingPunct
  , lexTokens
  , unquote
  , tokenizeLine
  , matchTemplate
  , fusedHoles
  , applyPattern
  , holesOf
  ) where

import           Control.Monad   (foldM)
import           Data.Char       (isSpace)
import           Data.Maybe      (listToMaybe)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Decision (Assertion (..), Kind, Strength (Stated), Subject (..))
import Lips.Kernel.Reader   (splitSubject)
import Lips.Kernel.Surface  (stripTrailingPunct)

-- | A template token: a literal to match (stored already normalized), a hole
-- that binds one loose token's surface form, or a multi-token hole that binds
-- SEVERAL tokens (>= 1) as one space-joined capture. The multi-token hole is
-- the capture form for a value of several words: written @\<name.words>@, it
-- may sit anywhere in the template and ends where the template's next literal
-- matches (at the end of the template it binds the rest of the line, so one
-- line may carry many items without the kernel dictating any collection
-- syntax).
--
-- A FUSED token holds literal text and holes inside ONE token, which is
-- how a value sits against punctuation (@println("\<text>")@, @--port=\<n>@,
-- @k=\<v>@). Without the fused form a hole had to be a whole whitespace token,
-- so no language with call or flag syntax could be read at all -- a missing
-- grammar case, not a program defect. A fused hole binds within its token only:
-- it stops where the next literal piece matches, and a value that must span
-- whitespace is either quoted (the quote makes it one token) or a @TMulti@.
data TplTok = TLit Text | THole Text | TMulti Text | TFused [FusedSeg]
  deriving (Eq, Show)

-- | A piece of a fused template token: literal text (stored lowercased, matched
-- case-insensitively like 'TLit') or a hole binding one non-empty run of
-- characters inside the same token.
data FusedSeg = FLit Text | FHole Text
  deriving (Eq, Show, Ord)

-- | A piece of a target (subject or assertion) string: literal text or a hole
-- reference filled from the bindings in scope.
data StrPart = SLit Text | SHole Text
  deriving (Eq, Show)

-- | What a STRUCTURE-BOUND hole is filled from. A template hole binds a token of
-- the line; a structure-bound hole binds a fact about where the line SITS, which
-- no token can carry. Written @\<name:index\>@ in an emit, never in a template.
--
-- Closed, and the extension point for any further structural fact (a depth, a
-- sibling count): one constructor, one entry in 'structTypes', and the fill site
-- in 'Lips.Kernel.Lang.Nest' -- never an open list the kernel enumerates.
data StructType
  = -- | The line's 1-based position among the lines that matched the same
    -- pattern in the same block. Gives an item with no key of its own an
    -- identity, so two anonymous records stay two.
    SIndex
  | -- | The subject of the line that heads this line's block (that line's first
    -- emit). Keys compose inductively, which is what makes unbounded depth work:
    -- a pattern nested under itself writes @\<k:key\>.\<name\>@ and a node three
    -- deep keys as @tree.File.New.Item@, so two subtrees may share a node name.
    SKey
  deriving (Eq, Show)

-- | The closed table of structure-bound hole types, by their spelling.
structTypes :: [(Text, StructType)]
structTypes = [("index", SIndex), ("key", SKey)]

-- | Read a hole reference as a structure-bound DECLARATION: @\"n:index\"@ is the
-- hole @n@, filled from the line's position among its siblings. An unrecognized
-- suffix is not one (a name may legitimately contain a colon), matching how a
-- template hole only drops a RECOGNIZED type.
structHole :: Text -> Maybe (Text, StructType)
structHole h = case T.breakOn ":" h of
  (name, ty) | not (T.null ty), not (T.null name)
             , Just st <- lookup (T.drop 1 ty) structTypes -> Just (name, st)
  _ -> Nothing

-- | The name a hole reference resolves to: @\"n:index\"@ and @\"n\"@ are the same
-- binding, so the declaration and every reference to it (including from a
-- descendant pattern) line up without a second spelling.
refName :: Text -> Text
refName h = maybe h fst (structHole h)

-- | The structure-bound holes a pattern declares, in emit order, deduplicated.
structHoles :: Pattern -> [(Text, StructType)]
structHoles p = nubFst
  [ s
  | e <- pEmits p
  , part <- peSubject e ++ peAssertion e
  , SHole h <- [part]
  , Just s <- [structHole h]
  ]
  where
    nubFst = foldr keep []
    keep x acc = if fst x `elem` map fst acc then acc else x : acc

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
--
-- 'pParents' names the patterns this one nests UNDER, in the order they are
-- tried: a matching line is read as an item of the block headed by the nearest
-- preceding line that matched the FIRST of them that has one, and that line's
-- captures are in scope here ('Lips.Kernel.Lang.Nest'). Nothing about a block is
-- spelled in the template, so the kernel never learns how a language marks one
-- -- the language's own words do, through the parent's template.
--
-- A list, not one parent, because a recursive item needs two: itself (an item
-- inside an item, resolved by depth) and the header that roots the outermost
-- ones. @n1.under.n1.under.n0@ reads exactly that way. Each LINE still has
-- exactly one parent; the list is the order they are tried in.
data Pattern = Pattern
  { pId       :: Text
  , pParents  :: [Text]
  , pTemplate :: [TplTok]
  , pEmits    :: [PatEmit]
  }
  deriving (Eq, Show)

-- | The common single-emit, top-level pattern (one loose line to one decision),
-- spelled out so call sites and tests stay readable.
patOne :: Text -> [TplTok] -> Kind -> [StrPart] -> [StrPart] -> Pattern
patOne i tpl k subj assn = Pattern i [] tpl [PatEmit k subj assn]

-- | A pattern nested under another, by parent id.
patUnder :: Text -> Text -> [TplTok] -> [PatEmit] -> Pattern
patUnder i parent = Pattern i [parent]

-- | Split a pattern id token into the pattern's own id and the parent it nests
-- under: @p3.under.p2@ is the pattern @p3@ inside @p2@'s block. One spelling at
-- both doors -- the stored subject path @lang.pattern.p3.under.p2@ and the mint
-- item's id token -- so the two cannot drift.
--
-- Carried on the id rather than inside the pattern body because the body is
-- free template text: a prefix there could not be told apart from a template
-- that legitimately begins with the word @under@, and refusing such a template
-- would be a missing grammar case (invariant 3). On the id it is also
-- structurally at most one parent, so \"two parents\" needs no check.
parsePatternId :: Text -> Either Text (Text, [Text])
parsePatternId tok = case T.splitOn ".under." tok of
  parts@(i : parents)
    | all (not . T.null) parts -> Right (i, parents)
  _ -> Left ("pattern id " <> tok <> ": a nested id is <id>.under.<parent>")

-- | The id token a pattern is stored and minted under (inverse of
-- 'parsePatternId'): the bare id, or @\<id\>.under.\<parent\>@ (repeated for a
-- recursive item's fallback chain).
renderPatternId :: Pattern -> Text
renderPatternId p = T.intercalate ".under." (pId p : pParents p)

-- | The hole names a pattern's TEMPLATE binds, in template order. A multi-token
-- hole binds a name too, so a target @<name>@ may be filled from such a capture
-- (otherwise 'applyPattern' could be partial and the reader would reject a
-- target hole bound only by a multi-token hole). Structure-bound holes are not
-- here: they are declared in the emits ('structHoles').
holesOf :: Pattern -> [Text]
holesOf p = [h | tok <- pTemplate p, h <- tokHoles tok]
  where
    tokHoles (THole h) = [h]
    tokHoles (TMulti h) = [h]
    tokHoles (TFused segs) = fusedHoles segs
    tokHoles _         = []

-- | The hole names a fused token binds, in order.
fusedHoles :: [FusedSeg] -> [Text]
fusedHoles segs = [h | FHole h <- segs]

-- | Normalize a token for literal comparison: lowercase after stripping
-- trailing punctuation. Total and deterministic (no morphology yet).
normalizeToken :: Text -> Text
normalizeToken = T.toLower . stripTrailingPunct

-- | Whitespace-split a line, but keep a double-quoted @"..."@ span as ONE
-- token (quotes included), so a quoted value may contain spaces. Shared by the
-- line tokenizer and the template parser, so quoting is treated identically on
-- both sides: a quoted hole @"<body>"@ in a template and a quoted value in a
-- line lex to single tokens that line up.
-- A quoted span is atomic wherever it STARTS, not only at the head of a token:
-- @println("hallo du")@ is one token, since the quote is the mark that says
-- "these spaces belong to a value". Reading it as two tokens would make a call
-- argument with a space unreadable.
lexTokens :: Text -> [Text]
lexTokens = go . T.stripStart
  where
    go t
      | T.null t  = []
      | otherwise = let (w, rest) = word "" t in w : go (T.stripStart rest)
    -- Accumulate one token: whitespace ends it, a quote pulls in the whole
    -- quoted span (spaces included) and the token continues after it.
    word acc t = case T.uncons t of
      Nothing -> (acc, t)
      Just (c, cs)
        | isSpace c -> (acc, cs)
        | c == '"' ->
            let (inner, after) = T.breakOn "\"" cs
             in word (acc <> "\"" <> inner <> "\"") (T.drop 1 after)
        | otherwise -> word (T.snoc acc c) cs

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
    -- Trailing sentence punctuation goes first, so a quoted value closing a
    -- sentence (@"hello".@) is still recognized as quoted and hands over its
    -- inner text.
    tok w = case unquote (stripTrailingPunct w) of
      Just inner -> (inner, T.toLower inner)
      Nothing    -> (stripTrailingPunct w, normalizeToken w)
    -- A token that normalizes to empty is pure sentence punctuation (a lone
    -- "." left when a period is fused to a quoted value). It carries no
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
    -- A fused token matches within one token: its literal pieces must appear,
    -- and each of its holes binds the characters between them.
    go (TFused segs : ts) ((surface, _) : rs) binds =
      [ b'
      | caps <- maybe [] (: []) (matchFused segs surface)
      , b <- foldM (\acc (h, v) -> bind h v acc) binds caps
      , b' <- go ts rs b
      ]
    go (TFused _ : _) [] _ = []
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

-- | Match a fused token's segments against one token's surface text, yielding
-- what each hole binds, in order. Literals compare case-insensitively (as
-- 'TLit' does); a hole binds a non-empty run of characters and takes the
-- FEWEST it can, so the literal after it lands on its first occurrence, and the
-- search backtracks when the rest of the token then fails.
matchFused :: [FusedSeg] -> Text -> Maybe [(Text, Text)]
matchFused segs surface = listToMaybe (go segs surface)
  where
    go [] rest = [[] | T.null rest]
    go (FLit l : ss) rest = case T.stripPrefix l (T.toLower rest) of
      Just _  -> go ss (T.drop (T.length l) rest)
      Nothing -> []
    go (FHole h : ss) rest =
      [ (h, T.take n rest) : caps
      | n <- [1 .. T.length rest]
      , caps <- go ss (T.drop n rest)
      ]

-- | Apply a matched pattern's bindings to produce one (subject, kind,
-- assertion, strength) tuple per emit. Bindings are complete by construction:
-- every target hole also appears in the template (validated when a pattern is
-- read), so substitution is total.
applyPattern :: Pattern -> Map Text Text -> [(Subject, Kind, Assertion, Strength)]
applyPattern p binds = map one (pEmits p)
  -- A key hole carries a whole subject PATH, so its segments are segments; every
  -- other hole stays one atomic segment (an HTTP route @/file.json@ is one key).
  -- Decided from the pattern's own declarations, so the reference spelling
  -- (@\<k:key\>@ or the plain @\<k\>@) does not change the reading.
  where
    one e =
      ( Subject (segsOf (peSubject e))
      , peKind e
      , Assertion (subst (peAssertion e))
      , Stated  -- a pattern reads a program line: its emit is always a stated fact
      )
    subst parts = T.concat (map fill parts)
    fill (SLit t)  = t
    fill (SHole h) = Map.findWithDefault (missing h) (refName h) binds
    -- A missing hole is a pattern the reader should have rejected; make it loud.
    missing h = error ("applyPattern: unbound hole <" <> T.unpack h <> "> in pattern " <> T.unpack (pId p))
    -- Build the subject segments from the template structure, NOT by filling to
    -- a flat string and splitting on ".": only a LITERAL dot separates segments,
    -- while a captured value is atomic and keeps any dots it carries (an HTTP
    -- route @\/file.json@ stays one key segment, not two). A literal's dots
    -- still split, so a plain subject like @backup.source@ is unchanged.
    segsOf = foldr step [""] . map fill'
      where
        fill' (SLit t)  = PLit t                     -- separator-bearing literal
        fill' (SHole h)
          | refName h `elem` keyHoles = PPath (splitSubject (valOf h))
          | otherwise                 = PAtom (valOf h)
        valOf h  = Map.findWithDefault (missing h) (refName h) binds
        keyHoles = [n | (n, SKey) <- structHoles p]
        step (PAtom v) (seg : rest)  = (v <> seg) : rest
        step (PAtom _) []            = []            -- unreachable: acc always non-empty
        step (PLit t)  acc           = prepend (T.splitOn "." t) acc
        step (PPath ps) acc          = prepend ps acc
        -- Join the last literal piece onto the first accumulated segment; the
        -- earlier pieces become their own segments (the dots that separate them).
        prepend pieces (seg : rest) =
          init pieces ++ [(last pieces <> seg)] ++ rest
        prepend pieces []           = pieces

-- | A filled target piece on its way to becoming subject segments: literal text
-- (whose dots separate), one atomic captured value (whose dots do not, so an
-- HTTP route @\/file.json@ stays one key), or a whole subject path from a key
-- hole, already segmented.
data Piece = PLit Text | PAtom Text | PPath [Text]

{-# LANGUAGE OverloadedStrings #-}

-- | The surface conventions of lips text: how a line is quoted, where it may be
-- split, and what counts as sentence noise at the end of a token. Every layer
-- that reads or writes lips text (a decision line, a @.lang@ pattern, a rule
-- body, a program token) shares them.
--
-- The quoting and separator rules every stored lips line shares: a decision
-- line, a @.lang@ pattern body, a rule body, an expect body. All of them wrap
-- free text in @"..."@ with @\\"@ and @\\\\@ escapes, and all of them separate
-- clauses with a token (@ => @, @ ; @) that the free text may itself contain.
--
-- One module, because this is one piece of knowledge. It used to live in three
-- copies with three levels of care: the pattern side split on the separator
-- that lies OUTSIDE quotes, while the rule side split naively, so a rule whose
-- rhs held @" ; "@ (an ordinary shell text, @\"cd \/x ; ls\"@) could not be
-- written at all -- and reported the defect as an unterminated string. A
-- missing grammar case is a kernel bug, so the careful rule became the only
-- rule.
module Lips.Kernel.Surface
  ( quoteText
  , parseQuoted
  , unescapedQuotes
  , splitOutsideQuotes
  , breakFirstOutsideQuotes
  , breakLastOutsideQuotes
  , stripTrailingPunct
  , valueTokens
  , valueText
  , fillValueHoles
  , NaturalKey
  , naturalKey
  ) where

import           Data.Char (isDigit, isSpace)
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Read as TR

-- | The canonical order of lips ids: a run of digits compares as a NUMBER, so
-- @p2@ precedes @p10@ in every stored file, the way a human reads the list.
-- Plain text order put @p10@ between @p1@ and @p2@, which makes a twenty-line
-- engine unreadable and a diff of two of them noise.
--
-- Ties (ids differing only in leading zeros, @p01@ vs @p1@) fall back to the
-- raw text, so the order stays TOTAL and consistent with equality -- required,
-- since 'Lips.Kernel.Decision.DecisionId' keys a Map.
data NaturalKey = NaturalKey [Chunk] Text
  deriving (Eq, Ord, Show)

-- | One run of an id: digits compare numerically, everything else as text.
-- Digits sort before letters at the same position, as in plain text order.
data Chunk = Number Integer | Word Text
  deriving (Eq, Ord, Show)

naturalKey :: Text -> NaturalKey
naturalKey t = NaturalKey (chunks t) t
  where
    chunks s = case T.uncons s of
      Nothing -> []
      Just (c, _)
        | isDigit c -> let (ds, rest) = T.span isDigit s
                        in Number (readDigits ds) : chunks rest
        | otherwise -> let (w, rest) = T.break isDigit s
                        in Word w : chunks rest
    -- 'T.span isDigit' guarantees a non-empty run of digits, so the decimal
    -- read cannot fail; 0 keeps the function total.
    readDigits ds = either (const 0) fst (TR.decimal ds)

-- | The parts of a STATED value: whitespace-separated, except that a @"..."@
-- span is one part and hands over its inner text (escapes undone by
-- 'parseQuoted').
--
-- A value can be built from several program words at once (a route's status and
-- its body, a button's label and its target), and a rule then reads one part by
-- position (@\<value.N\>@). Splitting on whitespace alone lost the boundary
-- between the parts, so a two-word part silently shifted every later index and
-- dropped the last part -- wrong output, every gate green. So a several-part
-- value quotes its parts ('Lips.Kernel.Lang.Pattern.applyPattern') and this is
-- the inverse: one part per hole, whatever a part contains. A one-part value
-- carries no quotes and still splits into words, which is what a rule building a
-- LIST out of one many-word value needs.
valueTokens :: Text -> [Text]
valueTokens = go . T.stripStart
  where
    go t
      | T.null t = []
      | T.head t == '"' = case parseQuoted t of
          -- An unterminated quote is not a part boundary: fall back to the plain
          -- word, so a value carrying a lone quote still yields tokens.
          Left _              -> plain t
          Right (inner, rest) -> inner : go (T.stripStart rest)
      | otherwise = plain t
    plain t = let (w, rest) = T.break isSpace t in w : go (T.stripStart rest)

-- | A stated value as one text, with the part quoting undone: the parts joined
-- by single spaces. A value with no quoted part is returned verbatim, so the
-- quoting stays an encoding of the multi-part case and a rule reading the whole
-- value never sees it.
valueText :: Text -> Text
valueText t
  | T.any (== '"') t = T.unwords (valueTokens t)
  | otherwise        = t

-- | Fill @\<value\>@ and @\<value.N\>@ in a template from a STATED value: the
-- whole value for @\<value\>@ (its parts joined by single spaces, as
-- 'valueText' reads it), the Nth part for @\<value.N\>@.
--
-- Lives beside 'valueTokens' because this is the module that already knows what
-- a PART is. It is plain-text filling, deliberately narrower than the rule
-- side's ('Lips.Kernel.Engine.Data'\'s @pick@, which also resolves typed holes
-- and the captures a subject binds): a contract states text, and a hole naming a
-- part that is not there is a 'Left' rather than an empty string, so a template
-- can never silently produce half a string.
fillValueHoles :: Text -> Text -> Either Text Text
fillValueHoles template val = go template
  where
    parts = valueTokens val
    go t = case T.breakOn "<value" t of
      (before, rest)
        | T.null rest -> Right before
        | otherwise -> case T.breakOn ">" (T.drop (T.length ("<value" :: Text)) rest) of
            -- An unterminated hole is literal text, not a silent fill.
            (_, "")         -> Right (before <> rest)
            (inner, closed) -> do
              filled <- fill inner
              ((before <> filled) <>) <$> go (T.drop 1 closed)
    -- What sits between "<value" and ">": nothing for the whole value, ".N" for
    -- its Nth part.
    fill inner
      | T.null inner = Right (valueText val)
      | Just d <- T.stripPrefix "." inner
      , Right (n, "") <- TR.decimal d
      , n >= 1, n <= length parts = Right (parts !! (n - 1))
      | otherwise = Left ("<value" <> inner <> "> is not a part of " <> val)

-- | Wrap text as a transport-quoted lips string, escaping @"@ and @\\@.
-- Inverse of 'parseQuoted'.
quoteText :: Text -> Text
quoteText a = "\"" <> T.concatMap esc a <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = T.singleton c

-- | Parse a leading transport-quoted string, returning its unescaped content
-- and whatever follows the closing quote. Fails loud on a missing opening
-- quote, a missing closing quote and a dangling escape; the caller prefixes the
-- message with its own context (which pattern, which rule).
parseQuoted :: Text -> Either Text (Text, Text)
parseQuoted t = case T.uncons t of
  Just ('"', rest) -> go rest T.empty
  _                -> Left "expected a quoted string"
  where
    go s acc = case T.uncons s of
      Nothing           -> Left "unterminated string"
      Just ('"', rest)  -> Right (acc, rest)
      -- Only @\"@ and @\\@ are TRANSPORT escapes. Any other escape belongs to
      -- the layer inside (a value's @\n@, which
      -- 'Lips.Kernel.Engine.Value.pString' turns into a newline), so it is
      -- passed through with its backslash intact. Swallowing the backslash here
      -- silently turned a minted @"200\n404"@ into @"200n404"@: valid output,
      -- wrong text, and no gate can see it.
      Just ('\\', more) -> case T.uncons more of
        Just (c, more')
          | c == '"' || c == '\\' -> go more' (T.snoc acc c)
          | otherwise             -> go more' (acc <> T.pack ['\\', c])
        Nothing         -> Left "dangling escape"
      Just (c, more)    -> go more (T.snoc acc c)

-- | Count unescaped double quotes in a prefix, so a scan can tell whether a
-- split point lies inside a quoted span (odd count) or outside it (even).
unescapedQuotes :: Text -> Int
unescapedQuotes t = go (T.unpack t) (0 :: Int)
  where
    go []              n = n
    go ('\\' : _ : cs) n = go cs n
    go ('"' : cs)      n = go cs (n + 1)
    go (_ : cs)        n = go cs n

-- | Every occurrence of @sep@ that lies outside quotes, as a break point.
outsideQuotes :: Text -> Text -> [(Text, Text)]
outsideQuotes sep t =
  [ (b, T.drop (T.length sep) a)
  | (b, a) <- T.breakOnAll sep t
  , even (unescapedQuotes b)
  ]

-- | Split on every @sep@ that lies outside quotes, leftmost first. A @sep@
-- inside a quoted span is content, not a separator.
splitOutsideQuotes :: Text -> Text -> [Text]
splitOutsideQuotes sep t = case outsideQuotes sep t of
  []           -> [t]
  ((b, a) : _) -> b : splitOutsideQuotes sep a

-- | Break at the FIRST @sep@ outside quotes: for a body whose left side is
-- quote-free and whose right side may hold the separator as content.
breakFirstOutsideQuotes :: Text -> Text -> Maybe (Text, Text)
breakFirstOutsideQuotes sep t = case outsideQuotes sep t of
  []       -> Nothing
  (x : _)  -> Just x

-- | Break at the LAST @sep@ outside quotes: for a body whose left side may
-- hold the separator as content (a pattern template writing @=>@ itself).
breakLastOutsideQuotes :: Text -> Text -> Maybe (Text, Text)
breakLastOutsideQuotes sep t = case outsideQuotes sep t of
  [] -> Nothing
  xs -> Just (last xs)

-- | Strip trailing sentence punctuation, so @inbox\/.@ captures as @inbox\/@,
-- a template literal @files.@ matches @files@, and a value token keeps its
-- meaning when a human ends the sentence. Internal punctuation (the slash in
-- @inbox\/@) is preserved: only the tail is noise. One definition, because the
-- language layer and the value grammar were each carrying their own copy of the
-- same character list.
stripTrailingPunct :: Text -> Text
stripTrailingPunct = T.dropWhileEnd (`elem` (".,;:!?" :: String))

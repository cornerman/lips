{-# LANGUAGE OverloadedStrings #-}

-- | The quoting and separator rules every stored lips line shares: a decision
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
module Lips.Kernel.Quoting
  ( quoteText
  , parseQuoted
  , unescapedQuotes
  , splitOutsideQuotes
  , breakFirstOutsideQuotes
  , breakLastOutsideQuotes
  ) where

import           Data.Text (Text)
import qualified Data.Text as T

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
      Just ('\\', more) -> case T.uncons more of
        Just (c, more') -> go more' (T.snoc acc c)
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

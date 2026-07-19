{-# LANGUAGE OverloadedStrings #-}

-- | The closed value language for minted rule right-hand sides.
--
-- A minted engine's rhs is NOT a Nix expression. It is a value in this closed
-- grammar -- string, list, boolean, integer -- and nothing else parses:
--
-- > value  ::= string | list | bool | int
-- > string ::= '"' (literal | ${pkgs.<dotted-path>} | <value> | <value.N>)* '"'
-- > list   ::= '[' value* ']'
--
-- Why: the first live minting run showed the model smuggling computation into
-- rhs strings (@lib.splitString@ gymnastics), with only the prompt forbidding
-- it. Per the spec (deduce-or-fail layer 1, structural; \"no workarounds by
-- definition\"), computation must be unrepresentable, not discouraged: this
-- AST has no constructor for function application, so a minted engine cannot
-- compute at realize time. The only interpolation a string may carry is a
-- @${pkgs.<dotted-path>}@ package reference (a name, not a computation).
--
-- Filling holes escapes the inserted program text (quotes, backslashes, and
-- @${@), so a program value can never break out of the Nix string it lands
-- in: injection is unrepresentable as well.
module Lips.Kernel.Engine.Value
  ( Value (..)
  , Piece (..)
  , parseValue
  , renderValue
  , fillValue
  , holeIndex
  ) where

import           Data.Char      (isDigit)
import           Data.Text      (Text)
import qualified Data.Text      as T
import qualified Data.Text.Read as TR

-- | One piece of a string value. 'PRef' is a @${pkgs.<dotted-path>}@ package
-- reference; 'PHole' is @\<value\>@ or @\<value.N\>@.
data Piece = PLit Text | PRef [Text] | PHole Text
  deriving (Eq, Show)

-- | A rhs value. No constructor for computation exists.
data Value
  = VStr [Piece]
  | VList [Value]
  | VBool Bool
  | VInt Integer
  deriving (Eq, Show)

-- | @value.N@ -> N (1-based); @value@ -> Nothing is NOT covered here, only
-- indexed holes. Shared with the rule executor.
holeIndex :: Text -> Maybe Int
holeIndex h = do
  numTxt <- T.stripPrefix "value." h
  case TR.decimal numTxt of
    Right (n, rest) | T.null rest, n >= 1 -> Just n
    _ -> Nothing

-- | Parse a rhs text into a 'Value'. Anything outside the grammar -- bare
-- identifiers, function application, non-pkgs interpolation -- is an error
-- naming what was rejected.
parseValue :: Text -> Either Text Value
parseValue t = do
  (v, rest) <- pValue (T.stripStart t)
  if T.null (T.stripStart rest)
    then Right v
    else Left ("trailing content after value (computation is not a value): " <> T.strip rest)

pValue :: Text -> Either Text (Value, Text)
pValue t = case T.uncons t of
  Nothing -> Left "empty rhs"
  Just ('"', rest) -> pString rest
  Just ('[', rest) -> pList (T.stripStart rest) []
  Just (c, _)
    | c == '-' || isDigit c -> pInt t
    | Just rest <- T.stripPrefix "true" t -> Right (VBool True, rest)
    | Just rest <- T.stripPrefix "false" t -> Right (VBool False, rest)
    | otherwise ->
        Left ("rhs must be a string, list, boolean, or integer (no Nix computation): " <> t)

pInt :: Text -> Either Text (Value, Text)
pInt t = case TR.signed TR.decimal t of
  Right (n, rest) -> Right (VInt n, rest)
  Left _          -> Left ("bad integer: " <> t)

pList :: Text -> [Value] -> Either Text (Value, Text)
pList t acc = case T.uncons t of
  Nothing          -> Left "unterminated list"
  Just (']', rest) -> Right (VList (reverse acc), rest)
  _ -> do
    (v, rest) <- pValue t
    pList (T.stripStart rest) (v : acc)

-- String scanning: literal text with escapes, ${pkgs...} refs, <value> holes.

pString :: Text -> Either Text (Value, Text)
pString = go [] T.empty
  where
    go pieces acc s = case T.uncons s of
      Nothing -> Left "unterminated string"
      Just ('"', rest) -> Right (VStr (reverse (flush acc pieces)), rest)
      Just ('\\', more) -> case T.uncons more of
        Just (c, more') -> go pieces (T.snoc acc c) more'
        Nothing         -> Left "dangling escape in string"
      Just ('$', more)
        | Just body <- T.stripPrefix "{" more -> do
            let (inside, after) = T.breakOn "}" body
            ref <- pkgsRef inside
            if T.null after
              then Left "unterminated ${...} in string"
              else go (PRef ref : flush acc pieces) T.empty (T.drop 1 after)
      Just ('<', more) -> do
        let (hole, after) = T.breakOn ">" more
        if T.null after
          then Left ("unterminated hole <" <> hole)
          else
            if hole == "value" || holeIndex hole /= Nothing
              then go (PHole hole : flush acc pieces) T.empty (T.drop 1 after)
              else Left ("unknown hole <" <> hole <> "> (only <value> and <value.N> are defined)")
      Just (c, more) -> go pieces (T.snoc acc c) more
    flush acc pieces = if T.null acc then pieces else PLit acc : pieces

-- | The one interpolation allowed: a dotted path rooted at @pkgs@. A name,
-- not a computation: spaces, parentheses, or operators do not parse.
pkgsRef :: Text -> Either Text [Text]
pkgsRef inside =
  let segs = T.splitOn "." inside
      okSeg s = not (T.null s) && T.all (\c -> c `elem` ("-_" :: String) || isDigit c || isAlpha c) s
      isAlpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
   in case segs of
        ("pkgs" : more) | not (null more), all okSeg more -> Right segs
        _ ->
          Left ("only ${pkgs.<path>} interpolation is allowed (a package reference, not computation): ${"
                  <> inside <> "}")

-- | Canonical text of a value; the exact Nix expression realize will splice.
-- Deterministic and injection-free by construction: literal string content is
-- re-escaped on the way out.
renderValue :: Value -> Text
renderValue (VBool True)  = "true"
renderValue (VBool False) = "false"
renderValue (VInt n)      = T.pack (show n)
renderValue (VList vs)    = "[ " <> T.unwords (map renderValue vs) <> " ]"
renderValue (VStr ps)     = "\"" <> T.concat (map piece ps) <> "\""
  where
    piece (PLit t)  = escape t
    piece (PRef r)  = "${" <> T.intercalate "." r <> "}"
    piece (PHole h) = "<" <> h <> ">"

-- | Escape text destined for the inside of a Nix string: quotes, backslashes,
-- and @${@ (which would otherwise open an interpolation -- the injection).
escape :: Text -> Text
escape = T.replace "${" "\\${" . T.replace "\"" "\\\"" . T.replace "\\" "\\\\"

-- | Fill every hole with (a selection from) the program value and render.
-- The filled text goes through 'escape', so program text can never alter the
-- shape of the value it lands in. Out-of-range @\<value.N\>@ is reported via
-- the callback's error channel by the caller; here it is caller-supplied.
fillValue :: (Text -> Text) -> Value -> Text
fillValue pick = renderValue . fillV
  where
    fillV (VStr ps)  = VStr (map fillP ps)
    fillV (VList vs) = VList (map fillV vs)
    fillV v          = v
    fillP (PHole h) = PLit (pick h)
    fillP p         = p

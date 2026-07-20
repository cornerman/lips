{-# LANGUAGE OverloadedStrings #-}

-- | The closed value language for minted rule right-hand sides.
--
-- A minted engine's rhs is NOT a Nix expression. It is a value in this closed
-- grammar, and its grammar is deliberately the Nix value algebra MINUS
-- computation (completeness plan, Target 1):
--
-- > value  ::= string | list | bool | int | float | path | null | typed-hole
-- > string ::= '"' (literal | ${pkgs.<dotted-path>} | <value> | <value.N>)* '"'
-- > list   ::= '[' value* ']'
-- > typed-hole ::= '<' ('value' | 'value.'N) ':' ('int'|'bool'|'float'|'path') '>'
--
-- Why the full algebra: every program value becomes a hole (mint doctrine),
-- and NixOS options are typed. A string hole can only produce a Nix string, so
-- an integer-typed option (a port) filled from a program value was
-- unrepresentable. Rather than grow the grammar one type at a time, it covers
-- the whole Nix value algebra; the only excluded form is @function@, which is
-- computation and routes to glue.
--
-- Two guarantees hold by construction:
--
--   * /No computation/. There is no constructor for function application, so a
--     minted engine cannot compute at realize time. The one interpolation a
--     string may carry is @${pkgs.<dotted-path>}@ (a package name, not a
--     computation).
--   * /No injection/. Filling a hole escapes inserted program text (quotes,
--     backslashes, @${@ for strings; charset-validated for paths; parsed to a
--     number/keyword for int\/float\/bool), so a program value can never alter
--     the shape of the value it lands in.
module Lips.Kernel.Engine.Value
  ( Value (..)
  , Piece (..)
  , HoleType (..)
  , parseValue
  , renderValue
  , fillValue
  , holeIndex
  ) where

import           Data.Char      (isDigit, isSpace)
import           Data.Text      (Text)
import qualified Data.Text      as T
import qualified Data.Text.Read as TR

-- | One piece of a string value. 'PRef' is a @${pkgs.<dotted-path>}@ package
-- reference; 'PHole' is @\<value\>@ or @\<value.N\>@ (a string hole).
data Piece = PLit Text | PRef [Text] | PHole Text
  deriving (Eq, Show)

-- | The type a bare (non-string) hole coerces its program token into. String
-- holes need no tag: they live inside 'VStr' as 'PHole'.
data HoleType = HInt | HBool | HFloat | HPath
  deriving (Eq, Show)

-- | A rhs value: the Nix value algebra minus computation. No constructor for
-- function application exists.
data Value
  = VStr [Piece]
  | VList [Value]
  | VBool Bool
  | VInt Integer
  | VFloat Double
  | VPath Text          -- ^ an unquoted Nix path literal (@\/x@, @.\/x@, @..\/x@)
  | VNull
  | VHole HoleType Text -- ^ a bare typed hole, filled and coerced from a program token
  deriving (Eq, Show)

-- | @value.N@ -> N (1-based); @value@ -> Nothing (not indexed). Shared with the
-- rule executor and the typed-hole parser.
holeIndex :: Text -> Maybe Int
holeIndex h = do
  numTxt <- T.stripPrefix "value." h
  case TR.decimal numTxt of
    Right (n, rest) | T.null rest, n >= 1 -> Just n
    _ -> Nothing

-- | A hole name is @value@ or @value.N@; nothing else binds.
validHoleName :: Text -> Bool
validHoleName h = h == "value" || holeIndex h /= Nothing

holeTypeText :: HoleType -> Text
holeTypeText HInt   = "int"
holeTypeText HBool  = "bool"
holeTypeText HFloat = "float"
holeTypeText HPath  = "path"

parseHoleType :: Text -> Maybe HoleType
parseHoleType "int"   = Just HInt
parseHoleType "bool"  = Just HBool
parseHoleType "float" = Just HFloat
parseHoleType "path"  = Just HPath
parseHoleType _       = Nothing

-- | Parse a rhs text into a 'Value'. Anything outside the grammar -- bare
-- identifiers, function application, non-pkgs interpolation, an untyped bare
-- hole -- is an error naming what was rejected.
parseValue :: Text -> Either Text Value
parseValue t = do
  (v, rest) <- pValue t
  if T.null (T.stripStart rest)
    then Right v
    else Left ("trailing content after value (computation is not a value): " <> T.strip rest)

pValue :: Text -> Either Text (Value, Text)
pValue raw =
  let t = T.stripStart raw
   in case T.uncons t of
        Nothing -> Left "empty rhs"
        Just ('"', rest) -> pString rest
        Just ('[', rest) -> pList (T.stripStart rest) []
        Just ('<', more) -> pTypedHole more
        Just (c, _)
          | isPathStart t                        -> pPath t
          | c == '-' || isDigit c                -> pNumber t
          | Just rest <- T.stripPrefix "true" t  -> Right (VBool True, rest)
          | Just rest <- T.stripPrefix "false" t -> Right (VBool False, rest)
          | Just rest <- T.stripPrefix "null" t  -> Right (VNull, rest)
          | otherwise ->
              Left ("rhs must be a string, list, number, bool, path, null, or a "
                     <> "typed <hole> (no Nix computation): " <> t)

isPathStart :: Text -> Bool
isPathStart t = any (`T.isPrefixOf` t) ["/", "./", "../"]

pNumber :: Text -> Either Text (Value, Text)
pNumber t = case TR.signed TR.decimal t of
  Left _ -> Left ("bad number: " <> t)
  Right (n, rest)
    | Just ('.', _) <- T.uncons rest -> case TR.signed TR.double t of
        Right (d, rest') -> Right (VFloat d, rest')
        Left _           -> Left ("bad float: " <> t)
    | otherwise -> Right (VInt n, rest)

-- | A path literal runs to whitespace or a list terminator. It carries no
-- string-injection surface (no quote, semicolon, or @${@ may appear), so it is
-- safe to emit unquoted.
pPath :: Text -> Either Text (Value, Text)
pPath t =
  let (p, rest) = T.span (\c -> not (isSpace c) && c /= ']') t
   in if validPathLit p then Right (VPath p, rest)
                        else Left ("bad path literal (injection risk): " <> p)

validPathLit :: Text -> Bool
validPathLit p =
  isPathStart p
    && not (T.any isSpace p)
    && not (T.any (`elem` ("\";" :: String)) p)
    && not ("${" `T.isInfixOf` p)

pTypedHole :: Text -> Either Text (Value, Text)
pTypedHole more =
  let (inside, after) = T.breakOn ">" more
   in if T.null after
        then Left ("unterminated hole <" <> inside)
        else case T.splitOn ":" inside of
          [hn, ty]
            | validHoleName hn, Just ht <- parseHoleType ty ->
                Right (VHole ht hn, T.drop 1 after)
          _ ->
            Left ("a hole outside a string must be typed "
                   <> "<value:int|bool|float|path> (or <value.N:...>): <" <> inside <> ">")

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
-- Deterministic and injection-free by construction.
renderValue :: Value -> Text
renderValue (VBool True)   = "true"
renderValue (VBool False)  = "false"
renderValue (VInt n)       = T.pack (show n)
renderValue (VFloat d)     = T.pack (show d)
renderValue VNull          = "null"
renderValue (VPath p)      = p
renderValue (VHole ht h)   = "<" <> h <> ":" <> holeTypeText ht <> ">"
renderValue (VList vs)     = "[ " <> T.unwords (map renderValue vs) <> " ]"
renderValue (VStr ps)      = "\"" <> T.concat (map piece ps) <> "\""
  where
    piece (PLit t)  = escape t
    piece (PRef r)  = "${" <> T.intercalate "." r <> "}"
    piece (PHole h) = "<" <> h <> ">"

-- | Escape text destined for the inside of a Nix string: quotes, backslashes,
-- and @${@ (which would otherwise open an interpolation -- the injection).
escape :: Text -> Text
escape = T.replace "${" "\\${" . T.replace "\"" "\\\"" . T.replace "\\" "\\\\"

-- | Fill every hole with (a selection from) the program value and render.
-- String holes go through 'escape'; typed holes coerce the program token into
-- their type and fail loud if it does not parse (the rewrite channel has no
-- 'Either', so a bad program value is an 'error', matching out-of-range
-- @\<value.N\>@). Either way program text cannot alter the value's shape.
fillValue :: (Text -> Text) -> Value -> Text
fillValue pick = renderValue . fillV
  where
    fillV (VStr ps)    = VStr (map fillP ps)
    fillV (VList vs)   = VList (map fillV vs)
    fillV (VHole ht h) = coerce ht h (pick h)
    fillV v            = v
    fillP (PHole h) = PLit (pick h)
    fillP p         = p

    coerce HInt h tok = case TR.signed TR.decimal (T.strip tok) of
      Right (n, r) | T.null r -> VInt n
      _ -> holeError h "int" tok
    coerce HFloat h tok = case TR.signed TR.double (T.strip tok) of
      Right (d, r) | T.null r -> VFloat d
      _ -> holeError h "float" tok
    coerce HBool h tok = case T.strip tok of
      "true"  -> VBool True
      "false" -> VBool False
      _       -> holeError h "bool" tok
    coerce HPath h tok =
      let p = T.strip tok in if validPathLit p then VPath p else holeError h "path" tok

    holeError h ty tok =
      error ("value hole <" <> T.unpack h <> ":" <> ty
              <> "> got a program value that is not a " <> ty <> ": " <> T.unpack tok)

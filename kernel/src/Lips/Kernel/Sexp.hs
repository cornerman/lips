{-# LANGUAGE OverloadedStrings #-}

-- | The closed s-expression grammar: what a minted clause is made of.
--
-- The kernel owns this grammar and never evaluates a word of it, exactly as it
-- owns the Nix value grammar of 'Lips.Kernel.Engine.Value' and never evaluates
-- that either. Nix builds anything while understanding no line of C++, because
-- what it owns is the derivation interface; the same split is what lets a clause
-- carry behaviour the kernel knows nothing about (decision doc 2026-08-02, §4
-- and §12).
--
-- > sexp   ::= symbol | string | int | float | bool | char | list | quote | hole
-- > list   ::= '(' sexp* ')'
-- > quote  ::= '\'' sexp                  -- data, never a call
-- > string ::= '"' (literal | hole)* '"'
-- > hole   ::= '#<' name [':' type] '>'
--
-- Three guarantees hold by construction, and each one is a defect the grammar
-- makes unrepresentable rather than a check somebody must remember to run:
--
--   * /A symbol is the only way a clause names anything./ So the gate
--     ('Lips.Kernel.Clause.Gate') has exactly one kind of thing to ground, and
--     an ungrounded name cannot hide inside another form.
--   * /No program value can become code./ The only fillable positions are a
--     typed hole and a string hole. There is no constructor for a filled
--     symbol, so a program's word can land in a string or a number and nowhere
--     else.
--   * /No computation of the kernel's own./ Rendering is serialization; nothing
--     here reduces, applies or evaluates.
--
-- The hole marker is @#\<...\>@ rather than the @\<...\>@ used elsewhere,
-- because @\<@ and @\>@ are ordinary Scheme identifier characters and a clause
-- must be able to compare two numbers. @#\<...\>@ is reserved notation in
-- Scheme (an unreadable object), which reads exactly right: unreadable until
-- filled.
module Lips.Kernel.Sexp
  ( SExp (..)
  , SPiece (..)
  , parseSexp
  , renderSexp
  , fillSexp
  , sexpSymbols
  ) where

import           Data.Char      (isAlpha, isDigit, isSpace)
import           Data.Text      (Text)
import qualified Data.Text      as T
import qualified Data.Text.Read as TR

import Lips.Kernel.Hole (HoleType (..), holeTypeText, parseHoleType)

-- | One piece of a string literal: text, or a hole the program's word fills.
-- A hole inside a string needs no type, because inside a string a value is
-- always text.
data SPiece = SLit Text | SPHole Text
  deriving (Eq, Show)

-- | A clause, or any part of one.
data SExp
  = SSym Text            -- ^ an identifier: the only way a clause names anything
  | SStr [SPiece]
  | SInt Integer
  | SFloat Double
  | SBool Bool
  | SChar Char           -- ^ @#\\=@: a clause splitting a field from its value needs one
  | SList [SExp]
  | SQuote SExp          -- ^ @'x@: data, so the gate does not look inside it
  | SHole HoleType Text  -- ^ @#\<value:int\>@, coerced from a program token
  deriving (Eq, Show)

-- | Every symbol the expression mentions, in order, duplicates kept. Quoted
-- data yields nothing: @'(system)@ names no procedure, it is a list of two
-- symbols as data, and treating it as a call would make the gate reject honest
-- clauses.
sexpSymbols :: SExp -> [Text]
sexpSymbols (SSym s)   = [s]
sexpSymbols (SList xs) = concatMap sexpSymbols xs
sexpSymbols _          = []

-- Parsing -------------------------------------------------------------------

-- | Parse one expression, which must be the whole text. Anything outside the
-- grammar is a 'Left' naming what was rejected.
parseSexp :: Text -> Either Text SExp
parseSexp t = do
  (x, rest) <- pSexp t
  if T.null (T.stripStart rest)
    then Right x
    else Left ("text is left over after the expression; a clause is one\
               \ expression, not a sequence: " <> T.strip rest)

pSexp :: Text -> Either Text (SExp, Text)
pSexp raw =
  let t = T.stripStart raw
   in case T.uncons t of
        Nothing          -> Left "the expression is empty"
        Just ('(', rest) -> pList rest []
        Just (')', _)    -> Left "a closing ) with no list open"
        Just ('\'', rest) -> do
          (x, rest') <- pSexp rest
          Right (SQuote x, rest')
        Just ('"', rest) -> pString rest [] T.empty
        Just ('#', rest) -> pHash rest
        _                -> pToken t

pList :: Text -> [SExp] -> Either Text (SExp, Text)
pList raw acc =
  let t = T.stripStart raw
   in case T.uncons t of
        Nothing          -> Left "a list is not closed with )"
        Just (')', rest) -> Right (SList (reverse acc), rest)
        _                -> do
          (x, rest) <- pSexp t
          pList rest (x : acc)

-- | The @#@ forms: booleans, a character, and a hole. A vector (@#(@) is
-- rejected, so the grammar stays the one this module documents.
pHash :: Text -> Either Text (SExp, Text)
pHash t = case T.uncons t of
  Just ('t', rest) -> Right (SBool True, dropWord rest)
  Just ('f', rest) -> Right (SBool False, dropWord rest)
  Just ('<', rest) -> pHole rest
  Just ('\\', rest) -> pChar rest
  _ -> Left ("after # a clause may write t, f, \\ for a character, or < for a\
             \ hole: #" <> T.take 12 t)
  where
    -- #true / #false spell the same booleans; drop the tail so both read.
    dropWord = T.dropWhile isAlpha

pChar :: Text -> Either Text (SExp, Text)
pChar t =
  let (name, after) = T.span isAlpha t
   in if T.length name > 1
        then case name of
          "space"   -> Right (SChar ' ', after)
          "newline" -> Right (SChar '\n', after)
          "tab"     -> Right (SChar '\t', after)
          _ -> Left ("not a character lips knows; write #\\<one char>, #\\space,\
                     \ #\\newline or #\\tab: #\\" <> name)
        else case T.uncons t of
          Just (c, rest) -> Right (SChar c, rest)
          Nothing        -> Left "a character literal #\\ ends with nothing after it"

pHole :: Text -> Either Text (SExp, Text)
pHole t =
  let (inside, after) = T.breakOn ">" t
      rest = T.drop 1 after
   in if T.null after
        then Left ("a hole is not closed with >: #<" <> inside)
        else case T.splitOn ":" inside of
          [hn, ty] | validHoleName hn, Just ht <- parseHoleType ty ->
            case ht of
              HPath -> Left (nixOnly "path" hn)
              HPkg  -> Left (nixOnly "pkg" hn)
              _     -> Right (SHole ht hn, rest)
          _ -> Left ("a hole outside a string must carry a type, like\
                     \ #<value:int>, #<value:float> or #<value:bool>: #<"
                      <> inside <> ">")
  where
    -- A path and a package are Nix notions: a clause has no store to name and
    -- no derivation to be. Refusing loudly beats inventing a Scheme reading.
    nixOnly ty hn =
      "a clause cannot carry a " <> ty <> " hole (#<" <> hn <> ":" <> ty
        <> ">); that type names a Nix notion, so it belongs in an option value,\
           \ not in behaviour"

-- | A string: literal text with the usual escapes, and holes.
pString :: Text -> [SPiece] -> Text -> Either Text (SExp, Text)
pString s pieces acc = case T.uncons s of
  Nothing -> Left "a string is not closed with a final quote"
  Just ('"', rest) -> Right (SStr (reverse (flush acc pieces)), rest)
  Just ('\\', more) -> case T.uncons more of
    Just ('n', more') -> pString more' pieces (T.snoc acc '\n')
    Just ('t', more') -> pString more' pieces (T.snoc acc '\t')
    Just ('r', more') -> pString more' pieces (T.snoc acc '\r')
    Just (c, more')   -> pString more' pieces (T.snoc acc c)
    Nothing           -> Left "a string ends on a stray backslash"
  Just ('#', more)
    | Just body <- T.stripPrefix "<" more ->
        let (inside, after) = T.breakOn ">" body
         in if T.null after
              then Left ("a hole inside the string is not closed with >: #<" <> inside)
              else if validHoleName inside
                then pString (T.drop 1 after) (SPHole inside : flush acc pieces) T.empty
                else Left ("unknown hole #<" <> inside <> "> inside a string")
  Just (c, more) -> pString more pieces (T.snoc acc c)
  where
    flush a ps = if T.null a then ps else SLit a : ps

-- | A bare token: a number if it reads wholly as one, else a symbol. Deciding
-- after tokenizing (rather than by first character) keeps @-@ a symbol and
-- @-3@ a number without a lookahead special case.
pToken :: Text -> Either Text (SExp, Text)
pToken t =
  let (tok, rest) = T.span isTokenChar t
   in if T.null tok
        then Left ("not part of any expression lips knows: " <> T.take 12 t)
        else Right (classify tok, rest)
  where
    classify tok
      | Right (n, r) <- TR.signed TR.decimal tok, T.null r = SInt n
      | Right (d, r) <- TR.signed TR.double tok, T.null r  = SFloat d
      | otherwise                                          = SSym tok

-- | What may appear inside a bare token. Whitespace and the four structural
-- characters end it; everything else (including @<@, @>@, @?@ and @!@, which
-- Scheme identifiers use freely) belongs to the token.
isTokenChar :: Char -> Bool
isTokenChar c = not (isSpace c) && c `notElem` ("()\"';" :: String)

-- | A hole name: @value@, @value.N@, or a capture name the rule's subject
-- binds. As in the value grammar, the parser cannot tell a real capture from a
-- typo (it does not see the subject), so it accepts identifier text here and
-- the mint gate rejects the unbound ones where the subject is in hand.
validHoleName :: Text -> Bool
validHoleName h = not (T.null h) && T.all ok h
  where ok c = isAlpha c || isDigit c || c `elem` ("-_." :: String)

-- Rendering -----------------------------------------------------------------

-- | Canonical text. Deterministic, and 'parseSexp' reads it back unchanged.
renderSexp :: SExp -> Text
renderSexp (SSym s)     = s
renderSexp (SInt n)     = T.pack (show n)
renderSexp (SFloat d)   = T.pack (show d)
renderSexp (SBool True) = "#t"
renderSexp (SBool False) = "#f"
renderSexp (SChar ' ')  = "#\\space"
renderSexp (SChar '\n') = "#\\newline"
renderSexp (SChar '\t') = "#\\tab"
renderSexp (SChar c)    = T.pack ['#', '\\', c]
renderSexp (SList xs)   = "(" <> T.unwords (map renderSexp xs) <> ")"
renderSexp (SQuote x)   = "'" <> renderSexp x
renderSexp (SHole ht h) = "#<" <> h <> ":" <> holeTypeText ht <> ">"
renderSexp (SStr ps)    = "\"" <> T.concat (map piece ps) <> "\""
  where
    piece (SLit t)   = escape t
    piece (SPHole h) = "#<" <> h <> ">"

-- | Escape text destined for the inside of a Scheme string. Backslash first, so
-- a genuine backslash in the text is not mistaken for one of the escapes on the
-- way back through 'parseSexp'. Scheme has no string interpolation, so a quote
-- and a backslash are the whole attack surface.
escape :: Text -> Text
escape = T.replace "\"" "\\\""
       . T.replace "\r" "\\r"
       . T.replace "\t" "\\t"
       . T.replace "\n" "\\n"
       . T.replace "\\" "\\\\"

-- Filling -------------------------------------------------------------------

-- | Fill every hole from the program value. A string hole becomes literal text
-- (escaped on render, so it cannot end the string or reach outside it); a typed
-- hole is coerced and fails loud when the program's word is not of that type.
-- Either way the shape of the clause is fixed before any program text is seen.
fillSexp :: (Text -> Either Text Text) -> SExp -> Either Text SExp
fillSexp pick = go
  where
    go (SStr ps)    = SStr <$> traverse piece ps
    go (SList xs)   = SList <$> traverse go xs
    go (SQuote x)   = SQuote <$> go x
    go (SHole ht h) = pick h >>= coerce ht h
    go x            = Right x

    piece (SPHole h) = SLit <$> pick h
    piece p          = Right p

    coerce HInt h tok = case TR.signed TR.decimal (T.strip tok) of
      Right (n, r) | T.null r -> Right (SInt n)
      _                       -> Left (holeError h "int" tok)
    coerce HFloat h tok = case TR.signed TR.double (T.strip tok) of
      Right (d, r) | T.null r -> Right (SFloat d)
      _                       -> Left (holeError h "float" tok)
    coerce HBool h tok = case T.strip tok of
      "true"  -> Right (SBool True)
      "false" -> Right (SBool False)
      _       -> Left (holeError h "bool" tok)
    -- Unreachable through 'parseSexp', which refuses both at parse time; stated
    -- here so the function is total without a partial pattern.
    coerce HPath h _ = Left (noSuchHole h "path")
    coerce HPkg h _  = Left (noSuchHole h "pkg")

    holeError h ty tok =
      "the value hole #<" <> h <> ":" <> ty <> "> was filled with something that\
      \ is not a " <> ty <> ": " <> tok
    noSuchHole h ty =
      "a clause cannot carry a " <> ty <> " hole (#<" <> h <> ":" <> ty <> ">)"

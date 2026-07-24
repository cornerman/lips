{-# LANGUAGE OverloadedStrings #-}

-- | The closed value language for minted rule right-hand sides.
--
-- A minted engine's rhs is NOT a Nix expression. It is a value in this closed
-- grammar, and its grammar is deliberately the Nix value algebra MINUS
-- computation (completeness plan, Target 1):
--
-- > value  ::= string | list | bool | int | float | path | null | typed-hole | tail-hole | ref | attrset
-- > string ::= '"' (literal | ${pkgs.<dotted-path>} | <value> | <value.N>)* '"'
-- > list   ::= '[' value* ']'
-- > ref    ::= ${pkgs.<dotted-path>} | ${artifact.<name>}   -- a bare reference value
-- > attrset ::= '{' (ident '=' value ';')* '}'              -- optional trailing ';'
-- > typed-hole ::= '<' ('value' | 'value.'N) ':' ('int'|'bool'|'float'|'path') '>'
-- > tail-hole  ::= '<' 'value.tail' '>'   -- fills to a VList of the program value's tokens
--
-- A @ref@ names a concrete thing (a package, a program-derived build) the
-- kernel never inspects; as a whole value it stands as a list element (a list
-- of derivations, e.g. @systemPackages@). Written @${...}@ so it round-trips
-- through 'parseValue' in @.lang@, but 'renderRealized' emits it bare
-- (@pkgs.curl@) for the module, since a Nix list holds derivations.
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
  , Ref (..)
  , HoleType (..)
  , parseValue
  , renderValue
  , renderRealized
  , fillValue
  , holeIndex
  , valueRefsDerivation
  , valueArtifactNames
  ) where

import           Data.Char      (isDigit, isSpace)
import           Data.Text      (Text)
import qualified Data.Text      as T
import qualified Data.Text.Read as TR

-- | One piece of a string value. 'PRef' is a @${pkgs.<dotted-path>}@ package
-- reference; 'PArt' is a @${artifact.<name>}@ reference to a program-derived
-- artifact (resolved by realize to its @let@-bound build); 'PHole' is
-- @\<value\>@ or @\<value.N\>@ (a string hole). All three are names, not
-- computation.
data Piece = PLit Text | PRef [Text] | PArt Text | PHole Text
  deriving (Eq, Show)

-- | A bare reference used as a whole value (e.g. a list element), naming a
-- concrete thing the kernel never inspects: 'RPkg' is a @pkgs.<path>@ package,
-- 'RArt' a @${artifact.<name>}@ program-derived build. Written @${...}@ by the
-- model and in the canonical form (so it round-trips through 'parseValue'), but
-- 'renderRealized' emits it bare (@pkgs.curl@, @artifact.weather@) because a
-- Nix list holds derivations, not interpolations.
data Ref = RPkg [Text] | RArt Text
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
  | VRef Ref            -- ^ a package\/artifact reference standing as a whole value
  | VAttr [(Text, Value)] -- ^ a Nix attrset of named fields (a listOf-submodule
                          -- element, e.g. an @ensureUsers@ entry). Keys are bare
                          -- identifiers only (closed, injection-safe); values are
                          -- 'Value's, so a hole inside a field fills and escapes
                          -- like any other. No quoted keys: a field name that is
                          -- not a bare identifier is rejected, so a program value
                          -- can never alter the attrset's shape.
  | VTail Text          -- ^ @<value.tail>@: fills to a 'VList' of the program
                          -- value's whitespace tokens (trailing sentence
                          -- punctuation stripped). The whole rhs, not a list
                          -- element: one line carrying many items becomes one
                          -- list, which 'Append' (B) can aggregate with others.
                          -- The name is always @value@ (the program value); an
                          -- empty tail fails loud, never guesses a shape.
  deriving (Eq, Show)

-- | Does this value interpolate a package (@${pkgs...}@) or artifact
-- (@${artifact...}@) reference anywhere? Such a value realizes to a
-- derivation, not a program value, so a @.expect@ containment check cannot
-- target the option it fills (the check evaluates with an empty @pkgs@ stub).
-- Used by 'Lips.Generate.Minting.uncheckableExpects' as a structural guard.
valueRefsDerivation :: Value -> Bool
valueRefsDerivation (VStr ps)  = any isRef ps
  where isRef (PRef _) = True
        isRef (PArt _) = True
        isRef _        = False
valueRefsDerivation (VList vs) = any valueRefsDerivation vs
valueRefsDerivation (VAttr fs) = any (valueRefsDerivation . snd) fs
valueRefsDerivation (VRef _)   = True
valueRefsDerivation _          = False

-- | The artifact names a value references, anywhere inside it: a string
-- interpolation @${artifact.<name>}@ or a bare whole-value reference. Used by
-- 'Lips.Kernel.Realize.realize' to detect a dangling artifact reference:
-- once realize parses each assertion to a 'Value', the references are
-- structural facts, not text to scan (replacing the old quote-aware text
-- scanner that the canonical-assertion refactor made redundant).
valueArtifactNames :: Value -> [Text]
valueArtifactNames (VStr ps)         = [ n | PArt n <- ps ]
valueArtifactNames (VList vs)        = concatMap valueArtifactNames vs
valueArtifactNames (VAttr fs)        = concatMap (valueArtifactNames . snd) fs
valueArtifactNames (VRef (RArt n))   = [n]
valueArtifactNames _                 = []

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

-- | The plain hole name a string-context @\<...\>@ denotes, accepting a
-- redundant @:type@ suffix. Inside a string the value is always text, so a
-- type annotation is meaningless there; rather than reject @\<value:int\>@ (a
-- form the mint writes naturally when it wants a number), degrade it to its
-- plain hole @\<value\>@ losslessly. A genuine option-type mismatch is still
-- caught one layer down by option grounding, so nothing is weakened. Returns
-- Nothing for a truly unknown hole.
stringHoleName :: Text -> Maybe Text
stringHoleName h =
  let base = case T.breakOn ":" h of
               (b, ty) | not (T.null ty), Just _ <- parseHoleType (T.drop 1 ty) -> b
               _ -> h
   in if validHoleName base then Just base else Nothing

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
    else Left ("text is left over after the value; the right-hand side must be one"
                <> " value, not code: " <> T.strip rest)

pValue :: Text -> Either Text (Value, Text)
pValue raw =
  let t = T.stripStart raw
   in case T.uncons t of
        Nothing -> Left "the right-hand side is empty"
        Just ('"', rest) -> pString rest
        Just ('[', rest) -> pList (T.stripStart rest) []
        Just ('{', rest) -> pAttr (T.stripStart rest) []
        Just ('<', more) -> pTypedHole more
        -- A ${pkgs...}/${artifact...} reference standing as a whole value (a
        -- list element or a top-level rhs), not inside a string.
        Just ('$', more) | Just body <- T.stripPrefix "{" more ->
          let (inside, after) = T.breakOn "}" body
           in if T.null after
                then Left "a ${...} reference is not closed with }"
                else (\r -> (VRef r, T.drop 1 after)) <$> parseRef inside
        Just (c, _)
          | isPathStart t                        -> pPath t
          | c == '-' || isDigit c                -> pNumber t
          | Just rest <- T.stripPrefix "true" t  -> Right (VBool True, rest)
          | Just rest <- T.stripPrefix "false" t -> Right (VBool False, rest)
          | Just rest <- T.stripPrefix "null" t  -> Right (VNull, rest)
          | otherwise ->
              Left ("the right-hand side must be one value: a string, list, number,"
                     <> " bool, path, null, or a typed hole like <value:int>. It cannot"
                     <> " run Nix code: " <> t)

isPathStart :: Text -> Bool
isPathStart t = any (`T.isPrefixOf` t) ["/", "./", "../"]

pNumber :: Text -> Either Text (Value, Text)
pNumber t = case TR.signed TR.decimal t of
  Left _ -> Left ("not a number: " <> t)
  Right (n, rest)
    | Just ('.', _) <- T.uncons rest -> case TR.signed TR.double t of
        Right (d, rest') -> Right (VFloat d, rest')
        Left _           -> Left ("not a float: " <> t)
    | otherwise -> Right (VInt n, rest)

-- | A path literal runs to whitespace or a list terminator. It carries no
-- string-injection surface (no quote, semicolon, or @${@ may appear), so it is
-- safe to emit unquoted.
pPath :: Text -> Either Text (Value, Text)
pPath t =
  -- A path value is terminated by whitespace, a list @]@, or an attrset
  -- field separator @;@ / closer @}@. Spanning past @;@ would fold the
  -- separator into the path (rejected by 'validPathLit'), so a path value
  -- inside an attrset (@{ n = ../a; }@) round-trips. None of these chars is
  -- legal inside a Nix path literal, so this stops at true boundaries only.
  let (p, rest) = T.span (\c -> not (isSpace c) && c `notElem` (";]}" :: String)) t
   in if validPathLit p then Right (VPath p, rest)
                        else Left ("not a valid path; a path must start with /, ./, or ../ and contain no quotes or ${...}: " <> p)

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
        then Left ("a hole is not closed with >: <" <> inside)
        else case inside of
          "value.tail" -> Right (VTail "value", T.drop 1 after)
          _ -> case T.splitOn ":" inside of
            [hn, ty]
              | validHoleName hn, Just ht <- parseHoleType ty ->
                  Right (VHole ht hn, T.drop 1 after)
            _ ->
              Left ("a hole outside a string must carry a type, like <value:int>,"
                     <> " <value:bool>, <value:float>, <value:path>, or be <value.tail>: <"
                     <> inside <> ">")

pList :: Text -> [Value] -> Either Text (Value, Text)
pList t acc = case T.uncons t of
  Nothing          -> Left "a list is not closed with ]"
  Just (']', rest) -> Right (VList (reverse acc), rest)
  _ -> do
    (v, rest) <- pValue t
    pList (T.stripStart rest) (v : acc)

-- | Parse an attrset body (the text after the opening @{@). Keys are bare
-- identifiers (a non-identifier key is rejected, so program text can never
-- leave the attrset's shape); values are full 'Value's. Fields are @;@-separated
-- with an optional trailing @;@, mirroring Nix.
pAttr :: Text -> [(Text, Value)] -> Either Text (Value, Text)
pAttr t acc = case T.uncons t of
  Nothing          -> Left "an attrset is not closed with }"
  Just ('}', rest) -> Right (VAttr (reverse acc), rest)
  _ -> do
    (name, afterName) <- pAttrKey t
    let t1 = T.stripStart afterName
    t2 <- case T.uncons t1 of
      Just ('=', r) -> Right (T.stripStart r)
      _ -> Left ("an attrset field needs = after its key " <> name)
    (v, afterV) <- pValue t2
    let t3 = T.stripStart afterV
    case T.uncons t3 of
      Just (';', r) -> pAttr (T.stripStart r) ((name, v) : acc)
      Just ('}', r) -> Right (VAttr (reverse ((name, v) : acc)), r)
      _ -> Left ("an attrset field must end with ; or } (after key " <> name <> ")")

-- | A bare-identifier attrset key: a non-empty run of @[_A-Za-z0-9]@ starting
-- with a letter or underscore. Hyphens and quotes are rejected so the key is
-- always a valid bare Nix attribute name (never subtraction or a string).
pAttrKey :: Text -> Either Text (Text, Text)
pAttrKey t =
  let (k, rest) = T.span isKeyChar t
   in case T.uncons k of
        Nothing -> Left ("an attrset key must be a plain name, not a string or symbol: " <> t)
        Just (c, _) | isAsciiAlpha c || c == '_' -> Right (k, rest)
        _ -> Left ("an attrset key must start with a letter or underscore: " <> k)
  where
    isKeyChar c = isAsciiAlpha c || isDigit c || c `elem` ("_-'-" :: String)
    -- ASCII-only (mirrors 'okSeg'): a Nix bare attribute name allows no
    -- unicode, so a broad 'Data.Char.isAlpha' would admit invalid keys.
    isAsciiAlpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
-- String scanning: literal text with escapes, ${pkgs...} refs, <value> holes.
pString :: Text -> Either Text (Value, Text)
pString = go [] T.empty
  where
    go pieces acc s = case T.uncons s of
      Nothing -> Left "a string is not closed with a final quote"
      Just ('"', rest) -> Right (VStr (reverse (flush acc pieces)), rest)
      Just ('\\', more) -> case T.uncons more of
        Just (c, more') -> go pieces (T.snoc acc c) more'
        Nothing         -> Left "a string ends on a stray backslash with nothing after it"
      Just ('$', more)
        | Just body <- T.stripPrefix "{" more -> do
            let (inside, after) = T.breakOn "}" body
            if T.null after
              then Left "a ${...} inside the string is not closed with }"
              else do
                p <- interp inside
                go (p : flush acc pieces) T.empty (T.drop 1 after)
      Just ('<', more) -> do
        let (hole, after) = T.breakOn ">" more
        if T.null after
          then Left ("a hole inside the string is not closed with >: <" <> hole)
          else
            case stringHoleName hole of
              Just base -> go (PHole base : flush acc pieces) T.empty (T.drop 1 after)
              Nothing   -> Left ("unknown hole <" <> hole <> ">; only <value> and <value.N> are defined")
      Just (c, more) -> go pieces (T.snoc acc c) more
    flush acc pieces = if T.null acc then pieces else PLit acc : pieces

-- | The interpolations allowed inside a string, both names not computation: a
-- @${pkgs.<path>}@ package reference, or a @${artifact.<name>}@ reference to a
-- program-derived build. Spaces, parentheses, or operators do not parse.
interp :: Text -> Either Text Piece
interp inside = refPiece <$> parseRef inside
  where refPiece (RPkg r) = PRef r
        refPiece (RArt n) = PArt n

-- | Parse the body of a @${...}@ into a reference, shared by string pieces and
-- whole-value references: a @${artifact.<name>}@ build ref or a @${pkgs.<path>}@
-- package ref. Anything else (a space, an operator) is computation, rejected.
parseRef :: Text -> Either Text Ref
parseRef inside
  | Just name <- T.stripPrefix "artifact." inside =
      if okSeg name
        then Right (RArt name)
        else Left ("${artifact.<name>} is not a valid build reference; the name after"
                    <> " artifact. must be a plain identifier: ${" <> inside <> "}")
  | otherwise = RPkg <$> pkgsRef inside

-- | A single identifier segment: non-empty, letters\/digits\/@-@\/@_@ only.
okSeg :: Text -> Bool
okSeg s = not (T.null s) && T.all (\c -> c `elem` ("-_" :: String) || isDigit c || isAlpha c) s
  where isAlpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')

-- | The dotted path rooted at @pkgs@ for a package reference.
pkgsRef :: Text -> Either Text [Text]
pkgsRef inside =
  let segs = T.splitOn "." inside
   in case segs of
        ("pkgs" : more) | not (null more), all okSeg more -> Right segs
        _ ->
          Left ("${" <> inside <> "} is not a value lips can use. Inside ${...} you can"
                  <> " only name a package (pkgs.<path>) or a build (artifact.<name>);"
                  <> " each part after the dot must be a plain identifier, with no"
                  <> " spaces, holes, or operators.")

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
renderValue (VRef r)       = renderRefCanon r
renderValue (VList vs)     = "[ " <> T.unwords (map renderValue vs) <> " ]"
renderValue (VAttr [])     = "{}"
renderValue (VAttr fs)     = "{ " <> T.unwords (map (\(k, v) -> k <> " = " <> renderValue v <> ";") fs) <> " }"
renderValue (VTail _)      = "<value.tail>"
renderValue (VStr ps)      = "\"" <> T.concat (map piece ps) <> "\""
  where
    piece (PLit t)  = escape t
    piece (PRef r)  = "${" <> T.intercalate "." r <> "}"
    piece (PArt n)  = "${artifact." <> n <> "}"
    piece (PHole h) = "<" <> h <> ">"

-- | The canonical @${...}@ form of a whole-value reference. Kept in @.lang@ so
-- 'parseValue' reads it back unchanged (round-trip).
renderRefCanon :: Ref -> Text
renderRefCanon (RPkg r) = "${" <> T.intercalate "." r <> "}"
renderRefCanon (RArt n) = "${artifact." <> n <> "}"

-- | The realized Nix form: identical to 'renderValue' everywhere except a
-- whole-value reference, which becomes a bare attribute path (@pkgs.curl@,
-- @artifact.weather@) so it stands as a derivation in a list, not an
-- interpolation. Used only for the emitted module, never for @.lang@.
renderRealized :: Value -> Text
renderRealized (VRef (RPkg r)) = T.intercalate "." r
renderRealized (VRef (RArt n)) = "artifact." <> n
renderRealized (VList vs)      = "[ " <> T.unwords (map renderRealized vs) <> " ]"
renderRealized (VAttr [])       = "{}"
renderRealized (VAttr fs)       = "{ " <> T.unwords (map (\(k, v) -> k <> " = " <> renderRealized v <> ";") fs) <> " }"
renderRealized v               = renderValue v

-- | Escape text destined for the inside of a Nix string: quotes, backslashes,
-- and @${@ (which would otherwise open an interpolation -- the injection).
escape :: Text -> Text
escape = T.replace "${" "\\${" . T.replace "\"" "\\\"" . T.replace "\\" "\\\\"

-- | Fill every hole with (a selection from) the program value and render.
-- The @pick@ selector is itself fallible (an out-of-range @\<value.N\>@ is a
-- 'Left'); string holes go through 'escape'; typed holes coerce the program
-- token into their type and return 'Left' if it does not parse. So a program
-- value that does not fit the rule surfaces as a value the caller propagates
-- (into 'Lips.Kernel.Refine.RewriteFailed'), never a crash. Either way program
-- text cannot alter the value's shape.
-- | Fill holes and render to the CANONICAL form ('renderValue'), so the
-- stored assertion round-trips through 'parseValue' (a ref stays @${pkgs..}@,
-- not a bare @pkgs..@). 'Lips.Kernel.Realize.realize' is the single point that
-- converts canonical to realized Nix ('renderRealized'); @.lang@ persistence
-- also uses 'renderValue'. A ref stored bare would not re-parse (a bare
-- identifier is not a value), so list aggregation -- which re-parses each
-- contributor's assertion as a 'Value' to concatenate VList elements --
-- depends on this canonical storage.
fillValue :: (Text -> Either Text Text) -> Value -> Either Text Text
fillValue pick = fmap renderValue . fillV
  where
    fillV (VStr ps)    = VStr <$> traverse fillP ps
    fillV (VList vs)   = VList <$> traverse fillV vs
    fillV (VAttr fs)   = VAttr <$> traverse (\(k, v) -> (k,) <$> fillV v) fs
    fillV (VHole ht h) = pick h >>= coerce ht h
    fillV (VTail h) = do
      -- The program value's whitespace tokens, each stripped of trailing
      -- sentence punctuation, become one VList. An empty tail is a loud Left:
      -- a tail hole binds "the rest of the line", and the matcher already
      -- rejects a zero-token rest, so reaching here empty is a shape mismatch.
      tok <- pick h
      let toks = map stripTailPunct (filter (not . T.null) (T.words tok))
      if null toks
        then Left ("the value hole <" <> h <> ".tail> matched no tokens; there is nothing left on the line to fill it")
        else Right (VList (map (VStr . (: []) . PLit) toks))
    fillV v            = Right v
    fillP (PHole h) = PLit <$> pick h
    fillP p         = Right p

    coerce HInt h tok = case TR.signed TR.decimal (T.strip tok) of
      Right (n, r) | T.null r -> Right (VInt n)
      _ -> Left (holeError h "int" tok)
    coerce HFloat h tok = case TR.signed TR.double (T.strip tok) of
      Right (d, r) | T.null r -> Right (VFloat d)
      _ -> Left (holeError h "float" tok)
    coerce HBool h tok = case T.strip tok of
      "true"  -> Right (VBool True)
      "false" -> Right (VBool False)
      _       -> Left (holeError h "bool" tok)
    coerce HPath h tok =
      let p = T.strip tok in if validPathLit p then Right (VPath p) else Left (holeError h "path" tok)

    holeError h ty tok =
      "the value hole <" <> h <> ":" <> ty
        <> "> was filled with something that is not a " <> ty <> ": " <> tok

-- | Strip trailing sentence punctuation from a token. A twin of
-- 'Lips.Kernel.Lang.Pattern.stripTrailingPunct', duplicated here so the value
-- grammar stays decoupled from the language layer; the two share a rule, so
-- they name it alike and must be kept in step.
stripTailPunct :: Text -> Text
stripTailPunct = T.dropWhileEnd (`elem` (".,;:!?" :: String))

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
-- > typed-hole ::= '<' ('value' | 'value.'N) ':' ('int'|'bool'|'float'|'path'|'pkg') '>'
-- > tail-hole  ::= '<' 'value.tail' [':' ('int'|'bool'|'float'|'path'|'pkg')] '>'
-- >               -- bare: a VList of string tokens; with :pkg, a VList of pkgs.<token> refs
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
  , bindSelfValue
  , bindCaptureValue
  , valueCaptures
  , valuePathHoles
  , valueUsesAssertion
  , holeIndex
  , valueRefsDerivation
  , sourceText
  , valueArtifactNames
  , valueArtifactPaths
  , valuePaths
  , parseHoleType
  ) where

import           Data.Char       (isDigit, isSpace)
import qualified Data.Map.Strict as Map
import           Data.Maybe      (isJust)
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Kernel.Capture (NamePiece (..), fillName, nameParse, nameTokens, selfName)
import Lips.Kernel.Surface (stripTrailingPunct)

-- | One piece of a string value. 'PRef' is a @${pkgs.<dotted-path>}@ package
-- reference; 'PArt' is a @${artifact.<name>}@ reference to a program-derived
-- artifact (resolved by realize to its @let@-bound build); 'PHole' is
-- @\<value\>@ or @\<value.N\>@ (a string hole). All three are names, not
-- computation.
-- 'PSelf' is the reserved @\<self\>@ token inside a string: the instance name
-- (the program's file basename), resolved by 'bindSelfValue' at realize time,
-- exactly as the same token in an option-path segment is. It is a name, not a
-- program value, so it is distinct from 'PHole'.
data Piece = PLit Text | PRef [Text] | PArt Text | PHole Text | PSelf
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
-- holes need no tag: they live inside 'VStr' as 'PHole'. 'HPkg' turns a
-- program token into a @pkgs.<token>@ derivation reference (a package whose
-- name comes from the program), validated segment-by-segment so program text
-- can never alter the path. It bridges the two universes a hole fills to
-- (values) and a ref names (derivations), letting a program-name token become
-- a derivation without computation.
data HoleType = HInt | HBool | HFloat | HPath | HPkg
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
  | VTail (Maybe HoleType) Text
                          -- ^ @<value.tail>[@:@type]@: fills to a 'VList' of
                          -- the program value's whitespace tokens (trailing
                          -- sentence punctuation stripped). The whole rhs, not
                          -- a list element: one line carrying many items
                          -- becomes one list, which 'Append' (B) can aggregate
                          -- with others. The name is always @value@ (the
                          -- program value); an empty tail fails loud, never
                          -- guesses a shape. 'Nothing' yields string elements
                          -- (the original form); @'Just' 'HPkg'@ yields
                          -- @pkgs.<token>@ derivation elements, so a line of
                          -- package names realizes to a list of derivations.
  deriving (Eq, Show)

-- | The value as plain SOURCE text, or 'Nothing' when it has no text form. Only
-- a fully literal string and a number qualify: a reference resolves to a store
-- path that only nix knows (and lips fills source offline), and a list or
-- attrset has no textual form at all. Used by
-- 'Lips.Kernel.Realize.realizeArtifactFills', so a fill that cannot be written
-- into source fails loud instead of rendering Nix syntax into a program.
sourceText :: Value -> Maybe Text
sourceText (VStr ps)  = T.concat <$> traverse lit ps
  where lit (PLit t) = Just t
        lit _        = Nothing
sourceText (VInt n)   = Just (T.pack (show n))
sourceText (VFloat n) = Just (T.pack (show n))
sourceText _          = Nothing

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
valueRefsDerivation (VRef _)         = True
valueRefsDerivation (VHole HPkg _)   = True
valueRefsDerivation (VTail (Just _) _) = True
valueRefsDerivation _                = False

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

-- | Every path a value names INSIDE an artifact: each @${artifact.<name>}@
-- interpolation paired with the @\/rel\/path@ that follows it in the same
-- string. What that path holds is decided by the artifact's SOURCE (a go.mod
-- module line, a Cargo name), not by the derivation, so it is the one thing no
-- static gate can know: 'Lips.Kernel.Realize.realizeArtifactPaths' reports the
-- pairs and a caller that may BUILD looks inside the result. A bare reference
-- (a list element) names the whole build and yields nothing -- building it is
-- the whole check there.
--
-- The path ends at the first space, so a command carrying arguments
-- (@"${artifact.x}\/bin\/x --port 8080"@) still names one file. A reference
-- followed by anything but @\/@ names the store path itself, so it too yields
-- nothing.
valueArtifactPaths :: Value -> [(Text, Text)]
valueArtifactPaths (VStr ps)  = go ps
  where
    go (PArt n : rest@(PLit t : _))
      | "/" `T.isPrefixOf` t = (n, T.takeWhile (not . isSpace) t) : go rest
    go (_ : rest) = go rest
    go []         = []
valueArtifactPaths (VList vs) = concatMap valueArtifactPaths vs
valueArtifactPaths (VAttr fs) = concatMap (valueArtifactPaths . snd) fs
valueArtifactPaths _          = []

-- | Every path literal a value names, anywhere inside it. A path is the only
-- value that points OUTSIDE the module text at a file that must be there, so
-- 'Lips.Kernel.Realize.realizeStagedPaths' collects them for the caller to
-- check against the staged tree. Structural, like 'valueArtifactNames': a
-- @\"./x\"@ written as a string is a string, not a path.
valuePaths :: Value -> [Text]
valuePaths (VPath p)  = [p]
valuePaths (VList vs) = concatMap valuePaths vs
valuePaths (VAttr fs) = concatMap (valuePaths . snd) fs
valuePaths _          = []

-- | Resolve the reserved @\<self\>@ token inside a value to the instance name,
-- the value-side twin of the option-path segment binding in
-- 'Lips.Kernel.Engine.Data.bindSelf'. A @'PSelf'@ string piece becomes the
-- name as literal text; an artifact reference named @\<self\>@ (string piece or
-- whole value) becomes one named for the instance. Every other value is
-- untouched. Run per-instance before realize, so the shared @.lang@ keeps
-- @\<self\>@ literal.
bindSelfValue :: Text -> Value -> Value
bindSelfValue name = go
  where
    go (VStr ps)              = VStr (map piece ps)
    go (VList vs)             = VList (map go vs)
    go (VAttr fs)             = VAttr (map (\(k, v) -> (k, go v)) fs)
    go (VRef (RArt n))        = VRef (RArt (bound n))
    -- A path literal is opaque text, so <self> inside one (an artifact's
    -- args.src ./artifacts/<self>-core) fills here, the same occurrence fill a
    -- capture already gets in 'bindCaptureValue'.
    go (VPath p)              = VPath (bound p)
    go v                      = v
    piece PSelf               = PLit name
    piece (PArt n)            = PArt (bound n)
    piece p                   = p
    -- Occurrence fill over the shared name grammar, so a COMPOSED name
    -- (<self>-core: the instance's own build, suffixed) resolves like a whole
    -- <self>. A capture in the same name is left standing for the match pass.
    bound = fillName (\t -> if t == selfName then Just name else Nothing)

-- | Every @\<capture\>@ inside a path literal or a name, in order. @\<self\>@
-- is skipped for the same reason as elsewhere: it is not a capture.
pathCaptures :: Text -> [Text]
pathCaptures = filter (/= selfName) . nameTokens

-- | Resolve a @\<capture\>@ used as an artifact NAME to the key the rule's
-- subject bound, the value-side twin of the emit-path fill in
-- 'Lips.Kernel.Capture.fillCaptures'. A capture reaches a value two ways: as a
-- string hole (handled by 'fillValue'\'s @pick@, since a hole is already a
-- value slot) and as the name of an artifact reference, which is a NAME and so
-- needs this structural pass, exactly as @\<self\>@ does. A capture the map
-- does not bind is left alone, so the caller\'s own check reports it by name
-- rather than a silent literal reaching realize.
bindCaptureValue :: Map.Map Text Text -> Value -> Value
bindCaptureValue caps = go
  where
    go (VStr ps)  = VStr (map piece ps)
    go (VList vs) = VList (map go vs)
    go (VAttr fs) = VAttr (map (\(k, v) -> (k, go v)) fs)
    go (VRef (RArt n)) = VRef (RArt (bound n))
    -- A capture inside a path literal fills too, so args.src ./artifacts/<name>
    -- resolves to the staged directory of the artifact this rule keyed.
    go (VPath p)  = VPath (bound p)
    go v          = v
    piece (PArt n) = PArt (bound n)
    piece p        = p
    -- Occurrence fill over the shared name grammar: a capture may be the whole
    -- name or embedded in it (<name>-core), and an unbound token is left
    -- standing so the caller reports it by name.
    bound = fillName (`Map.lookup` caps)

-- | Every capture name a value mentions: a string hole that is neither
-- @\<value\>@ nor @\<value.N\>@, and an artifact reference named by a capture.
-- The mint gate uses it to reject a rule whose value names a capture its
-- subject never binds -- a defect no decision in the corpus need witness, so
-- catching it statically beats waiting for it to fire on an author's machine.
valueCaptures :: Value -> [Text]
valueCaptures = go
  where
    go (VStr ps)  = concatMap piece ps
    go (VList vs) = concatMap go vs
    go (VAttr fs) = concatMap (go . snd) fs
    go (VRef (RArt n)) = capOf n
    -- A path literal is opaque text, so a capture inside it is not a 'Piece';
    -- scanned here because an artifact's args.src is written ./artifacts/<name>,
    -- and an unfilled one used to reach the module as the literal text "<name>".
    go (VPath p)  = pathCaptures p
    go _          = []
    piece (PHole h) | h /= "value", not (isJust (holeIndex h)) = [h]
    piece (PArt n)  = capOf n
    piece _         = []
    -- Every capture the name mentions, whole or embedded (<cmd>-core names two
    -- pieces, one of them a capture). <self> is <...>-shaped but is NOT a
    -- capture: it binds to the instance name at realize time ('bindSelfValue'),
    -- so no rule subject binds it and 'pathCaptures' drops it.
    capOf = pathCaptures

-- | The path-TYPED holes in a value, by name. A @\<x:path\>@ hole coerces a
-- program word into a bare Nix path, and a bare Nix path means "copy this
-- location into the store": pure evaluation refuses an absolute one outright,
-- and for a runtime directory (a document root, a data dir) copying is never
-- what the author meant -- the option wants the STRING @"/var/www/shop"@.
--
-- A Nix path is therefore an engine LITERAL (a relative in-tree path such as
-- @.\/artifacts\/x@, which is exactly how an artifact names its source), never a
-- coercion of a program word. This names the offenders so the mint gate can
-- refuse them while the engine is still rejectable; without it the engine
-- realizes valid-looking Nix that only fails when something forces the path.
valuePathHoles :: Value -> [Text]
valuePathHoles = go
  where
    go (VStr _)        = []          -- a hole inside a string stays a string
    go (VList vs)      = concatMap go vs
    go (VAttr fs)      = concatMap (go . snd) fs
    go (VHole HPath h) = [h]
    go (VTail (Just HPath) h) = [h]
    go _               = []

-- | Does this rhs read the MATCHED decision's assertion? True for a
-- @\<value\>@ or @\<value.N\>@ hole anywhere inside it (a string piece, a bare
-- typed hole, a tail hole), recursing into lists and attrsets. The dual of
-- 'valueCaptures', which reports the capture names and deliberately skips
-- these two.
--
-- A 'VPath' is not scanned: 'fillValue' leaves a path untouched (only
-- 'bindCaptureValue' and 'bindSelfValue' rewrite one), so a @\<value\>@ written
-- inside a path never receives the matched assertion. Answering False there
-- keeps the answer honest -- a caller asking "does the program's word reach
-- this option" must not be told yes by a hole nothing fills.
valueUsesAssertion :: Value -> Bool
valueUsesAssertion = go
  where
    go (VStr ps)    = any piece ps
    go (VList vs)   = any go vs
    go (VAttr fs)   = any (go . snd) fs
    go (VHole _ h)  = assertionHole h
    go (VTail _ h)  = assertionHole h
    go _            = False
    piece (PHole h) = assertionHole h
    piece _         = False
    assertionHole h = h == "value" || isJust (holeIndex h)

-- | @value.N@ -> N (1-based); @value@ -> Nothing (not indexed). Shared with the
-- rule executor and the typed-hole parser.
holeIndex :: Text -> Maybe Int
holeIndex h = do
  numTxt <- T.stripPrefix "value." h
  case TR.decimal numTxt of
    Right (n, rest) | T.null rest, n >= 1 -> Just n
    _ -> Nothing

-- | A hole name is @value@, @value.N@, or a CAPTURE name the rule's subject
-- binds (@\<cmd\>@ matching @cmd.\<cmd\>.msg@). The parser cannot tell a real
-- capture from a typo, since it does not see the subject, so it accepts any
-- identifier here and 'Lips.Kernel.Engine.Overlap.unboundCaptures' rejects the
-- unbound ones at the mint gate, where the subject is in hand.
validHoleName :: Text -> Bool
validHoleName h = h == "value" || holeIndex h /= Nothing || okSeg h

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
holeTypeText HPkg   = "pkg"

parseHoleType :: Text -> Maybe HoleType
parseHoleType "int"   = Just HInt
parseHoleType "bool"  = Just HBool
parseHoleType "float" = Just HFloat
parseHoleType "path"  = Just HPath
parseHoleType "pkg"   = Just HPkg
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
      rest = T.drop 1 after
   in if T.null after
        then Left ("a hole is not closed with >: <" <> inside)
        else case T.stripPrefix "value.tail" inside of
          Just suffix -> case T.uncons suffix of
            Nothing        -> Right (VTail Nothing "value", rest)
            Just (':', ty)
              | Just ht <- parseHoleType ty -> Right (VTail (Just ht) "value", rest)
            _ -> Left ("a <value.tail> hole may be bare or carry a single type, "
                        <> "like <value.tail:pkg>: <" <> inside <> ">")
          Nothing -> case T.splitOn ":" inside of
            [hn, ty]
              | validHoleName hn, Just ht <- parseHoleType ty ->
                  Right (VHole ht hn, rest)
            _ ->
              Left ("a hole outside a string must carry a type, like <value:int>,"
                     <> " <value:bool>, <value:float>, <value:path>, <value:pkg>, or be "
                     <> "<value.tail>: <" <> inside <> ">")

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

-- | A bare-identifier attrset key: a non-empty run of the characters a Nix bare
-- attribute name allows (@[_A-Za-z0-9-']@) starting with a letter or
-- underscore. A quoted or symbolic key is rejected, so program text can never
-- turn the key into a string or an expression.
pAttrKey :: Text -> Either Text (Text, Text)
pAttrKey t =
  let (k, rest) = T.span isKeyChar t
   in case T.uncons k of
        Nothing -> Left ("an attrset key must be a plain name, not a string or symbol: " <> t)
        Just (c, _) | isAsciiAlpha c || c == '_' -> Right (k, rest)
        _ -> Left ("an attrset key must start with a letter or underscore: " <> k)
  where
    isKeyChar c = isAsciiAlpha c || isDigit c || c `elem` ("_-'" :: String)
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
      -- \n, \t, \r are Nix control-character escapes, not a literal
      -- backslash: store the ACTUAL control char (mirroring how \" and \\
      -- store the actual quote\/backslash char), so 'escape' re-emits the
      -- textual \n\/\t\/\r on render. Without this, a minted script's
      -- newline (e.g. a shell script's \"line1\\nline2\") lost its backslash
      -- here and rendered as a bare, meaningless "n" (see writeShellApplication
      -- .text bug: "...bash\\ncurl..." realized to "...bashncurl...").
      Just ('\\', more) -> case T.uncons more of
        Just ('n', more') -> go pieces (T.snoc acc '\n') more'
        Just ('t', more') -> go pieces (T.snoc acc '\t') more'
        Just ('r', more') -> go pieces (T.snoc acc '\r') more'
        Just (c, more')   -> go pieces (T.snoc acc c) more'
        Nothing           -> Left "a string ends on a stray backslash with nothing after it"
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
          -- <self> is the reserved instance name (bound at realize), not a
          -- program-value hole; recognized here so a rule can name the
          -- program's own build/app inside a string.
          else if hole == selfName
            then go (PSelf : flush acc pieces) T.empty (T.drop 1 after)
          else
            case stringHoleName hole of
              Just base -> go (PHole base : flush acc pieces) T.empty (T.drop 1 after)
              Nothing   -> Left ("unknown hole <" <> hole <> ">; only <value>, <value.N> and <self> are defined")
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
      -- The reserved <self> names the program's OWN artifact (its instance
      -- name), resolved by 'bindSelfValue'; accepted here as the one
      -- non-identifier artifact name, symmetric with <self> in a path segment.
      -- A <capture> is admitted too: the rule's subject binds it and
      -- 'bindCaptureValue' resolves it before realize, so a build may be keyed
      -- by a program value exactly as an option path may.
      if okName name
        then Right (RArt name)
        else Left ("${artifact.<name>} is not a valid build reference; the name after"
                    <> " artifact. is identifier text (letters, digits, - and _) with"
                    <> " <self> or a <capture> the rule's subject binds embedded"
                    <> " anywhere in it, e.g. ${artifact.<self>-core}: ${" <> inside <> "}")
  | otherwise = RPkg <$> pkgsRef inside

-- | An artifact NAME: non-empty text in the shared name grammar
-- ('Lips.Kernel.Capture.nameParse'), whose literal parts are identifier text.
-- So @core@, @\<self\>@, @\<cmd\>@ and @\<self\>-core@ are all names, while a
-- space, an unterminated @\<@ or an empty @\<\>@ is not. One grammar, because a
-- program that builds a core and a wrapper around it must be able to name both.
okName :: Text -> Bool
okName name = case nameParse name of
  Left _       -> False
  Right []     -> False
  Right pieces -> all okPiece pieces
  where
    okPiece (NLit t) = okSeg t
    okPiece (NTok _) = True

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
                  <> " spaces, holes, or operators."
                  -- A target world may have its own ${...} syntax (another
                  -- tool's resource references), which is plain TEXT here. That
                  -- is expressible -- as an escaped literal -- so the refusal
                  -- names it, rather than reading as "lips cannot do this".
                  <> " If you meant the literal text ${" <> inside <> "} (another"
                  <> " tool's own reference syntax, not Nix), escape it: \\${"
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
renderValue (VRef r)       = renderRefCanon r
renderValue (VList vs)     = "[ " <> T.unwords (map renderValue vs) <> " ]"
renderValue (VAttr [])     = "{}"
renderValue (VAttr fs)     = "{ " <> T.unwords (map (\(k, v) -> k <> " = " <> renderValue v <> ";") fs) <> " }"
renderValue (VTail Nothing _)   = "<value.tail>"
renderValue (VTail (Just ht) _) = "<value.tail:" <> holeTypeText ht <> ">"
renderValue (VStr ps)      = "\"" <> T.concat (map piece ps) <> "\""
  where
    piece (PLit t)  = escape t
    piece (PRef r)  = "${" <> T.intercalate "." r <> "}"
    piece (PArt n)  = "${artifact." <> n <> "}"
    piece (PHole h) = "<" <> h <> ">"
    piece PSelf     = "<self>"

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
-- @${@ (which would otherwise open an interpolation -- the injection), and the
-- three control chars 'pString' unescapes on the way in (an actual
-- newline\/tab\/CR, stored verbatim in a 'PLit' so a program value can carry
-- one, is written back out as the textual @\n@\/@\t@\/@\r@ Nix escape --
-- otherwise a real newline would break the single-line quoted string).
-- Backslash-doubling runs first so a genuine backslash in the text is not
-- mistaken for one of these escapes on the way back through 'parseValue'.
escape :: Text -> Text
escape = T.replace "${" "\\${"
       . T.replace "\"" "\\\""
       . T.replace "\r" "\\r"
       . T.replace "\t" "\\t"
       . T.replace "\n" "\\n"
       . T.replace "\\" "\\\\"

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
    fillV (VTail mht h) = do
      -- The program value's whitespace tokens, each stripped of trailing
      -- sentence punctuation, become one VList. An empty tail is a loud Left:
      -- a tail hole binds "the rest of the line", and the matcher already
      -- rejects a zero-token rest, so reaching here empty is a shape mismatch.
      -- 'Nothing' keeps the original string elements; @'Just' ht@ coerces each
      -- token the way a bare @<value:ht>@ would, so @<value.tail:pkg>@ yields a
      -- list of @pkgs.<token>@ derivations (one line of package names becomes
      -- one list of packages).
      tok <- pick h
      let toks = map stripTrailingPunct (filter (not . T.null) (T.words tok))
      if null toks
        then Left ("the value hole <" <> h <> ".tail> matched no tokens; there is nothing left on the line to fill it")
        else case mht of
          Nothing -> Right (VList (map (VStr . (: []) . PLit) toks))
          Just ht -> VList <$> traverse (coerce ht h) toks
    fillV v            = Right v
    fillP (PHole h) = PLit <$> pick h
    -- A PSelf that reached fill was not bound to an instance: 'bindSelfValue'
    -- must run first (it always does in the run pipeline). Fail loud rather
    -- than emit a literal "<self>".
    fillP PSelf     = Left "the <self> token was not bound to an instance name before realize"
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
    -- A package name from a program token: split on '.' (so a dotted attr path
    -- like python311Packages.requests is one derivation) and gate every
    -- segment through 'okSeg'. Program text can never alter the path: a space,
    -- operator, '${', or non-identifier char fails loud here.
    coerce HPkg h tok =
      let p = T.strip tok
          segs = T.splitOn "." p
       in if not (T.null p) && all okSeg segs
            then Right (VRef (RPkg ("pkgs" : segs)))
            else Left (pkgHoleError h tok)

    holeError h ty tok =
      "the value hole <" <> h <> ":" <> ty
        <> "> was filled with something that is not a " <> ty <> ": " <> tok
    pkgHoleError h tok =
      "the value hole <" <> h <> ":pkg> was filled with a token that is not a valid "
        <> "package name (letters, digits, '-', '_', and dots only): " <> tok


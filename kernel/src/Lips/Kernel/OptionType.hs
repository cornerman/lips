{-# LANGUAGE OverloadedStrings #-}

-- | A domain-blind, typed schema of option paths, and a pure check that every
-- minted rule fills a known option with a value of a compatible type. The
-- kernel learns nothing NixOS-specific here: it consumes a schema of typed
-- paths (produced by a shell layer such as 'Lips.Nix.Options'), never the
-- wording of any target's type system. Completeness by construction: 'OTOther'
-- is the explicit unconstrained fallback for a type this layer does not model,
-- so an unforeseen option type never forces a rejection.
module Lips.Kernel.OptionType
  ( OptionType (..)
  , OptionSchema
  , OptionError (..)
  , valueMatches
  , checkEmits
  , renderOptionError
  , renderOptionType
  , dotted
  , Answer (..)
  , answerQuery
  , nearOptions
  ) where

import qualified Data.List       as List
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Engine.Data  (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Value (HoleType (..), Value (..))

-- | The modelled option types. 'OTOther' carries the raw type text for any
-- form this layer does not model (submodules, enums, unions, attrsets); it
-- matches every value, so it never rejects.
data OptionType
  = OTBool | OTInt | OTFloat | OTString | OTPath
  | OTListOf OptionType
  | OTOther Text
  deriving (Eq, Show)

-- | A target's option schema: option path (segments) to its type. A path
-- segment may be the wildcard sentinel @"*"@, which matches any concrete
-- segment; the shell layer emits it for a name placeholder (a target's
-- @attrsOf@-of-submodule instance name), so one schema entry covers every
-- instance. The sentinel is a generic convention here; which source spelling
-- becomes @"*"@ is the shell layer's business, not the kernel's.
type OptionSchema = Map [Text] OptionType

-- | Why a minted rule's option assignment is inadmissible. The first field is
-- the rule id (for a deduce-or-fail echo), the second the option path.
data OptionError
  = UnknownOption Text [Text]
  | TypeMismatch  Text [Text] OptionType Value
  deriving (Eq, Show)

-- | Is this rhs value shape compatible with the option's declared type?
-- Lenient where Nix coerces (an int fills a float; a string fills a path),
-- strict where a mistyped hole is a real mint defect (a quoted string in an
-- int option). 'OTOther' is unconstrained.
valueMatches :: OptionType -> Value -> Bool
valueMatches ot v = case (ot, v) of
  (OTBool,   VBool _)        -> True
  (OTBool,   VHole HBool _)  -> True
  (OTInt,    VInt _)         -> True
  (OTInt,    VHole HInt _)   -> True
  (OTFloat,  VFloat _)       -> True
  (OTFloat,  VInt _)         -> True
  (OTFloat,  VHole HFloat _) -> True
  (OTString, VStr _)         -> True
  (OTPath,   VPath _)        -> True
  (OTPath,   VHole HPath _)  -> True
  (OTPath,   VStr _)         -> True
  (OTListOf t, VList vs)     -> all (valueMatches t) vs
  (OTOther _, _)             -> True
  _                          -> False

-- | Check every emit of every rule against the schema. A path that matches a
-- leaf option (wildcard-aware) is type-checked. A path that is not a leaf but
-- descends into a declared option (a submodule or free-form attrset, whose
-- children the schema does not enumerate) is accepted unconstrained. A path
-- that no declared option covers is 'UnknownOption'. This mirrors how a target
-- names options: leaves are listed, name placeholders are wildcards, and
-- free-form regions accept any deeper key.
checkEmits :: OptionSchema -> [MapRule] -> [OptionError]
checkEmits schema rules =
  [ err
  | r <- rules, e <- mrEmits r
  , not (reservedRoot (emPath e))   -- kernel vocabulary, not target options
  , err <- checkEmit (mrId r) (emPath e) (emRhs e)
  ]
  where
    entries = Map.toList schema
    checkEmit rid path v =
      case Map.lookup path schema of                     -- fast path: exact, no wildcard
        Just t  -> mismatch rid path t v
        Nothing -> case [ t | (k, t) <- entries, matchesPath k path ] of
          (t : _) -> mismatch rid path t v              -- wildcard leaf match
          []
            -- Descends into a declared option whose children the schema does
            -- not enumerate. Only an UNMODELLED type can have such children (a
            -- submodule, an attrset, a target's "anything"): a modelled scalar
            -- or list is a leaf by construction, so a path below one names
            -- nothing, in any world.
            | any freeformAncestor entries -> []
            | otherwise -> [UnknownOption rid path]
          where
            freeformAncestor (k, t) = isPrefixPath k path && unmodelled t
            unmodelled (OTOther _) = True
            unmodelled _           = False
    mismatch rid path t v =
      -- Whole-element mismatch (a non-submodule list, or a scalar in the wrong
      -- slot): one TypeMismatch at the option path. For a listOf-submodule the
      -- OTOther catch-all makes valueMatches pass here, so this arm is silent
      -- and the per-field check below is the real gate.
      [ TypeMismatch rid path t v | not (valueMatches t v) ]
        ++ submoduleFieldMismatches rid path v
    -- H3: a listOf-submodule option (list of (submodule)) is field-checked
    -- when the schema lists the submodule's fields as *-wildcard leaves
    -- (services.postgresql.ensureUsers.*.ensureDBOwnership :: boolean). The
    -- element type is OTOther (an unconstrained catch-all by itself), so the
    -- bare valueMatches pass would accept any VAttr; this steps into each
    -- VAttr element and valueMatches each field against its leaf type. The
    -- schema is already here (this is the one door minted engines enter,
    -- generate); the run path stays schema-free (invariant 1). Assembly is
    -- element-preserving (concatenate, never merge/split a VAttr), so
    -- pre-assembly field-checking is complete -- nothing assembly does can
    -- introduce a field-type error absent from a fragment. A submodule whose
    -- fields the schema does NOT list has no leaves to check against and
    -- degrades to unconstrained, which is correct (the kernel can't constrain
    -- what the schema doesn't; completeness by construction, not a guess).
    --
    -- Each failing field is its OWN TypeMismatch (no new error variant): the
    -- path carries the field name (path ++ [name], no "*" -- a listOf has no
    -- instance key) so the regenerate door names the exact offending field,
    -- not the whole element.
    submoduleFieldMismatches rid path v = case v of
      VList elems -> concatMap (elemMismatches rid path) elems
      _            -> []
    elemMismatches rid path (VAttr fs) =
      [ TypeMismatch rid (path ++ [name]) ft val
      | (name, val) <- fs
      , Just ft <- [fieldLeaf path name]
      , not (valueMatches ft val) ]
    elemMismatches _    _     _          = []   -- a non-attrset element: OTOther
    -- Look up a field's leaf type under the emit path's * wildcard. The path
    -- [services,postgresql,ensureUsers] with field "ensureDBOwnership" becomes
    -- [services,postgresql,ensureUsers,*,ensureDBOwnership]; matchesPath
    -- ("*" matches any segment) resolves the concrete-instance leaf.
    fieldLeaf path name =
      case [ ft | (k, ft) <- entries, matchesPath k (path ++ ["*", name]) ] of
        (ft : _) -> Just ft
        []       -> Nothing

-- | Does a schema key match a concrete path exactly (same length, each segment
-- literal-equal or a @"*"@ wildcard)?
matchesPath :: [Text] -> [Text] -> Bool
matchesPath key path = length key == length path && and (zipWith segEq key path)

-- | Is a schema key a strict wildcard-aware prefix of a concrete path (so the
-- path descends past a declared option into its submodule/free-form region)?
isPrefixPath :: [Text] -> [Text] -> Bool
isPrefixPath key path = length key < length path && and (zipWith segEq key path)

segEq :: Text -> Text -> Bool
segEq k c = k == "*" || k == c

-- | An emit rooted at @artifact@ or @claim@ is the kernel's OWN vocabulary, not
-- a target option assignment, so the option schema does not constrain it: the
-- first becomes a @let@-bound derivation in the realized module (see
-- 'Lips.Kernel.Realize'), the second an experiment @check@ runs (see
-- 'Lips.Kernel.Claim'). Grounding either against the world's schema would
-- refuse every engine that builds or observes anything, since no world declares
-- these paths.
reservedRoot :: [Text] -> Bool
reservedRoot ("artifact" : _) = True
reservedRoot ("claim" : _)    = True
-- A clause is behaviour, assembled by 'Lips.Kernel.Realize.realizeClauses' and
-- gated by 'Lips.Kernel.Clause.Gate'. No world declares it, and its type check
-- is the gate, not an option type.
reservedRoot ("clause" : _)   = True
reservedRoot _                = False

-- | The human wording of an option type (the nixpkgs 'type' string, not the
-- Haskell 'show' form), so a mismatch message reads "boolean" / "list of
-- (submodule)", not "OTBool" / "OTListOf (OTOther \"(submodule)\")". These
-- messages feed the regenerate door, so the human wording improves the loop's
-- convergence, not just a human's reading. 'OTOther' carries the raw type text
-- from optionsJSON (e.g. @"(submodule)"@, @"attribute set of anything"@).
renderOptionType :: OptionType -> Text
renderOptionType OTBool         = "boolean"
renderOptionType OTInt          = "integer"
renderOptionType OTFloat        = "floating point number"
renderOptionType OTString       = "string"
renderOptionType OTPath         = "path"
renderOptionType (OTListOf t)   = "list of " <> renderOptionType t
renderOptionType (OTOther x)    = x

-- | A one-line, human-facing reason, naming the rule so a rejection points
-- straight at the offending minted line.
renderOptionError :: OptionError -> Text
renderOptionError (UnknownOption rid p) =
  "rule " <> rid <> ": unknown option " <> dotted p
renderOptionError (TypeMismatch rid p t _) =
  "rule " <> rid <> ": option " <> dotted p <> " has type " <> renderOptionType t
    <> " but the rule fills it with an incompatible value"

dotted :: [Text] -> Text
dotted = T.intercalate "."

-- | What a schema lookup answers with. The shape follows the match set, because
-- one shape lies: an alphabetical slice of a large match set hides the obvious
-- answer behind alphabetically earlier noise. Measured against the pinned NixOS
-- schema, "nginx" matches 1514 paths whose first 40 alphabetically are all OTHER
-- services that merely mention nginx, with services.nginx itself absent. So a
-- large match set answers with WHERE the matches live, ranked by how many each
-- namespace holds: a namespace with many matches is the one ABOUT the word, a
-- namespace with one or two merely references it.
data Answer
  = Leaves     [([Text], OptionType)]  -- ^ few enough to name exactly, with types
  | Freeform   [Text] OptionType       -- ^ inside a declared free-form option:
                                       --   the nearest declared ancestor and its
                                       --   type. Accepted by 'checkEmits',
                                       --   typed by nothing.
  | Nowhere                            -- ^ no match at all
  | Namespaces [([Text], Int)] Int     -- ^ where the matches live, heaviest
                                       --   first, plus how many namespaces the
                                       --   cap hid
  deriving (Eq, Show)

-- | Look a query up in a schema. A dotted prefix browses a namespace; anything
-- else is a substring search over the dotted paths, which is what lets a caller
-- that knows a domain word but not the namespace find it ("backup" reaches
-- services.restic.backups, because the caller chose a good word).
--
-- Grouping depth for a large match set is one segment below what was asked
-- about, floored at 2: a world's depth-1 partition is a dozen buckets and never
-- discriminates, so 2 is the shallowest informative grouping.
--
-- Case-sensitive throughout: option names are lowercase-dotted by convention,
-- and the kernel must not invent a casing rule for a target it knows nothing
-- about.
-- A query with no match is not always absent: 'checkEmits' accepts any path
-- that descends into a declared option whose children the schema does not
-- enumerate (a free-form attrset, a target's "anything" valueType). The lookup
-- and the gate read ONE schema, so they must answer alike -- otherwise the
-- lookup calls a legal path a typo, and the caller refuses a program the gate
-- would have passed. 'Freeform' names the nearest declared ancestor, so the
-- answer also says where typing stops.
answerQuery :: Int -> Text -> OptionSchema -> Answer
answerQuery cap q schema
  | null matches          = case freeformAncestors of
      (a : _) -> uncurry Freeform a
      []      -> Nowhere
  | length matches <= cap = Leaves (List.sortOn fst matches)
  | otherwise             = Namespaces (take cap groups) (length groups - cap)
  where
    segments = T.splitOn "." q
    entries  = Map.toList schema
    -- Segment-wise, not string-wise: a string prefix would report the leaf
    -- @…backups.*.paths@ as an answer to the wrong path @…backups.*.path@,
    -- which is precisely the mistake 'nearOptions' exists to correct.
    byPrefix = [ e | e@(k, _) <- entries, segments `List.isPrefixOf` k ]
    matches
      | not (null byPrefix) = byPrefix
      | otherwise           = [ e | e@(k, _) <- entries, q `T.isInfixOf` dotted k ]
    -- Longest first: the nearest declared ancestor is the one that tells the
    -- reader how deep the schema's knowledge actually reaches.
    freeformAncestors =
      List.sortOn (negate . length . fst)
        [ e | e@(k, t) <- entries, k `List.isPrefixOf` segments, k /= segments
            , case t of OTOther _ -> True; _ -> False ]
    depth  = max 2 (length segments + 1)
    groups = List.sortOn (\(p, n) -> (negate n, p))
           . Map.toList
           . Map.fromListWith (+)
           $ [ (take depth k, 1 :: Int) | (k, _) <- matches ]

-- | Options near a path the schema does not have. Walk the path's own prefixes
-- from longest to shortest and answer at the first one that matches something,
-- so a rule naming @services.x.backups.*.path@ is answered with the real leaves
-- under @services.x.backups.*@. Reuses 'answerQuery', so a wrong LEAF yields
-- exact leaves while a wrong NAMESPACE yields the breakdown: same rule, no
-- second renderer.
--
-- The full path is deliberately not tried: it is already known to be absent, and
-- asking would fall through to the substring search, which would answer a wrong
-- leaf with the single near-spelling instead of the whole namespace beside it.
nearOptions :: Int -> [Text] -> OptionSchema -> Answer
nearOptions cap path schema =
  case [ a | p <- prefixes, let a = answerQuery cap (dotted p) schema, a /= Nowhere ] of
    (a : _) -> a
    []      -> Nowhere
  where
    -- 'drop 1 . inits' skips the empty prefix (which would match everything);
    -- 'dropLast' keeps the absent path itself out of the walk.
    prefixes = reverse (drop 1 (List.inits (dropLast path)))

-- | 'init' that is total: the empty list has no last element to drop.
dropLast :: [a] -> [a]
dropLast [] = []
dropLast xs = init xs

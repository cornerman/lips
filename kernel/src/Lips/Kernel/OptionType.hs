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
  ) where

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
  , not (artifactRooted (emPath e))   -- build-group vocabulary, not target options
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
            | any (\(k, _) -> isPrefixPath k path) entries -> []   -- descends into a declared option
            | otherwise -> [UnknownOption rid path]
    mismatch rid path t v = [ TypeMismatch rid path t v | not (valueMatches t v) ]

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

-- | An emit rooted at @artifact@ is the kernel's build-group vocabulary: it
-- becomes a @let@-bound derivation in the realized module (see
-- 'Lips.Kernel.Realize'), not a target option assignment, so the option schema
-- does not constrain it.
artifactRooted :: [Text] -> Bool
artifactRooted ("artifact" : _) = True
artifactRooted _               = False

-- | A one-line, human-facing reason, naming the rule so a rejection points
-- straight at the offending minted line.
renderOptionError :: OptionError -> Text
renderOptionError (UnknownOption rid p) =
  "rule " <> rid <> ": unknown NixOS option " <> dotted p
renderOptionError (TypeMismatch rid p t _) =
  "rule " <> rid <> ": option " <> dotted p <> " has type " <> T.pack (show t)
    <> " but the rule fills it with an incompatible value"

dotted :: [Text] -> Text
dotted = T.intercalate "."

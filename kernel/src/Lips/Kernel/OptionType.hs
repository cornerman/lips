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

-- | A target's option schema: option path (segments) to its type.
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

-- | Check every emit of every rule against the schema. An option not in the
-- schema is 'UnknownOption'; a present option whose value shape does not match
-- its type is 'TypeMismatch'. Empty result means admissible.
checkEmits :: OptionSchema -> [MapRule] -> [OptionError]
checkEmits schema rules =
  [ err
  | r <- rules, e <- mrEmits r
  , err <- case Map.lookup (emPath e) schema of
             Nothing -> [UnknownOption (mrId r) (emPath e)]
             Just t  -> [ TypeMismatch (mrId r) (emPath e) t (emRhs e)
                        | not (valueMatches t (emRhs e)) ]
  ]

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

{-# LANGUAGE OverloadedStrings #-}

-- | The NixOS-specific shell layer: turn a NixOS @optionsJSON@ document into
-- the kernel's domain-blind 'OptionSchema'. All NixOS knowledge lives here --
-- the JSON object shape and the wording of NixOS type descriptions -- so the
-- kernel stays blind. A different target (terranix) would add its own module
-- producing the same 'OptionSchema'.
--
-- The NixOS @type@ field is a human description string, not a structured type
-- (e.g. @\"16 bit unsigned integer; between 0 and 65535 (both inclusive)\"@),
-- so 'classifyNixType' is a closed classifier over the scalar and list
-- wordings; every other wording (unions, enums, submodules, attrsets) maps to
-- 'OTOther', which the checker leaves unconstrained.
module Lips.Nix.Options
  ( classifyNixType
  , parseNixOptionsJson
  ) where

import           Data.Aeson           (eitherDecode, withObject, (.:))
import           Data.Aeson.Types     (parseEither)
import qualified Data.Aeson.Key       as K
import qualified Data.Aeson.KeyMap    as KM
import           Data.ByteString.Lazy (ByteString)
import qualified Data.Map.Strict      as Map
import           Data.Text            (Text)
import qualified Data.Text            as T

import Lips.Kernel.OptionType (OptionSchema, OptionType (..))

-- | Classify one NixOS type description. List is tested first (its element
-- text may itself contain a scalar keyword); then scalar keywords; else the
-- raw text is kept as 'OTOther' (unions, enums, submodules, attrsets).
classifyNixType :: Text -> OptionType
classifyNixType raw0
  | Just el <- T.stripPrefix "list of " raw = OTListOf (classifyNixType el)
  | raw == "boolean"                        = OTBool
  | "integer" `T.isInfixOf` raw             = OTInt
  | raw == "floating point number"          = OTFloat
  | isString raw                            = OTString
  | raw == "path" || raw == "absolute path" = OTPath
  | otherwise                               = OTOther raw
  where
    raw = T.strip raw0
    -- Only a bare string family, not a union like "null or string".
    isString r = r == "string" || r == "non-empty string"
              || "string " `T.isPrefixOf` r || "strings " `T.isPrefixOf` r

-- | Parse an @optionsJSON@ document to an 'OptionSchema'. Keys are dotted
-- option paths; only the @type@ field of each entry is read.
parseNixOptionsJson :: ByteString -> Either Text OptionSchema
parseNixOptionsJson bytes = do
  top <- either (Left . T.pack) Right (eitherDecode bytes)
  either (Left . T.pack) Right (parseEither toSchema top)
  where
    toSchema = withObject "optionsJSON" $ \km ->
      fmap Map.fromList $
        traverse
          (\(k, val) -> do
              ty <- withObject "option" (.: "type") val
              pure (map normSeg (T.splitOn "." (K.toText k)), classifyNixType ty))
          (KM.toList km)

    -- A NixOS schema key segment written @<...>@ (e.g. @<name>@) is a name
    -- placeholder for an attrsOf/listOf-of-submodules instance; it becomes the
    -- kernel's wildcard sentinel @"*"@, so one schema entry covers every
    -- concrete instance name.
    normSeg s
      | "<" `T.isPrefixOf` s && ">" `T.isSuffixOf` s = "*"
      | otherwise = s

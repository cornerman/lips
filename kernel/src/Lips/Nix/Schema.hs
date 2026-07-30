{-# LANGUAGE OverloadedStrings #-}

-- | Which parser reads a target world's option schema. One door, so the two
-- callers that ground against a schema (@generate@'s admissibility gate and the
-- read-only @options@ lookup) cannot disagree about a world, and adding a world
-- means adding a line here beside its 'Lips.Nix.Target' constructor.
module Lips.Nix.Schema
  ( schemaFor
  ) where

import Data.ByteString.Lazy (ByteString)
import Data.Text            (Text)

import Lips.Kernel.OptionType (OptionSchema)
import Lips.Nix.Kubenix       (parseKubenixOptionsJson)
import Lips.Nix.Options       (parseNixOptionsJson)
import Lips.Nix.Target        (Target (..))

-- | Parse the world's @optionsJSON@ document. NixOS and home-manager are read
-- as they come; kubenix needs reshaping first (see 'Lips.Nix.Kubenix').
schemaFor :: Target -> ByteString -> Either Text OptionSchema
schemaFor Nixos       = parseNixOptionsJson
schemaFor HomeManager = parseNixOptionsJson
schemaFor Kubenix     = parseKubenixOptionsJson

{-# LANGUAGE OverloadedStrings #-}

-- | The realization target: which Nix world an engine's option paths belong
-- to. This is target-tier knowledge (Lips.Nix.*), never kernel knowledge --
-- the kernel emits @path = value@ and never names a world. An engine is born
-- into a world at mint time through the option paths its rules emit; this type
-- names that choice so @generate@ can steer the mint and ground against the
-- right schema, and so it can be recorded in the generation event.
module Lips.Nix.Target
  ( Target (..)
  , defaultTarget
  , parseTarget
  , targetSlug
  ) where

import Data.Text (Text)

-- | The Nix worlds lips targets. A closed set: adding a world (darwin, nix-on-droid)
-- is a deliberate extension here plus a schema source, never an open
-- list the kernel enumerates.
data Target = Nixos | HomeManager | Kubenix | Terranix
  deriving (Eq, Show, Enum, Bounded)

-- | Absent an explicit choice, lips targets NixOS (the original world).
defaultTarget :: Target
defaultTarget = Nixos

-- | Parse a CLI slug to a target; Nothing for anything else (fail loud).
parseTarget :: String -> Maybe Target
parseTarget "nixos"        = Just Nixos
parseTarget "home-manager" = Just HomeManager
parseTarget "kubenix"      = Just Kubenix
parseTarget "terranix"     = Just Terranix
parseTarget _              = Nothing

-- | The canonical slug, used on the CLI and in the .generation record.
targetSlug :: Target -> Text
targetSlug Nixos       = "nixos"
targetSlug HomeManager = "home-manager"
targetSlug Kubenix     = "kubenix"
targetSlug Terranix    = "terranix"

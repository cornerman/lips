{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | The worlds lips ships, as the very bytes a human gets from @lips world
-- \<name\>@: built-in and local worlds are the same data read the same way, so
-- a house world starts as a copy of one of these.
--
-- 'embedStringFile' resolves its path against GHC's working directory, exactly
-- as the mint prompt's embeds do (see 'Lips.Generate.Minting'): both the direct
-- @ghc -isrc@ invocation from @kernel\/@ and the flake build see ".." as the
-- repo root.
module Lips.World.Builtin
  ( builtinWorlds
  , builtinWorld
  ) where

import           Data.FileEmbed (embedStringFile)
import           Data.Text      (Text)
import qualified Data.Text      as T

import           Lips.World     (World, parseWorld)

-- | Every shipped world by name, paired with its file's raw bytes.
builtinWorlds :: [(Text, Text)]
builtinWorlds =
  [ ("nixos",        T.pack $(embedStringFile "../assets/worlds/nixos.world"))
  , ("home-manager", T.pack $(embedStringFile "../assets/worlds/home-manager.world"))
  , ("kubenix",      T.pack $(embedStringFile "../assets/worlds/kubenix.world"))
  , ("terranix",     T.pack $(embedStringFile "../assets/worlds/terranix.world"))
  ]

-- | A shipped world, parsed. A parse failure here is a BUILD defect, not a
-- user's mistake: the suite parses every built-in, so this can only fire on a
-- name that is not shipped, which every caller resolves before asking.
builtinWorld :: Text -> Maybe World
builtinWorld name = do
  raw <- lookup name builtinWorlds
  either (error . T.unpack) Just (parseWorld raw)

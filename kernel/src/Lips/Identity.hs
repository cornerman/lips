{-# LANGUAGE OverloadedStrings #-}

-- | The filesystem naming convention for solutions (plan 2026-07-22, "language
-- as a configurable module"). A program file is
-- @\<instance\>.\<language\>.lips@: the uniform @.lips@ marker is the editor
-- and language-server handle (one extension every tool associates -- vim,
-- VS Code, Emacs), the segment before it names the shared lips language, and
-- what precedes THAT is the instance. So @examples/ledger.backup.lips@ is
-- instance @ledger@ in language @backup@, and its language artifacts live
-- beside it named by the language (@examples/backup.lang@), shared by every
-- @*.backup.lips@ program.
--
-- The instance is optional: @backup.lips@ (just @\<language\>.lips@) is the
-- singleton shorthand, its instance name defaulting to the language
-- (@\<self\>@ = @backup@). Start there, add @photos.backup.lips@ later, with no
-- re-mint.
--
-- This is shell-tier, not kernel calculus: it maps program paths to sidecar
-- paths and to the @\<self\>@ binding. It is the only place that knows the
-- convention, so the rest of the app reads paths by name and never rebuilds
-- the mapping. It uses @filepath@ (a boot library), which is why it sits
-- outside @Kernel/@ (the kernel stays base+containers+text).
module Lips.Identity
  ( languageName
  , instanceName
  , langPath
  , expectPath
  , generationPath
  , directionPath
  , artifactsPath
  , decisionsPath
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import           System.FilePath (dropExtension, takeBaseName, takeDirectory, takeExtension, takeFileName, (<.>), (</>))

-- | The program core: the path with the @.lips@ marker stripped.
-- @a/ledger.backup.lips@ -> @a/ledger.backup@; @a/backup.lips@ -> @a/backup@.
core :: FilePath -> FilePath
core = dropExtension

-- | The language a program is written in: the segment just before @.lips@.
-- @ledger.backup.lips@ -> @backup@; the shorthand @backup.lips@ -> @backup@.
languageName :: FilePath -> String
languageName p = case takeExtension (core p) of
  "" -> takeFileName (core p)   -- <language>.lips: the core basename IS the language
  e  -> drop 1 e                -- <instance>.<language>.lips: the last core extension

-- | The instance name, bound to @\<self\>@ in the grammar: the segment before
-- the language. @ledger.backup.lips@ -> @ledger@; the shorthand @backup.lips@
-- has no separate instance, so it defaults to the language (@backup@).
instanceName :: FilePath -> Text
instanceName p = T.pack $ case takeExtension (core p) of
  "" -> takeFileName (core p)   -- default: instance = language
  _  -> takeBaseName (core p)   -- the basename before the language extension

-- | A language-level sidecar path, named by the language and shared by every
-- program in it: @examples/ledger.backup@ + @lang@ -> @examples/backup.lang@.
langLevel :: String -> FilePath -> FilePath
langLevel ext file = takeDirectory file </> languageName file <.> ext

-- | The shared grammar: @examples/backup.lang@.
langPath :: FilePath -> FilePath
langPath = langLevel "lang"

-- | The shared behavioral contract: @examples/backup.expect@.
expectPath :: FilePath -> FilePath
expectPath = langLevel "expect"

-- | The shared mint record: @examples/backup.generation@.
generationPath :: FilePath -> FilePath
generationPath = langLevel "generation"

-- | The shared owner-taste file for the mint: @examples/backup.direction@.
directionPath :: FilePath -> FilePath
directionPath = langLevel "direction"

-- | The shared minted-source directory: @examples/backup.artifacts@.
artifactsPath :: FilePath -> FilePath
artifactsPath = langLevel "artifacts"

-- | The per-instance crystal witness (derived, gitignored), named after the
-- program so instances never collide: @examples/ledger.backup.decisions@.
decisionsPath :: FilePath -> FilePath
decisionsPath = (<.> "decisions")

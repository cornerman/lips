{-# LANGUAGE OverloadedStrings #-}

-- | The filesystem naming convention for solutions (plan 2026-07-22, "language
-- as a configurable module"). A program file is
-- @\<instance\>.\<language\>.lips@: the uniform @.lips@ marker is the editor
-- and language-server handle (one extension every tool associates -- vim,
-- VS Code, Emacs), the segment before it names the shared lips language, and
-- what precedes THAT is the instance. So @examples/ledger.backup.lips@ is
-- instance @ledger@ in language @backup@, and everything the machine writes
-- for that language lives in ONE folder beside the program, named by the
-- language (@examples/backup/@) and shared by every @*.backup.lips@ program:
--
-- > examples/
-- >   ledger.backup.lips        <- yours (the only files at this level)
-- >   photos.backup.lips
-- >   backup/                   <- everything the machine writes
-- >     backup.lang backup.expect backup.generation backup.direction
-- >     artifacts/
-- >     out/                    <- derived, gitignored by one rule
-- >       ledger.decisions
-- >       ledger/               <- compiled module dir (default.nix, flake.nix)
--
-- The split is the point: a listing separates what a human owns (@*.lips@)
-- from what the machine derived, and the path says which is which. Inside the
-- folder the four language files keep the language prefix, so a basename stays
-- self-describing in an editor tab or a grep hit; the instance-derived names
-- under @out/@ drop it, because the folder already supplies it.
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
  , langDir
  , outDir
  , artifactsPath
  , decisionsPath
  , compiledPath
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

-- | The one folder holding everything minted or derived for a program's
-- language: @examples/ledger.backup.lips@ -> @examples/backup@.
langDir :: FilePath -> FilePath
langDir file = takeDirectory file </> languageName file

-- | The derived subtree inside the language folder: @examples/backup/out@.
-- Kept apart from the committed files so one rule covers every derived thing,
-- whatever the instances are called -- and lips writes that rule itself, as an
-- @out/.gitignore@ holding @*@, so no repo has to be configured to keep derived
-- output untracked.
outDir :: FilePath -> FilePath
outDir file = langDir file </> "out"

-- | A language-level sidecar path, named by the language and shared by every
-- program in it: @examples/ledger.backup.lips@ + @lang@ ->
-- @examples/backup/backup.lang@.
langLevel :: String -> FilePath -> FilePath
langLevel ext file = langDir file </> languageName file <.> ext

-- | The shared grammar: @examples/backup/backup.lang@.
langPath :: FilePath -> FilePath
langPath = langLevel "lang"

-- | The shared behavioral contract: @examples/backup/backup.expect@.
expectPath :: FilePath -> FilePath
expectPath = langLevel "expect"

-- | The shared mint record: @examples/backup/backup.generation@.
generationPath :: FilePath -> FilePath
generationPath = langLevel "generation"

-- | The shared owner-taste file for the mint: @examples/backup/backup.direction@.
directionPath :: FilePath -> FilePath
directionPath = langLevel "direction"

-- | The shared minted-source directory: @examples/backup/artifacts@. A
-- directory inside the language folder, so it needs no prefix to stay
-- unambiguous.
artifactsPath :: FilePath -> FilePath
artifactsPath file = langDir file </> "artifacts"

-- | The per-instance crystal witness (derived, gitignored), named after the
-- instance so instances never collide:
-- @examples/backup/out/ledger.decisions@.
decisionsPath :: FilePath -> FilePath
decisionsPath file = outDir file </> T.unpack (instanceName file) <.> "decisions"

-- | Where @compile@ materializes the module directory by default (derived,
-- gitignored): @examples/backup/out/ledger@, so the address a user runs is
-- @path:examples/backup/out/ledger#vm@.
compiledPath :: FilePath -> FilePath
compiledPath file = outDir file </> T.unpack (instanceName file)

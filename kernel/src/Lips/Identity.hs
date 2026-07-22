{-# LANGUAGE OverloadedStrings #-}

-- | The filesystem naming convention for solutions (plan 2026-07-22, "language
-- as a configurable module"). A program file is @\<basename\>.\<language\>@: the
-- extension names the shared language, the basename names the unique instance.
-- So @examples/ledger.backup@ is instance @ledger@ written in language
-- @backup@, and its language artifacts live beside it named by the language
-- (@examples/backup.lang@), shared by every @*.backup@ program.
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
import           System.FilePath (takeBaseName, takeDirectory, takeExtension, (<.>), (</>))

-- | The language a program is written in: its extension without the dot.
-- @examples/ledger.backup@ -> @backup@.
languageName :: FilePath -> String
languageName = drop 1 . takeExtension

-- | The instance name, bound to @\<self\>@ in the grammar: the file basename
-- without its language extension. @examples/ledger.backup@ -> @ledger@.
instanceName :: FilePath -> Text
instanceName = T.pack . takeBaseName

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

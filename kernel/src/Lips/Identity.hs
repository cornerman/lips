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
-- >   ledger.backup.lips        <- yours
-- >   photos.backup.lips        <- yours
-- >   backup.direction          <- yours (taste steering the mint, optional)
-- >   backup/                   <- everything the machine writes
-- >     backup.lang backup.expect backup.generation
-- >     artifacts/
-- >     out/                    <- derived, gitignored by one rule
-- >       ledger.decisions
-- >       ledger/               <- compiled module dir (default.nix, flake.nix)
--
-- The split is the point: a listing separates what a human owns from what the
-- machine wrote, and the path says which is which. Inside the
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
  , gapPath
  , directionPath
  , readmePath
  , langDir
  , outDir
  , artifactsPath
  , decisionsPath
  , compiledPath
  , resolveLangDir
  , requireProgram
  , langPathIn
  , expectPathIn
  , generationPathIn
  , artifactsPathIn
  , worldPathIn
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import           System.FilePath (dropExtension, dropTrailingPathSeparator, takeBaseName, takeDirectory, takeExtension, takeFileName, (<.>), (</>))

-- | Does this path name a program at all? Every other function here reads a
-- path as @\<instance\>.\<language\>.lips@ without asking, so a path missing
-- the marker was silently reinterpreted: @notes.txt@ became language @txt@ and
-- @backup\/backup.lang@ (a MINTED file) became a program in language @lang@,
-- both then reported as some later missing file. Deduce-or-fail at the door
-- instead: the marker is the convention's only anchor, so a path without it is
-- refused naming it. The language segment may be absent (the singleton
-- shorthand) but must not be empty, which rules out a bare @.lips@.
requireProgram :: FilePath -> Either Text ()
requireProgram file
  | takeExtension file /= ".lips" = Left $ T.pack file
      <> " is not a lips program: a program file ends in .lips."
      <> "\n\n\8594 pass the program (<instance>.<language>.lips, or <language>.lips),"
      <> " not a file lips writes."
  | null (takeFileName (core file)) = Left $ T.pack file
      <> " names no language: a program is <instance>.<language>.lips"
      <> " (or <language>.lips)."
      <> "\n\n\8594 name the file after its language, e.g. backup.lips."
  | otherwise = Right ()

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

-- | The machine-readable refusal artifact: @examples/backup/backup.gap@.
-- Written only when @generate@ refuses (never on a successful mint, where a
-- mint-reported gap already lands inside 'readmePath'); the point is the
-- cross-repo escalation workflow (DESIGN Doctrine) -- a refusal a user hits in
-- their OWN repo must be a shippable, git-committable artifact, not only
-- on-screen text that scrolls away.
gapPath :: FilePath -> FilePath
gapPath = langLevel "gap"

-- | The owner's taste steering the mint: @examples/backup.direction@. A human
-- writes it, so it sits at the TOP level with the programs, not in the machine's
-- folder -- the one rule that governs this layout is that a directory listing
-- shows what a human owns and nothing else. It is language-scoped (shared by
-- every instance), hence named by the language rather than the instance.
directionPath :: FilePath -> FilePath
directionPath file = takeDirectory file </> languageName file <.> "direction"

-- | The language explained in the mint's own words: @examples/backup/README.md@.
-- Named README rather than @<language>.md@ because it is prose for a human, and
-- README is the one filename every reader and forge already resolves to "read
-- this first"; its first line warns that the next mint overwrites it.
readmePath :: FilePath -> FilePath
readmePath file = langDir file </> "README.md"

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

-- | An explicit-directory variant of 'langLevel': the caller supplies the
-- directory (already resolved, e.g. via 'resolveLangDir') instead of it being
-- re-derived from @file@. Used by @compile@\/@check@ when @--lang@
-- overrides the sibling convention.
langLevelIn :: FilePath -> String -> FilePath -> FilePath
langLevelIn dir ext file = dir </> languageName file <.> ext

-- | 'langPath', reading from an explicitly given directory.
langPathIn :: FilePath -> FilePath -> FilePath
langPathIn dir = langLevelIn dir "lang"

-- | 'expectPath', reading from an explicitly given directory.
expectPathIn :: FilePath -> FilePath -> FilePath
expectPathIn dir = langLevelIn dir "expect"

-- | 'generationPath', reading from an explicitly given directory.
generationPathIn :: FilePath -> FilePath -> FilePath
generationPathIn dir = langLevelIn dir "generation"

-- | The world file copied beside an engine, named after the world it is. Named
-- by the WORLD rather than by the language: a language folder holds one engine
-- and the world it was minted into, and the name is what the record pins.
worldPathIn :: FilePath -> Text -> FilePath
worldPathIn dir name = dir </> T.unpack name <.> "world"

-- | 'artifactsPath', reading from an explicitly given directory: a directory
-- inside the given directory, so (like 'artifactsPath') it needs no prefix to
-- stay unambiguous.
artifactsPathIn :: FilePath -> FilePath -> FilePath
artifactsPathIn dir _file = dir </> "artifacts"

-- | Resolve the directory @compile@\/@check@ read the four committed language
-- files from. @Nothing@ (no @--lang@) keeps today's sibling convention
-- ('langDir'). @Just d@ must be a folder named after the program's OWN
-- declared language (its @.lips@ filename is the one place that names it);
-- otherwise this fails loud, naming both sides, before any file IO runs
-- against @d@ -- deduce-or-fail, the same posture as a missing @.lang@.
-- A trailing separator on @d@ is tolerated ('dropTrailingPathSeparator')
-- so @--lang services/a/backup/@ matches exactly as
-- @--lang services/a/backup@ does.
resolveLangDir :: FilePath -> Maybe FilePath -> Either Text FilePath
resolveLangDir file Nothing  = Right (langDir file)
resolveLangDir file (Just d0)
  | takeFileName d == lang = Right d
  | otherwise = Left $ T.pack file <> " is written in ." <> T.pack lang
      <> ", but " <> T.pack d0 <> " is named ." <> T.pack (takeFileName d)
      <> ".\n\n\8594 point --lang at a folder named " <> T.pack lang
      <> ", or rename the program."
  where lang = languageName file
        d    = dropTrailingPathSeparator d0

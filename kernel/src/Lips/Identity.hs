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
-- >     backup.grammar          <- the shared reading of every program
-- >     nixos/                  <- one folder per world it is minted into
-- >       backup.rules backup.expect backup.generation nixos.world README.md
-- >     kubenix/
-- >       backup.rules backup.expect backup.generation kubenix.world README.md
-- >     artifacts/
-- >     out/                    <- derived, gitignored by one rule
-- >       ledger.decisions
-- >       ledger/nixos/         <- compiled module dir (default.nix, flake.nix)
--
-- The split is the point: a listing separates what a human owns from what the
-- machine wrote, and the path says which is which. A second split runs inside
-- the machine's folder: the grammar is the language's cross-world contract and
-- sits at the top, while everything that depends on WHERE a program lands
-- (rules, contract, record, the world file itself) sits in the world's own
-- folder. Every minted file keeps the language prefix, so a basename stays
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
  , directionPath
  , langDir
  , outDir
  , artifactsPath
  , decisionsPath
  , compiledPath
  , resolveLangDir
  , requireProgram
  , grammarPathIn
  , worldDirIn
  , rulesPathIn
  , expectPathIn
  , generationPathIn
  , readmePathIn
  , languageRecordPathIn
  , languageReadmePathIn
  , languageGapPathIn
  , gapPathIn
  , timingPathIn
  , watchedFiles
  , languageTimingPathIn
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

-- | The owner's taste steering the mint: @examples/backup.direction@. A human
-- writes it, so it sits at the TOP level with the programs, not in the machine's
-- folder -- the one rule that governs this layout is that a directory listing
-- shows what a human owns and nothing else. It is language-scoped (shared by
-- every instance), hence named by the language rather than the instance.
directionPath :: FilePath -> FilePath
directionPath file = takeDirectory file </> languageName file <.> "direction"

-- | The shared minted-source directory: @examples/backup/artifacts@. A
-- directory inside the language folder, so it needs no prefix to stay
-- unambiguous.
artifactsPath :: FilePath -> FilePath
artifactsPath file = langDir file </> "artifacts"

-- | The per-instance crystal witness (derived, gitignored), named after the
-- instance so instances never collide. It is not split by world: the witness
-- records how the GRAMMAR read a program, taken before any rule runs, so every
-- world sees the same one.
-- @examples/backup/out/ledger.decisions@.
decisionsPath :: FilePath -> FilePath
decisionsPath file = outDir file </> T.unpack (instanceName file) <.> "decisions"

-- | Where @compile@ materializes the module directory by default (derived,
-- gitignored): @examples/backup/out/ledger/nixos@, so the address a user runs
-- is @path:examples/backup/out/ledger/nixos#vm@. Split by world, because two
-- worlds compile the same instance into two different modules and a single
-- directory could hold only the last one written.
compiledPath :: FilePath -> Text -> FilePath
compiledPath file world = outDir file </> T.unpack (instanceName file) </> T.unpack world

-- | An explicit-directory variant of 'langLevelIn': the caller supplies the
-- directory (already resolved, e.g. via 'resolveLangDir') instead of it being
-- re-derived from @file@. Used by @compile@\/@check@ when @--lang@
-- overrides the sibling convention.
langLevelIn :: FilePath -> String -> FilePath -> FilePath
langLevelIn dir ext file = dir </> languageName file <.> ext

-- | The shared grammar: @services\/a\/backup\/backup.grammar@. It sits at the
-- LANGUAGE level, above every world folder, because the patterns are the
-- language's whole cross-world contract: one reading of a program, the same in
-- every world it is lowered into. Each world's rules are read as a
-- concatenation with it, which is why the two halves may live in separate
-- files at all (a @.lang@ is a flat list of decisions, split by subject).
grammarPathIn :: FilePath -> FilePath -> FilePath
grammarPathIn dir = langLevelIn dir "grammar"

-- | A world's own folder inside the language folder:
-- @services\/a\/backup\/nixos@. Named by the world, so a listing of the
-- language folder is the list of worlds it was minted into.
worldDirIn :: FilePath -> Text -> FilePath
worldDirIn dir world = dir </> T.unpack world

-- | One world's lowering of the language:
-- @services\/a\/backup\/nixos\/backup.rules@. Keeps the language prefix inside
-- the world folder for the same reason every other minted file does: a
-- basename stays self-describing in an editor tab or a grep hit.
rulesPathIn :: FilePath -> Text -> FilePath -> FilePath
rulesPathIn dir world = langLevelIn (worldDirIn dir world) "rules"

-- | One world's behavioral contract:
-- @services\/a\/backup\/nixos\/backup.expect@. Per world, because it pins
-- option paths, and an option path only exists inside one world's namespace.
expectPathIn :: FilePath -> Text -> FilePath -> FilePath
expectPathIn dir world = langLevelIn (worldDirIn dir world) "expect"

-- | One world's mint record:
-- @services\/a\/backup\/nixos\/backup.generation@. Per world, because a
-- language is minted once per world and each event has its own inputs, its own
-- id and its own stamps.
generationPathIn :: FilePath -> Text -> FilePath -> FilePath
generationPathIn dir world = langLevelIn (worldDirIn dir world) "generation"

-- | One world's language explained in the mint's own words:
-- @services\/a\/backup\/nixos\/README.md@. Named README rather than
-- @\<language\>.md@ because it is prose for a human, and README is the one
-- filename every reader and forge already resolves to "read this first"; its
-- first line warns that the next mint overwrites it. Per world, because it is
-- one mint's account of one lowering.
readmePathIn :: FilePath -> Text -> FilePath
readmePathIn dir world = worldDirIn dir world </> "README.md"

-- | The record of a mint that covered the WHOLE language: @backup/backup.generation@,
-- beside the grammar it wrote. One call may write for several worlds, and its
-- event belongs to none of them alone, so it is filed where its outputs are. A
-- mint of a single world keeps writing that world's own record instead
-- ('generationPathIn'), so nothing committed moves.
languageRecordPathIn :: FilePath -> FilePath -> FilePath
languageRecordPathIn dir = langLevelIn dir "generation"

-- | The account of a mint that covered the whole language:
-- @backup/README.md@. Filed at the scope of the event, exactly as its record
-- is; a single-world mint writes 'readmePathIn' instead.
languageReadmePathIn :: FilePath -> FilePath
languageReadmePathIn dir = dir </> "README.md"

-- | The refusal artifact of a mint that covered the whole language:
-- @backup/backup.gap@. Filed at the scope of the event, like its record: a call
-- writing for several worlds refuses as a whole.
languageGapPathIn :: FilePath -> FilePath -> FilePath
languageGapPathIn dir = langLevelIn dir "gap"

-- | What a mint COST, beside the record of what it was made of:
-- @services\/a\/backup\/nixos\/backup.timing@. A separate file because the
-- record's bytes hash to the id every minted line is stamped with (invariant 6),
-- so a duration inside it would make two identical mints produce different ids.
timingPathIn :: FilePath -> Text -> FilePath -> FilePath
timingPathIn dir world = langLevelIn (worldDirIn dir world) "timing"

-- | The cost of a mint that covered the whole language:
-- @backup\/backup.timing@. Filed at the scope of the event, exactly as its
-- record and its refusal are: one call is one cost, however many worlds it
-- wrote for.
languageTimingPathIn :: FilePath -> FilePath -> FilePath
languageTimingPathIn dir = langLevelIn dir "timing"

-- | One world's machine-readable refusal artifact:
-- @services\/a\/backup\/nixos\/backup.gap@. Written only when @generate@
-- refuses (never on a successful mint, where a mint-reported gap already lands
-- inside 'readmePathIn'); the point is the cross-repo escalation workflow
-- (DESIGN Doctrine) -- a refusal a user hits in their OWN repo must be a
-- shippable, git-committable artifact, not only on-screen text that scrolls
-- away. Per world: a refusal is one world's mint failing, not the language's.
gapPathIn :: FilePath -> Text -> FilePath -> FilePath
gapPathIn dir world = langLevelIn (worldDirIn dir world) "gap"

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

-- | The files whose change means "compile again": the program, the taste that
-- steers its mint, and the engine it is read with (the shared grammar plus each
-- world's rules). Pure, so what the loop watches is testable without a clock.
--
-- Derived output is deliberately absent: @out\/@ is what compile WRITES, and
-- watching it would make the loop feed itself.
watchedFiles :: FilePath -> FilePath -> [Text] -> [FilePath]
watchedFiles dir file worlds =
  [ file, directionPath file, grammarPathIn dir file ]
    ++ [ rulesPathIn dir w file | w <- worlds ]

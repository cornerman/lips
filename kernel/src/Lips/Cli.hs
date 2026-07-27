{-# LANGUAGE OverloadedStrings #-}

-- | The lips CLI grammar, declared once as an optparse-applicative Parser so
-- real invocations, --help text, and --bash/--zsh/--fish-completion-script all
-- derive from the same source and can never drift apart -- unlike a
-- hand-rolled parser plus a separately hand-maintained completion script.
-- Kept free of program logic: this module only builds the Parser value (its
-- only IO is the tab-completion listing below); Main.hs runs it and
-- dispatches. See docs/superpowers/specs/2026-07-25-cli-completion-design.md.
module Lips.Cli
  ( Command (..)
  , GenerateOpts (..)
  , CompileOpts (..)
  , CheckOpts (..)
  , OptionsOpts (..)
  , cliParserInfo
  , generateOpts
  , compileOpts
  , checkOpts
  , optionsOpts
  , programCompleter
  ) where

import Control.Monad      (filterM)
import Data.List          (isPrefixOf, isSuffixOf)
import Options.Applicative
import System.Directory    (doesDirectoryExist, listDirectory)
import System.FilePath     (splitFileName, (</>))
import Text.Read          (readMaybe)

import Lips.Nix.Target (Target (..), defaultTarget, parseTarget)

-- | Everything @generate@ needs. @-m\/--model@ is the ONLY way to name a
-- model -- no positional guessing (deleted with @Lips.Generate.Args@'s
-- @looksLikeModel@); omitting it lets @pi@'s own configured default apply.
data GenerateOpts = GenerateOpts
  { goTarget     :: Target
  , goConfidence :: Double
  , goRenew      :: Bool
  , goVerbose    :: Bool
  , goModel      :: Maybe String
  , goThinking   :: String
  , goFiles      :: [FilePath]
  } deriving (Eq, Show)

-- | The reasoning level lips asks @pi@ for, ALWAYS passed explicitly. Unlike
-- the model (omitted, so pi's own default applies and is read back), an
-- unstated thinking level would be an ambient input steering the mint without
-- entering the record, the same hole @-nc@ closed for ambient context files.
-- Default @high@: a mint acts once, emits a whole engine against an exacting
-- grammar, and a refused mint costs a full round, so reasoning is cheap here.
defaultThinking :: String
defaultThinking = "high"

-- | Everything @compile@ needs. Exactly one program -- unlike @generate@'s
-- @some@, no forced symmetry: compile realizes into a single output
-- directory, it does not read a corpus. @coLangDir@ overrides where the
-- committed language files are read from (default: sibling of the program,
-- see 'Lips.Identity.resolveLangDir'); it never affects where compile WRITES
-- (that stays under the program's own directory).
data CompileOpts = CompileOpts
  { coOut     :: Maybe FilePath
  , coLangDir :: Maybe FilePath
  , coFile    :: FilePath
  } deriving (Eq, Show)

-- | Everything @check@ needs: the program, plus the same @--lang@
-- override @compile@ takes (same meaning: read-only, does not move derived
-- output).
data CheckOpts = CheckOpts
  { ceLangDir :: Maybe FilePath
  , ceFile    :: FilePath
  } deriving (Eq, Show)

-- | Everything @options@ needs. A read-only schema lookup: which world's
-- schema to search, how many entries an answer may print, and the query.
data OptionsOpts = OptionsOpts
  { ooTarget :: Target
  , ooLimit  :: Int
  , ooQuery  :: String
  } deriving (Eq, Show)

-- | The lips verbs, all visible/documented via 'hsubparser' (lsp was
-- previously reachable but absent from --help; now consistent with the rest).
data Command
  = Generate GenerateOpts
  | Compile CompileOpts
  | Check CheckOpts
  | Options OptionsOpts
  | Lsp
  deriving (Eq, Show)

-- | The top-level parser info, given the default confidence (0.7 in
-- production; tests pass their own to pin behavior independent of that
-- constant). @<**> helper@ wires up @--help@ (and, transitively via
-- @execParser@, @--bash\/--zsh\/--fish-completion-script@).
cliParserInfo :: Double -> ParserInfo Command
cliParserInfo defConf = info (cliParser defConf <**> helper) $
  fullDesc <> progDesc
    "lips turns an <instance>.<language> program, written in your own plain lines, into a NixOS configuration."

cliParser :: Double -> Parser Command
cliParser defConf = hsubparser
  (  command "generate"
       (info (Generate <$> generateOpts defConf)
             (progDesc "Mint the language from one or more example programs and verify each. The one step that uses AI."))
  <> command "compile"
       (info (Compile <$> compileOpts)
             (progDesc "Realize into a directory (flake.nix + default.nix + artifacts/) and print the nix commands that run it."))
  <> command "check"
       (info (Check <$> checkOpts)
             (progDesc "Verify the program still produces what it promised."))
  <> command "options"
       (info (Options <$> optionsOpts)
             (progDesc "Look up option paths and types in the pinned schema. Read-only, no AI."))
  <> command "lsp"
       (info (pure Lsp)
             (progDesc "Run the lips language server (stdio)."))
  )

programArg :: Parser FilePath
programArg = strArgument (metavar "PROGRAM" <> completer programCompleter)

-- | Tab completion for PROGRAM arguments. optparse-applicative answers every
-- completion itself, so the shells' own filename completion never runs: an
-- argument without a completer completes to nothing at all. A plain file
-- completer would be wrong the other way, offering the machine-written
-- neighbours (@.lang@, @.expect@, @.generation@, @out\/@) as if a human could
-- pass them. So list exactly what lips accepts: @*.lips@ programs, plus
-- directories to descend into. Listing it here (rather than via the
-- bash-only @action "file"@) is what makes it work in bash, zsh and fish
-- alike -- all three generated scripts ask the binary.
programCompleter :: Completer
programCompleter = mkCompleter $ \word -> do
  -- splitFileName keeps the separator on the directory part and yields "./"
  -- for a bare word, so @dir@ is always a listable path.
  let (dir, base) = splitFileName word
      -- Echo back paths in the shape the user typed: a bare word must not
      -- grow a "./" prefix, or the completion would replace what they wrote.
      shown n = if dir == "./" && not ("./" `isPrefixOf` word) then n else dir <> n
      -- Hidden entries only when explicitly asked for, as shells do.
      candidate n = base `isPrefixOf` n && (not ("." `isPrefixOf` n) || "." `isPrefixOf` base)
  listable <- doesDirectoryExist dir
  if not listable then pure [] else do
    names <- filter candidate <$> listDirectory dir
    dirs  <- filterM (doesDirectoryExist . (dir </>)) names
    pure $ [shown n <> "/" | n <- dirs]
        <> [shown n | n <- names, n `notElem` dirs, ".lips" `isSuffixOf` n]

-- | @--target@'s reader: reuses the existing 'parseTarget', so the CLI and
-- the @.generation@ record stay the single source of truth for target slugs.
-- An unknown value is an optparse-applicative parse error (a malformed
-- invocation), never a silent default.
targetReader :: ReadM Target
targetReader = eitherReader $ \s -> case parseTarget s of
  Just t  -> Right t
  Nothing -> Left ("unknown target " <> s <> " (expected nixos or home-manager)")

-- | @--confidence@'s reader: a Double in [0,1], the same range check
-- @Lips.Generate.Args.parseGenerate@ did inline, now in the reader so an
-- out-of-range value fails the same way an unknown @--target@ does.
confidenceReader :: ReadM Double
confidenceReader = eitherReader $ \s -> case readMaybe s of
  Just d | d >= 0, d <= 1 -> Right d
  _                       -> Left (s <> " is not a confidence in [0,1]")

generateOpts :: Double -> Parser GenerateOpts
generateOpts defConf = GenerateOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar "nixos|home-manager" <> help "The Nix world to realize into (default: nixos).")
  <*> option confidenceReader
        (long "confidence" <> value defConf
          <> metavar "0..1" <> help "Minimum pattern confidence to accept (default: 0.7).")
  <*> switch (long "renew" <> help "Re-bless the committed .expect contract from this mint.")
  <*> switch (long "verbose" <> short 'v' <> help "Echo the raw model reply.")
  <*> optional (strOption
        (long "model" <> short 'm' <> metavar "ID"
          <> help "Model id to use (default: pi's own configured default)."))
  <*> strOption
        (long "thinking" <> value defaultThinking
          <> metavar "off|minimal|low|medium|high|xhigh|max"
          <> help "Reasoning level to ask the model for (default: high). Recorded in .generation.")
  <*> some (strArgument (metavar "PROGRAM..." <> completer programCompleter))

-- | @--lang@: read the committed language files (.lang/.expect/
-- .generation/artifacts) from this directory instead of the program's sibling
-- folder. Never affects where derived output (out/) is written -- that stays
-- under the program's own directory. No short alias: a deliberate, occasional
-- override, not a fast-typed everyday flag (the same judgment as --renew).
-- The folder must be named after the program's own declared language;
-- 'Lips.Identity.resolveLangDir' enforces that and fails loud on mismatch.
langDirOpt :: Parser (Maybe FilePath)
langDirOpt = optional (strOption
  (long "lang" <> metavar "DIR"
    <> help "Read the language's committed files from DIR instead of the program's sibling folder (must be named after the program's language)."))

compileOpts :: Parser CompileOpts
compileOpts = CompileOpts
  <$> optional (strOption
        (long "out" <> short 'o' <> metavar "DIR"
          <> help "Output directory (default: <language>/out/<instance>)."))
  <*> langDirOpt
  <*> programArg

checkOpts :: Parser CheckOpts
checkOpts = CheckOpts
  <$> langDirOpt
  <*> programArg

-- | @--limit@'s reader: a positive entry cap. Zero or negative would make
-- every answer empty, which is a malformed invocation, not a narrow search.
limitReader :: ReadM Int
limitReader = eitherReader $ \s -> case readMaybe s of
  Just n | n > 0 -> Right n
  _              -> Left (s <> " is not a positive entry limit")

optionsOpts :: Parser OptionsOpts
optionsOpts = OptionsOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar "nixos|home-manager" <> help "Which world's schema to search (default: nixos).")
  <*> option limitReader
        (long "limit" <> value 40
          <> metavar "N" <> help "Maximum entries to print (default: 40).")
  <*> strArgument
        (metavar "QUERY" <> help "A dotted option prefix, or any substring of a path.")

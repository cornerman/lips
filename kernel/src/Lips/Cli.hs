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
  , defaultThinking
  ) where

import Control.Monad      (filterM)
import Data.List          (intercalate, isPrefixOf, isSuffixOf)
import qualified Data.Text as T
import Options.Applicative
import System.Directory    (doesDirectoryExist, listDirectory)
import System.FilePath     (splitFileName, (</>))
import Text.Read          (readMaybe)

import Lips.Nix.Target (Target (..), defaultTarget, parseTarget, targetSlug)

-- | Everything @generate@ needs. @-m\/--model@ is the ONLY way to name a
-- model -- no positional guessing (deleted with @Lips.Generate.Args@'s
-- @looksLikeModel@); omitting it lets @pi@'s own configured default apply.
data GenerateOpts = GenerateOpts
  { goTarget     :: Target
  , goSchema     :: Maybe String
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
--
-- Default @medium@, measured rather than guessed. A mint's cost is turns times
-- per-turn latency, and lips itself is under 1% of it (one @check_draft@ is
-- ~0.95s inside a six-minute mint). Reasoning level moves the second factor:
-- the same program minted in 6m22s at @high@ and 4m17s at @medium@, with the
-- same number of drafts and a behaviourally identical engine. What actually
-- costs a mint is a REFUSED draft, and that is bought with a clearer prompt, not
-- with a higher reasoning level. Raise it per run with @--thinking@ when a
-- program is genuinely hard; the level is recorded either way.
defaultThinking :: String
defaultThinking = "medium"

-- | Everything @compile@ needs. Exactly one program -- unlike @generate@'s
-- @some@, no forced symmetry: compile realizes into a single output
-- directory, it does not read a corpus. @coLangDir@ overrides where the
-- committed language files are read from (default: sibling of the program,
-- see 'Lips.Identity.resolveLangDir'); it never affects where compile WRITES
-- (that stays under the program's own directory).
data CompileOpts = CompileOpts
  { coOut        :: Maybe FilePath
  , coLangDir    :: Maybe FilePath
  , coNoContract :: Bool
  , coFile       :: FilePath
  } deriving (Eq, Show)

-- | Everything @check@ needs: the program, plus the same @--lang@
-- override @compile@ takes (same meaning: read-only, does not move derived
-- output).
data CheckOpts = CheckOpts
  { ceLangDir :: Maybe FilePath
  -- | Read the engine to check from stdin, in the mint's reply format, instead
  -- of loading the committed one. The mint's own validation door: a model
  -- checks a draft before answering, and the authoritative gate still runs
  -- afterwards in generate.
  , ceDraft   :: Bool
  , ceFile    :: FilePath
  } deriving (Eq, Show)

-- | Everything @options@ needs. A read-only schema lookup: which world's
-- schema to search, how many entries an answer may print, and the query.
data OptionsOpts = OptionsOpts
  { ooTarget :: Target
  , ooSchema :: Maybe String
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
    "lips builds a Nix configuration from a program you wrote in your own plain sentences."

-- | The three verbs a user works with day to day, in the loop's own order.
cliParser :: Double -> Parser Command
cliParser defConf = hsubparser
  (  command "generate"
       (info (Generate <$> generateOpts defConf)
             (progDesc "Learn the language of your programs and verify each one. The only step that uses AI."))
  <> command "compile"
       (info (Compile <$> compileOpts)
             (progDesc "Build the configuration into a directory, and print the nix commands that run it."))
  <> command "check"
       (info (Check <$> checkOpts)
             (progDesc "Confirm the program still produces what it promised. Offline, no AI."))
  )
  <|> hsubparser
  (  command "options"
       (info (Options <$> optionsOpts)
             (progDesc "Search the pinned option schema of a Nix world. Reads only, changes nothing."))
  <> command "lsp"
       (info (pure Lsp)
             (progDesc "Serve your editor: diagnostics for a program as you write it (stdio)."))
  <> commandGroup "tooling commands (editor/schema support):"
  <> hidden
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
  Nothing -> Left ("unknown target " <> s <> " (expected " <> targetMetavar <> ")")

-- | Every world's slug, listed from the type itself, so adding a target cannot
-- leave the help text or the error message naming a world that no longer is the
-- whole set.
targetMetavar :: String
targetMetavar = intercalate "|" [ T.unpack (targetSlug t) | t <- [minBound .. maxBound] ]

-- | @--confidence@'s reader: a Double in [0,1], the same range check
-- @Lips.Generate.Args.parseGenerate@ did inline, now in the reader so an
-- out-of-range value fails the same way an unknown @--target@ does.
confidenceReader :: ReadM Double
confidenceReader = eitherReader $ \s -> case readMaybe s of
  Just d | d >= 0, d <= 1 -> Right d
  _                       -> Left (s <> " is not a confidence in [0,1]")

-- | @--schema@: the flake whose option document grounds the mint, overriding
-- the pin baked into this binary. This is the knob for a caller whose own world
-- is not the one lips was built against (a stable channel, a company nixpkgs, a
-- home-manager release): grounding against the schema the module will actually
-- be evaluated with is what makes the mint's option check mean anything.
-- lips resolves it through @nix flake metadata@ and records the LOCKED result in
-- @.generation@, so a floating ref cannot make the record lie about what was
-- used. Shared by generate and options, since the lookup verb must read exactly
-- what a mint would read.
schemaOpt :: Parser (Maybe String)
schemaOpt = optional (strOption
  (long "schema" <> metavar "FLAKEREF"
    <> help "Build this world's option schema from FLAKEREF instead of the pin baked into lips. Recorded, locked, in .generation."))

generateOpts :: Double -> Parser GenerateOpts
generateOpts defConf = GenerateOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar targetMetavar <> help "Which Nix world the configuration is for (default: nixos).")
  <*> schemaOpt
  <*> option confidenceReader
        (long "confidence" <> value defConf
          <> metavar "0..1" <> help "How sure the model must be of every line it writes (default: 0.7). Anything less is refused.")
  <*> switch (long "renew" <> help "Accept this run's behaviour as the new contract, replacing the committed .expect.")
  <*> switch (long "verbose" <> short 'v' <> help "Show everything sent to the model and everything it says, as it happens.")
  <*> optional (strOption
        (long "model" <> short 'm' <> metavar "ID"
          <> help "Which model to ask (default: whichever pi is configured for)."))
  <*> strOption
        (long "thinking" <> value defaultThinking
          <> metavar "off|minimal|low|medium|high|xhigh|max"
          <> help "How hard the model should think (default: medium). Recorded in .generation.")
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
    <> help "Read the language from DIR instead of the folder beside the program (DIR must be named after the program's language)."))

compileOpts :: Parser CompileOpts
compileOpts = CompileOpts
  <$> optional (strOption
        (long "out" <> short 'o' <> metavar "DIR"
          <> help "Where to write the configuration (default: <language>/out/<instance>)."))
  <*> langDirOpt
  -- For the one caller that CANNOT run the gate: a compile inside a nix
  -- derivation (lib.modulesFromDir, the VM checks) has no nix to evaluate the
  -- realized module with. The flag makes that skip a stated choice at the call
  -- site instead of an unstated consequence of not staging the .expect file.
  <*> switch
        (long "no-contract"
          <> help "Do not check the contract, for a compile inside a nix build (which has no nix to evaluate with). The program must still crystallize.")
  <*> programArg

-- | Which engine @check@ judges. The two ways are mutually exclusive by
-- CONSTRUCTION rather than by a validating wrapper: optparse-applicative's
-- 'Parser' is applicative only, so it cannot inspect one field to reject
-- another. 'flag'' fails when @--draft@ is absent, so the alternative picks a
-- side, and whichever flag is left over then has no parser and the invocation
-- is refused -- in either argument order.
data EngineSource
  = FromLang (Maybe FilePath)
  | FromDraft

engineSource :: Parser EngineSource
engineSource =
  (FromDraft <$ flag' ()
     (long "draft"
       <> help "Judge a draft language read from stdin instead of the committed one (this is the door the mint checks itself through)."))
  <|> (FromLang <$> langDirOpt)

checkOpts :: Parser CheckOpts
checkOpts = mk <$> engineSource <*> programArg
  where
    mk FromDraft      f = CheckOpts Nothing  True  f
    mk (FromLang dir) f = CheckOpts dir      False f

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
          <> metavar targetMetavar <> help "Which Nix world's options to search (default: nixos).")
  <*> schemaOpt
  <*> option limitReader
        (long "limit" <> value 40
          <> metavar "N" <> help "How many entries an answer may print (default: 40).")
  <*> strArgument
        (metavar "QUERY" <> help "A dotted option prefix to browse, or any substring of a path to find one.")

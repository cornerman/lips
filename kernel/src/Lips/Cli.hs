{-# LANGUAGE OverloadedStrings #-}

-- | The lips CLI grammar, declared once as an optparse-applicative Parser so
-- real invocations, --help text, and --bash/--zsh/--fish-completion-script all
-- derive from the same source and can never drift apart -- unlike a
-- hand-rolled parser plus a separately hand-maintained completion script.
-- Kept free of IO: this module only builds the Parser value; Main.hs runs it
-- and dispatches. See docs/superpowers/specs/2026-07-25-cli-completion-design.md.
module Lips.Cli
  ( Command (..)
  , GenerateOpts (..)
  , CompileOpts (..)
  , cliParserInfo
  , generateOpts
  , compileOpts
  ) where

import Options.Applicative
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
  , goFiles      :: [FilePath]
  } deriving (Eq, Show)

-- | Everything @compile@ needs. Exactly one program -- unlike @generate@'s
-- @some@, no forced symmetry: compile realizes into a single output
-- directory, it does not read a corpus.
data CompileOpts = CompileOpts
  { coOut  :: Maybe FilePath
  , coFile :: FilePath
  } deriving (Eq, Show)

-- | The four lips verbs, all visible/documented via 'hsubparser' (lsp was
-- previously reachable but absent from --help; now consistent with the rest).
data Command
  = Generate GenerateOpts
  | Compile CompileOpts
  | Check FilePath
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
       (info (Check <$> programArg)
             (progDesc "Verify the program still produces what it promised."))
  <> command "lsp"
       (info (pure Lsp)
             (progDesc "Run the lips language server (stdio)."))
  )

programArg :: Parser FilePath
programArg = strArgument (metavar "PROGRAM")

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
  <*> some (strArgument (metavar "PROGRAM..."))

compileOpts :: Parser CompileOpts
compileOpts = CompileOpts
  <$> optional (strOption
        (long "out" <> short 'o' <> metavar "DIR"
          <> help "Output directory (default: <language>/out/<instance>)."))
  <*> programArg

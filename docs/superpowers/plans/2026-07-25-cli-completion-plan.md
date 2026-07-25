# CLI Completion via optparse-applicative Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-rolled `lips` argument parser (`Lips.Generate.Args` + the `case args of` dispatch in `Main.hs`) with an `optparse-applicative` parser, so bash/zsh/fish tab-completion falls out for free, always in sync with real parsing, and the model-guessing heuristic (`looksLikeModel`) is deleted.

**Architecture:** One new module, `Lips.Cli`, declares the whole CLI grammar as an `optparse-applicative` `Parser Command` (four subcommands via `hsubparser`: `generate`, `compile`, `check`, `lsp`). `Main.hs` runs it with `execParser` and dispatches on the resulting `Command` value; its hand-rolled `usage` text and `Lips.Generate.Args` module are deleted. The Nix packaging generates and ships the three completion scripts from the built binary via `installShellFiles`.

**Tech Stack:** Haskell (GHC, no cabal — direct `ghc -isrc -iapp`/`-itest` invocation per `flake.nix`), `optparse-applicative` (new dependency), hspec + QuickCheck (existing suite, `kernel/test/Spec.hs`). Build/test via `just test` or the `ghc` one-liner in `kernel/`; full check via `nix flake check`.

## Global Constraints

- Kernel stays domain-blind; this feature touches only `kernel/app/Main.hs`, a new `kernel/src/Lips/Cli.hs`, `kernel/test/Spec.hs`, and Nix packaging — no `Lips.Kernel.*` file changes.
- `run`/`compile`/`check` never call a model (invariant 1) — unaffected; this plan only replaces argument parsing, never domain logic.
- Deduce-or-fail: no argument-parsing behavior may silently default where today it fails loud (duplicate `--model`, unknown `--target`, out-of-range `--confidence` must all still be parse errors).
- `report`/`reportHead` and every domain error message in `Main.hs` are untouched — confirmed out of scope in the design (they fire after a successful parse, `optparse-applicative` errors fire only on a malformed invocation).
- No new CLI flags beyond what exists today (`-t/--target`, `--confidence`, `--renew`, `-v/--verbose`, `-m/--model`, `-o/--out`); no `--version`.
- `-m/--model` is the ONLY way to name a model — `looksLikeModel` and positional model-guessing are deleted, not preserved as a fallback.
- `--renew` stays long-only (deliberate, no short alias). `compile` takes exactly one program (not variadic like `generate`).
- Conformance suite stays `-Wall` clean. TDD: failing test first, then implement, then green, then commit. Small single-line commits; rebase + ff-merge (no merge commits); no co-author attribution in commit messages.
- Work in a worktree under `.worktrees/` (per `AGENTS.md`); `git add` new/changed files before any `nix build`/`nix run` (flakes see only git-tracked files).
- Design doc: `docs/superpowers/specs/2026-07-25-cli-completion-design.md` — read it before Task 1 for full rationale; this plan implements it task-by-task.

---

## File Structure

**New:**
- `kernel/src/Lips/Cli.hs` — the whole CLI grammar: `Command`, `GenerateOpts`, `CompileOpts`, `cliParserInfo`, `generateOpts`, `compileOpts` (the latter two exported so the test suite can parse sub-parsers directly, matching the existing test style of calling the parsing function directly rather than through `Main`).

**Modified:**
- `kernel/app/Main.hs` — `main` dispatches on `Lips.Cli.Command` via `execParser`; the hand-rolled `usage` function and the `case args of` block are deleted; `Lips.Generate.Args` import removed.
- `kernel/test/Spec.hs` — the `"generate argument parsing (--target, --confidence, model)"` describe block (lines ~63–88) is rewritten against `Lips.Cli.generateOpts` via `execParserPure`; import changes from `Lips.Generate.Args` to `Lips.Cli` plus `Options.Applicative`.
- `flake.nix` — `ghc` function gains `p.optparse-applicative`; `packages.default` gains `installShellFiles` + `installShellCompletion` calls.
- `justfile` — the `generate` recipe's conditional model arg becomes an explicit `--model` flag.

**Deleted:**
- `kernel/src/Lips/Generate/Args.hs`.

---

### Task 1: Add the `optparse-applicative` dependency

**Files:**
- Modify: `flake.nix` (the `ghc` function, used by `devShells.default`, `packages.default`, `checks.kernel-tests`)

**Interfaces:**
- Produces: `optparse-applicative` importable as `Options.Applicative` in every GHC invocation the flake drives (dev shell, package build, test check).

- [ ] **Step 1: Add the package to the shared `ghc` function**

In `flake.nix`, find:

```nix
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck p.aeson ]);
```

Replace with:

```nix
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck p.aeson p.optparse-applicative ]);
```

- [ ] **Step 2: Verify the dev shell resolves the package**

Run: `nix develop -c ghc-pkg list optparse-applicative`
Expected: prints a line like `optparse-applicative-0.18.1` (exact version may
differ; any resolved version is fine). If this fails with "cannot find
package", the attribute name is wrong for the pinned nixpkgs — check
`nix develop -c ghc-pkg list | grep -i optparse` to find the exact package name
and adjust Step 1.

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "flake: add optparse-applicative to the GHC package set"
```

---

### Task 2: Write `Lips.Cli` — the CLI grammar

**Files:**
- Create: `kernel/src/Lips/Cli.hs`
- Test: `kernel/test/Spec.hs` (new describe block, replacing the old `Lips.Generate.Args` one — written in this task, run at the end)

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target (..), defaultTarget, parseTarget)` (existing, unchanged).
- Produces:
  - `data GenerateOpts = GenerateOpts { goTarget :: Target, goConfidence :: Double, goRenew :: Bool, goVerbose :: Bool, goModel :: Maybe String, goFiles :: [FilePath] } deriving (Eq, Show)`
  - `data CompileOpts = CompileOpts { coOut :: Maybe FilePath, coFile :: FilePath } deriving (Eq, Show)`
  - `data Command = Generate GenerateOpts | Compile CompileOpts | Check FilePath | Lsp deriving (Eq, Show)`
  - `cliParserInfo :: Double -> ParserInfo Command` (top-level; `Double` is the default confidence, matching `Lips.Generate.Args.parseGenerate`'s existing signature convention)
  - `generateOpts :: Double -> Parser GenerateOpts` (exported so the test suite parses it directly, mirroring today's direct call to `parseGenerate`)
  - `compileOpts :: Parser CompileOpts` (exported for the same reason)

- [ ] **Step 1: Write the failing test for `generateOpts`**

In `kernel/test/Spec.hs`, replace the whole `describe "generate argument parsing (--target, --confidence, model)"` block (currently lines ~63–88) with:

```haskell
  describe "generate argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info (generateOpts 0.7) idm)
    it "defaults target to nixos, confidence to the default, renew/verbose off" $
      parseArgs ["ledger.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 False False Nothing ["ledger.backup.lips"])
    it "reads --target home-manager in any position" $
      parseArgs ["--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts HomeManager 0.7 False False Nothing ["a.backup.lips"])
    it "rejects an unknown target" $
      parseArgs ["--target", "darwin", "a.backup.lips"] `shouldBe` Nothing
    it "reads an explicit --model alongside multiple programs" $
      parseArgs ["--model", "anthropic/claude", "a.backup.lips", "b.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 False False (Just "anthropic/claude") ["a.backup.lips", "b.backup.lips"])
    it "combines --target and --confidence" $
      parseArgs ["--confidence", "0.9", "--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts HomeManager 0.9 False False Nothing ["a.backup.lips"])
    it "rejects an out-of-range confidence" $
      parseArgs ["--confidence", "1.5", "a.backup.lips"] `shouldBe` Nothing
    it "reads --renew in any position" $ do
      parseArgs ["--renew", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 True False Nothing ["a.backup.lips"])
      parseArgs ["a.backup.lips", "--renew"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 True False Nothing ["a.backup.lips"])
    it "reads -v/--verbose in any position" $ do
      parseArgs ["--verbose", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 False True Nothing ["a.backup.lips"])
      parseArgs ["a.backup.lips", "-v"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 False True Nothing ["a.backup.lips"])
    it "reads -m as the short alias for --model" $
      parseArgs ["-m", "anthropic/claude", "a.backup.lips"]
        `shouldBe` Just (GenerateOpts Nixos 0.7 False False (Just "anthropic/claude") ["a.backup.lips"])
    it "rejects a duplicate --model (fail loud, not last-wins)" $
      parseArgs ["--model", "a", "--model", "b", "a.backup.lips"] `shouldBe` Nothing
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing
```

Also replace the import line:

```haskell
import Lips.Generate.Args (parseGenerate)
```

with:

```haskell
import Lips.Cli (Command (..), GenerateOpts (..), CompileOpts (..), cliParserInfo, generateOpts, compileOpts)
import Options.Applicative (execParserPure, defaultPrefs, getParseResult, info, idm)
```

- [ ] **Step 2: Run the suite to verify it fails to compile (module doesn't exist yet)**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec'`
Expected: FAIL with `Could not find module 'Lips.Cli'`.

- [ ] **Step 3: Write `Lips.Cli`**

Create `kernel/src/Lips/Cli.hs`:

```haskell
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
          <> help "Output directory (default: <program without extension>)."))
  <*> programArg
```

- [ ] **Step 4: Run the suite to verify the new tests pass**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS, all examples in the "generate argument parsing (Lips.Cli)"
block green, and every other existing describe block unaffected (they don't
touch `Lips.Cli`/`Lips.Generate.Args` at all).

If "rejects a duplicate --model" unexpectedly passes with last-wins semantics
instead of failing: `optparse-applicative`'s default behavior for a plain
`option`/`optional (strOption ...)` is to reject a second occurrence of the
same flag as an unconsumed extra argument (this is what makes the test
meaningful) — if this assumption is wrong for the pinned version, that is a
real finding; do not force it to pass by adding `many`/custom logic beyond
what Step 3 already writes; report the discrepancy instead of routing around it.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/test/Spec.hs
git commit -m "cli: add Lips.Cli, the optparse-applicative grammar"
```

---

### Task 3: Wire `Main.hs` to `Lips.Cli`; delete `Lips.Generate.Args`

**Files:**
- Modify: `kernel/app/Main.hs`
- Delete: `kernel/src/Lips/Generate/Args.hs`

**Interfaces:**
- Consumes: `Lips.Cli (Command (..), GenerateOpts (..), CompileOpts (..), cliParserInfo)` (Task 2); `Options.Applicative (execParser)`.
- Produces: `main :: IO ()` unchanged in externally observed behavior (same four verbs, same flags with `-m`/`-t`/`-o`/`-v` short forms now additionally accepted) except: (a) a bare positional model id no longer works, `--model`/`-m` is required to name one; (b) `lsp` now appears in `lips --help`; (c) `--help`/malformed-invocation text comes from `optparse-applicative`, not the old `usage` function.

- [ ] **Step 1: Replace the import and `main`**

In `kernel/app/Main.hs`, replace:

```haskell
import           Lips.Generate.Args     (parseGenerate)
```

with:

```haskell
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), cliParserInfo)
import           Options.Applicative    (execParser)
```

Replace:

```haskell
main :: IO ()
main = do
  args <- getArgs
  case args of
    ["compile", file]                -> compileLoose Nothing file
    ["compile", "--out", dir, file]  -> compileLoose (Just dir) file
    ["check", file]              -> checkLoose file
    ["lsp"]              -> runLsp
    ("generate" : rest)  -> case parseGenerate defaultConfidence rest of
      Just (target, conf, renew, verbose, mmodel, fs) -> generate target conf renew verbose mmodel fs
      Nothing                         -> usage >> exitFailure
    _                    -> usage >> exitFailure

-- | Parse @generate@ arguments: optional @--confidence <0..1>@ and
-- @--model <id>@ flags in any position, then @[model] <program-file>...@ --
-- one or more programs (all of one language, checked later). A malformed
-- threshold, a duplicate model, or no program fails loud (returns Nothing).
usage :: IO ()
usage = do
  -- The tool's name is fixed. getProgName would leak the Nix wrapper's real
  -- target (.lips-unwrapped), so name it directly.
  let name = "lips" :: Text
  TIO.hPutStr stderr $ T.unlines
    [ "lips turns an <instance>.<language> program, written in your own plain lines, into a NixOS configuration."
    , ""
    , "usage:"
    , "  " <> name <> " generate [--target nixos|home-manager] [--confidence <0..1>] [--renew] [--verbose] [--model <id>|model] <program>..."
    , "      Mint the language from one or more example programs and verify each."
    , "      The one step that uses AI. --verbose echoes the raw model reply."
    , "  " <> name <> " compile [--out <dir>] <program>"
    , "      Realize into a directory (flake.nix + default.nix + artifacts/) and"
    , "      print the nix commands that run it (nix run/build over the dir)."
    , "  " <> name <> " check <program>"
    , "      Verify the program still produces what it promised."
    ]
```

with:

```haskell
main :: IO ()
main = do
  cmd <- execParser (cliParserInfo defaultConfidence)
  case cmd of
    Generate go -> generate (goTarget go) (goConfidence go) (goRenew go) (goVerbose go) (goModel go) (goFiles go)
    Compile co  -> compileLoose (coOut co) (coFile co)
    Check f     -> checkLoose f
    Lsp         -> runLsp
```

`getArgs` (from `System.Environment`) is no longer called directly by `main`
(`execParser` reads `getArgs` internally); remove `getArgs` from the
`System.Environment` import list, keeping `lookupEnv`:

```haskell
import           System.Environment (lookupEnv)
```

- [ ] **Step 2: Handle the now-total `generate` function**

`generate`'s empty-list clause currently reads:

```haskell
generate :: Target -> Double -> Bool -> Bool -> Maybe String -> [FilePath] -> IO ()
generate _ _ _ _ _ [] = usage >> exitFailure
```

`some (strArgument ...)` in `Lips.Cli.generateOpts` already guarantees
`goFiles` is non-empty by construction (the parser cannot produce a `Generate`
value with an empty file list), so this clause is dead in practice but must
stay for `-Wall`'s incomplete-patterns check. Replace `usage >> exitFailure`
(now undefined, `usage` is deleted) with a direct `die`:

```haskell
generate _ _ _ _ _ [] = die "lips generate needs at least one program (unreachable: the CLI parser requires one)."
```

- [ ] **Step 3: Compile and check for leftover references**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-build -o /tmp/lips-main'`
Expected: succeeds with no warnings (in particular no "defined but not used"
for `exitFailure`/`Text`/`T` if any import is now unused — remove any import
GHC flags as unused; `exitFailure` is still used elsewhere in `Main.hs`
(`die`), so it must stay).

- [ ] **Step 4: Delete the old parser module**

```bash
git rm kernel/src/Lips/Generate/Args.hs
```

- [ ] **Step 5: Rebuild the full test suite and the binary**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS (Args.hs's own tests are gone, replaced by Task 2's; nothing
else imported it — confirm with `grep -rn "Generate.Args" kernel/` returning
nothing).

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-build -o /tmp/lips-main'`
Expected: succeeds.

- [ ] **Step 6: Manual smoke test of the new CLI surface**

```bash
/tmp/lips-main --help                 # lists generate, compile, check, lsp
/tmp/lips-main generate --help        # shows -t/-m/-o(n/a)/-v with descriptions
/tmp/lips-main compile --help         # shows -o/--out
/tmp/lips-main generate examples/ledger.backup.lips   # SHOULD FAIL: no such flag combo needed, just confirm it reaches the real generate function (will fail later on missing pi/model if not configured -- that's expected, this step only confirms argument parsing itself doesn't reject a bare program path)
```

Expected: `--help` outputs list all four subcommands (`lsp` included); running
`generate` with a bare program path and no `--model` proceeds past argument
parsing (any failure from here on is `pi`/network/model related, not a parse
error) — confirming the model is no longer required to be guessed positionally.

- [ ] **Step 7: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "cli: dispatch through Lips.Cli; delete usage and Lips.Generate.Args"
```

---

### Task 4: Ship shell completion scripts from the Nix package

**Files:**
- Modify: `flake.nix` (`packages.default`)

**Interfaces:**
- Consumes: the built `lips` binary's `--bash-completion-script`/`--zsh-completion-script`/`--fish-completion-script` (provided automatically by `optparse-applicative`'s `execParser`, no extra code needed beyond Task 2/3 — verified in this task).
- Produces: `$out/share/bash-completion/completions/lips`, `$out/share/zsh/site-functions/_lips`, `$out/share/fish/vendor_completions.d/lips.fish` in the `lips` package output.

- [ ] **Step 1: Verify the completion flags work on the built binary (baseline, before packaging)**

```bash
nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-build -o /tmp/lips-main && /tmp/lips-main --bash-completion-script /tmp/lips-main | head -5'
```

Expected: prints a bash completion function definition (starts with something
like `_lips()` or `#!/usr/bin/env bash`-style boilerplate depending on the
`optparse-applicative` version) — proof the flag is live with zero extra code
in `Lips.Cli`/`Main.hs`.

- [ ] **Step 2: Add `installShellFiles` to `packages.default`**

In `flake.nix`, find:

```nix
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips" { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper ]; } ''
          cp -r ${./kernel}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/.lips-unwrapped"
          # generate checks minted rules against the NixOS option schema, which
          # it builds lazily from THIS pinned nixpkgs. Bake the ref as a STRING
          # (a rev, not a store path), so nixpkgs never enters the closure of
          # print/run/check; only generate resolves and evaluates it. A caller
          # may override with LIPS_OPTIONS_JSON (a prebuilt options.json).
          makeWrapper "$out/bin/.lips-unwrapped" "$out/bin/lips" \
            --set-default LIPS_NIXPKGS_FLAKE "github:NixOS/nixpkgs/${nixpkgs.rev}" \
            --set-default LIPS_HM_FLAKE "github:nix-community/home-manager/${home-manager.rev}"
        '';
      });
```

Replace with:

```nix
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips"
          { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper pkgs.installShellFiles ]; } ''
          cp -r ${./kernel}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/.lips-unwrapped"
          # generate checks minted rules against the NixOS option schema, which
          # it builds lazily from THIS pinned nixpkgs. Bake the ref as a STRING
          # (a rev, not a store path), so nixpkgs never enters the closure of
          # print/run/check; only generate resolves and evaluates it. A caller
          # may override with LIPS_OPTIONS_JSON (a prebuilt options.json).
          makeWrapper "$out/bin/.lips-unwrapped" "$out/bin/lips" \
            --set-default LIPS_NIXPKGS_FLAKE "github:NixOS/nixpkgs/${nixpkgs.rev}" \
            --set-default LIPS_HM_FLAKE "github:nix-community/home-manager/${home-manager.rev}"
          # Completion scripts derive from the SAME optparse-applicative Parser
          # that parses real invocations (Lips.Cli), so they cannot drift from
          # it the way a hand-maintained static script would. Generated from
          # the just-built binary; hermetic (no network, no AI call -- these
          # flags are a pure parser-introspection path, never reaching pi).
          installShellCompletion --cmd lips \
            --bash <($out/bin/lips --bash-completion-script $out/bin/lips) \
            --zsh  <($out/bin/lips --zsh-completion-script  $out/bin/lips) \
            --fish <($out/bin/lips --fish-completion-script $out/bin/lips)
        '';
      });
```

- [ ] **Step 3: Build the package and verify completion files are present**

```bash
git add flake.nix kernel/  # ensure Task 2/3 changes are tracked -- flakes see only git-tracked files
nix build . --print-out-paths
```

Expected: builds successfully; then:

```bash
ls result/share/bash-completion/completions/lips
ls result/share/zsh/site-functions/_lips
ls result/share/fish/vendor_completions.d/lips.fish
```

Expected: all three files exist and are non-empty.

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "flake: ship bash/zsh/fish completion scripts with the lips package"
```

---

### Task 5: Update `justfile`, `README.md`, `DESIGN.md`, `TODO.md`

**Files:**
- Modify: `justfile` (`generate` recipe)
- Modify: `DESIGN.md` (§13 "Done" section)
- Modify: `TODO.md` (drop or note completion if listed — it isn't currently, so no change needed there unless the ledger entry references it)

**Interfaces:** none (docs/build-glue only).

- [ ] **Step 1: Fix `justfile`'s `generate` recipe (it relied on the deleted heuristic)**

In `justfile`, find:

```
# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{model}}" ]; then
      nix run . -- generate "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi
```

Replace with:

```
# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{model}}" ]; then
      nix run . -- generate --model "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi
```

- [ ] **Step 2: Verify the recipe still works end-to-end (dry run of the argument shape)**

```bash
just --dry-run generate examples/ledger.backup.lips anthropic/claude
```

(If `just` has no `--dry-run` for shebang recipes, instead read the rendered
command by adding a temporary `set -x` at the top of the recipe body, running
it, then removing `set -x` again — do not leave `set -x` committed.)
Expected: the printed/executed command is
`nix run . -- generate --model anthropic/claude examples/ledger.backup.lips`.

- [ ] **Step 3: Add the DESIGN.md §13 "Done" entry**

In `DESIGN.md`, in section 13 under `### Done`, add a new bullet (place it
first, matching the existing pattern of newest-first):

```markdown
- **CLI: optparse-applicative parser, tab-completion for free.** `lips`'s
  argument parsing (`Lips.Generate.Args`'s hand-rolled loop, including the
  `looksLikeModel` heuristic that guessed whether a bare positional was a
  model id or a program file) is replaced by `Lips.Cli`, a single
  `optparse-applicative` `Parser Command` covering all four verbs
  (`generate`, `compile`, `check`, `lsp` -- `lsp` was reachable before but
  absent from `--help`; now consistent). `-m/--model` is the only way to name
  a model; short aliases `-t/--target`, `-o/--out`, `-v/--verbose` are added
  (`--renew` stays long-only, a deliberate rare action). Because completion
  scripts derive from the same `Parser` that parses real invocations, they
  cannot drift the way a hand-maintained static script would --
  `installShellCompletion` (nix packaging) ships bash/zsh/fish completions
  generated from the built binary at package build time. No change to any
  `report`/`reportHead` domain error (they are downstream of a successful
  parse). Spec: `docs/superpowers/specs/2026-07-25-cli-completion-design.md`.
```

- [ ] **Step 4: Check `TODO.md` for a stale reference (none expected)**

Run: `grep -n "completion\|optparse\|looksLikeModel" TODO.md`
Expected: no output (this feature was never tracked there — nothing to
remove). If it does find something, delete/update that line to reflect
completion.

- [ ] **Step 5: Commit**

```bash
git add justfile DESIGN.md
git commit -m "docs: record the optparse-applicative CLI migration in the ledger"
```

---

### Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the fast conformance suite**

```bash
just test
```

Expected: all tests pass, including the new `Lips.Cli` describe block from
Task 2 and every pre-existing block untouched.

- [ ] **Step 2: Run the full flake check**

```bash
just check
```

Expected: `nix flake check -L` passes — `kernel-tests` (the suite), the
`lipsModules-eval` check, `vm-smoke`, and `artifact-vm` (both use
`${lips}/bin/lips compile --out ...`, whose argument shape is unchanged by
this plan: `compile --out <dir> <program>` still parses identically under
`Lips.Cli.compileOpts`).

- [ ] **Step 3: Manual completion smoke test in a real shell**

```bash
nix build .
source <(result/bin/lips --bash-completion-script result/bin/lips)
lips <TAB><TAB>   # (interactively, in a bash session with the above sourced)
```

Expected: completion offers `generate`, `compile`, `check`, `lsp`. This step
is manual/interactive (cannot be scripted in this plan) — confirm the four
subcommands and, one level deeper, that `lips generate --<TAB><TAB>` offers
`--target`, `--confidence`, `--renew`, `--verbose`, `--model`.

- [ ] **Step 4: Confirm no dangling references to the deleted module**

```bash
grep -rn "Lips.Generate.Args\|looksLikeModel\|parseGenerate" kernel/ README.md DESIGN.md TODO.md justfile
```

Expected: no output.

---

## Self-Review Notes (for whoever executes this plan)

- Every task ends with a runnable verification command and an expected
  outcome — none require re-deriving what "pass" means from the design doc.
- Task 2's tests pin the exact behavior change (duplicate `--model` still
  fails, but no more positional guessing) called out as the key risk in the
  design doc's "Why the Current Parser Blocks This" section.
- Task 4 is the one step that cannot be verified by the sandboxed suite alone
  (needs `nix build`, which needs network/store access this planning session
  may not have) — Task 6 Step 2's `nix flake check` is the authoritative gate;
  do not claim this plan complete without having run it.

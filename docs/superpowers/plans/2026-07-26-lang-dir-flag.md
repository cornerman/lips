# `--lang-dir` Flag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `compile` and `check` read a language's committed files
(`.lang`/`.expect`/`.generation`/`artifacts/`) from a directory other than the
program's own sibling folder, via `--lang-dir DIR`, while derived output
(`out/`) stays local to the program.

**Architecture:** `Lips.Identity` gains a pure resolver
(`resolveLangDir`) plus explicit-directory variants of the four
committed-path functions. `Lips.Cli` threads a new `Maybe FilePath` through
`CompileOpts` and a new `CheckOpts` record. `Main.hs`'s `compileLoose`/
`checkLoose` resolve the directory once and pass it down to the helper
functions that used to re-derive it from the program path.

**Tech Stack:** Haskell (GHC, no cabal — flake-supplied package set),
`optparse-applicative`, `hspec`/`QuickCheck` (`kernel/test/Spec.hs`).

## Global Constraints

- No change to `generate` or `lsp` — no `--lang-dir` flag on either
  (spec "Scope").
- Derived output (`outDir`, `decisionsPath`, `compiledPath`) and the
  human-owned `directionPath` are never affected by `--lang-dir` (spec
  "Semantics", "Code Shape").
- `--lang-dir DIR`'s basename must equal the program's declared language;
  mismatch fails loud naming both sides, checked before any file IO against
  the resolved directory (spec "Validation").
- `kernel/` must stay `-Wall` clean; test with
  `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
  from inside `kernel/`, run via `nix develop -c bash -c '...'` (no `just` in
  this environment).
- Spec reference: `docs/superpowers/specs/2026-07-26-lang-dir-flag-design.md`.

---

### Task 1: `resolveLangDir` and explicit-directory path functions in `Lips.Identity`

**Files:**
- Modify: `kernel/src/Lips/Identity.hs`
- Test: `kernel/test/Spec.hs` (new `describe` block near the existing
  "solution identity (plan 2026-07-22: <instance>.<language>.lips)" block,
  around line 1727)

**Interfaces:**
- Consumes: nothing new (uses existing `languageName`, `langDir`, `langLevel`
  helpers already in `Lips.Identity`).
- Produces (used by Task 2 and Task 3):
  - `resolveLangDir :: FilePath -> Maybe FilePath -> Either Text FilePath`
  - `langPathIn :: FilePath -> FilePath -> FilePath`
  - `expectPathIn :: FilePath -> FilePath -> FilePath`
  - `generationPathIn :: FilePath -> FilePath -> FilePath`
  - `artifactsPathIn :: FilePath -> FilePath -> FilePath`
  - All four `*In` functions take `(dir, file)` in that order.

- [ ] **Step 1: Write the failing tests**

Add this `describe` block to `kernel/test/Spec.hs`, right after the existing
`"never collides between instances of one language"` / `"the shorthand puts
the singleton under the language's own name"` tests (i.e. right before the
`describe "reader fails loud on malformed lines..."` block, currently around
line 1748-1750):

```haskell
  describe "--lang-dir resolution (Lips.Identity.resolveLangDir)" $ do
    let prog = "services/b/photos.backup.lips"
    it "with no override, resolves to the sibling langDir" $
      resolveLangDir prog Nothing `shouldBe` Right (langDir prog)
    it "accepts an override folder named after the program's language" $
      resolveLangDir prog (Just "services/a/backup")
        `shouldBe` Right "services/a/backup"
    it "tolerates a trailing slash on the override" $
      resolveLangDir prog (Just "services/a/backup/")
        `shouldBe` Right "services/a/backup"
    it "rejects an override folder named after a different language" $ do
      resolveLangDir prog (Just "services/a/archival") `shouldSatisfy` isLeft
      let Left msg = resolveLangDir prog (Just "services/a/archival")
      msg `shouldSatisfy` T.isInfixOf "backup"
      msg `shouldSatisfy` T.isInfixOf "archival"

  describe "explicit-directory path functions (Lips.Identity.*In)" $ do
    let prog = "services/b/photos.backup.lips"
        dir  = "services/a/backup"
    it "reads the four committed files from the given directory, not the sibling" $ do
      langPathIn       dir prog `shouldBe` "services/a/backup/backup.lang"
      expectPathIn     dir prog `shouldBe` "services/a/backup/backup.expect"
      generationPathIn dir prog `shouldBe` "services/a/backup/backup.generation"
      artifactsPathIn  dir prog `shouldBe` "services/a/backup/artifacts"
```

`isLeft` is already imported in `Spec.hs` (used by the "reader fails loud on
malformed lines" block below it); `T` is already imported as `Data.Text as T`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec' 2>&1 | tail -40
```

Expected: a compile error — `resolveLangDir`, `langPathIn`, `expectPathIn`,
`generationPathIn`, `artifactsPathIn` are not in scope (not yet exported from
`Lips.Identity`).

- [ ] **Step 3: Implement in `Lips.Identity`**

Add `Data.Text (Text)` and `qualified Data.Text as T` imports (the module
currently imports both already — check the existing import list first; if
`Text`/`T` aren't imported, add them alongside the existing
`System.FilePath` import). Add `dropTrailingPathSeparator` to the
`System.FilePath` import list.

Add to the export list:

```haskell
  , resolveLangDir
  , langPathIn
  , expectPathIn
  , generationPathIn
  , artifactsPathIn
```

Add after the existing `langLevel` function:

```haskell
-- | An explicit-directory variant of 'langLevel': the caller supplies the
-- directory (already resolved, e.g. via 'resolveLangDir') instead of it being
-- re-derived from @file@. Used by @compile@/@check@ when @--lang-dir@
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

-- | 'artifactsPath', reading from an explicitly given directory: a directory
-- inside the given directory, so (like 'artifactsPath') it needs no prefix to
-- stay unambiguous.
artifactsPathIn :: FilePath -> FilePath -> FilePath
artifactsPathIn dir _file = dir </> "artifacts"

-- | Resolve the directory @compile@/@check@ read the four committed language
-- files from. @Nothing@ (no @--lang-dir@) keeps today's sibling convention
-- ('langDir'). @Just d@ must be a folder named after the program's OWN
-- declared language (its @.lips@ filename is the one place that names it);
-- otherwise this fails loud, naming both sides, before any file IO runs
-- against @d@ -- deduce-or-fail, the same posture as a missing @.lang@.
-- A trailing separator on @d@ is tolerated (@dropTrailingPathSeparator@)
-- so @--lang-dir services/a/backup/@ matches exactly as
-- @--lang-dir services/a/backup@ does.
resolveLangDir :: FilePath -> Maybe FilePath -> Either Text FilePath
resolveLangDir file Nothing  = Right (langDir file)
resolveLangDir file (Just d)
  | takeFileName (dropTrailingPathSeparator d) == lang = Right d
  | otherwise = Left $ T.pack file <> " is written in ." <> T.pack lang
      <> ", but " <> T.pack d <> " is named ." <> T.pack (takeFileName (dropTrailingPathSeparator d))
      <> ".\n\n\8594 point --lang-dir at a folder named " <> T.pack lang
      <> ", or rename the program."
  where lang = languageName file
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec' 2>&1 | tail -40
```

Expected: PASS, all new tests green, no new `-Wall` warnings, no existing
test regressed (still 254+ examples, 0 failures — the exact count grows by
the new tests added).

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Identity.hs kernel/test/Spec.hs
git commit -m "identity: resolveLangDir + explicit-directory path functions"
```

---

### Task 2: `--lang-dir` on the `compile` and `check` CLI parsers

**Files:**
- Modify: `kernel/src/Lips/Cli.hs`
- Test: `kernel/test/Spec.hs` (new `describe` block near the existing
  `"generate argument parsing (Lips.Cli)"` block)

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces (used by Task 3):
  - `CompileOpts { coOut :: Maybe FilePath, coFile :: FilePath, coLangDir :: Maybe FilePath }`
  - `data CheckOpts = CheckOpts { ceFile :: FilePath, ceLangDir :: Maybe FilePath } deriving (Eq, Show)`
  - `data Command = Generate GenerateOpts | Compile CompileOpts | Check CheckOpts | Lsp`
  - `checkOpts :: Parser CheckOpts` (exported, mirroring `compileOpts`)

- [ ] **Step 1: Write the failing tests**

Add this `describe` block to `kernel/test/Spec.hs`, right after the existing
`"generate argument parsing (Lips.Cli)"` block (after its last `it`, before
the `-- Tab completion must offer...` comment, currently around line 103):

```haskell
  describe "compile argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info compileOpts idm)
    it "defaults --out and --lang-dir to Nothing" $
      parseArgs ["a.backup.lips"]
        `shouldBe` Just (CompileOpts Nothing "a.backup.lips" Nothing)
    it "reads --lang-dir in any position, alongside --out" $ do
      parseArgs ["--lang-dir", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CompileOpts Nothing "a.backup.lips" (Just "services/a/backup"))
      parseArgs ["--out", "dir", "--lang-dir", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CompileOpts (Just "dir") "a.backup.lips" (Just "services/a/backup"))
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing

  describe "check argument parsing (Lips.Cli)" $ do
    let parseArgs = getParseResult . execParserPure defaultPrefs (info checkOpts idm)
    it "defaults --lang-dir to Nothing" $
      parseArgs ["a.backup.lips"] `shouldBe` Just (CheckOpts "a.backup.lips" Nothing)
    it "reads --lang-dir in any position" $ do
      parseArgs ["--lang-dir", "services/a/backup", "a.backup.lips"]
        `shouldBe` Just (CheckOpts "a.backup.lips" (Just "services/a/backup"))
      parseArgs ["a.backup.lips", "--lang-dir", "services/a/backup"]
        `shouldBe` Just (CheckOpts "a.backup.lips" (Just "services/a/backup"))
    it "fails with no program at all" $
      parseArgs [] `shouldBe` Nothing
```

Update the existing import line (currently
`import Lips.Cli (GenerateOpts (..), generateOpts, programCompleter)`) to:

```haskell
import Lips.Cli (GenerateOpts (..), CompileOpts (..), CheckOpts (..), generateOpts, compileOpts, checkOpts, programCompleter)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec' 2>&1 | tail -40
```

Expected: a compile error — `CompileOpts`'s 3-argument constructor doesn't
exist yet, `CheckOpts`/`checkOpts` aren't exported.

- [ ] **Step 3: Implement in `Lips.Cli`**

Change the module export list: replace

```haskell
  ( Command (..)
  , GenerateOpts (..)
  , CompileOpts (..)
  , cliParserInfo
  , generateOpts
  , compileOpts
  , programCompleter
  )
```

with

```haskell
  ( Command (..)
  , GenerateOpts (..)
  , CompileOpts (..)
  , CheckOpts (..)
  , cliParserInfo
  , generateOpts
  , compileOpts
  , checkOpts
  , programCompleter
  )
```

Replace the `CompileOpts` data declaration and the `Command` data
declaration:

```haskell
-- | Everything @compile@ needs. Exactly one program -- unlike @generate@'s
-- @some@, no forced symmetry: compile realizes into a single output
-- directory, it does not read a corpus. @coLangDir@ overrides where the
-- committed language files are read from (default: sibling of the program,
-- see 'Lips.Identity.resolveLangDir'); it never affects where compile WRITES
-- (that stays under the program's own directory).
data CompileOpts = CompileOpts
  { coOut     :: Maybe FilePath
  , coFile    :: FilePath
  , coLangDir :: Maybe FilePath
  } deriving (Eq, Show)

-- | Everything @check@ needs: the program, plus the same @--lang-dir@
-- override @compile@ takes (same meaning: read-only, does not move derived
-- output).
data CheckOpts = CheckOpts
  { ceFile    :: FilePath
  , ceLangDir :: Maybe FilePath
  } deriving (Eq, Show)
```

```haskell
-- | The four lips verbs, all visible/documented via 'hsubparser' (lsp was
-- previously reachable but absent from --help; now consistent with the rest).
data Command
  = Generate GenerateOpts
  | Compile CompileOpts
  | Check CheckOpts
  | Lsp
  deriving (Eq, Show)
```

Replace the `check` subcommand wiring:

```haskell
  <> command "check"
       (info (Check <$> checkOpts)
             (progDesc "Verify the program still produces what it promised."))
```

Add, near `compileOpts`, the shared flag and the new `checkOpts` parser
(place `langDirOpt` right before `compileOpts` and use it in both):

```haskell
-- | @--lang-dir@: read the committed language files (.lang/.expect/
-- .generation/artifacts) from this directory instead of the program's sibling
-- folder. Never affects where derived output (out/) is written -- that stays
-- under the program's own directory. No short alias: a deliberate, occasional
-- override, not a fast-typed everyday flag (the same judgment as --renew).
-- The folder must be named after the program's own declared language;
-- 'Lips.Identity.resolveLangDir' enforces that and fails loud on mismatch.
langDirOpt :: Parser (Maybe FilePath)
langDirOpt = optional (strOption
  (long "lang-dir" <> metavar "DIR"
    <> help "Read the language's committed files from DIR instead of the program's sibling folder (must be named after the program's language)."))

compileOpts :: Parser CompileOpts
compileOpts = CompileOpts
  <$> optional (strOption
        (long "out" <> short 'o' <> metavar "DIR"
          <> help "Output directory (default: <language>/out/<instance>)."))
  <*> programArg
  <*> langDirOpt

checkOpts :: Parser CheckOpts
checkOpts = CheckOpts
  <$> programArg
  <*> langDirOpt
```

Delete the old bare `compileOpts` definition (the one without `coLangDir`) —
it is being replaced by the version above.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec' 2>&1 | tail -40
```

Expected: PASS. This will also surface a compile error in `kernel/app/Main.hs`
(`Check f -> checkLoose f` no longer matches `Check CheckOpts`, and
`compileOpts`'s old positional-arg call sites break) — that's expected and is
Task 3's job; if `ghc` compiling `Spec.hs` fails only because of `Main.hs`,
note it and continue (Task 3 fixes `Main.hs`). If it fails for any other
reason, stop and fix it here first.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/test/Spec.hs
git commit -m "cli: add --lang-dir to compile and check, CheckOpts record"
```

---

### Task 3: Wire `--lang-dir` through `Main.hs`

**Files:**
- Modify: `kernel/app/Main.hs`
- Test: manual integration check (Step 4 below) — no `Spec.hs` changes;
  `Main.hs` isn't linked into `Spec.hs`, so this task is verified by the full
  `nix develop` build of the `lips` binary plus one end-to-end run.

**Interfaces:**
- Consumes:
  - `resolveLangDir`, `langPathIn`, `expectPathIn`, `generationPathIn`,
    `artifactsPathIn` from Task 1.
  - `Command (..)`, `CompileOpts (..)`, `CheckOpts (..)` from Task 2.
- Produces: nothing further downstream (this is the last task).

- [ ] **Step 1: Update the `main` dispatch and imports**

In `kernel/app/Main.hs`, update the import lines:

```haskell
import           Lips.Identity                 (artifactsPath, artifactsPathIn, compiledPath, decisionsPath, directionPath, expectPath, expectPathIn, generationPath, generationPathIn, instanceName, langDir, langPath, langPathIn, languageName, outDir, resolveLangDir)
import           Lips.Cli               (Command (..), GenerateOpts (..), CompileOpts (..), CheckOpts (..), cliParserInfo)
```

Update the `main` dispatch:

```haskell
main :: IO ()
main = do
  cmd <- execParser (cliParserInfo defaultConfidence)
  case cmd of
    Generate go -> generate (goTarget go) (goConfidence go) (goRenew go) (goVerbose go) (goModel go) (goFiles go)
    Compile co  -> compileLoose (coOut co) (coLangDir co) (coFile co)
    Check co    -> checkLoose (ceLangDir co) (ceFile co)
    Lsp         -> runLsp
```

- [ ] **Step 2: Thread the resolved directory through `compileLoose`/`checkLoose` and their helpers**

Replace `compileLoose`'s signature and body:

```haskell
compileLoose :: Maybe FilePath -> Maybe FilePath -> FilePath -> IO ()
compileLoose mout mLangDir file = do
  dir <- either die pure (resolveLangDir file mLangDir)
  checkLoose mLangDir file
  program <- readProgramOrDie file
  eng     <- loadLangOrDie dir file
  target  <- readRecordedTarget dir file
  case validate file eng program of
    Left f                 -> die (printFail file f)
    Right (_, nixMod, art) -> do
      let outDirPath = maybe (compiledPath file) id mout
      ensureDerived file
      callCommand ("mkdir -p " <> shq outDirPath)
      TIO.writeFile (outDirPath </> "default.nix") nixMod
      stageFromDisk dir (outDirPath </> "artifacts")
      artNames <- case art of
        Nothing            -> pure []
        Just (body, names) -> TIO.writeFile (outDirPath </> "artifact.nix") body >> pure names
      TIO.writeFile (outDirPath </> "flake.nix") (flakeText target (not (null artNames)))
      TIO.hPutStrLn stderr ("compiled " <> T.pack file <> " -> " <> T.pack outDirPath)
      TIO.hPutStrLn stderr "run it with nix over the compiled dir:"
      mapM_ (TIO.hPutStrLn stderr) (runCommands target artNames outDirPath)
```

(The local `dir` binding shadowed the earlier variable name; it's renamed to
`outDirPath` throughout this function's body to avoid clashing with the new
`dir` = resolved language directory. Every other line of the function keeps
its existing content — only these two names change.)

Replace `readRecordedTarget`:

```haskell
readRecordedTarget :: FilePath -> FilePath -> IO Target
readRecordedTarget dir file = do
  m <- tryRead (generationPathIn dir file)
  pure $ case m of
    Nothing  -> defaultTarget
    Just src -> case [ t | l <- T.lines src
                         , Just rest <- [T.stripPrefix "target:" l]
                         , Just t <- [parseTarget (T.unpack (T.strip rest))] ] of
      (t : _) -> t
      []      -> defaultTarget
```

Replace `checkLoose`:

```haskell
checkLoose :: Maybe FilePath -> FilePath -> IO ()
checkLoose mLangDir file = do
  dir     <- either die pure (resolveLangDir file mLangDir)
  program <- readProgramOrDie file
  eng     <- loadLangOrDie dir file
  -- First phase, pure and offline: how the program sits in its language.
  -- Always shown, so authoring is never blind; the behavioral gate runs only
  -- once the program crystallizes cleanly and completely.
  let d = diagnose file eng program
  TIO.putStrLn (renderDiagnosis file d)
  hFlush stdout  -- so the report lands before any stderr failure below
  if any escapes (diagLines d)
    then die (report
           (T.pack file <> " has lines its language cannot read yet.")
           []
           ("→ grow the language: lips generate " <> T.pack file))
    else if not (null (diagOpen d))
      then die (report
             (T.pack file <> " is incomplete while these questions stay open.")
             []
             "→ answer them by stating the detail in the program.")
      else expectGate dir file eng program
  where
    escapes Matched{} = False
    escapes _         = True
```

Replace `expectGate`:

```haskell
expectGate :: FilePath -> FilePath -> EngineData -> Text -> IO ()
expectGate dir file eng program = do
  expSrc <- tryRead (expectPathIn dir file)
  case expSrc of
    Nothing  -> TIO.putStrLn
      (T.pack file <> ": crystallizes cleanly; no behavioral contract yet ("
        <> T.pack (expectPathIn dir file) <> " is missing, written by generate).")
    Just src -> case readExpect src of
      Left es       -> die (unreadable file ".expect" es)
      Right expects
        | bad@(_ : _) <- uncheckableExpects (edRules eng) expects ->
            die (uncheckableReport file bad)
        | otherwise -> case validate file eng program of
        Left f       -> die (printFail file f)
        Right (base, nixMod, _) -> do
          -- Bind <self> in the contract's option paths to this instance, so it
          -- checks against the realized (already-bound) module.
          res <- runExpects (stageFromDisk dir) (map (bindSelfExpect (instanceName file)) expects) base nixMod
          case res of
            Right () -> TIO.putStrLn (T.pack file <> ": all "
                          <> tshow (length expects) <> " checks pass.")
            Left (ToolMissing e) -> die (nixMissing file "check the program" "check" e)
            Left (EvalFailed e)  -> die (nixEvalFailed file "check" e)
            Left (Violations fs) -> die (report
              (T.pack file <> " no longer produces what it promised:")
              fs
              ("→ if you changed the program on purpose, rebuild: lips generate " <> T.pack file))
```

Replace `loadLangOrDie`:

```haskell
loadLangOrDie :: FilePath -> FilePath -> IO EngineData
loadLangOrDie dir file = do
  let langFile = langPathIn dir file
  msrc <- tryRead langFile
  case msrc of
    Nothing  -> die (report
      (T.pack file <> " isn't set up yet (" <> T.pack langFile <> " is missing).")
      []
      ("→ create it: lips generate " <> T.pack file))
    Just src -> case readLang src of
      Left es  -> die (unreadable file ".lang" es)
      Right eng -> pure eng
```

Replace `stageFromDisk`:

```haskell
-- | Stage a language's committed @artifacts@ tree (found under @dir@) into
-- @dst@ (the temp module's @artifacts/@). A no-op when the program has no
-- artifacts.
stageFromDisk :: FilePath -> FilePath -> IO ()
stageFromDisk dir dst = do
  _ <- (try (readProcessWithExitCode "cp" ["-rT", artifactsPathIn dir "", dst] "")
          :: IO (Either IOException (ExitCode, String, String)))
  pure ()
```

Wait — `artifactsPathIn` takes `(dir, file)` but ignores `file` entirely
(per Task 1's implementation, `artifactsPathIn dir _file = dir </> "artifacts"`).
Pass the actual `file` for clarity even though it's unused, so the call site
reads consistently with the other `*In` functions:

```haskell
stageFromDisk :: FilePath -> FilePath -> FilePath -> IO ()
stageFromDisk dir file dst = do
  _ <- (try (readProcessWithExitCode "cp" ["-rT", artifactsPathIn dir file, dst] "")
          :: IO (Either IOException (ExitCode, String, String)))
  pure ()
```

(This changes `stageFromDisk`'s arity from 2 to 3 arguments; update every
call site accordingly — see below.)

Update `stageFromDisk`'s call sites:
- In `compileLoose`: `stageFromDisk dir file (outDirPath </> "artifacts")`
- In `expectGate`: `runExpects (stageFromDisk dir file) ...`

`generate`'s own call site of `writeSources`/artifact staging is unaffected
(it never reads via `stageFromDisk` — it calls `writeSources` directly with
`artifactsPath rep`, which is untouched by this plan).

- [ ] **Step 3: Run the full test suite**

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec' 2>&1 | tail -40
```

Expected: PASS, no `-Wall` warnings, all examples green (`Spec.hs` doesn't
link `Main.hs`, so this only confirms Tasks 1-2 still hold; Step 4 below
exercises the `Main.hs` changes).

Also compile `Main.hs` itself to catch type errors this task introduces:

```bash
cd kernel && nix develop -c bash -c 'ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-main-build -o /tmp/lips-main' 2>&1 | tail -60
```

Expected: compiles cleanly, no errors, no new `-Wall` warnings.

- [ ] **Step 4: End-to-end manual check**

Using the repo's existing `examples/ledger.backup.lips` +
`examples/backup/` (already minted, committed in this repo), verify
`--lang-dir` against a *copy* moved to simulate a separate directory:

```bash
cd /home/cornerman/projects/lips/.worktrees/lang-dir-flag
mkdir -p /tmp/lang-dir-check/services/b
cp examples/ledger.backup.lips /tmp/lang-dir-check/services/b/photos.backup.lips
# sanity: /tmp/lang-dir-check/services/b has ONLY the program, no backup/ sibling

# 1. Without --lang-dir it must fail loud (no local backup/ folder):
/tmp/lips-main check /tmp/lang-dir-check/services/b/photos.backup.lips ; echo "exit: $?"
# Expected: exit nonzero, message says photos.backup.lips isn't set up yet
# (services/b/backup/backup.lang is missing).

# 2. With --lang-dir pointing at THIS repo's real backup/ folder, it must
# find the committed files and run check to completion:
/tmp/lips-main check --lang-dir examples/backup /tmp/lang-dir-check/services/b/photos.backup.lips
echo "exit: $?"
# Expected: exit 0, "... all N checks pass." (or the "no behavioral contract
# yet" line if examples/backup has no .expect -- either way it must NOT say
# "isn't set up yet", proving it read examples/backup/backup.lang).

# 3. Derived output lands LOCALLY, not under examples/backup/out/:
ls /tmp/lang-dir-check/services/b/backup/out/ 2>&1
# Expected: NOT "No such file or directory" is fine too (check alone may not
# write it); the key assertion is:
ls examples/backup/out/ | grep -c photos
# Expected: 0 -- check must not have written anything under the LENDING
# directory's out/.

# 4. Mismatched language name fails loud, naming both sides:
mkdir -p /tmp/lang-dir-check/other-lang
/tmp/lips-main check --lang-dir /tmp/lang-dir-check/other-lang /tmp/lang-dir-check/services/b/photos.backup.lips
echo "exit: $?"
# Expected: exit nonzero, message contains both ".backup" and ".other-lang"
# (or whatever basename /tmp/lang-dir-check/other-lang has).

rm -rf /tmp/lang-dir-check
```

Confirm each numbered expectation against the actual output before moving
on; if step 2 or 3 doesn't match, the bug is almost certainly in
`compileLoose`/`checkLoose`'s handling of `dir` vs the program's own
directory — re-check Step 2's edits above.

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "cli: wire --lang-dir through compile and check"
```

---

## Self-Review Notes (for the plan author, already applied above)

- **Spec coverage:** CLI surface (Task 2), semantics/committed-vs-derived
  split (Task 3 Step 4.3), validation/fail-loud naming both sides (Task 1
  tests + Task 3 Step 4.4), code shape (`*In` functions, `resolveLangDir`,
  `CheckOpts`, threading through `Main.hs` — Tasks 1-3), tests (pure
  resolver tests, CLI parse tests, one integration check) are all covered.
  The spec's own "Tests" section asked for an integration-level case in the
  conformance suite; this plan instead uses a manual end-to-end check
  (Task 3 Step 4) because `Main.hs` isn't linked into `Spec.hs` today (only
  `Lips.Cli`/`Lips.Identity` are pure-library modules the suite imports) —
  adding `Main.hs` to the test build is out of scope for this plan (a larger,
  unrelated restructuring); the manual check exercises the same behavior.
- **No placeholders:** every step shows literal code, not a description of it.
- **Type consistency:** `CompileOpts`'s field order (`coOut`, `coFile`,
  `coLangDir`) matches across Task 2's parser and its tests, and
  `CompileOpts (Just "dir") "a.backup.lips" (Just "services/a/backup")`-style
  positional construction in the tests matches that field order.
  `stageFromDisk`'s arity change (2 → 3 args) is called out explicitly with
  both call sites updated in the same task.

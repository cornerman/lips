# Draft Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mint a second tool so a model can run lips' own deterministic gates over its draft engine and correct itself before answering, so a small model succeeds where today only a large one does.

**Architecture:** A new `--draft -` flag on `lips check` reads a draft engine from stdin in the model's reply format, materializes it into a throwaway language folder together with the governing `.expect`, and runs the gates. Five pure engine gates move from `generate` into `check` so one verifier serves three callers. A second tool in `assets/mint-tools.ts` shells out to it, exactly as `query_options` shells out to `lips options`.

**Tech Stack:** Haskell (GHC, hspec, optparse-applicative), TypeScript (the pi extension), Nix.

**Spec:** `docs/superpowers/specs/2026-08-01-draft-validation-design.md`

## Global Constraints

- Base branch: `main` at `598589c` or later. Work in a worktree under `.worktrees/`.
- The kernel is domain-blind. No program-specific, language-specific or option-specific knowledge enters `kernel/src/` or `kernel/app/`. See `AGENTS.md`, "The Kernel Knows Nothing".
- The suite and app must stay `-Wall` clean. No warnings.
- Fast test loop, run from `kernel/`: `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
- Full check before merge: `just ci` (needs KVM, present on this machine).
- `compile` and `check` must stay nixpkgs-free by default (TODO 5a). Only `generate` and `options` may build an option schema.
- Invariant 1: `compile`/`check` never call a model. This work adds no model call to either.
- Invariant 2: deduce-or-fail. A failure names the remedy; nothing guesses.
- Commits: small, single-line messages, no attribution, no merge commits.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Existing spellings to reuse verbatim: the flag is `--lang DIR` (field `ceLangDir`), not `--lang-dir`. Paths come from `Lips.Identity`: `langPathIn`, `expectPathIn`, `artifactsPathIn`.

---

### Task 1: The `--draft` flag exists and rejects conflicting use

**Files:**
- Modify: `kernel/src/Lips/Cli.hs` (the `CheckOpts` record near line 73, and `checkOpts` near line 243)
- Test: `kernel/test/Spec.hs` (the existing `describe "check argument parsing (Lips.Cli)"` block at line 170)

**Interfaces:**
- Produces: `CheckOpts` gains a field `ceDraft :: Bool`, set by `--draft`. Later tasks read it. Field order in the record is `ceLangDir`, `ceDraft`, `ceFile`, and `checkOpts`'s applicative chain must match that order.

Background for a reader new to this codebase: `Lips.Cli` holds only pure argument parsing, and `kernel/test/Spec.hs` tests it by running the parser over an argument list and asserting on the resulting record. Look at the block at line 170 for the exact helper style used, and copy it rather than inventing one.

The draft always arrives on stdin, so `--draft` is a switch, not an option taking a path. It is written `--draft -` at the call site for readability; the `-` is a conventional stdin marker only, and the parser does not consume it. Do not add a positional for it.

- [ ] **Step 1: Write the failing tests**

Add to the `describe "check argument parsing (Lips.Cli)"` block in `kernel/test/Spec.hs`. Match the surrounding helper style; if that block calls a local helper such as `parseCheck`, use it, and if it inlines `execParserPure`, inline it the same way.

```haskell
    it "defaults to reading the committed engine, not a draft" $
      fmap ceDraft (parseCheck ["prog.backup.lips"]) `shouldBe` Just False

    it "reads a draft engine from stdin when --draft is given" $
      fmap ceDraft (parseCheck ["--draft", "prog.backup.lips"]) `shouldBe` Just True

    it "refuses --draft together with --lang, which name two different engines" $
      parseCheck ["--draft", "--lang", "backup", "prog.backup.lips"] `shouldBe` Nothing
```

- [ ] **Step 2: Run the tests to verify they fail**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: compilation fails with `ceDraft` not in scope. That counts as the failing state.

- [ ] **Step 3: Add the field and the flag**

In `kernel/src/Lips/Cli.hs`, extend the record:

```haskell
data CheckOpts = CheckOpts
  { ceLangDir :: Maybe FilePath
  -- | Read the engine to check from stdin, in the mint's reply format, instead
  -- of loading the committed one. The mint's own validation door: a model
  -- checks a draft before answering, and the authoritative gate still runs
  -- afterwards in generate.
  , ceDraft   :: Bool
  , ceFile    :: FilePath
  } deriving (Eq, Show)
```

and the parser:

```haskell
checkOpts :: Parser CheckOpts
checkOpts = CheckOpts
  <$> langDirOpt
  <*> switch
        (long "draft"
          <> help "Check a draft engine read from stdin (the mint's reply format) instead of the committed one.")
  <*> programArg
```

- [ ] **Step 4: Make the conflict fail loud**

`optparse-applicative` cannot express this exclusion declaratively here, so enforce it in the parser body. Add, in `Lips.Cli`, right after `checkOpts`'s definition, a validating wrapper and use it where `checkOpts` is consumed by the command table:

```haskell
-- | --lang points at an engine that exists on disk; --draft builds a
-- temporary one from stdin. Together they name two different engines, so the
-- invocation is ambiguous and lips refuses it rather than silently preferring
-- one (invariant 2: deduce-or-fail).
checkOptsChecked :: Parser CheckOpts
checkOptsChecked = checkOpts >>= \co ->
  if ceDraft co && isJust (ceLangDir co)
    then fail "--draft and --lang name two different engines: --lang reads one from a folder, --draft reads one from stdin. Pass only one."
    else pure co
```

Replace the `checkOpts` reference in the `command "check"` entry with `checkOptsChecked`. Add `Data.Maybe (isJust)` to the imports if it is not already there.

- [ ] **Step 5: Run the tests to verify they pass**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: PASS, 538 examples, 0 failures, and no warnings.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/test/Spec.hs
git commit -m "check: a --draft flag, refused beside --lang"
```

---

### Task 2: Move the five pure engine gates into a reusable, pure function

**Files:**
- Create: `kernel/src/Lips/Kernel/Engine/Gate.hs`
- Modify: `kernel/app/Main.hs:528-532` (the five `assert*` calls) and their definitions at `750`, `765`, `783`, `808`, `827`
- Modify: `kernel/lips.cabal` (add the new module to `exposed-modules`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `Lips.Kernel.Engine.Gate.engineViolations :: EngineData -> [Text]`, returning one message per violation, empty when the engine is sound. Task 3 and Task 4 both call it.

Why this task exists: the five gates are currently `IO` actions that call `die`, so nothing else can reuse them. A function that RETURNS violations can be called by `generate` (which dies), by `check` (which dies), and by tests (which assert). This is the "functional core, imperative shell" split from `AGENTS.md`: the decision is pure, the exit is not.

The five gates are `assertPatternsOrthogonal`, `assertRulesOrthogonal`, `assertValuesReach`, `assertNoPathHoles`, `assertDemandsAnswerable`. They need no nixpkgs, which is why they may enter `check`. `assertOptionsAdmissible` is NOT one of them: it needs the option schema and must stay in `generate` (see Task 4).

Preserve each gate's existing message text exactly. It is the human-facing refusal wording and it is also what the model will read; changing it here would be an unrelated behavior change.

- [ ] **Step 1: Write the failing test**

Add a new top-level `describe` to `kernel/test/Spec.hs`. Build the engines with the same helpers the surrounding tests use for `EngineData`; read the existing `describe "generate minting ..."` block at line 972 to see how a `.lang` source is parsed into an engine in this suite, and reuse that path rather than constructing records by hand.

```haskell
  describe "engine gates are pure and reusable (Lips.Kernel.Engine.Gate)" $ do
    it "passes a sound engine" $ do
      let eng = engineFromLang
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.interval \"<secs>\""
            , "0.95 r1 match fact watch.interval => systemd.services.w.environment.S \"<value:int>\""
            ]
      engineViolations eng `shouldBe` []

    it "names two patterns that both match one line" $ do
      let eng = engineFromLang
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.a \"<secs>\""
            , "0.95 p2 pattern watch <n> seconds => fact watch.b \"<n>\""
            , "0.95 r1 match fact watch.a => systemd.services.w.environment.A \"<value:int>\""
            , "0.95 r2 match fact watch.b => systemd.services.w.environment.B \"<value:int>\""
            ]
      engineViolations eng `shouldNotBe` []
```

If no `engineFromLang` helper exists in the suite, write one beside the new `describe`:

```haskell
engineFromLang :: [Text] -> EngineData
engineFromLang ls = case readLang (T.unlines ls) of
  Left es -> error ("test engine does not parse: " <> show es)
  Right e -> e
```

- [ ] **Step 2: Run the test to verify it fails**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: compilation fails, `Lips.Kernel.Engine.Gate` not found.

- [ ] **Step 3: Create the pure module**

Create `kernel/src/Lips/Kernel/Engine/Gate.hs`. Move the DECISION logic out of each of the five `assert*` functions in `Main.hs` (definitions at lines 750, 765, 783, 808, 827) into pure helpers here, keeping their message text verbatim.

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | The engine-level gates that need no schema and no nix: an engine is
-- judged against itself. Pure, so one implementation serves generate (which
-- refuses a mint), check (which refuses a committed or draft engine) and the
-- conformance suite (which asserts). The schema-dependent gate is NOT here;
-- it lives in generate, which is the only verb that builds a schema.
module Lips.Kernel.Engine.Gate (engineViolations) where

import Data.Text (Text)
import Lips.Kernel.Engine.Data (EngineData (..))

-- | Every way an engine can be unsound on its own terms, in the order the
-- gates have always run. Empty means sound. Each message is the same text the
-- human refusal has always shown, so a model reading it and a human reading it
-- see one wording.
engineViolations :: EngineData -> [Text]
engineViolations eng = concat
  [ patternsOrthogonal eng
  , rulesOrthogonal eng
  , valuesReach eng
  , noPathHoles eng
  , demandsAnswerable eng
  ]
```

Implement the five helpers by lifting the bodies of the existing `assert*` functions: each currently computes a list of offenders and then calls `die` on a rendered report. Keep the computation and the rendering, return the rendered lines, and drop only the `die`.

- [ ] **Step 4: Rewire `generate` to the shared function**

In `Main.hs`, replace the five calls at lines 528-532 with one, keeping the existing failure shape so the refusal a human sees does not change:

```haskell
      case engineViolations eng of
        []   -> pure ()
        vs   -> die (validationReport rep (T.unlines vs))
```

Delete the five now-unused `assert*` definitions and any imports they alone required. Add `Lips.Kernel.Engine.Gate` to `exposed-modules` in `kernel/lips.cabal`.

- [ ] **Step 5: Run the tests to verify they pass**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: PASS with no warnings. Every pre-existing test must still pass; these gates are exercised indirectly across the suite, so a regression shows up here.

- [ ] **Step 6: Verify every committed engine still passes the gates**

This is the risk the spec flags: `TODO` item 6 records `assertDemandsAnswerable` refusing engines that are CORRECT (the `<k:key>` subject bug). Confirm the committed engines are unaffected before going further.

```bash
cd /home/cornerman/projects/lips
nix run . -- check examples/ledger.backup.lips
for p in examples/*.lips; do echo "== $p"; nix run . -- check "$p" || echo "FAILED: $p"; done
```
Expected: no `FAILED:` line. If one appears, STOP and report which engine and which gate. Do not weaken the gate to make it pass; either fix the gate or hold that single gate back from the shared function, and say so.

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Gate.hs kernel/app/Main.hs kernel/lips.cabal kernel/test/Spec.hs
git commit -m "gate: the schema-free engine gates as one pure function"
```

---

### Task 3: `check` runs the engine gates

**Files:**
- Modify: `kernel/app/Main.hs` (`checkLoose`, definition begins near line 211)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `engineViolations` from Task 2.
- Produces: no new names. `checkLoose`'s signature is unchanged.

Why: today a committed `.lang` is never re-verified for orthogonality, so drift from a bad merge or a change in matching semantics goes unnoticed. This closes that, and it is what makes `check` the single verifier the draft path can reuse.

Place the call immediately after the engine is loaded (`loadLangOrDie`) and BEFORE `diagnose`. An engine that is unsound on its own terms makes every later diagnosis untrustworthy, so it must fail first.

- [ ] **Step 1: Write the failing test**

`checkLoose` is `IO` and calls `die`, so test it end-to-end through the binary rather than in hspec. Create a shell-level conformance case; follow whatever existing pattern the repo uses for CLI-level tests (check `justfile` and `nix/` for the existing example-driven checks). If none fits, add this as a `just` recipe named `test-draft` in `justfile`:

```make
# A committed engine that is unsound on its own terms must be refused by check.
test-draft:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/broken"
    cat > "$tmp/one.broken.lips" <<'EOF'
    watch 30 seconds
    EOF
    cat > "$tmp/broken/broken.lang" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.a "<secs>" @gen:0000000000000000
    0.95 p2 pattern watch <n> seconds => fact watch.b "<n>" @gen:0000000000000000
    0.95 r1 match fact watch.a => systemd.services.w.environment.A "<value:int>" @gen:0000000000000000
    0.95 r2 match fact watch.b => systemd.services.w.environment.B "<value:int>" @gen:0000000000000000
    EOF
    if nix run . -- check "$tmp/one.broken.lips" 2>&1 | tee "$tmp/out"; then
      echo "FAIL: check accepted an engine whose patterns are not orthogonal"; exit 1
    fi
    grep -q "orthogonal\|two patterns\|both match" "$tmp/out" || { echo "FAIL: refusal did not name the overlap"; cat "$tmp/out"; exit 1; }
    echo "OK"
```

- [ ] **Step 2: Run it to verify it fails**

```bash
git add -A && just test-draft
```
Expected: `FAIL: check accepted an engine whose patterns are not orthogonal`.

- [ ] **Step 3: Add the gate to `checkLoose`**

In `Main.hs`, inside `checkLoose`, immediately after `eng <- loadLangOrDie dir file`:

```haskell
  -- An engine unsound on its own terms makes every later verdict meaningless,
  -- so it fails before the diagnosis. Same gate generate runs before accepting
  -- a mint, so a committed engine cannot drift below what minting required.
  case engineViolations eng of
    []  -> pure ()
    vs  -> die (validationReport file (T.unlines vs))
```

Add the import of `Lips.Kernel.Engine.Gate (engineViolations)`.

- [ ] **Step 4: Run it to verify it passes**

```bash
git add -A && just test-draft
```
Expected: `OK`.

Then confirm nothing regressed:
```bash
cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
cd .. && for p in examples/*.lips; do nix run . -- check "$p" >/dev/null || echo "FAILED: $p"; done
```
Expected: suite passes, no `FAILED:` line.

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs justfile
git commit -m "check: verify the engine is sound on its own terms"
```

---

### Task 4: `check --draft` materializes a draft and checks it

**Files:**
- Create: `kernel/src/Lips/Generate/Draft.hs`
- Modify: `kernel/app/Main.hs` (the `Check` dispatch at line 116, and a new entry point beside `checkLoose`)
- Modify: `kernel/lips.cabal`
- Test: `kernel/test/Spec.hs` and the `just test-draft` recipe from Task 3

**Interfaces:**
- Consumes: `parseEngineCandidates`, `assemble`, `expectsOf`, `sourcesOf` from `Lips.Generate.Minting`; `renderLang` from `Lips.Kernel.Lang.Store`; `langPathIn`, `expectPathIn`, `artifactsPathIn` from `Lips.Identity`; `engineViolations` from Task 2.
- Produces: `Lips.Generate.Draft.materializeDraft :: FilePath -> FilePath -> Text -> Maybe Text -> Either [Text] DraftTree`, and `data DraftTree = DraftTree { dtLangDir :: FilePath, dtWrite :: IO () }`. Task 5's tool calls the CLI, not these names.

Four rules this task must honor, each with a reason:

1. The throwaway folder must be NAMED after the language. `Identity.resolveLangDir` refuses a folder whose basename is not the program's language, so materialize to `<tmp>/<language>/`, not `<tmp>/`.
2. The `.expect` written into that folder is the GOVERNING contract, not the draft's own. On a regeneration the committed `.expect` governs (invariant 5); grading a model against expects it just wrote itself always passes and then the real gate refuses. The caller supplies it as the `Maybe Text` argument; `Nothing` means "use the draft's own minted expects", which is correct only on a first generation or under `--renew`.
3. The claim gate and the artifact build are SKIPPED, and the output says so. Running them costs minutes and, without KVM, hard-fails every call.
4. Report the FIRST failing gate with all of its violations, in the same text a human refusal shows.

- [ ] **Step 1: Write the failing test**

Add to `kernel/test/Spec.hs`:

```haskell
  describe "draft materialization (Lips.Generate.Draft)" $ do
    it "writes the draft engine into a folder named after the language" $ do
      let reply = T.unlines
            [ "0.95 p1 pattern watch <secs> seconds => fact watch.interval \"<secs>\""
            , "0.95 r1 match fact watch.interval => systemd.services.w.environment.S \"<value:int>\""
            ]
      case materializeDraft "/tmp/x" "one.backup.lips" reply Nothing of
        Left es -> expectationFailure ("draft did not materialize: " <> show es)
        Right t -> dtLangDir t `shouldBe` "/tmp/x/backup"

    it "reports the parse errors of an unreadable draft rather than guessing" $
      case materializeDraft "/tmp/x" "one.backup.lips" "not an engine line" Nothing of
        Left es -> es `shouldNotBe` []
        Right _ -> expectationFailure "an unreadable draft must not materialize"
```

- [ ] **Step 2: Run to verify it fails**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: compilation fails, `Lips.Generate.Draft` not found.

- [ ] **Step 3: Write the materializer**

Create `kernel/src/Lips/Generate/Draft.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Turn a mint's REPLY into a language folder on disk, so the ordinary
-- verifier can judge a draft engine exactly as it judges a committed one.
--
-- The draft arrives in reply format, not .lang format, deliberately: asking a
-- model to write one format for checking and another for answering would let
-- the two diverge, and the thing it checks must be the thing it ships.
module Lips.Generate.Draft
  ( DraftTree (..)
  , materializeDraft
  ) where

import           Data.Text (Text)
import qualified Data.Text as T
import           System.Directory (createDirectoryIfMissing)
import           System.FilePath ((</>))

import           Lips.Generate.Minting (assemble, expectsOf, parseEngineCandidates,
                                        sourcesOf, icItem)
import           Lips.Identity        (artifactsPathIn, expectPathIn, langPathIn, languageName)
import           Lips.Kernel.Lang.Store (renderLang)

-- | A materialized draft: the folder to point check at, and the action that
-- writes it. Split so the pure decision (does this draft parse) is testable
-- without touching a filesystem.
data DraftTree = DraftTree
  { dtLangDir :: FilePath
  , dtWrite   :: IO ()
  }

-- | Build a language folder from a reply. @root@ is a temporary directory,
-- @file@ the program the draft is for, @reply@ the mint's raw answer, and
-- @governing@ the contract that decides this mint: the committed .expect on a
-- regeneration, or Nothing to use the draft's own minted expects (correct only
-- on a first generation or under --renew).
materializeDraft :: FilePath -> FilePath -> Text -> Maybe Text -> Either [Text] DraftTree
materializeDraft root file reply governing =
  case parseEngineCandidates reply of
    (errs@(_ : _), _) -> Left errs
    ([], cands) ->
      let items = map icItem cands
          dir   = root </> languageName file
       in Right DraftTree
            { dtLangDir = dir
            , dtWrite = do
                createDirectoryIfMissing True dir
                writeFileT (langPathIn dir file) (renderLangForDraft (assemble items))
                writeFileT (expectPathIn dir file)
                  (maybe (renderExpects (expectsOf items)) id governing)
                writeSourceTree (artifactsPathIn dir file) (sourcesOf items)
            }
```

Fill in `renderLangForDraft`, `renderExpects`, `writeFileT` and `writeSourceTree` using the calls `generate` already makes for the same three artifacts in `Main.hs` (search for `renderLang`, the `.expect` write, and `writeSources`). Reuse those code paths; do not invent a second renderer, or the draft and the committed engine could differ in form.

Add the module to `exposed-modules` in `kernel/lips.cabal`.

- [ ] **Step 4: Run to verify it passes**

Run, from `kernel/`:
```
ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: PASS, no warnings.

- [ ] **Step 5: Wire it into the `check` dispatch**

In `Main.hs`, change the `Check` case at line 116 to branch on `ceDraft`:

```haskell
    Check co
      | ceDraft co -> checkDraft (ceFile co)
      | otherwise  -> () <$ checkLoose True (ceLangDir co) (ceFile co)
```

Add `checkDraft` beside `checkLoose`:

```haskell
-- | @check --draft@: judge an engine the mint has not committed yet. The draft
-- arrives on stdin in reply format; lips materializes it into a throwaway
-- language folder and runs the ordinary verifier over it.
--
-- Two gates are deliberately NOT run, and the output says which: the claim
-- gate (a sandbox claim compiles the artifact, a machine claim boots a VM and
-- needs KVM, so a per-call cost of minutes and a hard failure without KVM) and
-- the artifact build. Observational verification stays where it already is, in
-- generate's final gate. "Not verified" is stated, never rendered as verified.
checkDraft :: FilePath -> IO ()
checkDraft file = do
  reply     <- TIO.getContents
  governing <- lookupEnv "LIPS_MINT_EXPECT" >>= \m -> case m of
    Just p | not (null p) -> tryRead p
    _                     -> pure Nothing
  withSystemTempDirectory "lips-draft" $ \root ->
    case materializeDraft root file reply governing of
      Left errs -> die (validationReport file (T.unlines errs))
      Right t   -> do
        dtWrite t
        _ <- checkLoose False (Just (dtLangDir t)) file
        TIO.putStrLn "checked: the claim gate and the artifact build were NOT run."
```

Note `checkLoose False`: the `contract` flag also guards `claimGate`, and passing `False` is what skips it. That also skips the expect gate, which Task 6 restores; leave it for now and let Task 6's test drive it.

Add imports: `System.IO.Temp (withSystemTempDirectory)`, `System.Environment (lookupEnv)`, and `Lips.Generate.Draft`. Add `temporary` to `build-depends` in `kernel/lips.cabal` if it is not already there.

- [ ] **Step 6: Extend the shell test**

Add to the `test-draft` recipe in `justfile`, after the existing case:

```bash
    # A draft with two overlapping patterns is refused, read from stdin.
    cat > "$tmp/draft.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.a "<secs>"
    0.95 p2 pattern watch <n> seconds => fact watch.b "<n>"
    0.95 r1 match fact watch.a => systemd.services.w.environment.A "<value:int>"
    0.95 r2 match fact watch.b => systemd.services.w.environment.B "<value:int>"
    EOF
    if nix run . -- check --draft "$tmp/one.broken.lips" < "$tmp/draft.txt" 2>&1 | tee "$tmp/out2"; then
      echo "FAIL: --draft accepted overlapping patterns"; exit 1
    fi
    grep -q "orthogonal\|two patterns\|both match" "$tmp/out2" || { echo "FAIL: --draft refusal did not name the overlap"; exit 1; }

    # A sound draft is accepted, and says what it did not check.
    cat > "$tmp/good.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    EOF
    nix run . -- check --draft "$tmp/one.broken.lips" < "$tmp/good.txt" > "$tmp/out3" 2>&1 \
      || { echo "FAIL: a sound draft was refused"; cat "$tmp/out3"; exit 1; }
    grep -q "NOT run" "$tmp/out3" || { echo "FAIL: the skipped gates were not reported"; exit 1; }
    echo "OK"
```

Rename the program in the recipe from `one.broken.lips` to `one.watch.lips` throughout, and the folder from `broken/` to `watch/`, so the language name matches what the draft describes.

- [ ] **Step 7: Run it**

```bash
git add -A && just test-draft
```
Expected: `OK`.

- [ ] **Step 8: Commit**

```bash
git add kernel/src/Lips/Generate/Draft.hs kernel/app/Main.hs kernel/lips.cabal kernel/test/Spec.hs justfile
git commit -m "check: --draft materializes a mint's reply and judges it"
```

---

### Task 5: `--draft` runs the schema gate and the expect gate

**Files:**
- Modify: `kernel/app/Main.hs` (`checkDraft` from Task 4)
- Test: the `test-draft` recipe

**Interfaces:**
- Consumes: `assertOptionsAdmissible` (already in `Main.hs`, line 850), `DraftTree` from Task 4.
- Produces: no new names.

Why this is a separate task: Task 4 passed `checkLoose False`, which skips the claim gate but ALSO skips the expect gate. The draft path wants the expect gate and not the claim gate, so the two must be separated. And the schema gate must run here, because `check` may not build a schema (TODO 5a) while the draft path sits on the mint side where one already exists.

- [ ] **Step 1: Write the failing test**

Add to the `test-draft` recipe:

```bash
    # A draft naming an option that does not exist is refused.
    cat > "$tmp/badopt.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => services.ngnix.enable "<value:int>"
    EOF
    if LIPS_MINT_SCHEMA="$LIPS_OPTIONS_JSON" nix run . -- check --draft "$tmp/one.watch.lips" < "$tmp/badopt.txt" 2>&1 | tee "$tmp/out4"; then
      echo "FAIL: --draft accepted an option that does not exist"; exit 1
    fi
    grep -q "ngnix" "$tmp/out4" || { echo "FAIL: the refusal did not name the bad option"; exit 1; }
```

The suite has an offline schema fixture reached through `LIPS_OPTIONS_JSON`; find it (grep the repo for `LIPS_OPTIONS_JSON`) and set it in the recipe so this case needs no nixpkgs.

- [ ] **Step 2: Run to verify it fails**

```bash
git add -A && just test-draft
```
Expected: `FAIL: --draft accepted an option that does not exist`.

- [ ] **Step 3: Separate the two gates**

Give `checkLoose` a second flag rather than overloading `contract`, so each gate is named at the call site:

```haskell
checkLoose :: Bool -> Bool -> Maybe FilePath -> FilePath -> IO Realization
```

where the first `Bool` is `contract` (the expect gate, as today) and the second is `claims` (the claim gate). Change its last line from `when contract (claimGate dir file rl)` to `when claims (claimGate dir file rl)`. Update the three existing call sites: the `Check` dispatch and `compile`'s gate pass `True True`, the `--no-contract` path passes `False False`, and `checkDraft` passes `True False`.

- [ ] **Step 4: Run the schema gate in `checkDraft`**

In `checkDraft`, after `dtWrite t` and before the `checkLoose` call:

```haskell
        -- The schema gate cannot live in check, which must stay nixpkgs-free
        -- (a committed engine is judged offline). The draft path runs on the
        -- mint side, where generate has already built a schema, so it runs the
        -- gate itself: without it a draft naming an option that does not exist
        -- would read as clean here and be refused by the final gate.
        mschema <- lookupEnv "LIPS_MINT_SCHEMA"
        case mschema of
          Just p | not (null p) -> do
            eng <- loadLangOrDie (dtLangDir t) file
            assertOptionsAdmissible target p file eng
          _ -> pure ()
```

The `target` must come from the environment, as the existing tool already does: read `LIPS_MINT_TARGET` and parse it with the same reader `Lips.Nix.Target` exposes. When it is absent, fail loud rather than defaulting, for the reason `assets/mint-tools.ts` already gives: a silent default would ground a mint against the wrong world's schema.

- [ ] **Step 5: Run to verify it passes**

```bash
git add -A && just test-draft
```
Expected: `OK`.

Then the full suite and every example:
```bash
cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
cd .. && for p in examples/*.lips; do nix run . -- check "$p" >/dev/null || echo "FAILED: $p"; done
```

- [ ] **Step 6: Commit**

```bash
git add kernel/app/Main.hs justfile
git commit -m "check: --draft grounds its options and keeps the claim gate out"
```

---

### Task 6: `generate` exposes the tool and passes what it needs

**Files:**
- Modify: `assets/mint-tools.ts`
- Modify: `kernel/app/Main.hs` (`callPi`, and `generate` around line 597 where the contract is chosen)
- Test: the `test-draft` recipe

**Interfaces:**
- Consumes: `check --draft` from Tasks 4 and 5.
- Produces: the env contract `LIPS_MINT_PROGRAMS` (newline-separated program paths), `LIPS_MINT_EXPECT` (path to the governing contract, empty when the draft's own expects govern), `LIPS_MINT_SCHEMA` (the resolved schema path).

The governing-contract rule must NOT be re-derived in the tool. `generate` already computes it at line 597:

```haskell
committed <- if renew then pure Nothing else tryRead (expectPath rep)
```

but that runs AFTER the model call. Hoist the decision (not the read) above `callPi`, so the path can be exported, and keep one rule in one place.

- [ ] **Step 1: Export the three variables**

In `Main.hs`, before `callPi`, compute:

```haskell
  -- The mint's validation tool judges a draft against the contract that will
  -- actually gate it: the committed .expect on a regeneration, the draft's own
  -- minted expects on a first generation or under --renew. generate owns that
  -- rule (see the read below), so the tool is told the answer rather than
  -- re-deriving it and drifting.
  committedExpectPath <- if renew
    then pure Nothing
    else do
      there <- doesFileExist (expectPath rep)
      pure (if there then Just (expectPath rep) else Nothing)
```

and extend `childEnv` in `callPi` with the three variables. `callPi` will need them as parameters; add them to its signature rather than reading globals, so what the mint sees stays explicit at the call site.

- [ ] **Step 2: Add the tool**

In `assets/mint-tools.ts`, register a second tool beside `query_options`:

```ts
  pi.registerTool({
    name: "check_draft",
    label: "Check draft",
    description:
      "Check a DRAFT engine before you answer with it. Pass the complete set of " +
      "lines you intend to answer with; lips runs its own gates over them and " +
      "reports the first one that rejects the draft, in the same words the " +
      "refusal would use. It does not run the claim gate or the artifact build, " +
      "and it says so. A clean answer does not guarantee acceptance; a dirty one " +
      "guarantees refusal, so fix what it names and check again.",
    parameters: Type.Object({
      draft: Type.String({
        description: "The complete draft engine, in the answer format.",
      }),
    }),
    async execute(_toolCallId: string, params: { draft: string }) {
      // One program at a time: check takes exactly one, and the engine-level
      // gates are program-independent, so the first failure is the answer.
      for (const program of programs) {
        const r = spawnSync(bin, ["check", "--draft", program], {
          input: params.draft,
          encoding: "utf8",
        });
        if (r.status !== 0) {
          return {
            content: [{ type: "text", text: [r.stdout, r.stderr].filter(Boolean).join("\n") || "no output" }],
            details: {},
            isError: true,
          };
        }
      }
      return {
        content: [{ type: "text", text: "the draft passes every gate lips can run before you answer." }],
        details: {},
        isError: false,
      };
    },
  });
```

with, beside the existing `required(...)` calls:

```ts
// Newline-separated, supplied by generate: the model may not choose which
// programs its draft is judged against, or it could validate against a corpus
// that is not the one being minted.
const programs = required("LIPS_MINT_PROGRAMS").split("\n").filter(Boolean);
```

- [ ] **Step 3: Rewrite the header comment**

The file's header states a decision this task reverses. Replace the paragraph beginning "There is deliberately no tool that JUDGES an engine" with:

```ts
// Two tools, and neither one decides. query_options informs about NAMES;
// check_draft REPORTS which gate rejects a draft. The gate that decides still
// runs once, in Haskell, after the model is done -- a model that skips both
// tools is refused by exactly the same gates as before. What moved is when the
// mint can learn it is wrong, not who judges it.
```

- [ ] **Step 4: Update the prose that says the mint has one tool**

Four places claim a single tool. Update each:
- `assets/mint/body.md:82` ("YOUR ONE TOOL") — describe both tools, and state that `check_draft` should be called before answering.
- `assets/mint/body.md:90` ("There is no tool that judges your engine, and none that runs anything") — correct it: a tool reports which gate rejects a draft, nothing runs the result, and the deciding gate is still lips'.
- `README.md:83` ("The mint has a single tool") — say two, and what the second does.
- `README.md:203` ("the one schema-lookup tool it loads for that run") — say both tools.
- The `callPi` comment in `Main.hs` ("The mint's one tool (@query_options@)").

Keep the `body.md` addition SHORT. The prompt is already 854 lines and its length is part of the problem this feature exists to solve.

- [ ] **Step 5: Verify the prompt still parses**

`Minting.hs` notes a guard requiring every ` ```lips-engine ` block in `body.md` to parse. Run the suite:

```bash
cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/mint-tools.ts assets/mint/body.md README.md kernel/app/Main.hs
git commit -m "mint: a second tool, so a draft can be checked before it is answered"
```

---

### Task 7: Verify against a real mint, then land

**Files:**
- Modify: `DESIGN.md` (section 13, the milestone ledger)
- Modify: `TODO.md` (note what this does and does not address)

This is the only task that tests the actual goal. Everything before it tests the mechanism.

- [ ] **Step 1: Full CI**

```bash
just ci
```
Expected: `all checks passed!`.

- [ ] **Step 2: Mint a language with a small model, with the tool available**

```bash
nix run . -- generate --model anthropic/claude-sonnet-5 --verbose examples/hello.http.lips
```
Record: did it succeed, how many `check_draft` calls appear in the transcript, and what each reported. `examples/hello.http.lips` is artifact-bearing, which is where sonnet regressed before.

- [ ] **Step 3: Compare against the same mint without the tool**

Re-run with the tool disabled (temporarily unset `LIPS_MINT_PROGRAMS`, which makes the extension fail loud at load — instead, stash the `registerTool` block, rebuild, and re-run). Record the same three facts.

Report both outcomes honestly, including a null result. The spec states that neither recorded sonnet regression is fixed by this work, so a mint that still regresses is consistent with the design, not a failure of the implementation.

- [ ] **Step 4: Restore the git state and update the ledger**

Add a `DESIGN.md` section 13 entry describing what landed: the second mint tool, `check --draft`, the five gates moved into `check`, and the claim gate deliberately excluded. State the measured outcome from Steps 2 and 3.

In `TODO.md`, note that draft validation does not address silent quality regression (item 2a(ii) still owns that), and that it makes recovery from a refusal possible in-turn.

- [ ] **Step 5: Commit and merge**

```bash
git add DESIGN.md TODO.md
git commit -m "design: record draft validation in the ledger"
cd /home/cornerman/projects/lips
git rebase main <branch> && git checkout main && git merge --ff-only <branch>
```

---

## Self-Review

**Spec coverage.** Interface as a flag on `check`: Task 1. Reply-format materialization: Task 4. Throwaway folder named after the language: Task 4. Governing contract: Tasks 4 and 6. Five pure gates moved: Tasks 2 and 3. Schema gate on the mint side: Task 5. Claim gate skipped and reported: Tasks 4 and 5. First-failing-gate reporting: Task 4. No enforcement: nothing enforces tool use in any task, as intended. Documentation corrections: Task 6. Committed-engine risk: Task 2 Step 6. Live verification: Task 7.

**Placeholders.** None. Each code step carries the code. Two steps deliberately say "reuse the existing path" (Task 4 Step 3's renderers, Task 3 Step 1's test pattern) and name what to search for, because inventing a second renderer or a second test harness is the failure mode there.

**Type consistency.** `engineViolations :: EngineData -> [Text]` is defined in Task 2 and used in Tasks 3 and 5. `DraftTree`/`materializeDraft` are defined in Task 4 and used in Tasks 4 and 5. `ceDraft` is defined in Task 1 and used in Task 4. `checkLoose` gains its second `Bool` in Task 5, and that task lists every call site to update.

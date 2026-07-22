# Realization Target (NixOS / home-manager) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an engine be minted for a chosen Nix world (NixOS or home-manager): `generate --target <world>` steers the mint and grounds against that world's option schema, the world is pinned into `.generation`, `run` picks a harness from it, and a flake helper exposes each instance under the matching module label.

**Architecture:** The world is per-problem knowledge, so it lives in the engine's emitted option paths and is decided at mint time; the kernel stays world-blind. `generate` gains a `Target` input that selects the mint prompt's namespace steering and the grounding schema (nixpkgs `optionsJSON` vs home-manager `docs-json`). The world is recorded in `.generation` (entering `genId`). `run` reads it to boot a VM (nixos) or run eval-only (home-manager). The `.expect` gate is already world-blind, so `check` is unchanged.

**Tech Stack:** Haskell (GHC, `-Wall`), hspec/QuickCheck conformance suite, Nix flakes.

## Global Constraints

- The kernel stays world-blind: no `if world == nixos` in `Lips/Kernel/`. The `Target` type and all world specifics live in the `Lips.Nix.*` and `Lips.Generate.*` tiers. (AGENTS.md "The Kernel Knows Nothing".)
- Invariant preserved: nixpkgs/home-manager never enter the closure of `print`/`run`/`check`. Only `generate` builds an option schema. (Ledger "Option-schema grounding".)
- Suite and app must stay `-Wall` clean. (`AGENTS.md`.)
- Fast test loop: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec` (run via `nix develop -c bash -c '...'`, or `just test`).
- Backward compatibility: an engine minted before this change (no `target:` line in `.generation`) must still `print`/`run`/`check` and must default to `nixos`. All existing examples (`backup`, `feed`, `http`) stay byte-identical for NixOS.
- Small single-line commits; no `co-authored` attribution.
- home-manager option schema fact (verified 2026-07-22): flake output `packages.<system>.docs-json`, file at `<out>/share/doc/home-manager/options.json`, same JSON shape as NixOS (`{ "option.path": { "type": "<desc>", ... } }`).

---

### Task 1: `Target` type in the Nix tier

**Files:**
- Create: `kernel/src/Lips/Nix/Target.hs`
- Test: `kernel/test/Spec.hs` (add a `describe` block; add import)

**Interfaces:**
- Produces:
  - `data Target = Nixos | HomeManager` (deriving `Eq`, `Show`, `Enum`, `Bounded`)
  - `defaultTarget :: Target` (= `Nixos`)
  - `parseTarget :: String -> Maybe Target` (`"nixos" -> Just Nixos`, `"home-manager" -> Just HomeManager`, else `Nothing`)
  - `targetSlug :: Target -> Text` (`Nixos -> "nixos"`, `HomeManager -> "home-manager"`)

- [ ] **Step 1: Write the failing test**

In `kernel/test/Spec.hs`, add `import Lips.Nix.Target` near the other `Lips.Nix` import, and add this block inside `main = hspec $ do` (e.g. after the `Lips.Nix.Options` usage / near the option-type describe):

```haskell
  describe "realization target (Lips.Nix.Target)" $ do
    it "parses the two world slugs and rejects others" $ do
      parseTarget "nixos" `shouldBe` Just Nixos
      parseTarget "home-manager" `shouldBe` Just HomeManager
      parseTarget "darwin" `shouldBe` Nothing
    it "slug round-trips through parse for every target" $
      mapM_ (\t -> parseTarget (T.unpack (targetSlug t)) `shouldBe` Just t)
            [minBound .. maxBound]
    it "defaults to nixos" $
      defaultTarget `shouldBe` Nixos
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec'`
Expected: FAIL — `Could not find module Lips.Nix.Target`.

- [ ] **Step 3: Write minimal implementation**

Create `kernel/src/Lips/Nix/Target.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | The realization target: which Nix world an engine's option paths belong
-- to. This is target-tier knowledge (Lips.Nix.*), never kernel knowledge --
-- the kernel emits @path = value@ and never names a world. An engine is born
-- into a world at mint time through the option paths its rules emit; this type
-- names that choice so @generate@ can steer the mint and ground against the
-- right schema, and so it can be recorded in the generation event.
module Lips.Nix.Target
  ( Target (..)
  , defaultTarget
  , parseTarget
  , targetSlug
  ) where

import Data.Text (Text)

-- | The two Nix worlds lips targets. A closed set: adding a world (darwin,
-- terranix) is a deliberate extension here plus a schema source, never an
-- open list the kernel enumerates.
data Target = Nixos | HomeManager
  deriving (Eq, Show, Enum, Bounded)

-- | Absent an explicit choice, lips targets NixOS (the original world).
defaultTarget :: Target
defaultTarget = Nixos

-- | Parse a CLI slug to a target; Nothing for anything else (fail loud).
parseTarget :: String -> Maybe Target
parseTarget "nixos"        = Just Nixos
parseTarget "home-manager" = Just HomeManager
parseTarget _              = Nothing

-- | The canonical slug, used on the CLI and in the .generation record.
targetSlug :: Target -> Text
targetSlug Nixos       = "nixos"
targetSlug HomeManager = "home-manager"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS, `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Nix/Target.hs kernel/test/Spec.hs
git commit -m "kernel: add Lips.Nix.Target (world as target-tier data)"
```

---

### Task 2: Record the target in the generation event

**Files:**
- Modify: `kernel/src/Lips/Generate/Record.hs` (the `record` function)
- Test: `kernel/test/Spec.hs` (the existing `genId` block, ~lines 862-870)
- Modify: `kernel/app/Main.hs` (the single `record` call site)

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target, targetSlug)`
- Produces: new signature
  `record :: Text -> Target -> Double -> Text -> Text -> Text -> Text`
  (arguments: `model target confidence sysPrompt program reply`). Emits a
  `target: <slug>` line right after `model:`, so it enters `genId`.

- [ ] **Step 1: Update the failing test**

In `kernel/test/Spec.hs`, add `import Lips.Nix.Target` if not already present from Task 1. Replace the `genId` describe body (the block using `record "m" 0.7 ...`) with:

```haskell
  describe "generation record identity (spec 5: pinned event)" $ do
    it "genId is stable, and changes with reply, confidence, and target" $ do
      let r   = record "m" Nixos 0.7 "sp" "prog" "reply"
          r'  = record "m" Nixos 0.7 "sp" "prog" "reply2"
          rc  = record "m" Nixos 0.5 "sp" "prog" "reply"
          rt  = record "m" HomeManager 0.7 "sp" "prog" "reply"
      genId r `shouldBe` genId r
      genId r `shouldNotBe` genId r'
      genId r `shouldNotBe` genId rc
      genId r `shouldNotBe` genId rt
      T.length (genId r) `shouldBe` 16
    it "writes the target slug into the record text" $
      record "m" HomeManager 0.7 "sp" "prog" "reply"
        `shouldSatisfy` T.isInfixOf "target: home-manager"
```

(Keep whatever the block's original name was if it differed; the assertions above are the required ones.)

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec'`
Expected: FAIL — `record` applied to too many arguments / type error.

- [ ] **Step 3: Write minimal implementation**

In `kernel/src/Lips/Generate/Record.hs`, add the import and change `record`:

```haskell
import Lips.Nix.Target (Target, targetSlug)
```

```haskell
-- | The auditable record of a generation event. The target world co-determines
-- what the mint produced (the option namespace it aimed at and the schema it
-- was grounded against), so it is part of the event and enters 'genId': a
-- re-mint targeting a different world yields a different id, so every engine
-- line's @gen stamp pins the world it was minted for.
record :: Text -> Target -> Double -> Text -> Text -> Text -> Text
record model target confidence sysPrompt program reply = T.unlines
  [ "model: " <> model
  , "target: " <> targetSlug target
  , "confidence-threshold: " <> T.pack (show confidence)
  , "--- system prompt ---", sysPrompt
  , "--- program (input) ---", program
  , "--- raw reply ---", reply
  ]
```

- [ ] **Step 4: Update the call site in Main.hs**

In `kernel/app/Main.hs`, the `generate` function builds `let rec = record model confidence prompt corpus reply`. Change to thread the target (available after Task 3 makes `generate` take a `Target`; for now, if implementing Task 2 before Task 3, temporarily pass `defaultTarget`). The final form after Task 3:

```haskell
      let rec = record model target confidence prompt corpus reply
```

Add `import Lips.Nix.Target (Target (..), defaultTarget, parseTarget, targetSlug)` to Main.hs (also used by later tasks).

- [ ] **Step 5: Run tests to verify they pass**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS. (Main.hs is not compiled by the suite; verify it in Task 3.)

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Generate/Record.hs kernel/test/Spec.hs kernel/app/Main.hs
git commit -m "generate: record target world in the generation event (enters genId)"
```

---

### Task 3: `generate --target` on the CLI

**Files:**
- Modify: `kernel/app/Main.hs` (`parseGenerate`, `generate`, `main` dispatch, `usage`)
- Test: `kernel/test/Spec.hs` — `parseGenerate` is currently not exported/tested; add a pure helper test only if you first export it. Simpler: test the parse logic by refactoring the flag parse into a pure exported function. See Step 1.

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target, parseTarget, defaultTarget)`
- Produces: `parseGenerate :: [String] -> Maybe (Target, Double, Maybe String, [FilePath])`; `generate :: Target -> Double -> Maybe String -> [FilePath] -> IO ()`.

- [ ] **Step 1: Write the failing test**

`parseGenerate` lives in `Main.hs` (not a library module), so the suite cannot import it directly. Move the pure argument parser into a tiny library module so it is testable.

Create `kernel/src/Lips/Generate/Args.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Pure parser for @generate@ CLI arguments, in the library so the
-- conformance suite can pin it. Flags (@--target@, @--confidence@) may appear
-- in any position; then @[model] <program>...@.
module Lips.Generate.Args
  ( parseGenerate
  ) where

import System.FilePath (takeFileName)
import Text.Read       (readMaybe)

import Lips.Nix.Target (Target, defaultTarget, parseTarget)

parseGenerate :: Double -> [String] -> Maybe (Target, Double, Maybe String, [FilePath])
parseGenerate defConf = go Nothing Nothing []
  where
    go _ conf pos ("--target" : v : rest) =
      case parseTarget v of
        Just t  -> go (Just t) conf pos rest
        Nothing -> Nothing
    go _ _ _ ["--target"] = Nothing
    go tgt _ pos ("--confidence" : v : rest)
      | Just c <- readMaybe v, c >= 0, c <= 1 = go tgt (Just c) pos rest
      | otherwise                             = Nothing
    go _ _ _ ["--confidence"] = Nothing
    go tgt conf pos (a : rest) = go tgt conf (pos ++ [a]) rest
    go tgt conf pos []         = finish (maybe defaultTarget id tgt)
                                        (maybe defConf id conf) pos
    finish _ _ []       = Nothing
    finish t c (a : rest)
      | not (null rest), looksLikeModel a = Just (t, c, Just a, rest)
      | otherwise                         = Just (t, c, Nothing, a : rest)
    looksLikeModel s = '/' `elem` s && '.' `notElem` takeFileName s
```

Add to `kernel/test/Spec.hs` (`import Lips.Generate.Args (parseGenerate)`):

```haskell
  describe "generate argument parsing (--target, --confidence, model)" $ do
    it "defaults target to nixos and confidence to the default" $
      parseGenerate 0.7 ["ledger.backup.lips"]
        `shouldBe` Just (Nixos, 0.7, Nothing, ["ledger.backup.lips"])
    it "reads --target home-manager in any position" $
      parseGenerate 0.7 ["--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (HomeManager, 0.7, Nothing, ["a.backup.lips"])
    it "rejects an unknown target" $
      parseGenerate 0.7 ["--target", "darwin", "a.backup.lips"] `shouldBe` Nothing
    it "keeps model detection and multiple programs" $
      parseGenerate 0.7 ["anthropic/claude", "a.backup.lips", "b.backup.lips"]
        `shouldBe` Just (Nixos, 0.7, Just "anthropic/claude", ["a.backup.lips", "b.backup.lips"])
    it "combines --target and --confidence" $
      parseGenerate 0.7 ["--confidence", "0.9", "--target", "home-manager", "a.backup.lips"]
        `shouldBe` Just (HomeManager, 0.9, Nothing, ["a.backup.lips"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec'`
Expected: FAIL — `Could not find module Lips.Generate.Args`.

- [ ] **Step 3: Wire Main.hs to the new parser and thread the target**

In `kernel/app/Main.hs`:

1. Add `import Lips.Generate.Args (parseGenerate)` and remove the local `parseGenerate` definition (delete the whole `parseGenerate :: [String] -> ...` block and its `where`).
2. Update the dispatch in `main`:

```haskell
    ("generate" : rest)  -> case parseGenerate defaultConfidence rest of
      Just (target, conf, mmodel, fs) -> generate target conf mmodel fs
      Nothing                         -> usage >> exitFailure
```

3. Change `generate`'s signature and head:

```haskell
generate :: Target -> Double -> Maybe String -> [FilePath] -> IO ()
generate _ _ _ [] = usage >> exitFailure
generate target confidence mmodel files@(rep : _) = do
```

4. In `generate`, the prompt build becomes target-aware (Task 4) and the schema check becomes target-aware (Task 5). For this task only, keep `promptWithDirection direction` and `assertOptionsAdmissible rep eng` as-is; they change in Tasks 4-5. Ensure the `record` call passes `target` (from Task 2):

```haskell
      let rec = record model target confidence prompt corpus reply
```

5. Update `usage` to document the flag:

```haskell
    , "  " <> name <> " generate [--target nixos|home-manager] [--confidence <0..1>] [model] <program>..."
```

- [ ] **Step 4: Run tests and build the app**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS.
Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-app -o /tmp/lips'`
Expected: compiles `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Generate/Args.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "generate: parse --target and thread the world through generate"
```

---

### Task 4: Target-steered mint prompt

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`systemPrompt`, `promptWithDirection`, exports)
- Test: `kernel/test/Spec.hs` (the "generate prompt is a pinned artifact" and "direction file" blocks; add a home-manager steering assertion)
- Modify: `kernel/app/Main.hs` (`promptWithDirection` call site)

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target (..))`
- Produces:
  - `systemPromptFor :: Target -> Text`
  - `systemPrompt :: Text` (= `systemPromptFor Nixos`, kept for back-compat and the pinned-artifact test)
  - `promptWithDirection :: Maybe Text -> Target -> Text` (was `Maybe Text -> Text`)

- [ ] **Step 1: Write the failing test**

In `kernel/test/Spec.hs`, update the direction-file block to pass a target and add a home-manager steering assertion. Replace the two `promptWithDirection Nothing`/`(Just ...)` lines with target-passing forms, and add:

```haskell
    it "steers home-manager to its namespaces, nixos to system options" $ do
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "home-manager"
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "systemd.user.services"
      systemPromptFor HomeManager `shouldSatisfy` T.isInfixOf "home.packages"
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "NixOS"
```

Update the existing `promptWithDirection` assertions to the new arity, e.g.:

```haskell
      promptWithDirection Nothing Nixos `shouldBe` systemPrompt
      promptWithDirection (Just "   \n  ") Nixos `shouldBe` systemPrompt
```

and where the direction is checked to be appended (the `p` value), use `promptWithDirection (Just "...") Nixos`. Add `systemPromptFor` to the `Lips.Generate.Minting` import list in Spec.hs.

- [ ] **Step 2: Run test to verify it fails**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec'`
Expected: FAIL — `systemPromptFor` not in scope; `promptWithDirection` arity.

- [ ] **Step 3: Implement target steering**

In `kernel/src/Lips/Generate/Minting.hs`:

1. Add `import Lips.Nix.Target (Target (..))`.
2. Add `systemPromptFor` and `worldSection`, keep the existing big constant renamed to `commonBody`, and redefine `systemPrompt`:

```haskell
-- | The mint prompt for a target world: a world-steering preamble naming the
-- option namespaces to emit into, then the world-neutral body. The preamble is
-- the ONLY thing that differs per world; the body's grammar (patterns, rules,
-- typed holes, artifacts, expects) is identical.
systemPromptFor :: Target -> Text
systemPromptFor t = worldSection t <> "\n" <> commonBody

-- | Kept for back-compat and the pinned-artifact test: the NixOS prompt.
systemPrompt :: Text
systemPrompt = systemPromptFor Nixos

worldSection :: Target -> Text
worldSection Nixos = T.unlines
  [ "TARGET WORLD: NixOS (a whole machine, root). Emit NixOS option paths:"
  , "services.*, systemd.services.* and systemd.timers.*, environment.*,"
  , "networking.*, users.*, and so on. <self> keys an attrsOf-submodule"
  , "instance name (services.restic.backups.<self>, systemd.services.<self>)." ]
worldSection HomeManager = T.unlines
  [ "TARGET WORLD: home-manager (one user's $HOME, unprivileged). Emit"
  , "home-manager option paths ONLY, never NixOS system options: programs.*,"
  , "services.* (home-manager user services), systemd.user.services.* and"
  , "systemd.user.timers.*, home.packages, home.file.*, home.sessionVariables,"
  , "xdg.*. There is no system-level config and no root. <self> keys an"
  , "attrsOf-submodule instance name (systemd.user.services.<self>)." ]
```

3. Rename the current `systemPrompt = T.unlines [ ... ]` constant to `commonBody = T.unlines [ ... ]`. Inside it, replace the two NixOS-hard-coded steering phrases with world-neutral wording so the body does not fight the preamble:
   - `"map EVERY subject your patterns produce to\nNixOS option assignments"` → `"map EVERY subject your patterns produce to\noption assignments in the target world named above"`
   - `"Realize work as systemd services and timers or other NixOS options."` → `"Realize work as services and timers or other options in the target world."`
   (Leave illustrative examples like `services.nginx.defaultHTTPListenPort` and the feed example as-is; they teach syntax, not namespace.)
4. Update `promptWithDirection` — it appends the direction block inline (there is no `directionBlock` helper). Change only the two `systemPrompt` references to `systemPromptFor t`, keep the inline `DIRECTION`/`--- begin direction ---` block verbatim:

```haskell
promptWithDirection :: Maybe Text -> Target -> Text
promptWithDirection md t = case md of
  Just d | not (T.null (T.strip d)) ->
    systemPromptFor t <> T.unlines
      [ ""
      , "DIRECTION (the owner's taste for THIS program; optional, advisory)."
      -- ... keep the existing block lines unchanged ...
      , "--- begin direction ---"
      , T.strip d
      , "--- end direction ---"
      ]
  _ -> systemPromptFor t
```

5. Export `systemPromptFor` (add to the module export list).

Note: the pinned-artifact test (`systemPrompt shouldSatisfy isInfixOf clause`) checks clauses like `"act exactly once"`, `"pattern|match|demand|expect|because"`, `"reserved segment <self>"` — none of which are the two phrases reworded in Step 3, so that test stays green as long as `systemPrompt = systemPromptFor Nixos` still contains the common body verbatim.

- [ ] **Step 4: Update Main.hs call site**

In `kernel/app/Main.hs` `generate`, change:

```haskell
  let prompt = promptWithDirection direction target
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
Expected: PASS. If the "pinned artifact" block asserts a clause that was reworded in Step 3, update that clause string to the new neutral wording.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Generate/Minting.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "generate: steer the mint prompt by target world"
```

---

### Task 5: Ground against the target world's schema

**Files:**
- Modify: `kernel/app/Main.hs` (`assertOptionsAdmissible`, `ensureOptionSchema`, `schemaExpr`)
- Test: none in the suite (these are IO + nix). A pure `schemaExpr` test is added below.
- Modify: `kernel/test/Spec.hs` (only if `schemaExpr` is moved to a library module — see Step 1 note)

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target (..))`
- Produces (in Main.hs): `assertOptionsAdmissible :: Target -> FilePath -> EngineData -> IO ()`; `ensureOptionSchema :: Target -> FilePath -> IO FilePath`; `schemaExpr :: Target -> String -> Text`.

- [ ] **Step 1: Change `schemaExpr` to take a target**

In `kernel/app/Main.hs`, replace `schemaExpr`:

```haskell
-- | The Nix expression producing the target world's optionsJSON derivation.
-- NixOS: the pinned nixpkgs NixOS manual optionsJSON. home-manager: the pinned
-- home-manager flake's docs-json. Both are the same optionsJSON shape (Task 1
-- global constraint), so only the derivation differs.
schemaExpr :: Target -> String -> Text
schemaExpr Nixos flakeref = T.pack $ concat
  [ "let np = builtins.getFlake \"", flakeref, "\"; in "
  , "(import (np.outPath + \"/nixos\") "
  , "{ configuration = {}; system = builtins.currentSystem; })"
  , ".config.system.build.manual.optionsJSON" ]
schemaExpr HomeManager flakeref = T.pack $ concat
  [ "let hm = builtins.getFlake \"", flakeref, "\"; in "
  , "hm.packages.${builtins.currentSystem}.docs-json" ]
```

- [ ] **Step 2: Change `ensureOptionSchema` to pick the source and file per target**

```haskell
-- | Locate the target world's options.json. LIPS_OPTIONS_JSON overrides (test
-- seam). Otherwise build it from the pinned flake baked into the binary:
-- LIPS_NIXPKGS_FLAKE for nixos, LIPS_HM_FLAKE for home-manager. Only generate
-- pays this; print/run/check never touch a schema.
ensureOptionSchema :: Target -> FilePath -> IO FilePath
ensureOptionSchema target file = do
  override <- lookupEnv "LIPS_OPTIONS_JSON"
  case override of
    Just p  -> pure p
    Nothing -> do
      let (envVar, subPath) = case target of
            Nixos       -> ("LIPS_NIXPKGS_FLAKE", "/share/doc/nixos/options.json")
            HomeManager -> ("LIPS_HM_FLAKE",      "/share/doc/home-manager/options.json")
      mflake <- lookupEnv envVar
      case mflake of
        Nothing -> die (report
          "lips can't check the setup's options: no option schema source is configured."
          [T.pack envVar <> " (and LIPS_OPTIONS_JSON) are unset."]
          "\226\134\146 run the packaged lips: nix run . -- generate <program> (it bakes the pinned flakes).")
        Just flakeref -> do
          TIO.hPutStrLn stderr
            ("checking options against the " <> targetSlug target
              <> " schema: building it from pinned flake (" <> T.pack flakeref <> ").")
          TIO.hPutStrLn stderr
            "  the first build evaluates the manual and can take a few minutes; nix caches it afterwards."
          built <- try (readProcessWithExitCode "nix"
            [ "build", "--impure", "--no-link", "--print-out-paths"
            , "--expr", T.unpack (schemaExpr target flakeref) ] "")
          case built of
            Left e -> die (nixMissing file "build the option schema" "generate" (tshow (e :: IOException)))
            Right (ExitFailure _, _, err) -> die (validationReport file
              ("lips couldn't build the " <> targetSlug target <> " option schema:\n" <> T.pack err))
            Right (ExitSuccess, out, _) ->
              pure (T.unpack (T.strip (T.pack out)) <> subPath)
```

Note the NixOS `subPath` is `/share/doc/nixos/options.json`; the previous code appended `/share/doc/nixos/options.json` to the built path, so behavior is unchanged for nixos.

- [ ] **Step 3: Thread the target into `assertOptionsAdmissible` and its call**

```haskell
assertOptionsAdmissible :: Target -> FilePath -> EngineData -> IO ()
assertOptionsAdmissible target file eng = do
  schemaPath <- ensureOptionSchema target file
  ...  -- unchanged body
```

And in `generate`, change the call to `assertOptionsAdmissible target rep eng`.

- [ ] **Step 4: Verify the app builds; NixOS grounding still works offline via fixture**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-app -o /tmp/lips'`
Expected: compiles `-Wall` clean.

Sanity-check nixos grounding is unbroken using the offline fixture the suite already relies on (find it): `grep -rn LIPS_OPTIONS_JSON flake.nix justfile kernel` — reuse that fixture path to run `LIPS_OPTIONS_JSON=<fixture> /tmp/lips generate examples/ledger.backup.lips` should not regress on the schema step (it will still call `pi`; stop after the schema line prints, or expect the pi step). If no offline generate path exists, this step is confirmed by Task 7's packaged `nix run` path.

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "generate: ground against the target world's option schema"
```

---

### Task 6: `run` picks a harness from the recorded world

**Files:**
- Modify: `kernel/app/Main.hs` (`main` dispatch for `run`, add `readRecordedTarget`, split `runVm`)
- Test: none in the suite (IO). Verified by building the app and running against an example.

**Interfaces:**
- Consumes: `Lips.Nix.Target (Target (..), parseTarget, defaultTarget)`, `Lips.Identity (generationPath)`
- Produces: `readRecordedTarget :: FilePath -> IO Target`; `runProgram :: Target -> FilePath -> IO ()`.

- [ ] **Step 1: Read the recorded target from `.generation`**

Add to `kernel/app/Main.hs`:

```haskell
-- | The world an engine was minted for, read from its committed .generation
-- record (the @target:@ line). An engine minted before targets existed has no
-- such line and defaults to nixos, so old engines keep working.
readRecordedTarget :: FilePath -> IO Target
readRecordedTarget file = do
  m <- tryRead (generationPath file)
  pure $ case m of
    Nothing  -> defaultTarget
    Just src -> case [ t | l <- T.lines src
                         , Just rest <- [T.stripPrefix "target:" l]
                         , Just t <- [parseTarget (T.unpack (T.strip rest))] ] of
      (t : _) -> t
      []      -> defaultTarget
```

- [ ] **Step 2: Split `run` by world**

Replace the `["run", file] -> runVm file` dispatch with a target-resolving wrapper. In `main`:

```haskell
    ["run", file]                 -> runProgram Nothing file
    ["run", "--target", w, file]  -> case parseTarget w of
      Just t  -> runProgram (Just t) file
      Nothing -> usage >> exitFailure
```

Add `runProgram`:

```haskell
-- | Realize the program, then run it in the world it was minted for (an
-- explicit --target overrides). nixos boots a QEMU VM; home-manager has no
-- machine, so it is eval-only: realize and run the world-blind .expect gate.
runProgram :: Maybe Target -> FilePath -> IO ()
runProgram mtarget file = do
  target <- maybe (readRecordedTarget file) pure mtarget
  case target of
    Nixos       -> runVm file
    HomeManager -> runEvalOnly file
```

`runVm` stays exactly as it is (rename its dispatch only). Add `runEvalOnly`:

```haskell
-- | home-manager run: no VM. Realize, print the module to stdout, then run the
-- committed .expect gate (world-blind) so the values are witnessed. Mirrors
-- check's gate without the diagnosis headers; stays hermetic (no home-manager
-- eval).
runEvalOnly :: FilePath -> IO ()
runEvalOnly file = do
  program <- readProgramOrDie file
  eng     <- loadLangOrDie file
  case validate file eng program of
    Left f            -> die (printFail file f)
    Right (_, nixMod) -> do
      TIO.hPutStrLn stderr
        "home-manager module: no VM to boot; showing the module and checking its contract."
      TIO.putStr nixMod
      checkLoose file
```

- [ ] **Step 3: Update `usage`**

```haskell
    , "  " <> name <> " run [--target nixos|home-manager] <program>"
    , "      Boot as a local VM (nixos) or realize and check (home-manager)."
```

- [ ] **Step 4: Build and smoke the app on an existing example**

Run: `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-app -o /tmp/lips'`
Expected: compiles `-Wall` clean.
Run: `cd /home/cornerman/projects/lips && /tmp/lips print examples/ledger.backup.lips | head -3`
Expected: unchanged module header (nixos engine still prints).

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "run: pick VM (nixos) or eval-only (home-manager) from recorded world"
```

---

### Task 7: Flake — home-manager schema input, baked ref, and the module helper

**Files:**
- Modify: `flake.nix` (add `home-manager` input; bake `LIPS_HM_FLAKE`; expose `lib.modulesFromDir`)
- Create: `nix/modulesFromDir.nix` (the helper)
- Test: `nix flake check` (existing checks must still pass); a new `lipsModules-eval` check exercising the helper on the committed examples.

**Interfaces:**
- Produces: flake output `lib.modulesFromDir :: { pkgs, dir } -> { nixosModules :: AttrSet; homeManagerModules :: AttrSet }`, where each value is a module importable via `imports = [ ... ]`.

- [ ] **Step 1: Add home-manager input and bake the ref**

In `flake.nix`, add the input and thread it:

```nix
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager }:
```

In the `packages` `makeWrapper` call, add the home-manager ref alongside the nixpkgs ref:

```nix
          makeWrapper "$out/bin/.lips-unwrapped" "$out/bin/lips" \
            --set-default LIPS_NIXPKGS_FLAKE "github:NixOS/nixpkgs/${nixpkgs.rev}" \
            --set-default LIPS_HM_FLAKE "github:nix-community/home-manager/${home-manager.rev}"
```

- [ ] **Step 2: Write the helper**

Create `nix/modulesFromDir.nix`:

```nix
# Expose lips programs in a directory as flake module outputs, labeled by the
# world each engine was minted for. The label is read from the committed
# <language>.generation record (the `target:` line), so a program lands under
# nixosModules or homeManagerModules automatically. The realized module is
# DERIVED by running `lips print` in a derivation (offline, deterministic); the
# program and its .lang are the only committed inputs.
{ pkgs, lib, lips, dir }:
let
  entries = lib.filterAttrs (n: _: lib.hasSuffix ".lips" n) (builtins.readDir dir);
  parse = name:
    let parts = lib.splitString "." name;               # <instance>.<language>.lips
    in { instance = builtins.elemAt parts 0;
         language = builtins.elemAt parts 1; };
  targetOf = language:
    let genFile = dir + "/${language}.generation";
    in if builtins.pathExists genFile
          && lib.hasInfix "target: home-manager" (builtins.readFile genFile)
       then "home-manager" else "nixos";
  # Realize into a directory: module.nix plus a staged artifacts/ tree if the
  # program has one, so a relative `src = ./artifacts/<name>` resolves on import.
  realize = name: p:
    let base = lib.removeSuffix ".lips" name;
        artifactsSrc = dir + "/${name}.artifacts";
        hasArtifacts = builtins.pathExists artifactsSrc;
    in pkgs.runCommand "lips-${p.instance}-module" { } ''
      cp ${dir + "/${name}"} ${name}
      cp ${dir + "/${p.language}.lang"} ${p.language}.lang
      mkdir -p "$out"
      ${lips}/bin/lips print ${name} > "$out/module.nix"
      ${lib.optionalString hasArtifacts ''
        mkdir -p "$out/artifacts"
        cp -r ${artifactsSrc}/. "$out/artifacts/"
      ''}
    '';
  built = lib.mapAttrs' (name: _:
    let p = parse name;
        drv = realize name p;
    in lib.nameValuePair p.instance {
         target = targetOf p.language;
         module = "${drv}/module.nix";
       }) entries;
  byTarget = t: lib.mapAttrs (_: v: import v.module)
                  (lib.filterAttrs (_: v: v.target == t) built);
in {
  nixosModules = byTarget "nixos";
  homeManagerModules = byTarget "home-manager";
}
```

- [ ] **Step 3: Expose the helper from the flake**

In `flake.nix` `outputs`, add a `lib` attribute:

```nix
      lib.modulesFromDir = { pkgs, dir }:
        import ./nix/modulesFromDir.nix {
          inherit pkgs dir;
          lib = pkgs.lib;
          lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
```

- [ ] **Step 4: Add an eval check that the helper labels the committed examples**

In `flake.nix` `checks` (the Linux block), add:

```nix
        # The module helper labels each committed example by its recorded
        # world and produces an importable module path. All current examples
        # are nixos engines, so homeManagerModules is empty until a
        # home-manager example is committed (Task 8).
        lipsModules-eval =
          let
            mods = self.lib.modulesFromDir { inherit pkgs; dir = ../examples; };
          in pkgs.runCommand "lips-modules-eval" { } ''
            test -n "${toString (builtins.attrNames mods.nixosModules)}"
            touch "$out"
          '';
```

Note: `dir = ../examples` is relative to `flake.nix`; adjust to `./examples` (the flake is at repo root, examples is a sibling — use `./examples`). Verify the path resolves.

- [ ] **Step 5: Run flake check**

Run: `cd /home/cornerman/projects/lips && git add -A && nix flake check -L`
Expected: `kernel-tests`, `vm-smoke`, `artifact-vm`, and `lipsModules-eval` pass. (Flakes see only git-tracked files — `git add` first.)

- [ ] **Step 6: Commit**

```bash
git add flake.nix nix/modulesFromDir.nix flake.lock
git commit -m "flake: home-manager schema input and modulesFromDir helper (labeled by world)"
```

---

### Task 8 (requires `pi`): a home-manager example, minted end to end

**Files:**
- Create: `examples/<name>.<language>.lips` (a per-user intent, e.g. a user systemd timer or a `programs.*` config)
- Generated (by `lips generate`): `examples/<language>.lang`, `.expect`, `.generation` (with `target: home-manager`)
- Modify: `flake.nix` (an eval-only smoke check for the home-manager example)

This task needs the model gateway (`pi`), which is the user's harness and not in CI. Run it on the user's machine.

- [ ] **Step 1: Write a small per-user program**

Example `examples/notes.usertimer.lips`:

```
run a reminder that prints "water the plants" every day at 9am.
```

(Pick wording the owner actually wants; keep it one intent.)

- [ ] **Step 2: Mint it for home-manager**

Run: `cd /home/cornerman/projects/lips && git add examples/notes.usertimer.lips && nix run . -- generate --target home-manager examples/notes.usertimer.lips`
Expected: writes `examples/usertimer.lang`, `.expect`, `.generation`; the reply grounds against the home-manager schema; the module uses `systemd.user.services.*`/`systemd.user.timers.*`. If generate refuses, read its report and edit the program (deduce-or-fail), do not hand-edit output.

- [ ] **Step 3: Confirm the world is recorded and the module prints**

Run: `grep 'target:' examples/usertimer.generation`
Expected: `target: home-manager`.
Run: `nix run . -- print examples/notes.usertimer.lips`
Expected: a module assigning `systemd.user.*` (or `programs.*`) paths.

- [ ] **Step 4: Add an eval-only smoke check**

In `flake.nix` `checks` (Linux block), add a check that realizes the example and runs its world-blind `.expect` gate offline (mirrors `check-expect`, no VM):

```nix
        hm-eval =
          let lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          in pkgs.runCommand "lips-hm-eval"
               { nativeBuildInputs = [ pkgs.nix ]; } ''
            cp ${./examples/notes.usertimer.lips} notes.usertimer.lips
            cp ${./examples/usertimer.lang} usertimer.lang
            cp ${./examples/usertimer.expect} usertimer.expect
            export HOME="$TMPDIR"
            ${lips}/bin/lips check notes.usertimer.lips
            touch "$out"
          '';
```

Note: `lips check` shells `nix eval`; if the sandbox blocks it, mark this check as needing `--impure`/network and run it via `just` on the host instead (document which). Keep it deterministic and offline if possible.

- [ ] **Step 5: Run the check and commit**

Run: `git add -A && nix flake check -L`
Expected: `hm-eval` passes alongside the others.

```bash
git add examples/notes.usertimer.lips examples/usertimer.lang examples/usertimer.expect examples/usertimer.generation flake.nix
git commit -m "examples: home-manager user-timer, minted for home-manager, eval-only smoke"
```

- [ ] **Step 6: Update the milestone ledger**

Edit `DESIGN.md` section 13: move "Home-manager realization target" from Missing to Done, describing the actual shape (target at generate, recorded in `.generation`, world-blind `.expect` gate needs no HM eval harness, grounding parameterized by world, `run` eval-only, `modulesFromDir` helper). Commit.

```bash
git add DESIGN.md
git commit -m "ledger: home-manager realization target done"
```

---

## Self-Review

**Spec coverage:**
- Section 2/4 (world in paths, generate-time pinned input): Tasks 1-3 (Target type, --target, record).
- Section 3 (differences, world-blind gate): Task 5 grounding source; the world-blind gate is a pre-existing property confirmed in the spec, needs no code.
- Section 5 (run picks harness, check unchanged): Task 6.
- Section 6 (generate grounds per world): Task 5.
- Section 7 (flake helper, labels, explicit dir): Task 7.
- Section 8 (home-manager machinery minimal): Tasks 5-7; end-to-end proof Task 8.

**Placeholder scan:** Task 5 Step 4 and Task 8 Step 4 name sandbox caveats rather than a single command; both give the concrete fallback (offline fixture path via `grep`, run via `just` on host). Acceptable — they are environment branches, not undefined work.

**Type consistency:** `Target` constructors `Nixos`/`HomeManager` used identically across Tasks 1-6. `record` arity `model target confidence sysPrompt program reply` fixed in Task 2 and used in Task 3. `parseGenerate` returns `(Target, Double, Maybe String, [FilePath])` in Task 3, consumed in `main`. `promptWithDirection :: Maybe Text -> Target -> Text` defined Task 4, called Task 4 Step 4. `schemaExpr`/`ensureOptionSchema`/`assertOptionsAdmissible` all gain a leading `Target` in Task 5 and callers updated there.

**Ordering note:** Task 2 references `target` in the `generate` body that only exists after Task 3 changes `generate`'s signature. Implement Task 2's `record` change and test, but apply the Main.hs call-site edit (`record model target ...`) together with Task 3, or temporarily pass `defaultTarget` as noted in Task 2 Step 4.

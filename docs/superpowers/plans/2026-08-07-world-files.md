# World Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Worlds become data files (`<world>.world`); the enumerated `Target` type and all per-world Haskell (schema reshaping, flake harness arms) dissolve, so a world nobody foresaw works without a lips change.

**Architecture:** Strangler pattern. New modules (`Lips.World`, `Lips.World.Resolve`) grow beside the old `Target` code until every caller is switched, then `Lips.Nix.Target`, `Lips.Nix.Kubenix` and `Lips.Nix.Schema` are deleted. The four in-tree worlds ship as embedded `assets/worlds/*.world` files; the flake harness is assembled from a world-neutral skeleton plus world-supplied slots; the resolved world file is copied into the language folder at mint and hash-pinned in `.generation`; compile hard-requires the copy.

**Tech Stack:** Haskell (GHC, base+containers+text+aeson+file-embed), hspec conformance suite, Nix flakes, jq (kubenix schema reshaping).

**Spec:** `docs/superpowers/specs/2026-08-07-world-files-design.md` (decisions, slot factoring, format versions). Read it before starting.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Tests: `just test` = `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec` from `kernel/`. Full: `just ci` (needs KVM), `just check-expect`, `just test-draft`.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Work in a worktree under `.worktrees/`, small single-line commits, rebase + ff-merge, no merge commits, no co-author lines.
- The kernel (`Lips.Kernel.*`) is never touched except Task 2's `Realize.renderArtifacts`; nothing world-related enters it.
- No compat branch in lips code: a missing world file is a refusal naming the remedy, never a fallback (exception: pre-world-files records lack a hash pin, so the hash check applies only when the record carries one — sealed records cannot be edited, this is not a code branch on "old vs new" beyond that).
- Comments explain why, referring only to current code.
- `format: 1` header in `.world` files and new `.generation` records; absence in a record = format 0 (pre-world-files).
- Built-in world names (`nixos`, `home-manager`, `kubenix`, `terranix`, later `artifact`) are reserved: a local file with that name is refused.

---

### Task 0: Worktree

**Files:** none (setup).

- [ ] **Step 1:** `git worktree add .worktrees/world-files -b world-files` and work there for every following task.
- [ ] **Step 2:** `cd .worktrees/world-files/kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec` — confirm green baseline before changing anything.

---

### Task 1: Always Emit `artifact.nix`

Kills the only conditional in the per-world flake text (`nixosBuildsLet target hasArtifacts`), a prerequisite for slot assembly (spec: "One Simplification Falls Out"). The `packages.artifact` attrset and the printed rungs stay conditional (an empty attrset under `packages` is noise); only the FILE and the nixos shell's reference to it become unconditional.

**Files:**
- Modify: `kernel/src/Lips/Kernel/Realize.hs` (`renderArtifacts`)
- Modify: `kernel/src/Lips/Nix/Flake.hs` (`nixosBuildsLet` loses its `Bool`)
- Modify: `kernel/app/Main.hs` (compile writes `artifact.nix` unconditionally)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `renderArtifacts` returns `(Text, [Text])` (file body, artifact names) instead of `Maybe (Text, [Text])`; body is the current one, or an empty-set body `{ pkgs }: { }` when the program has no artifacts. `nixosBuildsLet :: Target -> [Text]`.

- [ ] **Step 1: Write the failing tests.** In `Spec.hs`, find the existing `renderArtifacts` describe-block (grep `renderArtifacts`) and change/add:

```haskell
it "renders an empty artifact set for an artifact-free program" $ do
  let (body, names) = renderArtifacts {- the block's existing artifact-free ground base -}
  names `shouldBe` []
  body `shouldSatisfy` T.isInfixOf "{ }"

it "the nixos shell references artifact.nix unconditionally" $
  flakeText Nixos noRungs `shouldSatisfy`
    T.isInfixOf "builtins.attrValues (import ./artifact.nix"
```

Adapt the first to the block's existing fixture style; the old `shouldBe Nothing` expectations for artifact-free programs are updated in the same edit.

- [ ] **Step 2:** Run the suite; expect type errors / failures around `renderArtifacts`.
- [ ] **Step 3: Implement.** `renderArtifacts` drops the `Maybe` (empty case renders `"# lips-realized artifact derivations. Generated; do not edit.\n{ pkgs }:\n{ }\n"` — keep its header comment). In `Flake.hs`, `nixosBuildsLet` drops the `Bool` parameter and always appends `" ++ builtins.attrValues (import ./artifact.nix { pkgs = pkgsFor system; })"` to the `shellPackages` line. In `Main.hs`, write `outDirPath </> "artifact.nix"` unconditionally (grep for the current conditional write). `Rungs.hasArtifacts` keeps gating `packagesOutput`'s `artifact =` line and the printed rungs.
- [ ] **Step 4:** Suite green, `-Wall` clean.
- [ ] **Step 5:** `just check-expect` (host-side, exercises compile over every example).
- [ ] **Step 6:** Commit: `realize: artifact.nix is always emitted, so the flake text needs no conditional`

---

### Task 2: `Lips.World` — Format, Types, Parser

The new data shape and its strict parser. Pure, no IO, testable inline.

**Files:**
- Create: `kernel/src/Lips/World.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces (later tasks rely on these exact names):**

```haskell
module Lips.World
  ( World (..)
  , Rung (..)
  , parseWorld          -- :: Text -> Either Text World
  , renderWorldError    -- error text helper used by parseWorld internally
  , worldFormat         -- :: Int  (the format this binary reads; 1)
  ) where

data Rung
  = RungCmd  { rgLabel :: Text, rgVerb :: Text, rgAttr :: Text, rgNote :: Text }
  | RungLine Text            -- a literal printed line, <dir> filled at print time
  deriving (Eq, Show)

data World = World
  { wName       :: Text      -- header `world:`
  , wModuleAttr :: Text      -- header `module-attr:` (e.g. "nixosModules")
  , wSchemaPin  :: Maybe Text -- header `schema-pin:` (env var name), optional
  , wSchemaFlake :: Maybe Text -- header `schema-flake:` (default flakeref), optional
  , wClaims     :: [Text]    -- header `claims:` (place slugs the world hosts: "machine", "sandbox")
  , wPreamble   :: Text      -- slot `preamble`
  , wSchema     :: Text      -- slot `schema` (Nix expr with a <flakeref> hole)
  , wInputs     :: [Text]    -- slot `inputs` (flake input lines, may be empty)
  , wInputArgs  :: Text      -- header `input-args:` (e.g. ", kubenix"), default ""
  , wBuilds     :: [Text]    -- slot `builds` (lines of one let-binding body), may be empty
  , wPackages   :: Maybe Text -- slot `packages` (Nix attrset expr)
  , wApps       :: Maybe Text -- slot `apps`
  , wDevShells  :: Maybe Text -- slot `devShells`
  , wRungs      :: [Rung]    -- slot `rungs`
  , wRaw        :: Text      -- the file verbatim, for copying and hashing
  } deriving (Eq, Show)
```

**Format** (from the spec, sharpened): header `key: value` lines, then `--- <slot> ---` blocks. Header keys closed: `format`, `world`, `module-attr`, `schema-pin`, `schema-flake`, `input-args`, `claims`. Slot names closed: `preamble`, `schema`, `inputs`, `builds`, `packages`, `apps`, `devShells`, `rungs`. Required: `format`, `world`, `module-attr`, `preamble`, `schema`. Unknown header key or slot name: refuse naming it (strict parsing catches unknown structure). `format` newer than `worldFormat`: refuse "this file declares format N; this lips reads M → upgrade lips". Rung lines: `label | verb | attr | note` (4 fields, `|`-separated, whitespace-trimmed; note may be empty) or `text: <literal>`.

- [ ] **Step 1: Write the failing tests** (new describe-block `"world files (Lips.World)"`):

```haskell
let hdr = "format: 1\nworld: w\nmodule-attr: wModules\nclaims: sandbox\n"
    minimal = hdr <> "--- preamble ---\nP\n--- schema ---\nE\n"
it "parses a minimal world" $ do
  let Right w = parseWorld minimal
  (wName w, wModuleAttr w, wClaims w) `shouldBe` ("w", "wModules", ["sandbox"])
  (T.strip (wPreamble w), T.strip (wSchema w)) `shouldBe` ("P", "E")
it "refuses an unknown header key, naming it" $
  parseWorld ("frmat: 1\n" <> minimal) `shouldSatisfy`
    either (T.isInfixOf "frmat") (const False)
it "refuses an unknown slot, naming it" $
  parseWorld (minimal <> "--- rung ---\nx\n") `shouldSatisfy`
    either (T.isInfixOf "rung") (const False)
it "refuses a newer format, naming both versions" $
  parseWorld (T.replace "format: 1" "format: 2" minimal) `shouldSatisfy`
    either (\e -> T.isInfixOf "2" e && T.isInfixOf "1" e) (const False)
it "refuses a missing required header" $
  parseWorld "format: 1\nworld: w\n--- preamble ---\nP\n--- schema ---\nE\n"
    `shouldSatisfy` either (T.isInfixOf "module-attr") (const False)
it "parses both rung forms" $ do
  let Right w = parseWorld (minimal
        <> "--- rungs ---\nrun it | run | vm | (needs KVM)\ntext: import it: <dir>\n")
  wRungs w `shouldBe`
    [ RungCmd "run it" "run" "vm" "(needs KVM)", RungLine "import it: <dir>" ]
it "keeps the raw bytes for hashing" $
  fmap wRaw (parseWorld minimal) `shouldBe` Right minimal
```

- [ ] **Step 2:** Run; expect "module Lips.World not found".
- [ ] **Step 3: Implement `Lips.World`.** Header section = lines until the first `--- `; split each at the first `: `. Slots by scanning for `^--- (\w+) ---$` markers; body = lines until next marker. Every refusal via one local `err :: Text -> Either Text a` producing `"world file: " <> reason` texts that include the offending name and, for format, both numbers and the remedy direction (newer → "upgrade lips"; the older direction cannot occur while `worldFormat = 1`). Module header comment: why worlds are data (one sentence, pointer to the spec).
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `world: the world file format, parsed strictly (unknown names and newer formats refuse loud)`

---

### Task 3: The Four Built-In World Files

Port each world's knowledge out of Haskell into `assets/worlds/<name>.world`. Old code still runs everything; these files are data + embeds + parse tests only. Content sources: preamble = `assets/mint/<name>.md` (moved verbatim); schema = `schemaExpr` from `Lips/Schema.hs` wrapped to a canonical output; builds/packages/apps/devShells = the world's arms in `Lips/Nix/Flake.hs`; rungs = `runCommands`' `systemLines`; claims = `unplaceableClaims` inverted (nixos hosts `machine sandbox`, the rest `sandbox`).

**Canonical schema contract:** the slot's expression, with `<flakeref>` substituted, must evaluate to a derivation whose `$out` IS the options.json file (kills `schemaSubPath`). Wrap the existing exprs:

```
--- schema ---
let np = builtins.getFlake "<flakeref>";
    pkgs = import np { system = builtins.currentSystem; };
    doc = (import (np.outPath + "/nixos")
      { configuration = {}; system = builtins.currentSystem; })
      .config.system.build.manual.optionsJSON;
in pkgs.runCommand "options.json" { }
     "cp ${doc}/share/doc/nixos/options.json $out"
```

(nixos shown; home-manager, kubenix, terranix analogous, each porting its own `schemaExpr` body and sub-path from `Lips/Schema.hs`. kubenix's additionally pipes through the Task 5 jq — author it here, prove it in Task 5.)

**kubenix jq** (inside kubenix.world's schema `runCommand`, replacing `Lips/Nix/Kubenix.hs`'s three reshapings; `sort_by(.key | split("."))` is load-bearing — segment order, not string order, or `dropInnerNodes`' adjacency argument breaks on names like `a.b-c`):

```
${pkgs.jq}/bin/jq '
  to_entries
  | map(.key |= (if startswith("kubernetes.api.resources.")
        then "kubernetes.resources." + .[25:] else . end))
  | map(.value.type |= (if (type == "string") and startswith("null or ")
        then (.[8:] | if startswith("(") and endswith(")") then .[1:-1] else . end)
        else . end))
  | sort_by(.key | split("."))
  | . as $es
  | [ range(0; length) as $i | $es[$i]
      | select(($i + 1 >= ($es | length))
          or (($es[$i+1].key | startswith($es[$i].key + ".")) | not)) ]
  | from_entries
' "$doc" > $out
```

Known cosmetic delta, accepted by the spec discussion: an unmodelled optional's refusal wording loses its `null or ` prefix (the old Haskell kept the original wording when the unwrapped type stayed unmodelled; jq cannot call `classifyNixType`).

**Files:**
- Create: `assets/worlds/nixos.world`, `assets/worlds/home-manager.world`, `assets/worlds/kubenix.world`, `assets/worlds/terranix.world`
- Create: `kernel/src/Lips/World/Builtin.hs` (embeds)
- Delete: `assets/mint/nixos.md`, `home-manager.md`, `kubenix.md`, `terranix.md` (content moves into the world files; `body.md` and `direction.md` stay)
- Modify: `kernel/src/Lips/Generate/Minting.hs` (the four `<world>Doc` embeds die; `systemPromptFor` temporarily reads `Builtin` preambles keyed by `Target` until Task 6)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
module Lips.World.Builtin ( builtinWorlds ) where
-- | The worlds lips ships, parsed at first use; a parse failure here is a
-- build defect, surfaced by the suite test below, never at a user.
builtinWorlds :: [(Text, Text)]   -- (name, raw file bytes) via embedStringFile
```

- [ ] **Step 1: Failing test:**

```haskell
it "every built-in world file parses, under its own name" $
  forM_ builtinWorlds $ \(n, raw) ->
    fmap wName (parseWorld raw) `shouldBe` Right n
it "the built-ins carry the claim places the old code hard-coded" $ do
  let claimsOf n = either (const []) wClaims
        (parseWorld (fromJust (lookup n builtinWorlds)))
  claimsOf "nixos" `shouldBe` ["machine", "sandbox"]
  claimsOf "kubenix" `shouldBe` ["sandbox"]
```

- [ ] **Step 2:** Run; fails (no module, no files).
- [ ] **Step 3:** Author the four `.world` files (port, don't invent: every line traces to `mint/<name>.md`, `Schema.hs`, `Flake.hs`, or `Main.hs`'s `unplaceableClaims`). `home-manager.world` has no `builds`/`packages`/`apps`, one `RungLine` rung, `devShells` empty. Write `Builtin.hs` (embed pattern: copy the `embedStringFile "../assets/…"` comment-and-path idiom from `Minting.hs`). Point `systemPromptFor` at the parsed built-ins' `wPreamble` (still `Target`-keyed; the seam moves in Task 6).
- [ ] **Step 4:** Suite green. `git add assets/worlds` before any nix invocation.
- [ ] **Step 5:** Commit: `worlds: the four built-in worlds become world files; mint preambles move in`

---

### Task 4: Flake Assembly From Slots

`flakeText`/`runCommands` stop matching on `Target` and assemble from a `World`. The world-neutral skeleton (description, nixpkgs input, `forSystems`, artifact/site/claims outputs) stays lips-owned; the world contributes its slots verbatim.

**Files:**
- Modify: `kernel/src/Lips/Nix/Flake.hs`
- Modify: callers: `kernel/src/Lips/Gate.hs`, `kernel/app/Main.hs` (pass a `World`; both already have one in scope after Task 6 — for THIS task give them `builtinWorld :: Target -> World` from `Builtin`, a temporary shim deleted in Task 6)
- Test: `kernel/test/Spec.hs` (existing `flakeText`/`runCommands` blocks)

**Interfaces:**
- Produces: `flakeText :: World -> Rungs -> Text`, `runCommands :: World -> [Text] -> Rungs -> FilePath -> [Text]`. `Rungs` unchanged.
- Assembly: `inputs` lines after the nixpkgs input; output args = `", self'"`-style `wInputArgs`; when `wBuilds` nonempty, one let-binding `builds = <wBuilds lines>` in the outer let (the ONE fixed name, spec: "Two fixed names carry the whole interface"); `packages` = lips' artifact/site/claims lines `//`-merged textually with `wPackages` content; same for `apps`, `devShells`; module output line = `wModuleAttr <> ".default = import ./default.nix;"`. `runCommands`: world rungs render as today's `cmd` layout; `RungLine` prints literally with `<dir>` replaced by the out dir.

- [ ] **Step 1: Convert the existing tests.** Every `flakeText Nixos …` becomes `flakeText (builtinWorld Nixos) …`; assertions unchanged — the four built-ins must reproduce today's semantics, so today's tests ARE the golden gate. Add the built-in world files' slot references:

```haskell
it "the assembled nixos flake still carries vm, shell and serviceShells" $ do
  let t = flakeText (builtinWorld Nixos) noRungs
  mapM_ (\s -> t `shouldSatisfy` T.isInfixOf s)
    ["builds = ", "vm = (builds system).vm", "nixosModules.default"]
it "a world with empty slots yields only lips' own outputs" $ do
  let Right w = parseWorld (hdr <> "--- preamble ---\nP\n--- schema ---\nE\n")
  flakeText w noRungs { hasClaims = True } `shouldSatisfy` T.isInfixOf "claims"
  flakeText w noRungs `shouldNotSatisfy` T.isInfixOf "builds ="
```

(reuse Task 2's `hdr`; the second test is `artifact.world`'s physics, proven before the file exists). Rename `nixosBuildsLet`-era internals as they dissolve into slot assembly.

- [ ] **Step 2:** Run; type errors across Flake/Gate/Main.
- [ ] **Step 3:** Implement assembly; port each world's arm content into its Task 3 world file if a diff shows drift (the world files were authored from the same arms — reconcile until the suite's infix assertions hold for all four).
- [ ] **Step 4:** Suite green; `just check-expect` (compiled flakes still evaluate).
- [ ] **Step 5:** Commit: `flake: the harness assembles a world-neutral skeleton plus the world's slots`

---

### Task 5: kubenix Schema Check; Delete the Reshaper

The jq (authored in Task 3) gets an offline CI witness, then the Haskell dies. Grounding runs only at generate, which CI never does — without this check a wrong jq surfaces at the next kubenix mint, far from the change.

**Files:**
- Modify: `flake.nix` (new check `kubenix-schema`; the kubenix flake is already a pinned input, so the check is offline)
- Delete: `kernel/src/Lips/Nix/Kubenix.hs`, `kernel/src/Lips/Nix/Schema.hs` (`schemaFor` dies; every world's document now parses with `parseNixOptionsJson`)
- Modify: `kernel/src/Lips/Schema.hs` (drop `schemaFor` import; parse via `parseNixOptionsJson` directly)
- Test: `kernel/test/Spec.hs` (delete the `parseKubenixOptionsJson` block; its reshaping semantics now live behind the flake check)

**Interfaces:**
- Consumes: kubenix.world's schema slot (Task 3).
- Produces: `checks.<system>.kubenix-schema` — builds the world file's schema derivation and asserts, with jq: `kubernetes.resources.deployments.*.spec.replicas` present with type containing `integer`; no key starts with `kubernetes.api.resources`; the inner node `kubernetes.resources.deployments.*.spec` absent.

- [ ] **Step 1:** Write the flake check. Extract the schema expression at check time from `assets/worlds/kubenix.world` — the check reads the file with `builtins.readFile`, takes everything after the `--- schema ---` marker up to the next `--- ` marker (a small Nix `let` with `builtins.split`), substitutes the pinned kubenix input for `<flakeref>`, and `import`s the resulting expression via `builtins.toFile` + `import`. Assertions as a `runCommand` with jq `-e` queries over the built JSON.
- [ ] **Step 2:** `git add -A && nix build .#checks.x86_64-linux.kubenix-schema` — expect PASS (or iterate the jq in kubenix.world until the three assertions hold; this is the task's actual verification work).
- [ ] **Step 3:** Delete `Kubenix.hs`, `Schema.hs` (Nix/), their Spec block and imports; suite green, `-Wall` clean.
- [ ] **Step 4:** Commit: `schema: kubenix reshaping moves into its world file's jq, witnessed by an offline flake check`

---

### Task 6: Generate Side — World-Driven Mint and Record

`Target` leaves the generate path: prompt, schema resolution, claims placement, record.

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`systemPromptFor :: World -> Text` = `wPreamble <> "\n" <> promptBody`; `unplaceableClaims :: [Text] -> [Claim] -> [Text]` — a claim is unplaceable when its place slug is not in the world's `wClaims`; place slugs: `PlaceMachine` = `"machine"`, sandbox = `"sandbox"`, read the actual constructor names from `Claim.hs`)
- Modify: `kernel/src/Lips/Schema.hs` (`ensureOptionSchema :: World -> Maybe String -> Text -> IO (FilePath, Text)`; precedence `--schema` > `LIPS_OPTIONS_JSON` > `env (wSchemaPin)` > `wSchemaFlake` > refuse listing all four; `buildOptionSchema` substitutes `<flakeref>` into `wSchema` and drops `schemaSubPath` — the derivation's `$out` IS the file; `assertOptionsAdmissible`/`optionsQuery` take `World`, parse with `parseNixOptionsJson`)
- Modify: `kernel/src/Lips/Generate/Record.hs` (`record` takes world name + world-file hash instead of `Target`; new header lines `format: 1` and `world: <name> <hash>` where hash = `hashBytes (encodeUtf8 (wRaw w))`; `target:` line dies for new records)
- Modify: `kernel/app/Main.hs` generate path; delete the `builtinWorld` shim from Task 4 where generate is concerned
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `record :: Text -> Text -> Text -> Text -> Text -> Double -> Text -> Text -> Text -> Text -> Text` (model, worldName, worldHash, schema, thinking, confidence, sysPrompt, program, transcript, reply) — order: `format:`, `model:`, `world: <name> <hash>`, `schema:`, `thinking:`, `confidence-threshold:`, then the three `---` sections as today.

- [ ] **Step 1: Failing tests:**

```haskell
it "a new record carries format and world pin, entering genId" $ do
  let r1 = record "m" "nixos" "h1" "s" "high" 0.7 "p" "c" "t" "y"
      r2 = record "m" "nixos" "h2" "s" "high" 0.7 "p" "c" "t" "y"
  r1 `shouldSatisfy` T.isInfixOf "format: 1"
  r1 `shouldSatisfy` T.isInfixOf "world: nixos h1"
  genId r1 `shouldNotBe` genId r2
it "a claim is unplaceable when the world does not host its place" $ do
  unplaceableClaims ["sandbox"] [machineClaim] `shouldBe` [clId machineClaim]
  unplaceableClaims ["machine", "sandbox"] [machineClaim] `shouldBe` []
```

(build `machineClaim` from the existing claim fixtures in the current `unplaceableClaims` tests — grep them.)

- [ ] **Step 2:** Run; type errors.
- [ ] **Step 3:** Implement; update every existing Spec use of `systemPromptFor`/`record`/`unplaceableClaims`/`ensureOptionSchema`.
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `generate: the mint is world-driven; records pin the world file by hash`

---

### Task 7: Resolution, Copy-In, `--worlds`, `lips world`

How a name becomes a world at generate, and how a human gets a built-in's bytes.

**Files:**
- Create: `kernel/src/Lips/World/Resolve.hs`
- Modify: `kernel/src/Lips/Cli.hs` (`--target` becomes a plain string option, `parseTarget`/`targetReader` die; new `--worlds DIR` on generate and options, mirroring `langDirOpt`'s judgment: no short alias; new verb `world` with an optional name argument)
- Modify: `kernel/app/Main.hs` (generate resolves the world, copies `wRaw` to `<langDir>/<name>.world` before recording; `world` verb; `options` resolves against cwd)
- Modify: `kernel/src/Lips/Identity.hs` (add `worldPathIn :: FilePath -> Text -> FilePath` = `dir </> T.unpack name <.> "world"` — Identity is the only place that knows the layout)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
module Lips.World.Resolve
  ( resolveWorld   -- :: FilePath -> Maybe FilePath -> Text -> IO (Either Text World)
                   --    base dir, --worlds override, name
  , builtinNames   -- :: [Text]
  ) where
```

Resolution: name refers to `<dir>/<name>.world` (dir = `--worlds` value, else the program's own directory); if the file exists and the name is a built-in's, refuse ("built-in names are reserved; call yours house-<name>"); if it exists, parse it; else the built-in; else refuse listing `builtinNames` and the searched path. `lips world` (no arg) lists built-in names; `lips world <name>` prints the built-in's raw bytes to stdout (the authoring seed and the migration tool).

- [ ] **Step 1: Failing tests** (pure parts; `resolveWorld`'s IO tested via tmp dirs like the existing Identity/Stage tests — grep `withTempDir` usage in Spec):

```haskell
it "a local file shadowing a built-in name is refused" $ do
  withTempDir $ \d -> do
    TIO.writeFile (d </> "nixos.world") "format: 1\n…"
    r <- resolveWorld d Nothing "nixos"
    r `shouldSatisfy` either (T.isInfixOf "reserved") (const False)
it "an unknown name refuses listing the built-ins and the searched path" $ …
it "a local custom world resolves from the program's directory" $ …
it "--worlds overrides the search directory" $ …
```

- [ ] **Step 2:** Run; failures.
- [ ] **Step 3:** Implement. Generate path order: resolve → copy `wRaw` into the language folder (overwrite byte-identical is fine; a DIFFERENT existing copy for the same name is refused — the committed copy is the engine's truth, not the search path's) → mint → record with the copy's hash.
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `world: resolution beside the program, reserved built-in names, --worlds, and a print verb`

---

### Task 8: Compile Side — Hard Require the Copied World

`readRecordedTarget` becomes `readRecordedWorld`; `Target` dies everywhere.

**Files:**
- Modify: `kernel/app/Main.hs` (`readRecordedWorld :: FilePath -> FilePath -> IO World`: read the record; a `world: <name> <hash>` line names the copy and pins it — read `<langDir>/<name>.world`, missing → die naming the remedy (`lips world <name> > <langDir>/<name>.world` for a built-in, or restore your custom file), hash mismatch → die naming both hashes; a record with only `target: <slug>` (format 0) names the copy without a pin — file still REQUIRED, no hash check, since sealed records cannot be edited; no record → the existing no-record failure)
- Modify: `kernel/src/Lips/Gate.hs` (takes `World`, the Task 4 shim dies)
- Delete: `kernel/src/Lips/Nix/Target.hs`; every remaining `Target` import
- Test: `kernel/test/Spec.hs` (the `Lips.Nix.Target` describe-block dies; `readRecordedTarget`'s scan test becomes `readRecordedWorld`'s)

- [ ] **Step 1: Failing tests:** compile-path refusals are exercised through the record-reading pure helper — extract `recordedWorldName :: Text -> Either Text (Text, Maybe Text)` (record text → world name + optional hash; prefers `world:`, falls back to `target:`, refuses records with neither) so it is testable inline:

```haskell
it "prefers the world pin over the legacy target line" $
  recordedWorldName "format: 1\nworld: nixos abc\ntarget: x\n"
    `shouldBe` Right ("nixos", Just "abc")
it "reads a format-0 record by its target line, unpinned" $
  recordedWorldName "model: m\ntarget: kubenix\n" `shouldBe` Right ("kubenix", Nothing)
it "refuses a record naming no world" $
  recordedWorldName "model: m\n" `shouldSatisfy` isLeft
```

- [ ] **Step 2:** Run; failures.
- [ ] **Step 3:** Implement; delete `Target.hs` and chase `-Wall`.
- [ ] **Step 4:** Suite green. `just check-expect` — EXPECTED TO FAIL now (examples have no world files); that failure is Task 10's input, do not "fix" it here.
- [ ] **Step 5:** Commit: `compile: the copied world file is required and hash-checked; the Target enum dies`

---

### Task 9: `modulesFromDir` Reads the World File

The deploy path stops enumerating worlds: the module attribute comes from the copied world file's own header.

**Files:**
- Modify: `nix/modulesFromDir.nix`
- Test: the existing `lipsModules-eval` flake check (it evaluates over `examples/`, which Task 10 migrates — run it there)

- [ ] **Step 1:** Implement: for each language dir, read the world name from `.generation` (`world: ` line's first word, else `target: ` line — same precedence as Haskell, in Nix string ops), then `builtins.readFile` `<dir>/<name>.world`, take the `module-attr: ` header value (split lines, match prefix). Group instances under their `module-attr` value: the result exposes `nixosModules`, `homeManagerModules`, `kubenixModules`, `terranixModules` exactly as today AND any custom world's attr with zero new code. Keep the existing header comment style; document that the attr name is the world file's own word.
- [ ] **Step 2:** Verification deferred to Task 10's `just ci` (the check needs migrated examples).
- [ ] **Step 3:** Commit: `deploy: modulesFromDir groups by the world file's own module-attr`

---

### Task 10: Migrate the Examples (One-Off, Not Kept)

Every committed language folder gains its world file copy. Records are sealed and stay byte-identical; only new sibling files land.

**Files:**
- Create (generated): `examples/<lang>/<world>.world` for every language folder
- No lips code, no committed script.

- [ ] **Step 1:** Build lips in the worktree (`git add -A && nix build`), then run the one-off inline:

```bash
for g in examples/*/*.generation; do
  d=$(dirname "$g")
  w=$(grep -m1 '^target:' "$g" | awk '{print $2}'); w=${w:-nixos}
  ./result/bin/lips world "$w" > "$d/$w.world"
done
```

(the `${w:-nixos}` covers records from before targets existed, which `readRecordedTarget` today defaults the same way — check `git grep -L '^target:' examples/*/*.generation` first and eyeball any hit.)

- [ ] **Step 2:** `git add examples && just check-expect` — green again (Task 8's expected break heals).
- [ ] **Step 3:** `just test && just test-draft && just ci` (full: module eval, artifact build, VM boot; needs KVM).
- [ ] **Step 4:** Commit: `examples: every language folder carries its world file copy`

---

### Task 11: Docs and Ledger

**Files:**
- Modify: `README.md` (The Files table gains the `<world>.world` row; the `--target` paragraph says names resolve to world files, `lips world` exists, built-in names reserved)
- Modify: `DESIGN.md` §13 ledger (new Done entry: worlds are data; what moved where; the jq delta; pointer to both specs)
- Modify: `TODO.md` (the "World files" backlog item moves to done-pointer; the terranix-grounding and CRD items gain one line each: the schema slot is now the place a richer source plugs into)

- [ ] **Step 1:** Write the three edits; run the 21 writing rules over new prose.
- [ ] **Step 2:** Commit: `docs: worlds-as-data lands in README, ledger and TODO`
- [ ] **Step 3:** Finish: rebase on main, ff-merge, delete the worktree (finishing-a-development-branch skill).

---

## Horizon (Do Not Build Now): Multi-World Builds

The next plan, after this lands (spec: `2026-08-07-multi-world-builds-design.md`). Named here so nothing in this plan paints over it:

1. Engine split `<language>.grammar` + `<world>/<language>.rules|.expect|<world>.world` — `Lips.Identity` grows the per-world paths; this plan's flat `<langDir>/<name>.world` moves one level down then.
2. `.generation` becomes multi-event (one per backend); this plan's single-event records must stay readable (absence rule again).
3. Append-only grammar guard (byte-identity of old pattern lines across backend mints).
4. `--target a,b` multi-mints; compile-all into `out/<instance>/<world>/`.
5. `artifact.world` ships (the empty world; Task 4's "empty slots" test is its physics).
6. Cross-world references (`export.*`, `${program...}`, derived-hash value form) stay backlog behind both.

## Self-Review Notes

- Spec coverage: defect (T8 deletes the enum), six knobs (T3), slots (T4), jq + fallback risk (T5; fallback `schema-shape:` not planned — if T5's check cannot be made to pass, STOP and re-plan that task, the spec names the retreat), copy+hash (T6/T7/T8), resolution (T7), format versions (T2, T6), trust (spec prose, no task), migration (T10), `artifact.nix` simplification (T1).
- Deliberately excluded: flake-ref world sharing (spec defers to Nix), `artifact.world` (horizon), any kernel change beyond T1.
- Type consistency: `World`/`Rung`/`parseWorld` (T2) consumed by T3-T8; `record` signature fixed in T6 and used in T7; `recordedWorldName` only in T8.

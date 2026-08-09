# One Mint, Many Worlds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lips generate --target a,b` becomes ONE model call that writes the shared grammar and both worlds' rules, so the call that discovers a cross-world defect is the call that may fix it.

**Architecture:** The reply gains a per-item `@<world>` tag. Patterns, source blocks, the report, gaps and because-notes stay shared; rules, demands, merges and expects belong to one world. `generate` resolves every world and builds every schema before the call, sends one prompt carrying each world's preamble scoped to its own section, then runs the existing gates once per world over that world's engine (the shared grammar plus its own rules). Worlds that pass are written; a world that fails is refused alone and the run exits nonzero. One event writes one record, at the language level, pinning every world it covers.

**Tech Stack:** Haskell (GHC, base+containers+text+aeson+file-embed+optparse-applicative), hspec conformance suite, Nix flakes, one TypeScript pi extension (`assets/mint-tools.ts`).

**Spec:** `docs/superpowers/specs/2026-08-09-one-mint-many-worlds-design.md`. Read it first; it carries the measurement this plan is built on and the alternatives already rejected.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Fast test: from `kernel/`, `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`. The app must build separately: `ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/bapp -o /tmp/lips` (Spec does not import `app/Main.hs`, so a suite-only run misses breakage there).
- Full: `nix flake check`, the check-expect loop (`for p in examples/*.lips; do nix run . -- check "$p"; done`), and `just test-draft`.
- `just` needs `XDG_RUNTIME_DIR=/tmp` in this sandbox.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Work in a worktree under `.worktrees/`, small single-line commits, rebase + ff-merge, no merge commits, no co-author lines.
- The kernel (`Lips.Kernel.*`) is not touched at all by this plan. Every change is in the shell (`Lips.Generate.*`, `Lips.Identity`, `Lips.Language`, `app/Main.hs`) or in assets.
- A committed record is SEALED: its bytes hash to the id its lines are stamped with, so nothing here rewrites one.
- Single-world behaviour must stay byte-identical: with one world in the run the `@world` tag is optional and defaults to that world, and every committed example keeps checking and compiling untouched.
- Comments explain why, referring only to current code.

---

### Task 0: Worktree and Baseline

**Files:** none (setup).

- [ ] **Step 1:** `git worktree add .worktrees/one-mint -b one-mint`, and work there for every following task.
- [ ] **Step 2:** From `.worktrees/one-mint/kernel`, run the fast test and confirm the baseline: 813 examples, 0 failures.

---

### Task 1: The Reply Learns Which World An Item Is For

Pure parsing. Nothing reads the new field yet, so the tree stays green.

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`ItemCandidate`, `parseEngineCandidates`, `parseLine`)
- Test: `kernel/test/Spec.hs` (the `parseEngineCandidates` describe-block; grep `ItemCandidate`)

**Interfaces:**

```haskell
data ItemCandidate = ItemCandidate
  { icItem       :: EngineItem
  , icConfidence :: Confidence
  , icLine       :: Text
  , icId         :: Text
  , icWorld      :: Maybe Text   -- ^ NEW: Nothing = shared by every world
  }

-- | The world list the reply is written for decides two things: which tag names
-- a world lips is actually minting, and whether a tag may be omitted.
parseEngineCandidates :: [Text] -> Text -> ([Text], [ItemCandidate])
```

The tag sits right after the id and starts with `@`: `0.95 r1 @kubenix match fact job.schedule => ...`. Rules:

- A tag naming a world not in the list is an error naming both the tag and the list.
- A tag on a SHARED kind (`pattern`, `source`, `report`, `gap`, `because`) is an error: those are the language's, not a world's.
- A world-bound kind (`match`, `demand`, `merge`, `expect`) with no tag takes the single world when the list has exactly one, and is an error when the list has several.

- [ ] **Step 1: Write the failing tests.** Add to the parse block:

```haskell
it "reads the world tag that follows an item's id" $ do
  let (errs, cs) = parseEngineCandidates ["nixos", "kubenix"] (T.unlines
        [ "0.95 p1 pattern watch <secs> seconds => fact watch.i \"<secs>\""
        , "0.95 r1 @nixos match fact watch.i => systemd.services.w.environment.S \"<value:int>\""
        , "0.95 r2 @kubenix match fact watch.i => kubernetes.resources.pods.w.spec.hostname \"\\\"<value>\\\"\"" ])
  errs `shouldBe` []
  map icWorld cs `shouldBe` [Nothing, Just "nixos", Just "kubenix"]

it "defaults an untagged rule to the one world, and refuses it when there are several" $ do
  let one  = "0.95 r1 match fact watch.i => systemd.services.w.environment.S \"<value:int>\""
  map icWorld (snd (parseEngineCandidates ["nixos"] one)) `shouldBe` [Just "nixos"]
  fst (parseEngineCandidates ["nixos", "kubenix"] one) `shouldSatisfy` any (T.isInfixOf "names no world")

it "refuses a tag naming a world this mint does not write" $
  fst (parseEngineCandidates ["nixos"] "0.95 r1 @kubenix match fact watch.i => a.b \"<value>\"")
    `shouldSatisfy` any (T.isInfixOf "kubenix")

it "refuses a tag on a shared item, which belongs to no single world" $
  fst (parseEngineCandidates ["nixos", "kubenix"]
        "0.95 p1 @nixos pattern watch <secs> seconds => fact watch.i \"<secs>\"")
    `shouldSatisfy` any (T.isInfixOf "shared")
```

- [ ] **Step 2:** Run the suite; expect type errors (the arity changed) plus the new failures.
- [ ] **Step 3: Implement.** In `parseLine`, after reading the id, peek at the next token: when it starts with `@`, take it as the world and strip it. Thread the world list from `parseEngineCandidates` into `parseLine`. Decide shared-versus-bound from the item kind keyword, which is already read there. Fix the existing call sites mechanically (`app/Main.hs`, `Lips.Generate.Draft`) by passing the single world they know.
- [ ] **Step 4:** Suite green, `-Wall` clean, app builds.
- [ ] **Step 5:** Commit: `minting: a reply item names the world it is for`

---

### Task 2: One Reply, One Engine Per World

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`assemble`, `expectsOf`, `sourcesOf` callers)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- | The items one world's engine is built from: every shared item, plus the
-- items tagged for that world. The grammar is the shared half, so two worlds'
-- engines differ only below it.
itemsFor :: Text -> [ItemCandidate] -> [EngineItem]
```

`sourcesOf` keeps taking every item, because a source tree is the language's and
shared. `assemble` and `expectsOf` are called per world, on `itemsFor w cands`.

- [ ] **Step 1: Write the failing test:**

```haskell
it "builds each world's engine from the shared items plus its own" $ do
  let (_, cs) = parseEngineCandidates ["nixos", "kubenix"] (T.unlines
        [ "0.95 p1 pattern watch <secs> seconds => fact watch.i \"<secs>\""
        , "0.95 r1 @nixos match fact watch.i => systemd.services.w.environment.S \"<value:int>\""
        , "0.95 r2 @kubenix match fact watch.i => kubernetes.resources.pods.w.spec.hostname \"\\\"<value>\\\"\"" ])
      nixosEng = assemble (itemsFor "nixos" cs)
  length (edPatterns nixosEng) `shouldBe` 1
  map mrId (edRules nixosEng) `shouldBe` ["r1"]
  map mrId (edRules (assemble (itemsFor "kubenix" cs))) `shouldBe` ["r2"]
```

- [ ] **Step 2:** Run; expect "not in scope: itemsFor".
- [ ] **Step 3: Implement.** `itemsFor w = map icItem . filter (\c -> icWorld c `elem` [Nothing, Just w])`. Doc comment: why sources are not filtered (one program's source, shared by the worlds that run it).
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `minting: one reply yields one engine per world, over a shared grammar`

---

### Task 3: The Prompt Carries Every World, Scoped

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`systemPromptFor`, `promptWithDirection`)
- Create: `kernel/../assets/mint/worlds.md` (replaces `assets/mint/shared.md`)
- Delete: `assets/mint/shared.md`
- Test: `kernel/test/Spec.hs` (the prompt describe-blocks)

**Interfaces:**

```haskell
-- | The mint prompt for one or more worlds: each world's preamble in its own
-- section, then the world-neutral body, then the multi-world rules (only when
-- there are several worlds).
systemPromptFor :: [World] -> Text
promptWithDirection :: Maybe Text -> Maybe Text -> [World] -> Text
  -- ^ direction, inherited grammar, worlds
```

The wrapper text is the one measured on 2026-08-09 and must be kept verbatim in
spirit: each section is absolute inside itself and nowhere else, and a
prohibition in one section says nothing about any other world.

`assets/mint/worlds.md` carries what `shared.md` said plus what the measurement
taught, with the `{{WORLDS}}` substitution:

- the `@<world>` tag rule, with one tagged rule per world as the example;
- which kinds are shared and carry no tag;
- ids unique across the reply, except a `because` note, which repeats the id of
  the item it explains;
- every world must be served;
- a fact must be spendable by every world, with the committed `examples/cron`
  pair as the worked example (pattern `<hh>:<mm>` into `fact job.schedule
  "<hh> <mm>"`, then both worlds' rules assembling their own notation), and the
  warning that splitting further than the worlds need makes a later world refuse
  for discarding a word;
- **where a world needs a fact the program does not state, write that world's
  demand, never a value.** Measured: told nothing, the mint invented a container
  image at confidence 0.8, which is above the default threshold and would have
  shipped.

- [ ] **Step 1: Write the failing tests:**

```haskell
it "scopes each world's preamble to its own section" $ do
  let p = systemPromptFor [shippedWorld "nixos", shippedWorld "kubenix"]
  mapM_ (\c -> p `shouldSatisfy` T.isInfixOf c)
    [ "--- world nixos ---", "--- world kubenix ---"
    , "ABSOLUTE INSIDE ITSELF AND NOWHERE ELSE" ]

it "says nothing about several worlds when there is one" $ do
  let p = systemPromptFor [shippedWorld "nixos"]
  p `shouldNotSatisfy` T.isInfixOf "--- world nixos ---"
  p `shouldNotSatisfy` T.isInfixOf "TAG EVERY WORLD-BOUND ITEM"

it "tells a multi-world mint to demand what a world needs and the program omits" $ do
  let p = systemPromptFor [shippedWorld "nixos", shippedWorld "kubenix"]
  mapM_ (\c -> p `shouldSatisfy` T.isInfixOf c)
    [ "TAG EVERY WORLD-BOUND ITEM", "write that world's demand", "<value.2> <value.1>" ]
```

- [ ] **Step 2:** Run; expect type errors and failures.
- [ ] **Step 3: Implement.** One world keeps today's shape exactly (`wPreamble w <> "\n" <> promptBody`), so every committed example's prompt is unchanged. Several worlds get the scoped wrapper, the body, then `worlds.md` with `{{WORLDS}}` filled. Keep the existing `grammarDoc`/`directionDoc` sections after it.
- [ ] **Step 4:** Suite green; `just test-draft`.
- [ ] **Step 5:** Commit: `mint: one prompt carries every world, each scoped to its own section`

---

### Task 4: The Joint Record

**Files:**
- Modify: `kernel/src/Lips/Generate/Record.hs` (`record`, `recordedWorld`)
- Modify: `kernel/src/Lips/Identity.hs` (`languageRecordPath`, `languageReadmePath`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- Identity: the joint event's own files, at the language level.
languageRecordPathIn :: FilePath -> FilePath -> FilePath   -- dir, program -> dir/<language>.generation
languageReadmePathIn :: FilePath -> FilePath                -- dir -> dir/README.md

-- Record: a record covers one or more worlds, each with its own file hash and
-- schema pin.
record :: Text -> [(Text, Text, Text)] -> Text -> Double -> Text -> Text -> Text -> Text -> Text
  -- ^ model, [(world, worldHash, schemaPin)], thinking, confidence, prompt, corpus, transcript, reply

-- | The pin for one world in a record that may cover several. Nothing when the
-- record does not name that world at all.
recordedWorldPin :: Text -> Text -> Maybe (Text, Maybe Text)  -- ^ record, world -> (name, hash)
```

`recordedWorld` (one world, the old shape) stays for records already committed:
a single-world mint keeps writing exactly today's bytes, so no committed record
changes meaning and no stamp moves.

- [ ] **Step 1: Write the failing tests:**

```haskell
it "pins every world a joint mint covered, each by its own hash" $ do
  let rec = record "m" [("nixos", "h1", "s1"), ("kubenix", "h2", "s2")]
                   "medium" 0.7 "p" "c" "t" "r"
  recordedWorldPin rec "nixos"   `shouldBe` Just ("nixos", Just "h1")
  recordedWorldPin rec "kubenix" `shouldBe` Just ("kubenix", Just "h2")
  recordedWorldPin rec "terranix" `shouldBe` Nothing

it "writes a one-world record exactly as before, so no committed stamp moves" $ do
  let joint = record "m" [("nixos", "h1", "s1")] "medium" 0.7 "p" "c" "t" "r"
  recordedWorld joint `shouldBe` Right ("nixos", Just "h1")
```

- [ ] **Step 2:** Run; expect failures.
- [ ] **Step 3: Implement.** One world renders the existing `world:`/`schema:` lines verbatim; several render one `world:` line each (name, hash) and one `schema:` line each, prefixed by the world. Doc comment on why the one-world case is byte-preserved (sealed records, invariant 6).
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `record: one event may cover several worlds, each pinned by its own hash`

---

### Task 5: generate Makes One Call

The heart. `generate` stops being per world.

**Files:**
- Modify: `kernel/app/Main.hs` (`main`'s `Generate` arm, `generate`, `callPi`, the write step)
- Test: exercised end to end in Task 9; the pure pieces are already covered by Tasks 1-4.

**Interfaces:**

```haskell
generate :: [World] -> Maybe Text -> Maybe String -> Double -> Compat -> Bool
         -> Maybe String -> String -> [FilePath] -> IO ()
  -- ^ worlds, inherited grammar, schema override, confidence, compat, verbose,
  --   model, thinking, programs
```

Order inside one run:

1. resolve every world (a bad name costs no call, as today);
2. `ensureOptionSchema` for every world, before the call, so a schema that cannot
   be built costs no call either; keep each `(world, schemaPath, schemaPin)`;
3. one `callPi`, with `LIPS_MINT_WORLDS` (comma-separated) and
   `LIPS_MINT_SCHEMAS` (`<world>=<path>` per line) in the child environment,
   replacing `LIPS_MINT_WORLD`/`LIPS_MINT_SCHEMA` when there are several;
4. parse once with `parseEngineCandidates (map wName worlds)`;
5. shared gates once: the report block must exist, sources must be named, the
   append-only guard against an inherited grammar;
6. per world, over `assemble (itemsFor w cands)`: `engineViolations`,
   `assertOptionsAdmissible` against that world's schema, `validate` for every
   program, the Nix parse, the staged-source gate, the contract, the artifact
   build and the claim gates. Collect `Either Text Realization` per world;
7. write: the shared files once (grammar, `artifacts/`, the joint record, the
   language README), then each world that passed (its rules, expect, world file
   copy, and its own record only when the run mints exactly one world);
8. exit nonzero when any world failed, after writing the ones that held.

- [ ] **Step 1: Wire the call.** Change the `Generate` arm to resolve all worlds and call `generate` once. Delete the `forM_ (zip worlds (tails ...))` loop and `inheritedGrammar`'s per-iteration re-read (it is read once, before the call).
- [ ] **Step 2: Split the gates.** Extract the per-world gate sequence into a local `gateWorld :: World -> FilePath -> EngineData -> IO (Either Text [(FilePath, Realization)])` so the loop reads as one pass per world, and a world's failure becomes a `Left` instead of a `die`.
- [ ] **Step 3: Split the write.** Shared writes happen once; per-world writes loop. A world that failed writes nothing at all, not even its folder.
- [ ] **Step 4:** `-Wall` clean, app builds, suite green.
- [ ] **Step 5:** Commit: `generate: one model call writes the grammar and every world's rules`

---

### Task 6: A World That Fails Does Not Take The Others

**Files:**
- Modify: `kernel/app/Main.hs` (`checkWorld`)
- Modify: `kernel/src/Lips/Report.hs` (a per-world open-questions report)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- | The questions one world's demands leave open, named as that world's.
unansweredReport :: FilePath -> Text -> [Text] -> Text
```

Measured on 2026-08-09: kubenix needs a container image the program never
states, so its rules demand one while nixos demands nothing of the kind. A
demand lives in `<world>/<language>.rules`, so an unanswered demand is a fact
about THAT WORLD, and killing the whole run for it is wrong. A conflict stays
fatal: it is refinement over the shared grammar, true in every world.

- [ ] **Step 1: Write the failing test:**

```haskell
it "names the world whose questions are open, not the program" $ do
  let t = unansweredReport "nightly.timer.lips" "kubenix" ["which image should the run use?"]
  t `shouldSatisfy` T.isInfixOf "kubenix"
  t `shouldSatisfy` T.isInfixOf "which image should the run use?"
  -- the other worlds are unaffected, so this must not read as a program defect
  t `shouldNotSatisfy` T.isInfixOf "lips generate"
```

- [ ] **Step 2:** Run; expect "not in scope".
- [ ] **Step 3: Implement.** Add `unansweredReport` beside `unportableReport`, worded the same way (this world asks for something the program does not state; answer it in the program, or compile the worlds that hold). In `checkWorld`, turn the `diagOpen` branch into a `Left` for that world instead of a `die`, keeping the `unanswerableDemands` case fatal (a demand outside every emitted subject family is an engine defect, not a world's question).
- [ ] **Step 4:** Suite green; every committed example still checks (they are single-world, so a fatal-versus-per-world difference is invisible there).
- [ ] **Step 5:** Commit: `check: an open question belongs to the world that asked it`

---

### Task 7: Shared Files Freeze Together

Closes a live clobber: every world's mint replaces `artifacts/` wholesale
(`app/Main.hs:1010`), so minting a second world today deletes the source the
first world's rules reference.

**Files:**
- Modify: `kernel/app/Main.hs` (the write step)
- Test: `kernel/test/Spec.hs` (pure part) plus a shell check in Task 9

**Interfaces:**

```haskell
-- | What a mint may not change when it does not own the language level: the
-- shared files belong to the worlds that are not being re-minted.
sharedFileViolations :: Maybe Text -> Text -> [SourceFile] -> [SourceFile] -> [Text]
  -- ^ inherited grammar, freshly rendered grammar, committed sources, minted sources
```

- [ ] **Step 1: Write the failing test:**

```haskell
it "refuses a frozen mint that would rewrite the shared source tree" $ do
  let committed = [SourceFile "hello" "main.go" "old"]
      minted    = [SourceFile "hello" "main.go" "new"]
  sharedFileViolations (Just "g") "g" committed minted
    `shouldSatisfy` any (T.isInfixOf "main.go")
  sharedFileViolations (Just "g") "g" committed committed `shouldBe` []
  -- not frozen: the mint owns the language level and may rewrite anything
  sharedFileViolations Nothing "g" committed minted `shouldBe` []
```

- [ ] **Step 2:** Run; expect "not in scope".
- [ ] **Step 3: Implement.** When a grammar is inherited (the frozen case), the language level is read-only: the rendered grammar must satisfy `appendOnlyViolations` (already true) AND the minted source tree must equal the committed one, file for file. Refuse naming the files that differ, with the same remedy as a changed pattern (re-mint every world together). In the write step, skip every shared write when frozen.
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `generate: a mint that does not own the language level may not rewrite it`

---

### Task 8: The Tools Learn The World

**Files:**
- Modify: `assets/mint-tools.ts`
- Modify: `kernel/app/Main.hs` (`checkDraft`, `draftWorld`, `draftWorldOrDefault`)
- Modify: `kernel/src/Lips/Generate/Draft.hs` (`DraftTree`, `materializeDraft`)
- Test: `justfile`'s `test-draft` recipe gains a multi-world case

**Interfaces:**

```haskell
data DraftTree = DraftTree
  { dtLangDir :: FilePath
  , dtGrammar :: Text
  , dtWorlds  :: [(Text, Text, Text)]  -- ^ world, rules, expect
  , dtSources :: [SourceFile]
  }
materializeDraft :: FilePath -> [Text] -> FilePath -> Text -> Maybe Text -> Either [Text] DraftTree
```

`query_options` gains a required `world` parameter, described as "one of:
<the worlds this mint writes for>", and refuses a world outside that list rather
than searching the wrong schema. It reads `LIPS_MINT_WORLDS`; the single-world
case is the one-element list, so `LIPS_MINT_WORLD` disappears.

`check_draft` passes the tagged draft to `lips check --draft`, which materializes
every world the draft names and runs the ordinary verifier over each. Without
this the model cannot see `partsExist` fire, which is the mechanical signal that
a rule reads a part its pattern does not produce, and the whole point of one call
is that the model can still act on it.

- [ ] **Step 1: Write the failing test** in `kernel/test/Spec.hs`:

```haskell
it "materializes a tagged draft as one grammar and one folder per world" $ do
  let reply = T.unlines
        [ "0.95 p1 pattern watch <secs> seconds => fact watch.i \"<secs>\""
        , "0.95 r1 @nixos match fact watch.i => systemd.services.w.environment.S \"<value:int>\""
        , "0.95 r2 @kubenix match fact watch.i => kubernetes.resources.pods.w.spec.hostname \"\\\"<value>\\\"\"" ]
  case materializeDraft "/tmp/root" ["nixos", "kubenix"] "one.watch.lips" reply Nothing of
    Left es -> expectationFailure (show es)
    Right t -> do
      map (\(w, _, _) -> w) (dtWorlds t) `shouldBe` ["nixos", "kubenix"]
      dtGrammar t `shouldSatisfy` T.isInfixOf "lang.pattern.p1"
      [ r | ("nixos", r, _) <- dtWorlds t ] `shouldSatisfy` all (T.isInfixOf "engine.rule.r1")
      [ r | ("kubenix", r, _) <- dtWorlds t ] `shouldSatisfy` all (not . T.isInfixOf "engine.rule.r1")
```

- [ ] **Step 2:** Run; expect failures.
- [ ] **Step 3: Implement the Haskell side.** `materializeDraft` splits per world with `itemsFor`; `checkDraft` reads `LIPS_MINT_WORLDS`, writes every world's folder, and runs `checkLoose` (which discovers the worlds by looking, as it already does). The schema gate runs per world, reading `LIPS_MINT_SCHEMAS`.
- [ ] **Step 4: Implement the extension.** `assets/mint-tools.ts`: `required("LIPS_MINT_WORLDS").split(",")`, a `world` parameter on `query_options` validated against that list, and the description naming the list. `check_draft` is unchanged apart from the environment it inherits.
- [ ] **Step 5: Extend `just test-draft`** with a two-world fixture: a hand-written `watch/watch.grammar` plus `watch/nixos/` and `watch/kubenix/` rules, and a tagged draft on stdin that must be accepted; then a draft whose kubenix rule reads `<value.2>` of a one-part fact, which must be refused naming the missing part.
- [ ] **Step 6:** Suite green; `XDG_RUNTIME_DIR=/tmp just test-draft` green.
- [ ] **Step 7:** Commit: `mint tools: a lookup names the world it asks about, and a draft may cover several`

---

### Task 9: The Live Joint Mint

The only step that cannot be verified offline. It costs one model call.

**Files:**
- Modify: `examples/timer/` (a second world lands beside nixos)

- [ ] **Step 1:** `git add -A && nix build`, then
  `nix run . -- generate --target nixos,kubenix examples/nightly.timer.lips -m anthropic/claude-opus-5`.
- [ ] **Step 2: Read the result against the measurement.** Expect `timer/timer.grammar` to capture the time in parts (`<hh>:<mm>` or equivalent), `timer/nixos/` and `timer/kubenix/` both present, and each world's rules assembling its own spelling. A kubenix demand for the container image is the CORRECT outcome, not a defect: the program states no image. If that demand is unanswered, kubenix fails alone (Task 6) and nixos still lands.
- [ ] **Step 3: Answer the demand.** Add the sentence the demand asks for to `examples/nightly.timer.lips` (an image line), re-run the same generate, and confirm both worlds land.
- [ ] **Step 4: Verify the compile.** `nix run . -- compile examples/nightly.timer.lips` writes `out/nightly/nixos` and `out/nightly/kubenix`; read both `default.nix` files and confirm `OnCalendar = "*-*-* 03:00:00"` and `spec.schedule = "00 03 * * *"` (or the same two parts in cron order).
- [ ] **Step 5:** `nix flake check` (the module helper now exposes `nightly` under both `nixosModules` and `kubenixModules`).
- [ ] **Step 6:** Commit the program and the engine separately: `examples: nightly states the image its kubernetes world needs` then `examples: timer is minted for nixos and kubenix in one call`.

---

### Task 10: Docs and Ledger

**Files:**
- Modify: `README.md` (the `--target a,b` paragraph: one call, not one per world; what a tag is; that a world may demand what another does not)
- Modify: `kernel/README.md` (the module table entry for `Lips.Generate.Minting`)
- Modify: `DESIGN.md` §13 (a Done entry, and the previous entry's sequential-mint sentence corrected to point at it)
- Modify: `TODO.md` (item 0 closes to a pointer; what remains is the demand duplication and the reply-size limit)
- Modify: `AGENTS.md` (the generate line: one AI call per language, not per world)

- [ ] **Step 1:** Write the edits; run the 21 writing rules over new prose.
- [ ] **Step 2:** Commit: `docs: one mint, many worlds lands in README, ledger and TODO`
- [ ] **Step 3:** Finish: rebase on main, ff-merge, delete the worktree (finishing-a-development-branch skill).

---

## Horizon (Do Not Build Now)

1. **Demand duplication across worlds.** Two worlds needing the same fact write
   the same demand twice, and the diagnosis prints the open question once per
   world. The fix would be a shared demand, which breaks the rule that a line's
   subject prefix decides its file. Left until it hurts more than that rule.
2. **Reply size at many worlds.** Four or five worlds in one answer will strain
   output limits. The staged path (mint two, add the third against a frozen
   grammar) already exists; measure before building anything.
3. **`artifact.world`,** unchanged from the previous plan's horizon.
4. **Cross-program references** (`export.*`), unchanged.

## Self-Review Notes

- Spec coverage: the decision (T1, T2, T3, T5), the joint record (T4), the
  invention-versus-demand finding (T3 prompt, T6 per-world failure), the shared
  clobber (T7), per-world lookup and the draft signal (T8), the measurement
  reproduced live (T9).
- Deliberately excluded: computation in the value grammar (rejected in the
  spec), shared demands, gap feedback (the fallback design, only if the
  measurement ever inverts).
- Type consistency: `icWorld` (T1) is consumed by `itemsFor` (T2), which is used
  by T5's gate loop and T8's draft path; `record`'s world list (T4) is written by
  T5 and read by `readRecordedWorld`; `sharedFileViolations` (T7) is called only
  by T5's write step; `unansweredReport` (T6) only by `checkWorld`.
- The one task that cannot be verified offline is T9. Its expected outcome
  includes a REFUSAL (kubenix demanding an image), which is correct behaviour and
  must not be "fixed" in code.

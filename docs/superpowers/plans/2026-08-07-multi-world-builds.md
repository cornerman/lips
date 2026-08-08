# Multi-World Builds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One language serves several worlds: a shared grammar plus per-world rules, minted world by world, compiled into one directory per world.

**Architecture:** A language folder gains one subdirectory per world. The engine FORMAT does not change: `.lang` is already a flat list of decisions keyed by subject prefix (`lang.pattern.*` versus `engine.*`), so `<language>.grammar` and `<world>/<language>.rules` are that same list split in two and read back by concatenation. `generate --target a,b` is one lips run and two model calls, left to right; call 2 receives the committed grammar and may only append to it. `compile` loops over every minted world.

**Tech Stack:** Haskell (GHC, base+containers+text+aeson+file-embed+optparse-applicative), hspec conformance suite, Nix flakes.

**Spec:** `docs/superpowers/specs/2026-08-07-multi-world-builds-design.md`. Read it before starting. Its prerequisite (`2026-08-07-world-files-design.md`, worlds as data) is BUILT and merged; this plan continues from there.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Tests: `just test` = from `kernel/`, `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`. The app must build too: `ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/bapp -o /tmp/lips` (Spec does not import `Lips.Schema` or `app/Main.hs`, so a suite-only run can miss breakage).
- Full: `nix flake check` (module eval, artifact eval + build, VM boot, kubenix schema; needs KVM), the check-expect loop (`for p in examples/*.lips; do nix run . -- check "$p"; done`), and `just test-draft`.
- `just` fails in this sandbox with a runtime-dir permission error; run its recipes' bodies directly, or `XDG_RUNTIME_DIR=/tmp just <recipe>`.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Work in a worktree under `.worktrees/`, small single-line commits, rebase + ff-merge, no merge commits, no co-author lines.
- The kernel (`Lips.Kernel.*`) is not touched except `Lips.Kernel.Lang.Store` (untouched in fact: it already reads a concatenation) and `Lips.Generate.Record`'s stamp checking. Nothing world-specific enters the kernel.
- No compat branch: after the move there is ONE layout. The examples are migrated in the same commit that moves it.
- Comments explain why, referring only to current code.
- A record is SEALED: its bytes are never edited, so migration moves files and splits a `.lang`, and never rewrites a `.generation`.

---

### Task 0: Worktree

**Files:** none (setup).

- [ ] **Step 1:** `git worktree add .worktrees/multi-world -b multi-world`, and work there for every following task.
- [ ] **Step 2:** `cd .worktrees/multi-world/kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec` — confirm the baseline (792 examples, 0 failures) before changing anything.

---

### Task 1: `Lips.Identity` Learns the World Layer

Pure paths only; nothing reads them yet, so the tree stays green. `Lips.Identity` is the only module that may know this layout.

**Files:**
- Modify: `kernel/src/Lips/Identity.hs`
- Test: `kernel/test/Spec.hs` (the existing `Lips.Identity` describe-block; grep `langPath`)

**Interfaces (later tasks rely on these exact names):**

```haskell
worldDirIn     :: FilePath -> Text -> FilePath              -- langDir -> langDir/<world>
grammarPathIn  :: FilePath -> FilePath -> FilePath          -- langDir, program -> langDir/<language>.grammar
rulesPathIn    :: FilePath -> Text -> FilePath -> FilePath   -- langDir, world, program
expectPathIn   :: FilePath -> Text -> FilePath -> FilePath   -- CHANGED: gains the world
generationPathIn :: FilePath -> Text -> FilePath -> FilePath -- CHANGED: gains the world
readmePathIn   :: FilePath -> Text -> FilePath               -- langDir, world -> langDir/<world>/README.md
gapPathIn      :: FilePath -> Text -> FilePath -> FilePath    -- langDir, world, program
compiledPath   :: FilePath -> Text -> FilePath                -- CHANGED: out/<instance>/<world>
```

`worldPathIn :: FilePath -> Text -> FilePath` keeps today's signature (a `<name>.world` inside a given directory); a world's committed copy is `worldPathIn (worldDirIn dir w) w`. `artifactsPath`/`artifactsPathIn`, `directionPath`, `decisionsPath`, `outDir`, `langDir` are unchanged — a staged artifact tree and the crystal witness are the grammar's, not a world's.

This task is ADDITIVE ONLY. `langPath`, `expectPath`, `generationPath`, `readmePath` and `gapPath` (the no-dir variants that derive `langDir` from the program) stay untouched here and are deleted in Task 4, where their last callers move. Changing `expectPathIn`, `generationPathIn` and `compiledPath`'s signatures does break `app/Main.hs` at once, so make those two changes and fix the call sites mechanically in this task by threading the world the caller already reads from the record; the app must build before you commit.

- [ ] **Step 1: Write the failing tests.** In `Spec.hs`, find the Identity describe-block and add:

```haskell
it "puts a world's files in its own folder beside the shared grammar" $ do
  let f = "examples/ledger.backup.lips"
  grammarPathIn (langDir f) f `shouldBe` "examples/backup/backup.grammar"
  worldDirIn (langDir f) "nixos" `shouldBe` "examples/backup/nixos"
  rulesPathIn (langDir f) "nixos" f `shouldBe` "examples/backup/nixos/backup.rules"
  expectPathIn (langDir f) "nixos" f `shouldBe` "examples/backup/nixos/backup.expect"
  generationPathIn (langDir f) "nixos" f `shouldBe` "examples/backup/nixos/backup.generation"
  worldPathIn (worldDirIn (langDir f) "nixos") "nixos" `shouldBe` "examples/backup/nixos/nixos.world"
  readmePathIn (langDir f) "nixos" `shouldBe` "examples/backup/nixos/README.md"

it "keeps the grammar's own outputs world-free, and splits compiled output by world" $ do
  let f = "examples/ledger.backup.lips"
  decisionsPath f `shouldBe` "examples/backup/out/ledger.decisions"
  artifactsPath f `shouldBe` "examples/backup/artifacts"
  compiledPath f "kubenix" `shouldBe` "examples/backup/out/ledger/kubenix"
```

- [ ] **Step 2:** Run the suite; expect "not in scope" errors for the new names.
- [ ] **Step 3: Implement.** Add the functions above to `Lips.Identity`, each with a comment saying WHY it sits where it does. Two comments carry real information and must be written:
  - on `grammarPathIn`: the grammar is the language's whole cross-world contract, so it sits at the language level and every world's rules are read as a concatenation with it.
  - on `decisionsPath`: the crystal witness is the GRAMMAR's reading of a program, taken before any rule runs, so it is the same in every world and is not split by one.
- [ ] **Step 4:** Suite green, `-Wall` clean, app builds.
- [ ] **Step 5:** Commit: `identity: a language folder holds a shared grammar and one folder per world`

---

### Task 2: Which Worlds a Language Holds

Discovery, by looking: a world is a subdirectory holding this language's `.generation`. Not a list in a file, so a folder and its truth cannot disagree.

**Files:**
- Create: `kernel/src/Lips/Language.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
module Lips.Language ( mintedWorlds ) where
-- | The worlds a committed language folder holds, sorted, each a subdirectory
-- carrying this language's own .generation record.
mintedWorlds :: FilePath -> FilePath -> IO [Text]   -- langDir, program file
```

`out/` and `artifacts/` are excluded for free: neither holds a `<language>.generation`.

- [ ] **Step 1: Write the failing test** (a new describe-block `"a language's worlds (Lips.Language)"`; copy the tmp-dir idiom from the `resolution (Lips.World.Resolve)` block — `getTemporaryDirectory`, `createDirectoryIfMissing`, `removeDirectoryRecursive`):

```haskell
it "finds every world folder holding this language's record, sorted" $
  withDir (\d -> do
    createDirectoryIfMissing True (d </> "nixos")
    createDirectoryIfMissing True (d </> "kubenix")
    createDirectoryIfMissing True (d </> "out")
    createDirectoryIfMissing True (d </> "artifacts")
    TIO.writeFile (d </> "nixos" </> "backup.generation") "format: 1\n"
    TIO.writeFile (d </> "kubenix" </> "backup.generation") "format: 1\n"
    mintedWorlds d "x/ledger.backup.lips")
    `shouldReturn` ["kubenix", "nixos"]

it "finds none in a folder with no world at all" $
  withDir (\d -> mintedWorlds d "x/ledger.backup.lips") `shouldReturn` []

it "ignores a folder holding another language's record" $
  withDir (\d -> do
    createDirectoryIfMissing True (d </> "nixos")
    TIO.writeFile (d </> "nixos" </> "other.generation") "format: 1\n"
    mintedWorlds d "x/ledger.backup.lips")
    `shouldReturn` []
```

- [ ] **Step 2:** Run; expect "module Lips.Language not found".
- [ ] **Step 3: Implement.** `listDirectory`, keep entries that `doesDirectoryExist`, keep those where `doesFileExist (generationPathIn dir (T.pack e) file)`, `sort`. Module header comment: why discovery is a listing rather than a declared list (a declared list can disagree with the folder; a listing cannot).
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `language: a world is a folder holding this language's record, found by looking`

---

### Task 3: Stamps Against Several Records

Invariant 6 with one record per world: a line's `@gen:` stamp must name ONE of its language's records. Grammar lines name whichever event wrote them, rules name their own world's.

**Files:**
- Modify: `kernel/src/Lips/Generate/Record.hs` (`stampFaults`, `StampFault`, `renderStampFault`)
- Test: `kernel/test/Spec.hs` (the existing `"generation stamps (does the engine name the record beside it)"` block)

**Interfaces:**

```haskell
data StampFault
  = StaleStamp Int Text [Text]  -- ^ line, the stamp it carries, the ids actually available
  | Unstamped Int [Text]        -- ^ line, the ids available
  | OrphanStamp Int Text        -- ^ line, the stamp, with no record at all
stampFaults :: [Text] -> Text -> [StampFault]   -- ^ every record of the language, then the engine text
```

`[]` records means "no record at all" (today's `Nothing`), and then only `OrphanStamp` can fire.

- [ ] **Step 1: Write the failing tests.** Rewrite the block's cases against the new signature and add the multi-record one:

```haskell
it "accepts a line stamped by ANY of the language's records" $ do
  let recA = record "m" "nixos" "h" "s" "high" 0.7 "p" "c" "t" "a"
      recB = record "m" "kubenix" "h" "s" "high" 0.7 "p" "c" "t" "b"
      src  = T.unlines [ line 1 (" @gen:" <> genId recA)
                       , line 2 (" @gen:" <> genId recB) ]
  stampFaults [recA, recB] src `shouldBe` []

it "names what IS available when a stamp matches no record" $ do
  let recA = record "m" "nixos" "h" "s" "high" 0.7 "p" "c" "t" "a"
  stampFaults [recA] (T.unlines [line 1 " @gen:deadbeefdeadbeef"])
    `shouldBe` [StaleStamp 1 "deadbeefdeadbeef" [genId recA]]

it "still refuses a stamp where no record exists at all" $
  stampFaults [] (T.unlines [line 1 " @gen:deadbeefdeadbeef"])
    `shouldBe` [OrphanStamp 1 "deadbeefdeadbeef"]
```

(`line` is the block's existing helper; keep it.)

- [ ] **Step 2:** Run; type errors in the block.
- [ ] **Step 3: Implement.** `stampFaults recs src`: compute `ids = map genId recs`; per decision line, `Just g | g `notElem` ids -> [StaleStamp n g ids]` when `ids` is non-empty, `[OrphanStamp n g]` when empty; `Nothing` with non-empty `ids -> [Unstamped n ids]`. Update `renderStampFault` to list the available ids (`", and the records beside it hash to "` <> intercalate ", "). Update the doc comment: several records exist because a language is minted once per world.
- [ ] **Step 4:** Suite green; fix `app/Main.hs`'s `assertStamps` call to pass a one-element list for now (`maybe [] (:[]) mrec`), so the app still builds.
- [ ] **Step 5:** Commit: `record: a stamp names one of its language's records, now that a language is minted per world`

---

### Task 4: The Layout Moves

The heart, and atomic: `generate` writes the new layout, `compile`/`check` read it and loop over every minted world, and the 20 committed examples are migrated in the same commit. Splitting this would leave a commit whose writer and reader disagree.

**Files:**
- Modify: `kernel/app/Main.hs` (`loadLangOrDie`, `assertStamps`, `checkLoose`, `expectGate`, `compileLoose`, `generate`'s write step, `checkDraft`)
- Modify: `kernel/src/Lips/Generate/Draft.hs` (`DraftTree` gains the world)
- Modify: `kernel/src/Lips/Identity.hs` (delete the deprecated no-dir variants if Task 1 kept them)
- Migrate (generated, no committed script): every `examples/<language>/`
- Test: `kernel/test/Spec.hs` (the `materializeDraft` block)

**Interfaces:**

```haskell
-- Main.hs
loadLangOrDie :: FilePath -> Text -> FilePath -> IO EngineData  -- langDir, world, program
assertStamps  :: FilePath -> FilePath -> IO ()                   -- langDir, program: reads EVERY world's record
checkLoose    :: Bool -> Bool -> Maybe FilePath -> FilePath -> IO [(Text, Realization)]
  -- ^ one realization per minted world, in world order
-- Draft.hs
data DraftTree = DraftTree { dtLangDir :: FilePath, dtWorld :: Text, dtGrammar :: Text
                           , dtRules :: Text, dtExpect :: Text, dtSources :: [SourceFile] }
materializeDraft :: FilePath -> Text -> FilePath -> Text -> Maybe Text -> Either [Text] DraftTree
  -- ^ root, world, program, reply, governing contract
```

`loadLangOrDie dir w file` reads `grammarPathIn dir file` and `rulesPathIn dir w file` and calls `readLang` on `grammar <> rules`. A missing grammar names `generate`; a missing rules file names the world (`lips generate --target <w> <program>`).

- [ ] **Step 1: Write the failing test** for the draft split (find the existing `materializeDraft` cases and add):

```haskell
it "materializes a draft as a shared grammar plus one world's rules" $ do
  let reply = T.unlines
        [ "0.95 p1 pattern watch <secs> seconds => fact watch.i \"<secs>\""
        , "0.95 r1 match fact watch.i => systemd.services.w.environment.S \"<value:int>\"" ]
  case materializeDraft "/tmp/root" "nixos" "one.watch.lips" reply Nothing of
    Left es -> expectationFailure (show es)
    Right t -> do
      dtWorld t `shouldBe` "nixos"
      dtGrammar t `shouldSatisfy` T.isInfixOf "lang.pattern.p1"
      dtGrammar t `shouldNotSatisfy` T.isInfixOf "engine.rule.r1"
      dtRules t `shouldSatisfy` T.isInfixOf "engine.rule.r1"
      dtRules t `shouldNotSatisfy` T.isInfixOf "lang.pattern.p1"
```

- [ ] **Step 2:** Run; expect failures (`dtWorld`/`dtGrammar`/`dtRules` not in scope).
- [ ] **Step 3: Split the rendered engine.** In `Lips.Generate.Draft`, render the engine once with `renderLang` as today, then split its LINES by subject: field 3 (whitespace-separated) starting with `lang.` goes to `dtGrammar`, everything else to `dtRules`. Write one helper, exported, because Task 4's generate path and the migration both need the same rule:

```haskell
-- | Split a rendered engine into the shared grammar (the pattern lines) and one
-- world's rules. The subject prefix already carries the split -- lang.* is the
-- language, engine.* is its lowering into a world -- so this is a partition of
-- the same canonical text, and readLang reads the two back by concatenation.
splitEngine :: Text -> (Text, Text)
```

- [ ] **Step 4:** Suite green for the draft block.
- [ ] **Step 5: Move the readers.** In `Main.hs`:
  - `assertStamps dir file`: `ws <- mintedWorlds dir file`; read every `generationPathIn dir w file` (an existing-but-unreadable record still dies as today); read grammar and every world's rules; call `stampFaults recs (grammar <> T.concat rules)`.
  - `checkLoose contract claims mLangDir file`: resolve `dir`, `ws <- mintedWorlds dir file`; die naming `generate` when `ws` is empty; for each `w`, `loadLangOrDie dir w file` then `expectGate` with `expectPathIn dir w file`, and return `[(w, rl)]`.
  - The whole body loops, diagnosis included, and each world's output gets a heading naming it. This looks like duplicated output and is not: `diagnose` reads `edDemands` (a world's own demands) and the inert-word report reads `edRules`, so a line that is answered in one world and open in another must say so twice. Only the pattern-matching half of each diagnosis is shared, and that is the half a reader compares between the two.
  - `engineViolations eng` likewise runs per world, over that world's grammar+rules pair, which is exactly the engine that world realizes with.
  - `expectGate` gains the world (for `expectPathIn` and for `claimGate`, which already takes a `World` — read it with `readRecordedWorld dir w file`).
  - `readRecordedWorld` gains the world name: it reads `generationPathIn dir w file` and the copy at `worldPathIn (worldDirIn dir w) w`; the name in the record must equal `w` (they cannot disagree: the folder is named after the record's world), so keep the hash check and drop nothing else.
- [ ] **Step 6: Move compile.** `compileLoose` loops: for each `(w, rl)` from `checkLoose`, write `compiledPath file w` (or `mout </> T.unpack w` when `--out` is given — an explicit out dir still splits by world, or two worlds would overwrite one another), and print each world's rungs under a heading naming the world.
- [ ] **Step 7: Move generate's write step.** Write `grammarPathIn dir file` (the grammar half of `splitEngine`), then under `worldDirIn dir w`: `rulesPathIn` (the rules half), `expectPathIn`, `generationPathIn`, `worldPathIn (worldDirIn dir w) w`, `readmePathIn dir w`. The refusal artifact moves with them, `gapPathIn dir w file`: a refusal is one world's mint failing, not the language's. `artifacts/` and `out/` stay at the language level. Delete `langPath`, `expectPath`, `generationPath`, `readmePath` and `gapPath` from `Lips.Identity` once this step's call sites are moved, and update the closing summary lines (grep `the language, ` in `Main.hs`) to name the grammar, the world's rules and the world's contract separately.
- [ ] **Step 8: Migrate the examples.** Build the binary (`git add -A && nix build`), then run the one-off inline:

```bash
for g in examples/*/*.lang; do
  d=$(dirname "$g"); lang=$(basename "$g" .lang)
  w=$(awk '/^world: /{print $2; exit}' "$d/$lang.generation")
  [ -z "$w" ] && w=$(awk '/^target: /{print $2; exit}' "$d/$lang.generation")
  [ -z "$w" ] && w=nixos
  mkdir -p "$d/$w"
  awk '$3 ~ /^lang\./' "$g" > "$d/$lang.grammar"
  awk '$3 !~ /^lang\./' "$g" > "$d/$w/$lang.rules"
  git mv "$d/$lang.expect" "$d/$w/$lang.expect"
  git mv "$d/$lang.generation" "$d/$w/$lang.generation"
  git mv "$d/$w.world" "$d/$w/$w.world"
  [ -f "$d/README.md" ] && git mv "$d/README.md" "$d/$w/README.md"
  git rm -q "$g"
done
```

Then verify the split lost nothing: `cat examples/*/*.grammar examples/*/*/*.rules | wc -l` must equal the pre-migration `.lang` line count (record it before running the loop with `cat examples/*/*.lang | wc -l`).

- [ ] **Step 9: Move the draft path.** `checkDraft` reads `LIPS_MINT_WORLD`, passes it to `materializeDraft`, writes grammar + `<world>/rules` + `<world>/expect`, and points `checkLoose` at `dtLangDir`.
- [ ] **Step 10:** Suite green, `-Wall` clean, app builds. Then the offline gate over every example: `for p in examples/*.lips; do nix run . -- check "$p" || echo FAIL $p; done` (`git add -A` first).
- [ ] **Step 11:** Commit: `layout: a language's rules, contract and record move into its world's folder`

---

### Task 5: A World That Does Not Hold Stops Only Itself

A program can crystallize (the shared grammar reads it) and land nowhere in one world's rules. Today that kills the whole run; with several worlds it must kill only the world it is true of.

**Files:**
- Modify: `kernel/app/Main.hs` (`checkLoose`'s loop, `compileLoose`'s loop)
- Modify: `kernel/src/Lips/Report.hs` (the message)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `Lips.Report.unportableReport :: FilePath -> Text -> [Decision] -> Text` — program, world, the unmapped ground decisions (the `Unmapped ds` payload of `Lips.Kernel.Run.RunError`). It renders each as `loc d <> ": " <> niceSubject (dSubject d)`, the same two helpers `failureReport`'s existing `Unmapped` arm uses, so one defect keeps one voice.
- `checkLoose` returns `[(Text, Either Text Realization)]`: `Left` is that world's refusal text, already rendered.

**Why a new message rather than the existing one:** `Lips.Report.failureReport`'s `Unmapped` arm says "asks for things its setup can't do" and `printFail` appends "→ rebuild the setup: lips generate <program>". With one world that is right. With several it is false: re-minting nixos cannot make a kubenix-only line land in nixos, and following that remedy burns a model call to learn nothing. The `Unmapped` arm stays for the single-world path; the multi-world loop uses the new one.

- [ ] **Step 1: Write the failing test** (`Lips.Report` is pure, so the message is testable inline):

```haskell
it "names the world a program does not reach, not the program" $ do
  let t = unportableReport "api.web.lips" "nixos" ["services.thing.enable"]
  t `shouldSatisfy` T.isInfixOf "world nixos"
  t `shouldSatisfy` T.isInfixOf "services.thing.enable"
  -- it must NOT send the reader to generate: re-minting nixos cannot make a
  -- kubenix-only line land there.
  t `shouldNotSatisfy` T.isInfixOf "lips generate"
```

- [ ] **Step 2:** Run; expect "not in scope: unportableReport".
- [ ] **Step 3: Implement.** Add `unportableReport` to `Lips.Report`'s export list, worded as the spec's decisive argument: the language READS these lines and they land nowhere in this world, so the program is not portable to it; the remedy is to compile the world it is for (`lips compile --target <other>`), or to state the placement this world needs. In `Main.hs`'s per-world loop, match `FailRun (Unmapped ds)` before the generic `printFail` and turn it into `Left (unportableReport file w ds)` for that world, then keep going. Every other failure stays fatal for the whole run: a conflict or an unanswered demand is a fact about the PROGRAM, true in every world, so reporting it once per world would repeat one defect N times.
- [ ] **Step 4: Wire the outcome.** compile writes every world that returned `Right`, prints each failing world's report, and exits nonzero when any failed (a plain `exitWith (ExitFailure 1)` after the reports, so the written output still stands). Same rule for `check`. Comment at the exit: writing what holds and still failing is deliberate — you get the artifact you can have, and CI cannot mistake a non-portable program for a portable one.
- [ ] **Step 5:** Suite green.
- [ ] **Step 6:** Commit: `compile: a world that does not hold fails alone, naming itself`

---

### Task 6: `--target a,b` Mints World by World

**Files:**
- Modify: `kernel/src/Lips/Cli.hs` (`goTarget :: [Text]`, a comma-separated reader)
- Modify: `kernel/app/Main.hs` (`generate` loops over worlds; the append-only guard)
- Modify: `kernel/assets/mint/body.md` (the appending instruction)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `Lips.Cli.goTarget :: [Text]` — `--target nixos,kubenix` splits on commas, order preserved, duplicates refused by the parser naming the repeat.
- `Lips.Generate.Minting.appendOnlyViolations :: Text -> Text -> [Text]` — committed grammar, newly minted grammar; the ids of pattern lines that were changed or dropped. Byte-identity, stamps included: appending world 2 never touches world 1's record, so its lines keep their stamps.

- [ ] **Step 1: Write the failing tests:**

```haskell
it "reads a comma-separated world list, in order, and refuses a repeat" $ do
  let parseArgs = getParseResult . execParserPure defaultPrefs (info (generateOpts 0.7) idm)
  fmap goTarget (parseArgs ["--target", "nixos,kubenix", "a.web.lips"])
    `shouldBe` Just ["nixos", "kubenix"]
  parseArgs ["--target", "nixos,nixos", "a.web.lips"] `shouldBe` Nothing

it "accepts an appended pattern and refuses a changed or dropped one" $ do
  let old = T.unlines [ "p1 meta lang.pattern.p1 stated \"a <x> => fact f \\\"<x>\\\"\" @gen:aaaa"
                      , "p2 meta lang.pattern.p2 stated \"b <y> => fact g \\\"<y>\\\"\" @gen:aaaa" ]
      addP3 = old <> "p3 meta lang.pattern.p3 stated \"c <z> => fact h \\\"<z>\\\"\" @gen:bbbb\n"
      changed = T.replace "a <x>" "a <x> now" old
      dropped = T.unlines (take 1 (T.lines old))
  appendOnlyViolations old addP3 `shouldBe` []
  appendOnlyViolations old changed `shouldBe` ["p1"]
  appendOnlyViolations old dropped `shouldBe` ["p2"]
```

- [ ] **Step 2:** Run; expect failures.
- [ ] **Step 3: Implement the reader.** In `Cli.hs`, `--target` becomes `T.splitOn "," . T.pack`, trimmed, empty entries refused; a repeated name is an `eitherReader` failure naming it. Every caller of `goTarget` in `Main.hs` takes the head for now.
- [ ] **Step 4: Implement the guard.** In `Minting.hs`, `appendOnlyViolations` keys both texts' lines by their id (field 1) and returns the ids whose line text differs or is absent from the new text. Doc comment: why byte-identity is the right guard and why it is achievable (world 1's record is untouched, so its stamps do not move).
- [ ] **Step 5: Loop the mint.** In `generate`, for each world in order: resolve it (`resolveWorldOrDie`), build its schema, run the mint, run every gate, write that world's folder. From the SECOND world on:
  - the prompt carries the committed grammar and the instruction to reuse it (Step 6);
  - after parsing the reply, run `appendOnlyViolations` against the committed grammar and die naming the changed ids plus the remedy (`re-mint every world together: lips generate --target <all>,<new> --compat <mode>`);
  - the grammar written is the committed one plus the new lines, so world 1's lines keep their bytes.
- [ ] **Step 6: Tell the mint.** Add a section to `assets/mint/body.md`, gated on a `{{GRAMMAR}}` substitution that is empty on a first mint: when a grammar is given, its pattern lines must come back exactly, new patterns may be added, and a pattern that must change is a refusal with a gap naming it. Substitute it in `promptWithDirection` beside `{{CONTRACTS}}`.
- [ ] **Step 7:** Suite green; `just test-draft`.
- [ ] **Step 8: Prove it end to end** with one real mint (this costs a model call and is the task's actual verification): pick `examples/nightly.timer.lips` (nixos, small, no artifacts) and run `nix run . -- generate --target nixos,kubenix examples/nightly.timer.lips -m anthropic/claude-opus-5`. Expected: `timer/timer.grammar` unchanged where it overlaps, `timer/kubenix/` created with rules, expect, record and `kubenix.world`. Then `nix run . -- compile examples/nightly.timer.lips` writes both `out/nightly/nixos/` and `out/nightly/kubenix/`. If the mint refuses, read its `.gap`: a refusal naming a pattern it cannot reuse is the guard WORKING, and the remedy is a joint re-mint, not a code change.
- [ ] **Step 9:** Commit the code and the new engine separately: `generate: --target a,b mints world by world, appending to the shared grammar` then `examples: nightly is minted for kubenix beside nixos`

---

### Task 7: Deploy and the Flake Checks Read the World Layout

**Files:**
- Modify: `nix/modulesFromDir.nix`
- Modify: `flake.nix` (the three checks that stage a language by hand: `vm-smoke`, the artifact checks, `nginx-vm` — grep `\.generation`)

- [ ] **Step 1: Implement `modulesFromDir`.** For each language, list its subdirectories holding `<language>.generation` (the Nix twin of `mintedWorlds`: `builtins.readDir`, filter `"directory"`, filter `pathExists`). For each `(instance, world)` pair, read that world's `module-attr:` from `<world>/<world>.world` and compile with `--target <world>`, so one instance appears under every world it was minted for. The realize derivation stages: the program, `<language>.grammar`, `<world>/<language>.rules`, `<world>/<language>.generation`, `<world>/<world>.world`, and `artifacts/` when present.
- [ ] **Step 2: Implement the flake checks.** Each hand-staged check copies the same five paths for its one world (`examples/backup/nixos/...`), mirroring the migration.
- [ ] **Step 3:** `git add -A && nix build --no-link .#checks.x86_64-linux.lipsModules-eval` — expect PASS. Then `nix flake check` in full.
- [ ] **Step 4:** Commit: `deploy: one instance appears under every world it was minted for`

---

### Task 8: Docs and Ledger

**Files:**
- Modify: `README.md` (The Files table gains `<language>.grammar` and the world folder; the `--target` paragraph gains the comma form and what compile writes per world)
- Modify: `kernel/README.md` (the module table gains `Lips.Language`)
- Modify: `DESIGN.md` §13 (new Done entry) and the `README.md` line the spec supersedes ("Nothing translates between worlds")
- Modify: `TODO.md` (the multi-world item closes to a pointer; `artifact.world` and cross-program references become the named next steps)

- [ ] **Step 1:** Write the edits; run the 21 writing rules over new prose.
- [ ] **Step 2:** Commit: `docs: one program, several worlds lands in README, ledger and TODO`
- [ ] **Step 3:** Finish: rebase on main, ff-merge, delete the worktree (finishing-a-development-branch skill).

---

## Horizon (Do Not Build Now)

1. `artifact.world`, the world-free world. Blocked on one decision: the world file format REQUIRES a `schema` slot, and a world with no options has none — so either the slot becomes optional and grounding admits only `artifact.*`/`site.*`/`claim.*` subjects, or the world declares an empty schema and grounding refuses everything. Decide before planning.
2. Cross-program references: `export.*` and `${program.<instance>.<path>}`, plus the derived-hash value form the GitOps section of the spec fixes as the requirement. Needs the foreign-derivation naming question in `TODO.md` answered first.
3. A per-world `.direction` (house convention shared by every language in a world), already in `TODO.md`.
4. Demand duplication across worlds — left as duplication until it hurts, by the spec.

## Self-Review Notes

- Spec coverage: §1 grammar as contract (T1, T4), §2 append-only (T6), §3 `--target a,b` (T6), §4 compile every backend (T4 step 6, T5), §5 `artifact.world` (horizon, deliberately excluded), the middle-layer note (prose, no task), the seam and GitOps sections (horizon item 2). Migration, named as undecided in the spec, is T4 step 8.
- Deliberately excluded: a world-neutral vocabulary (the spec forbids it), per-world demands deduplication, `artifact.world`.
- Type consistency: `mintedWorlds` (T2) is used by T4, T5 and mirrored in Nix by T7; `stampFaults :: [Text] -> Text -> [StampFault]` (T3) is called only by `assertStamps` (T4); `splitEngine` (T4) is used by the draft path and generate's write step; `appendOnlyViolations` (T6) only by generate; `unportableReport` (T5) only by the compile/check loop.
- The one task that cannot be verified offline is T6 step 8 (a real mint). Its failure mode is documented as a working guard rather than a defect, so an executor does not "fix" the code to make a refusal go away.

# A World That Ignores A Fact — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A world may declare, with a reason, a fact it cannot place, so a program may state something only some of its worlds need.

**Architecture:** One closed grammar arm. A world's rules gain `ignore <kind> <subject> "<reason>"`, stored as `engine.ignore.<id>`; `runGround` treats an ignored ground decision as placed. The guard that keeps it honest is cross-world and lives in the shell: a world may ignore a fact only if some other world of the language places it, checked at mint time AND offline in `check`.

**Tech Stack:** Haskell (GHC, base+containers+text), hspec conformance suite, Nix flakes.

**Spec:** `docs/superpowers/specs/2026-08-09-a-world-that-ignores-design.md`. Read it first; it carries the measurement and the four rejected alternatives.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Fast test: from `kernel/`, `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`. The app builds separately: `ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/bapp -o /tmp/lips`.
- Full: `nix flake check`, `for p in examples/*.lips; do nix run . -- check "$p"; done`, `XDG_RUNTIME_DIR=/tmp just test-draft`.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Worktree under `.worktrees/`, small single-line commits, rebase + ff-merge.
- This plan DOES touch the kernel, deliberately and minimally: one closed arm in the engine grammar (`Lips.Kernel.Engine.Data`, `Lips.Kernel.Lang.Store`) and one clause in `Lips.Kernel.Run`. The kernel gains no knowledge of any domain, any world or any option: an ignore is `<kind> <subject> "<reason>"` and nothing else.
- Every committed engine must keep reading and compiling byte-identically: an engine with no ignore declaration behaves exactly as today.

---

### Task 0: Worktree and Baseline

- [ ] **Step 1:** `git worktree add .worktrees/ignore -b ignore`, work there.
- [ ] **Step 2:** From `kernel/`, run the suite: 828 examples, 0 failures.

---

### Task 1: The Declaration, In The Engine Format

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Data.hs` (`IgnoreSpec`, `parseIgnoreBody`, `renderIgnoreBody`)
- Modify: `kernel/src/Lips/Kernel/Lang/Store.hs` (`EngineData.edIgnores`, `EngLine`, `classify`, `renderLang`, `ignoreToDecision`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- Engine/Data.hs, beside DemandSpec, which it mirrors exactly.
data IgnoreSpec = IgnoreSpec
  { igId      :: Text
  , igKind    :: Kind
  , igSubject :: [Text]
  , igReason  :: Text
  }
  deriving (Eq, Show)

parseIgnoreBody  :: Text -> Text -> Either Text IgnoreSpec  -- id, body
renderIgnoreBody :: IgnoreSpec -> Text

-- Lang/Store.hs
edIgnores :: EngineData -> [IgnoreSpec]
```

Body grammar: `ignore <kind> <subject> "<reason>"`. The kind is read with the
existing `parseKindTok` (so the closed kind table decides what may be ignored),
the subject with `splitAttrPath` (so a family `pkg.<name>` works exactly as in a
rule), the reason with `parseQuoted`. Stored subject: `engine.ignore.<id>`.

- [ ] **Step 1: Write the failing tests:**

```haskell
it "round-trips an ignore declaration through .lang" $ do
  let src = "i1 meta engine.ignore.i1 stated \"ignore fact job.image \\\"no image on a machine\\\"\"\n"
  case readLang src of
    Left es  -> expectationFailure (show es)
    Right ed -> do
      map igId (edIgnores ed) `shouldBe` ["i1"]
      map igSubject (edIgnores ed) `shouldBe` [["job", "image"]]
      map igReason (edIgnores ed) `shouldBe` ["no image on a machine"]
      renderLang (FromSource (SourceLoc "lang" 0)) ed `shouldSatisfy` T.isInfixOf "engine.ignore.i1"

it "refuses an ignore with no reason, which is the whole point of writing it" $
  parseIgnoreBody "i1" "ignore fact job.image" `shouldSatisfy` isLeft
```

- [ ] **Step 2:** Run; expect "not in scope".
- [ ] **Step 3: Implement**, mirroring `DemandSpec`'s three functions and adding
  the `classify` arm plus the `renderLang` group (sorted by `igId`, after the
  merges). Update `classify`'s catch-all message to name `engine.ignore.*`.
  Doc comment on `IgnoreSpec`: why the reason is required (it is the artifact a
  human reviews; a declaration without one is a silent drop with extra steps).
- [ ] **Step 4:** Suite green, `-Wall` clean, app builds.
- [ ] **Step 5:** Commit: `engine: a world may declare a fact it cannot place`

---

### Task 2: An Ignored Decision Counts As Placed

**Files:**
- Modify: `kernel/src/Lips/Kernel/Run.hs` (`runGround`, and the caller's argument list)
- Modify: `kernel/app/Main.hs` (`validate` passes the ignores)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- Run.hs: the ignore set joins the rules and demands the runner is given.
runBase :: (Subject -> MergeMode) -> ([Value] -> Either Text Value) -> Vocabulary
        -> Int -> [Rule] -> [Demand] -> [IgnoreSpec] -> Base -> Either RunError [Decision]
```

In `runGround`, after refinement:

```haskell
  let placed d = any (\ig -> igKind ig == dKind d
                              && isJust (matchSubject (igSubject ig) (subjSegs (dSubject d)))) ignores
      realizable = filter (\d -> dKind d /= Concept && not (placed d)) (toList ground)
```

so an ignored decision is neither realized nor reported `Unmapped`. Matched with
`matchSubject`, so a family declaration covers every concrete member, exactly as
a rule or a demand does.

- [ ] **Step 1: Write the failing test** (in the run/realize block, using the
  existing `engineFromLang` helper):

```haskell
it "an ignored fact is placed, and does not reach the module" $ do
  let eng = engineFromLang
        [ "p1 meta lang.pattern.p1 stated \"image <img> => fact job.image \\\"<img>\\\"\""
        , "p2 meta lang.pattern.p2 stated \"name <n> => fact job.name \\\"<n>\\\"\""
        , "r1 meta engine.rule.r1 stated \"match fact job.name => systemd.services.j.description \\\"\\\\\\\"<value>\\\\\\\"\\\"\""
        , "i1 meta engine.ignore.i1 stated \"ignore fact job.image \\\"a machine runs it directly\\\"\"" ]
  -- the program states both lines; only the name reaches an option
  runProgram eng "image busybox\nname cleanup\n" `shouldSatisfy` isRight

it "an unignored fact with no rule is still unmapped" $ do
  let eng = engineFromLang
        [ "p1 meta lang.pattern.p1 stated \"image <img> => fact job.image \\\"<img>\\\"\"" ]
  runProgram eng "image busybox\n" `shouldSatisfy` isLeft
```

(`runProgram` is a local helper in that block: crystallize, then `runBase` with
the engine's rules, demands and ignores. If no such helper exists, write it
beside the test and reuse the argument shapes from `app/Main.hs`'s `validate`.)

- [ ] **Step 2:** Run; expect the first test to fail with `Unmapped`.
- [ ] **Step 3: Implement.** Thread `[IgnoreSpec]` into `runBase`/`runGround`;
  the comment at the filter says why an ignored decision is dropped rather than
  realized (it names no option; it is a fact this lowering has no place for).
- [ ] **Step 4:** Suite green; app builds.
- [ ] **Step 5:** Commit: `run: a fact a world declares it cannot place is not unmapped`

---

### Task 3: One Way To Say It (A Rule May Not Match A Concept)

Verified 2026-08-09: a rule matching a `concept` realizes it today, and a world
without such a rule is not refused, so this is a second, UNGUARDED way to express
the same asymmetry. With `ignore` in the grammar it must close, or the mint will
find the unguarded one. No committed engine matches a concept.

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Data.hs` (`parseRuleBody`)
- Test: `kernel/test/Spec.hs`

- [ ] **Step 1: Write the failing test:**

```haskell
it "refuses a rule that matches a concept, which realizes nothing by definition" $
  case parseRuleBody "r1" "match concept job.image => a.b \"<value:int>\"" of
    Right _  -> expectationFailure "a concept-matching rule must be refused"
    Left msg -> do
      msg `shouldSatisfy` T.isInfixOf "concept"
      msg `shouldSatisfy` T.isInfixOf "ignore"
```

- [ ] **Step 2:** Run; expect it to parse cleanly (the failure).
- [ ] **Step 3: Implement.** In `parseRuleBody`, refuse `Concept` on the match
  side, naming the two honest shapes: make it a `fact` and let the worlds that
  cannot place it declare `ignore`, or leave it a concept everywhere.
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `engine: a rule may not match a concept, so an asymmetry has one shape`

---

### Task 4: The Guard — Ignored Here, Placed Somewhere

**Files:**
- Modify: `kernel/src/Lips/Language.hs` (pure cross-world gate)
- Modify: `kernel/app/Main.hs` (`checkLoose` and `generate` call it)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- | The ignore declarations no world of the language places: (world, id,
-- subject). Empty is the sound case. A fact NOBODY places is the old refusal --
-- the language reads a word and discards it -- and `ignore` must not launder it.
orphanIgnores :: [(Text, EngineData)] -> [(Text, Text, Text)]
```

A subject is placed when some world's rules have a rule whose match side unifies
with it (`matchSubject` both ways, so a family placed by a family counts).

- [ ] **Step 1: Write the failing tests:**

```haskell
it "accepts an ignore whose fact another world places" $ do
  let nixos   = engineFromLang [ "i1 meta engine.ignore.i1 stated \"ignore fact job.image \\\"no image\\\"\"" ]
      kubenix = engineFromLang [ "r1 meta engine.rule.r1 stated \"match fact job.image => a.b \\\"\\\\\\\"<value>\\\\\\\"\\\"\"" ]
  orphanIgnores [("nixos", nixos), ("kubenix", kubenix)] `shouldBe` []

it "refuses an ignore no world places, naming the world and the subject" $ do
  let nixos = engineFromLang [ "i1 meta engine.ignore.i1 stated \"ignore fact job.image \\\"no image\\\"\"" ]
  orphanIgnores [("nixos", nixos)] `shouldBe` [("nixos", "i1", "job.image")]
```

- [ ] **Step 2:** Run; expect "not in scope".
- [ ] **Step 3: Implement** the pure function, with the module comment saying why
  it lives here (it is a property OF A LANGUAGE across its worlds, which no
  single engine can judge, and which only exists as a check because one call
  writes every world).
- [ ] **Step 4: Wire it.** `checkLoose` already loads every world's engine: run
  the gate once over them and die naming the remedy (place the fact in the world
  that needs it, or drop the line from the program). `generate` runs the same
  gate over the reply's per-world engines plus the committed engines of worlds it
  is not re-minting, so a joint mint and a single-world mint are held to the same
  rule.
- [ ] **Step 5:** Suite green; every example still checks.
- [ ] **Step 6:** Commit: `language: a world may ignore a fact only if another world places it`

---

### Task 5: The Mint Learns To Write One

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`EngineItem`, `parseLine`, `assemble`, `carriesEngineMeaning`)
- Modify: `assets/mint/worlds.md`
- Test: `kernel/test/Spec.hs`

**Interfaces:** `EngineItem` gains `ItemIgnore IgnoreSpec`; `parseLine`'s keyword
table gains `"ignore"`; `assemble` fills `edIgnores`; `carriesEngineMeaning`
returns `True` for it (it is engine meaning, so a low-confidence one is refused
like any other). It is WORLD-BOUND: an untagged ignore in a several-world reply
is the same error a rule gets.

`assets/mint/worlds.md` gains the rule, after the demand rule:

- where a world cannot place a fact ANOTHER world needs, declare it with the
  reason, and never leave it silent;
- you may not ignore a fact no world places: that fact is dead, and lips refuses
  the language for reading a word and discarding it;
- prefer a fact both worlds can spend over an asymmetry: an image is genuinely
  one world's, a schedule is not.

- [ ] **Step 1: Write the failing test:**

```haskell
it "reads a world-bound ignore item" $ do
  let (errs, cs) = parseEngineCandidates ["nixos", "kubenix"]
        "0.9 i1 @nixos ignore fact job.image \"a machine runs the script directly\"\n"
  errs `shouldBe` []
  map icWorld cs `shouldBe` [Just "nixos"]
  length (edIgnores (assemble (itemsFor "nixos" cs))) `shouldBe` 1
  edIgnores (assemble (itemsFor "kubenix" cs)) `shouldBe` []

it "tells a multi-world mint to declare an asymmetry, and never to launder a dead fact" $ do
  let p = systemPromptFor [shippedWorld "nixos", shippedWorld "kubenix"]
  mapM_ (\c -> p `shouldSatisfy` T.isInfixOf c)
    [ "ignore fact", "you may not ignore a fact no world places" ]
```

- [ ] **Step 2:** Run; expect failures.
- [ ] **Step 3: Implement** the item kind and the prompt section.
- [ ] **Step 4:** Suite green; `just test-draft` green.
- [ ] **Step 5:** Commit: `mint: a world declares what it cannot place, and may not launder a dead fact`

---

### Task 6: Every Run Says What A World Ignores

**Files:**
- Modify: `kernel/app/Main.hs` (`checkWorld`, and `gateOneWorld` for symmetry)
- Test: covered by the live run in Task 7 (the line is one `note`)

- [ ] **Step 1: Implement.** After the grounding line, when a world's engine
  carries ignores, print one note per declaration: `nixos ignores job.image: a
  machine runs the script directly`. Comment: overuse must be visible on every
  run, not only to a reviewer who opens the rules file.
- [ ] **Step 2:** `-Wall` clean; every example still checks (none declares an
  ignore, so their output is unchanged).
- [ ] **Step 3:** Commit: `check: a world says which facts it ignores, and why`

---

### Task 7: The Live Proof

- [ ] **Step 1:** Add the sentence the kubenix mint asked for to
  `examples/nightly.timer.lips` (the container image), keeping the program in its
  own voice.
- [ ] **Step 2:** `git add -A && nix build`, then
  `nix run . -- generate --target nixos,kubenix examples/nightly.timer.lips -m anthropic/claude-opus-5`.
- [ ] **Step 3: Read the result.** Expect the shared grammar to capture the time
  in parts and the image as a fact; `timer/kubenix/timer.rules` to place the
  image; `timer/nixos/timer.rules` to carry an `ignore` for it with a reason. A
  mint that instead invents a nixos use for the image is a defect worth reading
  the report over.
- [ ] **Step 4:** `nix run . -- compile examples/nightly.timer.lips` writes both
  worlds; confirm `OnCalendar = "*-*-* 03:00:00"`, `spec.schedule = "00 03 * * *"`
  and the image in the kubenix module only.
- [ ] **Step 5:** `nix flake check`.
- [ ] **Step 6:** Commit: `examples: nightly states the image its kubernetes world needs`
  then `examples: timer is minted for nixos and kubenix in one call`.

---

### Task 8: Docs and Ledger

- [ ] **Step 1:** `README.md` (the multi-world paragraph gains the asymmetry rule),
  `kernel/README.md` (the `Lips.Kernel.Run` and `Lips.Language` rows),
  `DESIGN.md` §13 (a Done entry), `TODO.md` (item 0 closes to a pointer).
- [ ] **Step 2:** Commit: `docs: a world that ignores a fact lands in README, ledger and TODO`
- [ ] **Step 3:** Finish: rebase on main, ff-merge, delete the worktree.

## Horizon (Do Not Build Now)

1. **A count in the grounding line.** The ignore notes are separate lines today;
   folding them into `groundingReport`'s vouching classes would put them in the
   one summary a reviewer already reads. Needs a fifth class, so it waits for a
   second reason to touch that line.
2. **Demand duplication** and **reply size at many worlds**, unchanged from
   `TODO.md`'s backlog.

## Self-Review Notes

- Spec coverage: the declaration (T1), the kernel semantics (T2), one-shape
  (T3), the guard (T4), the mint (T5), visibility (T6), the measurement
  reproduced live (T7).
- Type consistency: `IgnoreSpec` (T1) is consumed by `runBase` (T2),
  `orphanIgnores` (T4), `assemble`/`itemsFor` (T5) and the notes (T6). `edIgnores`
  is the one accessor all of them read.
- The only step that cannot be verified offline is T7. A kubenix mint DEMANDING
  the image again (rather than reading the new sentence) is a prompt problem, not
  a code problem, and the fix is in `worlds.md`.

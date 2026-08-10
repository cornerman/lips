# A Contract Over A Reformatted Value — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A contract can assert an option whose text a rule ASSEMBLES from a fact's parts, so a program stating `03:00` can be gated in a world that spells it `*-*-* 03:00:00`.

**Architecture:** One new arm of the contract grammar. `expect <path> from <subject> is "<template>"` fills `<value>`/`<value.N>` from the fact and compares the option's realized text for EQUALITY; the existing form (no template) keeps comparing by containment. The unholdable whole-value expect is then refused by the engine gate, naming this form as the remedy, so the mint meets the rule inside its own call.

**Tech Stack:** Haskell (GHC, base+containers+text), hspec conformance suite, Nix flakes.

**Design:** opened as `TODO.md` item 0 on 2026-08-09 after three live mints refused to write a contract over a reformatted value, the third filing the gap `expect-cannot-assert-a-reformatted-value` itself. The mint's objection is sound: `contains "03"` also passes for text that merely happens to contain `03`.

**Why a template contract is not vacuous** (the objection to answer first): it restates what the rule assembles, and asserting a rule against itself would falsify nothing WITHIN one mint. The point of `.expect` is REGENERATION. The contract mint 1 wrote gates mint 2's engine, so a later mint that drops the seconds, reorders the fields or changes the separator is refused. That is the same argument `--compat` rests on, and it is exactly what part-containment only gestures at.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Fast test: from `kernel/`, `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`; the app builds separately with `-iapp app/Main.hs`.
- Full: `nix flake check`, `for p in examples/*.lips; do nix run . -- check "$p"; done`, `XDG_RUNTIME_DIR=/tmp just test-draft`.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Worktree under `.worktrees/`, small single-line commits, rebase + ff-merge.
- Every committed `.expect` must keep reading and holding unchanged: the new arm is optional, and an expect without a template behaves exactly as today (containment).
- `-t` is repeatable (`-t nixos -t kubenix`); there is no comma form.

---

### Task 0: Worktree and Baseline

- [ ] **Step 1:** `git worktree add .worktrees/contract -b contract`, work there.
- [ ] **Step 2:** From `kernel/`, run the suite: 838 examples, 0 failures.

---

### Task 1: The Template Arm Of The Contract

**Files:**
- Modify: `kernel/src/Lips/Kernel/Surface.hs` (`fillValueHoles`)
- Modify: `kernel/src/Lips/Kernel/Expect.hs` (`Expect`, `parseExpectBody`, `renderExpect`, `expectedValue`, `checkValues`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- Surface.hs, beside valueText/valueTokens, which already own what a PART is.
-- | Fill <value> and <value.N> in a template from a stated value. A hole naming
-- a part that is not there is a Left, so a template can never silently produce
-- half a string.
fillValueHoles :: Text -> Text -> Either Text Text   -- template, stated value

-- Expect.hs
data Expect = Expect
  { exId       :: Text
  , exPath     :: [Text]
  , exFrom     :: Subject
  , exToken    :: Maybe Int
  , exTemplate :: Maybe Text   -- ^ NEW: the whole text, with <value>/<value.N>
  }
```

Grammar: `expect <path> from <subject> is "<template>"`. Read `is` as a
keyword after the from-token; without it the expect is exactly today's.
`renderExpect` appends ` is "<template>"` when present, so a committed contract
round-trips.

Comparison, in `checkValues`: containment when there is no template (unchanged),
EQUALITY when there is one. A template states the option's whole text, so
containment would be a weaker claim than the words make.

The keyword is `is`, not `equals`: an expect line reads as a sentence about an
option's text, while `claim.<id>.equals` compares a program's OUTPUT, and the two
should not sound like the same operation.

- [ ] **Step 1: Write the failing tests:**

```haskell
it "fills a template from a stated value's parts" $ do
  fillValueHoles "*-*-* <value.1>:<value.2>:00" "\"03\" \"00\""
    `shouldBe` Right "*-*-* 03:00:00"
  fillValueHoles "<value>" "03" `shouldBe` Right "03"
  fillValueHoles "<value.3>" "\"03\" \"00\"" `shouldSatisfy` isLeft

it "reads and renders the template arm" $ do
  let src = "a1 expect systemd.timers.t.timerConfig.OnCalendar from job.schedule is \"*-*-* <value.1>:<value.2>:00\"\n"
  case readExpect src of
    Left es -> expectationFailure (show es)
    Right [e] -> do
      exTemplate e `shouldBe` Just "*-*-* <value.1>:<value.2>:00"
      renderExpect [e] `shouldBe` src
    Right other -> expectationFailure ("expected one expect, got " ++ show (length other))

it "keeps the plain form untouched" $
  case readExpect "a1 expect a.b from c.d\n" of
    Right [e] -> exTemplate e `shouldBe` Nothing
    other     -> expectationFailure (show other)

it "compares a template for equality and a plain expect by containment" $ do
  let tpl  = Expect "a1" ["a","b"] (Subject ["c","d"]) Nothing (Just "x-<value>-y")
      plain = Expect "a2" ["a","b"] (Subject ["c","d"]) Nothing Nothing
  -- the pair is (expected, actual) as runExpects hands it over
  checkValues [tpl]   [("x-1-y", "x-1-y")] `shouldBe` []
  checkValues [tpl]   [("x-1-y", "x-1-y-z")] `shouldSatisfy` (not . null)
  checkValues [plain] [("1", "x-1-y")] `shouldBe` []
```

- [ ] **Step 2:** Run; expect "not in scope" and type errors from the new field.
- [ ] **Step 3: Implement.** `expectedValue` returns the FILLED template when one
  is present (so the pair `runExpects` compares is already resolved), else
  today's whole-or-part value. Fix every `Expect` literal in the suite and in
  `Lips.Generate.Minting`'s expect parser path by passing `Nothing`.
- [ ] **Step 4:** Suite green, `-Wall` clean, app builds.
- [ ] **Step 5:** Commit: `expect: a contract may state the whole text a rule assembles`

---

### Task 2: The Unholdable Expect Is Refused

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Gate.hs` (a new check in `engineViolations`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- | An expect that cannot hold as written: it reads a several-part value WHOLE
-- (no #N, no template) while every rule filling its path assembles the text from
-- parts, so the option never contains the parts joined by a space.
unholdableExpects :: [Pattern] -> [MapRule] -> [Expect] -> [Text]
```

Fires only when all three are true, so no committed contract is caught: the
from-subject's emitted value has more than one part (the patterns decide), the
expect names neither a part nor a template, and no rule filling the path uses a
whole `<value>` hole. Measured cause: three mints wrote exactly this and the
contract gate refused them a minute later, after the model's call had ended.

- [ ] **Step 1: Write the failing test:**

```haskell
it "refuses a whole-value expect on a path assembled from parts" $ do
  let pat = patOne "p1" [TLit "at", TFused [FHole "hh", FLit ":", FHole "mm"]] Fact
              [SLit "job.schedule"] [SHole "hh", SHole "mm"]
      rule = MapRule "r1" Fact ["job", "schedule"]
               [Emit ["systemd","timers","t","timerConfig","OnCalendar"]
                     (VStr [PLit "*-*-* ", PHole "value.1", PLit ":", PHole "value.2", PLit ":00"])]
      whole = Expect "a1" ["systemd","timers","t","timerConfig","OnCalendar"]
                     (Subject ["job","schedule"]) Nothing Nothing
      part  = whole { exId = "a2", exToken = Just 1 }
      tpl   = whole { exId = "a3"
                    , exTemplate = Just "*-*-* <value.1>:<value.2>:00" }
  unholdableExpects [pat] [rule] [whole] `shouldSatisfy` any (T.isInfixOf "a1")
  unholdableExpects [pat] [rule] [part] `shouldBe` []
  unholdableExpects [pat] [rule] [tpl]  `shouldBe` []
```

- [ ] **Step 2:** Run; expect "not in scope".
- [ ] **Step 3: Implement**, reusing `Lips.Kernel.Engine.Landing.emitViews` the way
  `partFaults` does to learn a subject family's part count. The message names the
  remedy in the order a mint should prefer: state the whole text with
  `is "<template>"`, or assert one part with `#N`.
- [ ] **Step 4: Wire it** into `engineViolations`, so `check --draft` reports it
  inside the mint's own call.
- [ ] **Step 5:** Suite green; every committed example still checks (none writes
  such an expect: they were all refused at mint time, which is why none exists).
- [ ] **Step 6:** Commit: `engine: an expect that cannot hold is refused where the mint can still fix it`

---

### Task 3: The Mint Learns The Form

**Files:**
- Modify: `assets/mint/body.md` (the expect section)
- Modify: `assets/mint/worlds.md` (the split-fact rule points at it)
- Test: `kernel/test/Spec.hs` (the prompt describe-blocks)

The body's expect section gains: where a rule ASSEMBLES an option's text from a
fact's parts, the contract states the whole text with the same template, so a
later mint that spells it differently is refused. Show the pair:

    0.95 r2 match fact job.schedule => systemd.timers.<self>.timerConfig.OnCalendar "\"*-*-* <value.1>:<value.2>:00\""
    0.95 a2 expect systemd.timers.<self>.timerConfig.OnCalendar from job.schedule is "*-*-* <value.1>:<value.2>:00"

and the rule that a whole-value expect over a several-part fact is refused,
because the parts joined by a space appear in no notation.

`worlds.md` replaces its `#N` paragraph with a pointer to this form (the `#N`
form stays legal and is the right one when a world writes ONE part into its own
option, e.g. an hour into a field that holds only an hour).

- [ ] **Step 1: Write the failing test:**

```haskell
it "teaches the template contract beside the assembling rule" $ do
  let p = systemPromptFor [shippedWorld "nixos"]
  mapM_ (\c -> p `shouldSatisfy` T.isInfixOf c)
    [ "is \"*-*-* <value.1>:<value.2>:00\"", "joined by a space" ]
```

- [ ] **Step 2:** Run; expect failure.
- [ ] **Step 3: Implement** the prompt edits.
- [ ] **Step 4:** Suite green; `just test-draft` green.
- [ ] **Step 5:** Commit: `mint: a contract over an assembled value states the whole text`

---

### Task 4: The Live Proof, And The Example That Was Blocked

- [ ] **Step 1:** Restore the image sentence in `examples/nightly.timer.lips`
  (`run it in the image busybox:1.36.`), which the kubenix world demanded.
- [ ] **Step 2:** `git add -A && nix build`, then
  `nix run . -- generate -t nixos -t kubenix examples/nightly.timer.lips -m anthropic/claude-opus-5`.
- [ ] **Step 3: Read the result.** Expect: the shared grammar captures the time in
  parts and the image as a fact; `timer/nixos/timer.rules` assembles `OnCalendar`
  and declares `ignore fact job.image` with a reason; `timer/kubenix/timer.rules`
  places the image and the cron schedule; both contracts use the `is` form for
  the assembled values. Both worlds must land.
- [ ] **Step 4:** `nix run . -- compile examples/nightly.timer.lips` writes both
  worlds; confirm `OnCalendar = "*-*-* 03:00:00"`, `spec.schedule = "00 03 * * *"`,
  and the image in the kubenix module only.
- [ ] **Step 5:** `nix flake check`, `just check-expect`, `just test-draft`.
- [ ] **Step 6:** Commit: `examples: nightly states the image its kubernetes world needs`
  then `examples: timer is minted for nixos and kubenix in one call`.

If the mint still refuses to contract the assembled value, READ its gap before
changing anything: a third distinct objection is a design signal, not a prompt
bug, and the honest fallback is to let the option go unvouched with the grounding
line saying so.

---

### Task 5: Docs and Ledger

- [ ] **Step 1:** `README.md` (the contract paragraph gains the form), `kernel/README.md`
  (`Lips.Kernel.Expect`'s row), `DESIGN.md` §13 (a Done entry, including the
  regeneration argument for why it is not vacuous), `TODO.md` (item 0 closes; item
  1, the unchecked draft, becomes item 0).
- [ ] **Step 2:** Commit: `docs: a contract over an assembled value lands in README, ledger and TODO`
- [ ] **Step 3:** Finish: rebase on main, ff-merge, delete the worktree.

## Horizon (Do Not Build Now)

1. **The unchecked draft** (`TODO.md`): `check_draft` records each validated
   draft's fingerprint and `generate` refuses a reply matching none. Cheapest
   remaining win, and it would have caught both wasted mints.
2. **Equality for the plain form.** With a template arm available, containment
   looks like the odd one out; changing it would rewrite every committed
   contract, so it waits for a reason beyond symmetry.

## Self-Review Notes

- The vacuity objection is answered in the header, because an implementer who
  does not see it will wonder why the contract restates the rule.
- Type consistency: `exTemplate` (T1) is read by `expectedValue`/`checkValues`
  (T1) and by `unholdableExpects` (T2); `fillValueHoles` (T1) is the one place
  that knows what `<value.N>` means for plain text.
- The only step that cannot be verified offline is T4, and its failure mode has a
  stated fallback rather than a retry loop.

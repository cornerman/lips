# Block Grammar (Pattern Nesting) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the last deferred piece of template-grammar completeness: a program
line can state a block of child lines, and a child line's decision can see the block
it sits in.

**Architecture:** Blocks are a crystallize-time *scope*, not a new decision shape. The
atom, merge, refine, realize, `.expect` and the canonical `.decisions` text form do not
change. A pattern gains one optional field, its parent pattern id, carried in the
subject path (`lang.pattern.p3.under.p2`). A child line scopes to the nearest preceding
line that matched its parent pattern; its binding environment is its own captures over
its ancestors' captures. An item with no key of its own gets identity from a
structure-bound hole `<n:index>`, filled from position among siblings. Self-nesting
(`p3.under.p3`) is the one place leading whitespace carries meaning.

**Tech Stack:** Haskell (base + containers + text in `Kernel/`), hspec conformance suite
in `kernel/test/Spec.hs`, `just test` to run it.

## Global Constraints

- The kernel knows nothing about any actual program. No domain word, no builder name, no
  option name enters `Kernel/`. Nesting is a relation between pattern ids; the kernel never
  learns what a block *is*.
- No surface convention for marking a block. Indentation stays semantically weightless
  except for a pattern nested under itself. `-` and `:` stay ordinary literal tokens.
- The template grammar does not change. Nesting is carried outside the template string, so
  a template starting with the word `under` keeps working (a missing template case is a
  kernel bug, invariant 3).
- Illegal states unrepresentable: at most one parent per pattern, structurally.
- Deduce-or-fail: a child line with no preceding parent match fails loud naming the line
  and the pattern it wanted; never a silent reinterpretation.
- Every committed example must keep compiling to a **byte-identical** module. Verify with
  `just check-expect` and a diff of `<language>/out/<instance>/default.nix` before and after.
- The suite and app stay `-Wall` clean.
- Small single-line commits; rebase, never merge.

## File Structure

| File | Responsibility |
|---|---|
| `kernel/src/Lips/Kernel/Lang/Pattern.hs` | modify: `pParent`, struct-hole grammar (`<n:index>`), scope-aware `applyPattern` fill |
| `kernel/src/Lips/Kernel/Lang/Nest.hs` | **create**: the pattern-nesting relation, the per-line scope pass, and the whole-engine nesting checks |
| `kernel/src/Lips/Kernel/Lang/Store.hs` | modify: read/render `lang.pattern.<id>.under.<parent>`; run `checkNesting` at the one door |
| `kernel/src/Lips/Kernel/Lang/Crystallize.hs` | modify: forward scope pass, `NoParentBlock`, `Restated` |
| `kernel/src/Lips/Kernel/Lang/Diagnose.hs` | modify: report each line's block parent and restatements |
| `kernel/src/Lips/Kernel/Engine/Answerable.hs` | modify: subject families built with the scope-aware hole set |
| `kernel/src/Lips/Kernel/Engine/Reach.hs` | modify: marker bindings cover ancestors' holes |
| `kernel/src/Lips/Generate/Minting.hs` | modify: qualified pattern id at the mint door |
| `assets/mint/body.md` | modify: teach nesting and `<n:index>` |
| `kernel/test/Spec.hs` | modify: conformance tests, three block fixtures |

---

### Task 1: A restated line is a defect, not a silent merge

Two program lines that crystallize to an identical decision (same subject, same
assertion) merge into one at exit 0 today, and no diagnostic can see it: `diagInert`
works per kind, `diagDropped` per hole. Reproduced: a release-pipeline program whose
fourth step repeats its second realizes a three-element script from four lines.
DESIGN §4 already calls this an error ("no more, through redundancy errors").

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Crystallize.hs`
- Modify: `kernel/src/Lips/Kernel/Lang/Diagnose.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `CrystError` gains `Restated Int Int Text` (this line, the earlier line it
  restates, the rendered subject). `Diagnosis` gains
  `diagRestated :: [(Int, Int, Text)]`.

- [ ] **Step 1: Write the failing test**

```haskell
it "reports a line that restates an earlier one" $ do
  let pat = patOne "p1" [TLit "-", TMulti "step"] Fact
              [SLit "step.", SHole "step", SLit ".command"] [SHole "step"]
      src = "- run tests.\n- publish.\n- run tests.\n"
  crystallize "prog" [pat] src
    `shouldBe` Left [Restated 3 1 "step.run tests.command"]
```

- [ ] **Step 2: Run it and watch it fail**

`just test` — expected: does not compile (`Restated` not in scope).

- [ ] **Step 3: Implement**

In `Crystallize.hs`: after `classifyLines`, group the produced decisions by
`(dSubject, dAssertion)`; every group with more than one contributing source line
yields one `Restated` per line after the first, naming the first. Render the subject
with `Lips.Kernel.Decision.joinSubject`. Only *different* lines count: a dense line
emitting two identical decisions is an engine defect reported elsewhere, so compare by
source line, not by decision id.

- [ ] **Step 4: Run the test**

`just test` — expected: PASS.

- [ ] **Step 5: Surface it in diagnostics**

`Diagnosis` gains `diagRestated`, filled from the same helper (export it from
`Crystallize` so the two never diverge). `Lips.Cli`'s report prints it under
`"restates an earlier line (N) -- delete it or say something new"`.

- [ ] **Step 6: Prove no committed example regresses**

Run `for p in examples/*.lips; do /tmp/lips check "$p"; done`. Expected: all green.

- [ ] **Step 7: Commit**

```bash
git commit -am "crystallize: a line restating an earlier one is a defect, not a silent merge"
```

---

### Task 2: A pattern may carry a parent id

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Pattern.hs`
- Modify: `kernel/src/Lips/Kernel/Lang/Store.hs`
- Modify: `kernel/src/Lips/Generate/Minting.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  data Pattern = Pattern { pId :: Text, pParent :: Maybe Text
                         , pTemplate :: [TplTok], pEmits :: [PatEmit] }
  patOne :: Text -> [TplTok] -> Kind -> [StrPart] -> [StrPart] -> Pattern  -- pParent = Nothing
  patUnder :: Text -> Text -> [TplTok] -> [PatEmit] -> Pattern             -- explicit parent
  parsePatternId :: Text -> (Text, Maybe Text)   -- "p3.under.p2" -> ("p3", Just "p2")
  renderPatternId :: Pattern -> Text             -- ("p3", Just "p2") -> "p3.under.p2"
  ```
  `parsePatternBody :: Text -> Text -> Either Text Pattern` keeps its signature and
  takes the *qualified* id token, so both doors share one spelling.

- [ ] **Step 1: Write the failing tests**

```haskell
it "round-trips a nested pattern through the .lang" $ do
  let p = patUnder "p3" "p2" [TLit "-", THole "path"]
            [PatEmit Fact [SLit "host.", SHole "domain", SLit ".route.", SHole "path"]
                          [SHole "path"]]
      ed = EngineData [pat2, p] [] [] []
  readLang (renderLang prov ed) `shouldBe` Right ed

it "stores the parent in the subject path" $
  renderLang prov (EngineData [patUnder "p3" "p2" [TLit "x"] [emitConcept]] [] [] [])
    `shouldSatisfy` T.isInfixOf "lang.pattern.p3.under.p2"

it "reads a qualified id at the mint door" $
  fmap pParent (parsePatternBody "p3.under.p2" "- <path> => concept a.<path> \"x\"")
    `shouldBe` Right (Just "p2")

it "leaves an unqualified id parentless" $
  fmap pParent (parsePatternBody "p3" "- <path> => concept a.<path> \"x\"")
    `shouldBe` Right Nothing
```

- [ ] **Step 2: Run and watch them fail**

`just test` — expected: does not compile (`patUnder`, `pParent` not in scope).

- [ ] **Step 3: Implement**

- `Pattern` gains `pParent`; `patOne` sets `Nothing`; add `patUnder`.
- `parsePatternId` splits on the literal `.under.` (pattern ids are single identifiers,
  so the split is unambiguous); a token with more than one `.under.` fails loud.
- `parsePatternBody` calls `parsePatternId` on its id token and stores both halves;
  every error message keeps naming the bare id.
- `Store.patternToDecision` renders the subject `["lang","pattern", renderPatternId p]`
  — note `renderPatternId` returns one segment containing dots, so it must go through
  the same path the reader splits: emit segments `["lang","pattern",pid]` for a
  parentless pattern (byte-identical to today) and `["lang","pattern",pid,"under",par]`
  for a nested one.
- `Store.classify` and `decisionToPattern` gain the five-segment arm.
- `Minting.parseLine` passes `idTok` through unchanged (already does); the
  `ItemCandidate`'s `icId` keeps the qualified token, so a refusal names what the mint
  wrote.

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS, and every existing `.lang` round-trip test unchanged.

- [ ] **Step 5: Prove byte-identity on the corpus**

`just check-expect` plus a diff of every `examples/*/out/*/default.nix` against the
pre-change build. Expected: no diff (no committed pattern is nested).

- [ ] **Step 6: Commit**

```bash
git commit -am "pattern: an id may name the pattern it nests under (lang.pattern.p3.under.p2)"
```

---

### Task 3: The structure-bound hole `<n:index>`

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Pattern.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  data StructType = SIndex deriving (Eq, Show)   -- closed; the extension point
  structHole :: Text -> Maybe (Text, StructType) -- "n:index" -> Just ("n", SIndex)
  refName    :: Text -> Text                     -- "n:index" -> "n"; "path" -> "path"
  structHoles :: Pattern -> [(Text, StructType)] -- declared across all emits
  ```
  `applyPattern` fills `SHole h` by looking up `refName h`, so `<n:index>` (the
  declaration) and `<n>` (a reference, including from a descendant) resolve to one
  binding.

- [ ] **Step 1: Write the failing tests**

```haskell
it "declares a structure-bound hole in an emit subject" $
  structHoles (patOne "p1" [TLit "-", TMulti "s"] Fact
                 [SLit "step.", SHole "n:index"] [SHole "s"])
    `shouldBe` [("n", SIndex)]

it "fills a struct hole and a plain reference from one binding" $
  applyPattern (patOne "p1" [TLit "-"] Fact [SLit "s.", SHole "n:index"] [SHole "n"])
               (Map.fromList [("n", "2")])
    `shouldBe` [(Subject ["s","2"], Fact, Assertion "2", Stated)]

it "refuses a struct hole whose name collides with a template hole" $
  parsePatternBody "p1" "- <n> => fact s.<n:index> \"<n>\""
    `shouldSatisfy` isLeft
```

- [ ] **Step 2: Run and watch them fail**

`just test` — expected: does not compile.

- [ ] **Step 3: Implement**

- `structHole` parses `<name>:<type>` against a closed table `[("index", SIndex)]`; an
  unknown type after a colon is left alone (a name may contain a colon), matching how
  `dropHoleType` only drops a *recognized* type.
- `parseBody`'s unbound-hole check treats a hole with a recognized struct type as
  self-bound. Ancestors' holes are NOT resolved here (a pattern parse sees one pattern);
  Task 4's `checkNesting` does that, at `readLang`, which is the door that sees them all.
  So `parseBody` only rejects an unbound hole in a **parentless** pattern.
- `applyPattern`'s `fill`/`fill'` look up `refName h`.
- Rendering is untouched: `SHole "n:index"` renders as `<n:index>`, so round-trip holds.

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "pattern: <n:index>, a hole bound from a line's position among its siblings"
```

---

### Task 4: `Lang/Nest.hs` — the relation, the scope, the checks

**Files:**
- Create: `kernel/src/Lips/Kernel/Lang/Nest.hs`
- Modify: `kernel/src/Lips/Kernel/Lang/Store.hs` (run `checkNesting` inside `readLang`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  data NestError
    = UnknownParent Text Text      -- pattern, the parent id nothing defines
    | NestCycle [Text]             -- the cycle, in order (a 1-cycle is legal: self-nesting)
    | UnboundInScope Text [Text]   -- pattern, holes bound by neither self nor ancestors
    deriving (Eq, Show)

  ancestorsOf   :: [Pattern] -> Pattern -> [Pattern]   -- nearest first, excluding self
  holesInScope  :: [Pattern] -> Pattern -> [Text]      -- own template + own struct + ancestors'
  checkNesting  :: [Pattern] -> [NestError]
  renderNestError :: NestError -> Text

  data Frame = Frame { frLine :: Int, frIndent :: Int, frIndex :: Int
                     , frParent :: Maybe Int, frEnv :: Map Text Text }
  data Scoped = Scoped { scParentLine :: Maybe Int, scEnv :: Map Text Text }
  scopeLine :: [Pattern] -> Map Text [Frame] -> Pattern -> Int -> Int -> Map Text Text
            -> Either Text (Scoped, Map Text [Frame])
  ```
  `scopeLine pats frames p line indent ownBinds` returns the line's full binding
  environment and the updated frame store, or the loud message for a child with no
  preceding parent.

- [ ] **Step 1: Write the failing tests**

```haskell
it "puts an ancestor's captures in a child's scope" $ do
  let p2 = patOne "p2" [TLit "host", THole "domain"] Concept [SLit "host.", SHole "domain"] []
      p3 = patUnder "p3" "p2" [TLit "-", THole "path"]
             [PatEmit Fact [SLit "host.", SHole "domain", SLit ".route.", SHole "path"] [SHole "path"]]
  holesInScope [p2,p3] p3 `shouldMatchList` ["path","domain"]

it "refuses a parent no pattern defines" $
  checkNesting [patUnder "p3" "nope" [TLit "x"] [emitConcept]]
    `shouldBe` [UnknownParent "p3" "nope"]

it "refuses a nesting cycle longer than self-nesting" $
  checkNesting [patUnder "p3" "p4" [TLit "x"] [emitConcept]
               ,patUnder "p4" "p3" [TLit "y"] [emitConcept]]
    `shouldBe` [NestCycle ["p3","p4"]]

it "allows a pattern nested under itself" $
  checkNesting [patUnder "p3" "p3" [TLit "-", THole "x"] [emitConcept]] `shouldBe` []

it "refuses a hole no ancestor binds" $
  checkNesting [patOne "p2" [TLit "host"] Concept [SLit "host"] []
               ,patUnder "p3" "p2" [TLit "-"]
                  [PatEmit Fact [SLit "r.", SHole "ghost"] []]]
    `shouldBe` [UnboundInScope "p3" ["ghost"]]
```

- [ ] **Step 2: Run and watch them fail**

`just test` — expected: module not found.

- [ ] **Step 3: Implement `Nest.hs`**

- `ancestorsOf` walks `pParent` with a visited set, stopping at self-nesting and at a
  missing parent (so it is total even on a malformed engine; `checkNesting` is what
  refuses).
- `holesInScope p = holesOf p ++ map fst (structHoles p) ++ concatMap holesOf ancestors ++ ancestors' struct names`.
- `checkNesting` runs the three checks over every pattern, in pattern-id order, so the
  report is deterministic.
- `scopeLine`: parent frame = for `pParent p == Just q`, if `q == pId p` the last frame of
  `p` with `frIndent < indent`, else the last frame of `q`; `Nothing` when `pParent` is
  `Nothing`. A `Just` parent with no frame is `Left`. Index = 1 + the number of existing
  frames of `p` whose `frParent` equals this line's parent line. Env =
  `ownBinds <> indexBinds <> parentEnv` (left-biased `Map.union`, so own captures shadow
  an ancestor's).

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS.

- [ ] **Step 5: Wire `checkNesting` into `readLang`**

After the per-line pass succeeds, run `checkNesting` over `edPatterns` and turn each
`NestError` into a `ParseError` on the offending pattern's own line. One door, so
`generate`, `compile`, `check` and `lsp` all inherit it. Test:

```haskell
it "readLang refuses an engine whose nesting does not close" $
  readLang "p3 meta lang.pattern.p3.under.p2 stated \"- <x> => fact a.<x> \\\"<x>\\\"\"\n"
    `shouldSatisfy` isLeft
```

- [ ] **Step 6: Commit**

```bash
git commit -am "nest: the pattern-nesting relation, its scope, and the checks that close it"
```

---

### Task 5: Crystallize walks the block tree

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Crystallize.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `CrystError` gains `NoParentBlock Int Text Text` (line, source text, the
  parent pattern id it wanted). `LineOutcome`'s `Matched` gains a
  `Maybe Int` parent line: `Matched Int Text Text (Maybe Int) [Decision]`.

- [ ] **Step 1: Write the failing tests (the three trial languages)**

```haskell
it "scopes two vhost blocks so a repeated route key does not collide" $ do
  -- host <domain>: / proxies to <up>, twice, different hosts
  subjectsOf (crystallize "g" vhostPats vhostSrc)
    `shouldMatchList` [ ["host","shop.example.com"], ["host","blog.example.com"]
                      , ["host","shop.example.com","route","/","proxy"]
                      , ["host","blog.example.com","route","/","proxy"] ]

it "numbers anonymous siblings per block" $
  subjectsOf (crystallize "m" scrapePats scrapeSrc)
    `shouldMatchList` [ ["targets"], ["targets","1"], ["targets","2"]
                      , ["targets","1","job"], ["targets","1","url"]
                      , ["targets","2","job"], ["targets","2","url"] ]

it "keeps a repeated step distinct when the item is index-keyed" $
  length (subjectsOf (crystallize "r" pipePats pipeSrc)) `shouldBe` 6

it "fails loud on a child line with no preceding parent" $
  crystallize "g" vhostPats "- / proxies to http://localhost:3000.\n"
    `shouldBe` Left [NoParentBlock 1 "- / proxies to http://localhost:3000." "p2"]

it "resolves depth by indentation only when a pattern nests under itself" $
  subjectsOf (crystallize "t" treePats "- a\n  - b\n    - c\n- d\n")
    `shouldMatchList` [["n","1"],["n","1","1"],["n","1","1","1"],["n","2"]]
```

- [ ] **Step 2: Run and watch them fail**

`just test` — expected: FAIL (colliding subjects, then a missing constructor).

- [ ] **Step 3: Implement**

`classifyLines` keeps the raw line to measure indentation (`T.length (T.takeWhile isSpace l)`)
*before* stripping, then folds `scopeLine` across the lines in order, threading the frame
store. A matched pattern's bindings become `ownBinds`; `decisionsAt` receives `scEnv`.
`crystallize` maps a `Left` from `scopeLine` to `NoParentBlock`.

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS.

- [ ] **Step 5: Prove byte-identity on the corpus**

`just check-expect` and diff every compiled `default.nix`. Expected: no diff (every
committed pattern is parentless and unindented, so `scopeLine` is the identity there).

- [ ] **Step 6: Commit**

```bash
git commit -am "crystallize: a child line scopes to the nearest preceding line of its parent pattern"
```

---

### Task 6: The static gates see the whole scope

`Reach.droppedValues` and `Answerable.emittedFamilies` both build subject families by
running a pattern's own substitution with markers. `applyPattern` calls `error` on an
unbound hole, so both must bind the ancestors' holes too or a nested engine crashes the
mint gate.

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Reach.hs`
- Modify: `kernel/src/Lips/Kernel/Engine/Answerable.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Lang.Nest.holesInScope`.
- Produces: `droppedValues :: [Pattern] -> [MapRule] -> [DroppedValue]` and
  `unanswerableDemands :: [Pattern] -> [DemandSpec] -> [UnanswerableDemand]` keep their
  signatures; both now take the whole pattern list as the scope source, which they
  already receive.

- [ ] **Step 1: Write the failing tests**

```haskell
it "judges a nested pattern's dropped word without crashing on an ancestor hole" $
  droppedValues [vhostParent, vhostChild] [vhostRule] `shouldBe` []

it "sees a nested pattern's subject family when judging a demand" $
  unanswerableDemands [vhostParent, vhostChild]
    [DemandSpec "q1" ["host","<d>","route","<p>","proxy"] "which upstream?"]
    `shouldBe` []
```

- [ ] **Step 2: Run and watch them fail**

`just test` — expected: the first crashes with `applyPattern: unbound hole <domain>`.

- [ ] **Step 3: Implement**

Replace `holesOf p` with `holesInScope pats p` where the *marker map* is built (both
modules), keeping `holesOf p` where the question is "which words does THIS line bind"
(`droppedValues`' outer loop stays per-pattern: an ancestor's word is judged when the
ancestor is judged).

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "gates: dropped-value and demand checks read a pattern's whole scope"
```

---

### Task 7: The report shows the block tree

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Diagnose.hs`
- Modify: `kernel/src/Lips/Cli.hs` (per-line report)
- Test: `kernel/test/Spec.hs`

- [ ] **Step 1: Write the failing test**

```haskell
it "names the block a line sits in" $ do
  let d = diagnose "g" vhostEngine vhostSrc
  [ (n, par) | Matched n _ _ par _ <- diagLines d ] `shouldBe`
    [ (1, Nothing), (2, Nothing), (3, Just 2), (4, Just 2), (5, Nothing), (6, Just 5) ]
```

- [ ] **Step 2: Run and watch it fail**

`just test` — expected: FAIL (arity).

- [ ] **Step 3: Implement**

`Diagnose` passes the parent through; `Lips.Cli`'s per-line line gains `under line N`
after the subject when the parent is present. The vhost trial's headers must stop being
reported as inert once their captures reach a realizing child: leave `inertLines` alone
(a `Concept` header still realizes nothing itself), but the printed wording for an inert
line that *is* some line's parent becomes `heads the block at lines N-M`, so the report
no longer calls a load-bearing header decoration.

- [ ] **Step 4: Run the test**

`just test` — expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "diagnose: a line's report names the block it sits in"
```

---

### Task 8: The mint is told (a capability the model never hears of is dead)

**Files:**
- Modify: `assets/mint/body.md`
- Test: `kernel/test/Spec.hs` (the prompt-invariant test and the `lips-engine` fenced-block guard)

- [ ] **Step 1: Write the failing test**

```haskell
it "generate prompt teaches nesting and the index hole" $ do
  systemPromptFor NixOS `shouldSatisfy` T.isInfixOf "p3.under.p2"
  systemPromptFor NixOS `shouldSatisfy` T.isInfixOf "<n:index>"
```

- [ ] **Step 2: Run and watch it fail**

`just test` — expected: FAIL.

- [ ] **Step 3: Write the prompt section**

One reference subsection, each prohibition stated once: when to nest (a child line that
needs a word from the line above it; an item with no key of its own), how to spell it
(the qualified id), what `<n:index>` is for, and the two refusals the kernel makes
(a parent nothing defines, a hole no ancestor binds). Add one worked example in a
synthetic domain (neither nginx nor prometheus — the existing examples' domains are
deliberately synthetic), inside a ` ```lips-engine ` block so the existing
`parseEngineCandidates` guard checks it.

- [ ] **Step 4: Run the tests**

`just test` — expected: PASS, including the fenced-block guard parsing the new example.

- [ ] **Step 5: Commit**

```bash
git commit -am "mint: teach pattern nesting and the index hole"
```

---

### Task 9: The three trial languages, live

The trials that drove this design (`gateway.vhost.lips`, `release.pipeline.lips`,
`metrics.scrape.lips`) become the proof, minted for real rather than hand-written.

**Files:**
- Create: `examples/gateway.vhost.lips` and its minted `examples/vhost/`
- Test: `kernel/test/Spec.hs` already covers the physics; this task proves the loop.

- [ ] **Step 1: Mint one of the three**

```bash
nix run . -- generate examples/gateway.vhost.lips -m anthropic/claude-sonnet-5
```

Expected: the mint reaches for nesting on its own (the design came from three
independent hand-written engines that all wanted it). If it does not, that is a prompt
finding, not a kernel finding — record it in the ledger rather than editing the engine
by hand (invariant 4).

- [ ] **Step 2: Verify end to end**

```bash
nix run . -- check examples/gateway.vhost.lips
nix run . -- compile examples/gateway.vhost.lips
```

Expected: green, and the realized module carries two distinct
`services.nginx.virtualHosts.*` entries with their own locations.

- [ ] **Step 3: Prove an edit flows with no model**

Change one upstream port in the program, `compile` again, diff the module. Expected: one
changed line, no regeneration.

- [ ] **Step 4: Commit**

```bash
git add examples/gateway.vhost.lips examples/vhost
git commit -m "examples: a two-host gateway, the first program written in blocks"
```

---

### Task 10: Ledger and TODO

**Files:**
- Modify: `DESIGN.md` §13 (move template completeness from "deferred" to done)
- Modify: `TODO.md` (drop item 2)

- [ ] **Step 1: Write the ledger entry**

Under "Done": what the three trials proved (a wrong-advice conflict, a silently dropped
line at exit 0, an inexpressible program), why blocks are a scope and not a decision
shape, the two rejected spellings (a body prefix, which would make a template starting
with `under` unreadable; a separate `nest` item, which would let one pattern carry two
parents), and the one place indentation now carries meaning.

- [ ] **Step 2: Update §13's template-completeness bullet**

Replace "Deferred, with the reason: true parent-child block aggregation ..." with what
landed, and record that the deferred framing ("a decision that owns a list") was wrong:
`Append` already carries lists, and what was missing was scope.

- [ ] **Step 3: Drop TODO item 2 and commit**

```bash
git commit -am "ledger: block grammar (pattern nesting) landed; template completeness closed"
```

---

## Self-Review

**Spec coverage.** Nesting declaration (Task 2), scope inheritance (Tasks 4-5),
`<n:index>` (Task 3), self-nesting by indentation (Tasks 4-5), fail-loud on a missing
parent (Task 5), whole-engine checks at one door (Task 4), the static gates (Task 6),
diagnostics (Task 7), the mint (Task 8), live proof (Task 9), ledger (Task 10). The
independent restatement bug is Task 1.

**Placeholders.** None: every step names its file, its test, and its command.

**Type consistency.** `pParent`/`patUnder`/`parsePatternId` (Task 2) are used by
`holesInScope`/`checkNesting` (Task 4) and by `scopeLine` (Task 5); `structHoles`/`refName`
(Task 3) are used by `holesInScope` (Task 4) and by the crystallize fold (Task 5);
`Matched`'s new `Maybe Int` (Task 5) is consumed by `Diagnose` (Task 7).

**Risk to watch.** `Matched`'s arity change touches `Diagnose`, `Cli`, `Lsp.Derive` and
several tests; do it in Task 5's commit so nothing half-compiles.

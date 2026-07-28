# Dropped Program Value Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make it a loud kernel defect when a language binds a word from a program and then discards it, so a program line can never look load-bearing while changing nothing.

**Architecture:** One new pure, domain-blind static check over engine data
(`Lips.Kernel.Engine.Reach.droppedValues`), the sibling of the rule-overlap
check that already runs at the mint gate. It walks each pattern's template
holes, asks where each hole's word lands (a decision's subject segment, a
decision's value, or nowhere), and asks whether any rule matching that decision
carries the word onward into an option path or an option value. A word carried
by nobody is reported. `generate` refuses such an engine; `check`/`compile`
report it per program line for engines already committed.

**Tech Stack:** Haskell (GHC in the nix dev shell), hspec conformance suite in
`kernel/test/Spec.hs`, no new dependencies.

## Global Constraints

- The kernel stays domain-blind: no program word, language name, builder name or
  option name may appear in kernel code. The check reasons only over the shape
  of patterns and rules.
- The suite and app must stay `-Wall` clean.
- Fast test loop: `just test` (from repo root) or, inside `kernel/`:
  `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec && /tmp/lips-dv-spec`.
- Baseline at branch point (`0b7659e`): 318 examples, 0 failures.
- Small single-line commits; no merge commits; no AI attribution in commit
  messages.
- Failure at the mint gate only (`generate`). Loading a committed engine
  (`run`/`check`/`compile`) must NOT start failing: `examples/http` ships this
  exact defect and `just check-expect` has to stay green.

---

## Background: The Defect, With Evidence

`examples/hello.http.lips` contains the line

```
write the server in go, using only the standard library with no external dependencies.
```

The committed engine reads it and drops it:

```
p3 ... "write the server in <lang> using only the standard library with no external dependencies => steer server.language \"<lang>\""
r3 ... "match steer server.language => artifact.helloserver.builder \"\\\"buildGoModule\\\"\" ; ..."
```

`r3` matches the decision `p3` produces and emits five constants. The word
`go` reaches nothing. Edit the program to say `rust` and `compile` still emits
`buildGoModule`, offline, silently, forever. The untracked `examples/board/`
mint reproduces it exactly (`p4`/`r4`, `fact tool.language`).

A mint filed this against itself (gap report finding 3, recoverable via
`git show ca09f97^:docs/gaps/README.md`) and named the remedy this plan
implements:

> the same rule would wrongly still emit buildGoModule ... The existing example
> works only because nobody edits that word. ... the honest fix is that changing
> the language word must fail loud, not silently keep `buildGoModule`.

Finding 1 of the same report is the general disease ("the mint may quietly
demote any inconvenient line to decoration, and no structural guard notices").
`diagInert` closed its visibility half for whole lines (`Concept`-only lines).
This plan closes the half where the `.lang` claims a word matters (a `fact` or
`steer` carrying it) while the rules throw it away.

**The rule this plan makes physics:** if a pattern binds a word and some
non-`Concept` emit carries it, then some rule matching that emit must reference
it — through `<value>`/`<value.N>` for a word in the decision's value, or
through the aligned subject capture for a word in the decision's subject. A word
no emit mentions at all is likewise reported.

**Deliberately NOT in scope** (record these, do not build them):

1. *Partial token drop.* A value built from two holes (`"<count> <period>"`)
   whose rule uses only `<value.1>` still drops `<period>`. Detecting it needs a
   static token-index map from holes to positions, which a multi-token capture
   makes unsound. Both real repros are total drops. Add a `TODO.md` line.
2. *Concept-only holes.* A hole reaching only a `Concept` emit is a declaration
   the mint made in the `.lang` and the human reads in the mint report; whole
   inert lines are already named by `diagInert`. No committed engine emits a
   `Concept`, so a per-hole decorative report would have zero call sites today
   (YAGNI). Add a `TODO.md` line.
3. *Source line dependencies* (the other candidate remedy in finding 1: stamp
   which program lines an artifact's baked source depends on). Independent
   subsystem, its own plan later.

**False rejections are as costly as missed defects** (the stance
`Engine/Overlap.hs` already takes: the gate must pass every sound engine).
Where alignment is not statically decidable the check must call the word
*carried*. Three such cases, all handled below: a rule whose aligned subject
segment is a LITERAL (the word selects the rule, so it is load-bearing), an emit
no rule matches at all (the existing unmapped-decision failure owns that case),
and a subject segment mixing literal text with a hole (treated as a plain
variable).

## File Structure

- Create `kernel/src/Lips/Kernel/Engine/Reach.hs` — the check. Named for the
  property it decides: does a program word reach the realized output.
- Modify `kernel/src/Lips/Kernel/Engine/Value.hs` — add `valueUsesAssertion`
  (does this rhs read the matched decision's assertion?).
- Modify `kernel/src/Lips/Kernel/Engine/Overlap.hs` — export `subjectsUnify`,
  extracted from `overlapOf`, so one unification serves both checks.
- Modify `kernel/src/Lips/Kernel/Lang/Diagnose.hs` — add `diagDropped`, joining
  dropped holes onto the program lines that matched their pattern.
- Modify `kernel/app/Main.hs` — `assertValuesReach` at the mint gate beside
  `assertRulesOrthogonal`; a `read and discarded` block in `renderDiagnosis`.
- Modify `kernel/src/Lips/Generate/Minting.hs` — state the rule in the prompt.
- Modify `kernel/test/Spec.hs` — tests for each of the above.
- Modify `DESIGN.md` (ledger §13) and `TODO.md` — record what landed.

---

### Task 1: `valueUsesAssertion` (does a rhs read the matched value?)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Value.hs` (export list, plus a
  definition next to `valueCaptures`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `valueUsesAssertion :: Value -> Bool` — True when the value
  contains a `<value>` or `<value.N>` hole (a string piece, a bare typed hole,
  or a tail hole), scanning into lists and attrsets. `VPath` is NOT scanned:
  `fillValue` never fills a path from the assertion (paths carry captures only),
  so a `<value>` written inside a path does not read the matched value.

- [ ] **Step 1: Write the failing tests**

Add to `kernel/test/Spec.hs`, inside the existing
`describe "engine value grammar"` block (search for `valueCaptures` to find a
neighbouring block; any `describe` in that area is fine):

```haskell
    describe "valueUsesAssertion (does a rhs read the matched decision's value)" $ do
      let v t = case parseValue t of
            Right ok -> ok
            Left e   -> error (T.unpack ("bad test value: " <> e))

      it "sees <value> in a string" $
        valueUsesAssertion (v "\"echo <value>\"") `shouldBe` True

      it "sees an indexed <value.N>" $
        valueUsesAssertion (v "\"[ \\\"--keep-<value.2> <value.1>\\\" ]\"") `shouldBe` True

      it "sees a hole nested in a list" $
        valueUsesAssertion (v "[ \"<value>\" ]") `shouldBe` True

      it "does not see a constant" $
        valueUsesAssertion (v "\"buildGoModule\"") `shouldBe` False

      it "does not count a subject capture as reading the value" $
        valueUsesAssertion (v "\"<name>\"") `shouldBe` False
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec`
Expected: compile error, `Variable not in scope: valueUsesAssertion`.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Kernel/Engine/Value.hs`, add `valueUsesAssertion` to the
export list (right after `valueCaptures`), and define it directly below
`valueCaptures`:

```haskell
-- | Does this rhs read the MATCHED decision's assertion? True for a
-- @\<value\>@ or @\<value.N\>@ hole anywhere inside it (a string piece, a bare
-- typed hole, a tail hole), recursing into lists and attrsets. The dual of
-- 'valueCaptures', which reports the capture names and deliberately skips
-- these two.
--
-- A 'VPath' is not scanned: 'fillValue' leaves a path untouched (only
-- 'bindCaptureValue' and 'bindSelfValue' rewrite one), so a @\<value\>@ written
-- inside a path never receives the matched assertion. Answering False there
-- keeps the answer honest -- a caller asking "does the program's word reach
-- this option" must not be told yes by a hole nothing fills.
valueUsesAssertion :: Value -> Bool
valueUsesAssertion = go
  where
    go (VStr ps)    = any piece ps
    go (VList vs)   = any go vs
    go (VAttr fs)   = any (go . snd) fs
    go (VHole _ h)  = assertionHole h
    go (VTail _ h)  = assertionHole h
    go _            = False
    piece (PHole h) = assertionHole h
    piece _         = False
    assertionHole h = h == "value" || isJust (holeIndex h)
```

`isJust` is already imported in that module (used by `valueCaptures`); confirm
with `grep -n "^import           Data.Maybe" kernel/src/Lips/Kernel/Engine/Value.hs`
and add `isJust` to that import list only if missing.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec && /tmp/lips-dv-spec 2>&1 | tail -3`
Expected: 323 examples, 0 failures, no warnings.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Value.hs kernel/test/Spec.hs
git commit -m "kernel: a value knows whether it reads the matched decision's assertion"
```

---

### Task 2: `subjectsUnify` (one unification, two checks)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Overlap.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `subjectsUnify :: [Text] -> [Text] -> Bool` — could one concrete
  subject match both of these subject patterns? Sides are tagged internally, so
  a capture named the same on both sides stays independent. Different lengths
  never unify.
- Consumes: nothing from Task 1.

- [ ] **Step 1: Write the failing tests**

Add inside the existing
`describe "rule overlap (critical pairs over rule left-hand sides, spec 4)"`
block in `kernel/test/Spec.hs`:

```haskell
    it "unifies a capture with a literal at the same position" $ do
      subjectsUnify ["tool", "<lang>"] ["tool", "go"] `shouldBe` True
      subjectsUnify ["tool", "<lang>"] ["tool", "language"] `shouldBe` True

    it "does not unify different literals or different lengths" $ do
      subjectsUnify ["tool", "go"] ["tool", "rust"] `shouldBe` False
      subjectsUnify ["tool"] ["tool", "<lang>"] `shouldBe` False

    it "keeps a repeated capture constraining" $ do
      subjectsUnify ["x", "<a>", "<a>"] ["x", "p", "q"] `shouldBe` False
      subjectsUnify ["x", "<a>", "<a>"] ["x", "p", "p"] `shouldBe` True
```

Add `subjectsUnify` to the `Lips.Kernel.Engine.Overlap` import in `Spec.hs`
only if that import is explicit; it is currently a bare
`import Lips.Kernel.Engine.Overlap`, so nothing to change.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec`
Expected: `Variable not in scope: subjectsUnify`.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Kernel/Engine/Overlap.hs`: add `subjectsUnify` to the
export list after `ruleOverlaps`, add `import           Data.Maybe (isJust)` to
the imports, and define it directly below `overlapOf`:

```haskell
-- | Could one concrete subject match both of these subject patterns? The
-- yes/no half of 'overlapOf', without the witness -- shared so the
-- dropped-value check ('Lips.Kernel.Engine.Reach') asks the SAME question
-- about a pattern's emitted subject family and a rule's left-hand side. Two
-- copies of unification would be two places for the answer to drift.
subjectsUnify :: [Text] -> [Text] -> Bool
subjectsUnify l r = isJust (unify (terms "l" l) (terms "r" r))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec && /tmp/lips-dv-spec 2>&1 | tail -3`
Expected: 326 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Overlap.hs kernel/test/Spec.hs
git commit -m "kernel: expose subject unification, so one implementation answers both static checks"
```

---

### Task 3: `Engine/Reach.hs` — the dropped-value check

**Files:**
- Create: `kernel/src/Lips/Kernel/Engine/Reach.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `valueUsesAssertion` (Task 1), `subjectsUnify` (Task 2).
- Produces:
  - `data DropWhy = EmittedNowhere | IgnoredBy [Text] [Text]` (the subject
    family, then the ids of the rules that match it and carry nothing).
  - `data DroppedValue = DroppedValue { dvPattern :: Text, dvHole :: Text, dvWhy :: DropWhy }`
  - `droppedValues :: [Pattern] -> [MapRule] -> [DroppedValue]`
  - `renderDroppedValue :: DroppedValue -> Text`

**Why sentinel substitution, not a re-implementation:** the check needs to know
which subject SEGMENT a hole lands in. `applyPattern` already decides that
(a captured value is atomic: dots inside it do not split, dots in a literal do).
Calling `applyPattern` with each hole bound to a unique marker reuses the
production substitution instead of copying its segmentation rule, so the check
cannot drift from what `crystallize` actually produces.

- [ ] **Step 1: Write the failing tests**

Add a new top-level `describe` to `kernel/test/Spec.hs`, directly after the
`describe "rule overlap ..."` block, and add
`import Lips.Kernel.Engine.Reach` plus
`import Lips.Kernel.Lang.Store (EngineData (..), parsePatternBody)` to the
import list (check first: `Lips.Kernel.Lang.Store` may already be imported via
`Lips.Kernel.Lang.Diagnose`'s re-exports — it is not, so add it explicitly;
`parsePatternBody` and `parseRuleBody` are the readable way to build fixtures
from the exact text a mint writes).

```haskell
  -- A word the language BINDS and then discards makes a program line look
  -- load-bearing while changing nothing (gap finding 3: "the existing example
  -- works only because nobody edits that word"). Static, domain-blind, and
  -- checked at the mint gate, where the engine is still rejectable.
  describe "dropped program values (does every word the language reads reach output)" $ do
    let pat body = case parsePatternBody "p1" body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test pattern: " <> e))
        rul i body = case parseRuleBody i body of
          Right ok -> ok
          Left e   -> error (T.unpack ("bad test rule: " <> e))

    -- The committed examples/http defect, verbatim in shape.
    let langPat = pat "write the server in <lang> using only the standard library \
                      \=> steer server.language \"<lang>\""

    it "reports a captured word a matching rule replaces with a constant" $
      droppedValues [langPat]
        [ rul "r3" "match steer server.language => artifact.helloserver.builder \"\\\"buildGoModule\\\"\"" ]
        `shouldBe` [DroppedValue "p1" "lang" (IgnoredBy ["server", "language"] ["r3"])]

    it "accepts the same rule once its rhs reads the value" $
      droppedValues [langPat]
        [ rul "r3" "match steer server.language => artifact.helloserver.builder \"\\\"build<value>Module\\\"\"" ]
        `shouldBe` []

    it "accepts a presence match: a pattern with no hole drops nothing" $
      droppedValues [pat "run a postgresql database server => fact postgres.enable \"true\""]
        [ rul "r1" "match fact postgres.enable => services.postgresql.enable true" ]
        `shouldBe` []

    it "accepts indexed value holes as reading the value" $
      droppedValues [pat "keep <count> <period> snapshots => fact backup.retention \"<count> <period>\""]
        [ rul "r4" "match fact backup.retention => services.restic.backups.<self>.pruneOpts \"[ \\\"--keep-<value.2> <value.1>\\\" ]\"" ]
        `shouldBe` []

    -- The greet engine: <name> reaches output through the emit PATH, <msg>
    -- through the value. Neither is dropped, and this is the shape most CLI
    -- engines take, so a false rejection here would be expensive.
    let greetPat = pat "install a command <name> that prints <msg> => fact cmd.<name>.msg \"<msg>\""

    it "accepts a subject capture the rule carries into an emit path" $
      droppedValues [greetPat]
        [ rul "r1" "match fact cmd.<name>.msg => artifact.<name>.args.text \"\\\"echo <value>\\\"\"" ]
        `shouldBe` []

    it "reports a subject capture no emit path or value mentions" $
      droppedValues [greetPat]
        [ rul "r1" "match fact cmd.<name>.msg => environment.etc.greet.text \"\\\"<value>\\\"\"" ]
        `shouldBe` [DroppedValue "p1" "name" (IgnoredBy ["cmd", "<name>", "msg"] ["r1"])]

    it "accepts a literal rule segment: the word selects the rule" $
      droppedValues [pat "write it in <lang> => fact tool.<lang> \"<lang>\""]
        [ rul "r1" "match fact tool.go => artifact.<self>.builder \"\\\"buildGoModule\\\"\"" ]
        `shouldBe` []

    it "reports a hole no emit mentions at all" $
      droppedValues [pat "write the tool in <lang> with no dependencies => fact tool.built \"true\""]
        [ rul "r1" "match fact tool.built => artifact.<self>.args.vendorHash null" ]
        `shouldBe` [DroppedValue "p1" "lang" EmittedNowhere]

    it "leaves a decorative hole to the inert-line report" $
      droppedValues [pat "show a kanban board in <place> => concept tool.intro \"<place>\""] []
        `shouldBe` []

    it "stays silent when no rule matches the decision at all" $
      droppedValues [langPat] [] `shouldBe` []

    it "names the defect in the words the rule author needs" $
      map renderDroppedValue
        (droppedValues [langPat]
          [ rul "r3" "match steer server.language => artifact.helloserver.builder \"\\\"buildGoModule\\\"\"" ])
        `shouldBe`
          [ "pattern p1 binds <lang>, which reaches server.language, and rule r3 \
            \emits it nowhere: editing that word changes no output" ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec`
Expected: `Could not find module 'Lips.Kernel.Engine.Reach'`.

- [ ] **Step 3: Implement**

Create `kernel/src/Lips/Kernel/Engine/Reach.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Does every word the language READS reach the realized output?
--
-- Deduce-or-fail covers the line lips cannot read (it fails loud, naming the
-- remedy). It does not cover the line lips reads, admits as a fact, and then
-- throws away: a rule may match that fact and emit only constants, so the
-- program's word governs nothing. The author then reads a sentence that looks
-- load-bearing, edits it, and the realized output does not move. A mint filed
-- exactly this against itself while minting a CLI tool -- "the same rule would
-- wrongly still emit buildGoModule ... the existing example works only because
-- nobody edits that word" -- and named this check as the honest fix.
--
-- The check is static and domain-blind: it never asks what a word MEANS, only
-- whether the engine's own shape carries it. A hole reaches output when some
-- rule matching the decision it feeds either reads that decision's value
-- (@\<value\>@ / @\<value.N\>@) or names the aligned subject capture in an emit
-- path or an emit value. It reaches nothing when no emit mentions it at all.
--
-- Two neighbours own the cases this one does not. A hole reaching only a
-- 'Concept' is decoration the mint DECLARED, and whole inert lines are named by
-- 'Lips.Kernel.Lang.Diagnose'. A decision no rule maps at all already fails the
-- build loud.
--
-- Where alignment is not statically decidable the answer is "carried", because
-- the mint gate must pass every sound engine (the stance
-- 'Lips.Kernel.Engine.Overlap' takes: a false rejection costs as much as a
-- missed defect). Three such cases: a rule whose aligned subject segment is a
-- LITERAL (only programs saying that word match it, so the word selects the
-- rule and is load-bearing), an emit no rule matches, and a segment mixing
-- literal text with a hole (treated as a plain variable, so at worst the report
-- names an extra rule).
module Lips.Kernel.Engine.Reach
  ( DroppedValue (..)
  , DropWhy (..)
  , droppedValues
  , renderDroppedValue
  ) where

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Capture        (captureName, nameTokens)
import Lips.Kernel.Decision       (Assertion (..), Kind (Concept), Subject (..))
import Lips.Kernel.Engine.Data    (Emit (..), MapRule (..), renderAttrPath)
import Lips.Kernel.Engine.Overlap (subjectsUnify)
import Lips.Kernel.Engine.Value   (valueCaptures, valueUsesAssertion)
import Lips.Kernel.Lang.Pattern   (Pattern (..), applyPattern, holesOf)

-- | Why a word reaches no output.
data DropWhy
  = -- | No emit of its own pattern mentions it: the word dies at crystallize.
    EmittedNowhere
  | -- | It reaches this subject family, and these rules match it and carry it
    -- nowhere.
    IgnoredBy [Text] [Text]
  deriving (Eq, Show)

-- | One word the language binds and the engine discards: the pattern that
-- binds it, the hole that names it, and why it goes nowhere.
data DroppedValue = DroppedValue
  { dvPattern :: Text
  , dvHole    :: Text
  , dvWhy     :: DropWhy
  }
  deriving (Eq, Show)

-- | Every dropped word, in pattern then template order. Empty means every word
-- the language reads governs something in the realized output.
droppedValues :: [Pattern] -> [MapRule] -> [DroppedValue]
droppedValues pats rules =
  [ DroppedValue (pId p) h why
  | p <- pats
  , h <- holesOf p
  , Just why <- [dropOf rules p h]
  ]

-- | Where a hole's word lands, decided by running the pattern's own
-- substitution with each hole bound to a unique marker. Reusing
-- 'applyPattern' (rather than re-deriving how a subject splits into segments)
-- keeps this check honest: it sees exactly the subjects and assertions
-- crystallize will build.
dropOf :: [MapRule] -> Pattern -> Text -> Maybe DropWhy
dropOf rules p h
  | null carrying = if decorative then Nothing else Just EmittedNowhere
  | any reached judged = Nothing
  | otherwise = case [ (fam, ids) | (fam, ids, _) <- judged, not (null ids) ] of
      []                -> Nothing
      ((fam, ids) : _)  -> Just (IgnoredBy fam ids)
  where
    holes = holesOf p
    marks = Map.fromList [(x, marker x) | x <- holes]
    filled = [ (segs, k, a) | (Subject segs, k, Assertion a, _) <- applyPattern p marks ]
    mentions (segs, _, a) = any hit segs || hit a
    hit t = marker h `T.isInfixOf` t
    -- Only a realizing emit can carry a word to output; a Concept is dropped by
    -- realize, so a hole reaching one is decoration, reported elsewhere.
    carrying   = [ e | e@(_, k, _) <- filled, k /= Concept, mentions e ]
    decorative = any mentions [ e | e@(_, Concept, _) <- filled ]
    judged = map judge carrying
    reached (_, _, ok) = ok
    judge (segs, k, a) =
      let fam      = map famSeg segs
          idx      = [ i | (i, s) <- zip [0 :: Int ..] segs, hit s ]
          matching = [ r | r <- rules, mrKind r == k, subjectsUnify fam (mrSubject r) ]
       in (fam, map mrId matching, any (carries a idx) matching)
    -- A segment holding any marker becomes a capture named after the holes in
    -- it, so the rule side unifies against a variable -- and a hole repeated in
    -- two segments still constrains, since it yields the same variable twice.
    famSeg s = case [ x | x <- holes, marker x `T.isInfixOf` s ] of
      [] -> s
      hs -> "<" <> T.intercalate "+" hs <> ">"
    -- The rule carries the word if it reads the decision's value, or if it
    -- names the capture standing where the word lands. A LITERAL there means
    -- the rule only fires for that word, so the word already governs the
    -- choice of rule.
    carries a idx r =
      (hit a && any (valueUsesAssertion . emRhs) (mrEmits r))
        || or [ maybe True (usesCapture r) (captureName s)
              | (i, s) <- zip [0 :: Int ..] (mrSubject r)
              , i `elem` idx
              ]

-- | A marker no program text can collide with, since it is built here and only
-- ever compared against text this module substituted.
marker :: Text -> Text
marker h = "\SOH" <> h <> "\SOH"

-- | Does the rule name this capture anywhere its output can see: an emit path
-- segment (whole or embedded, hence 'nameTokens') or an emit value (a string
-- hole, an artifact name, a path)?
usesCapture :: MapRule -> Text -> Bool
usesCapture r c = any inEmit (mrEmits r)
  where
    inEmit e = c `elem` concatMap nameTokens (emPath e)
                 || c `elem` valueCaptures (emRhs e)

-- | One dropped word in the words its author (the model, at the mint gate)
-- needs: which pattern binds it, where it lands, and who ignores it.
renderDroppedValue :: DroppedValue -> Text
renderDroppedValue dv = case dvWhy dv of
  EmittedNowhere ->
    "pattern " <> dvPattern dv <> " binds <" <> dvHole dv
      <> "> and emits it nowhere: the word it reads reaches no decision"
  IgnoredBy fam ids ->
    "pattern " <> dvPattern dv <> " binds <" <> dvHole dv <> ">, which reaches "
      <> renderAttrPath fam <> ", and " <> rules' <> " emits it nowhere: editing"
      <> " that word changes no output"
    where
      rules' = (if length ids == 1 then "rule " else "rules ") <> T.intercalate ", " ids
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec && /tmp/lips-dv-spec 2>&1 | tail -3`
Expected: 337 examples, 0 failures, no warnings. If a rendered string differs
in wording, fix the TEST to match the implementation's exact text (the message
is the deliverable; the test pins it).

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Reach.hs kernel/test/Spec.hs
git commit -m "kernel: a word the language reads and then discards is a static defect"
```

---

### Task 4: Refuse a dropping engine at the mint gate

**Files:**
- Modify: `kernel/app/Main.hs` (import block; a new `assertValuesReach`; one
  call beside `assertRulesOrthogonal` at line ~351)

**Interfaces:**
- Consumes: `droppedValues`, `renderDroppedValue` (Task 3).
- Produces: `assertValuesReach :: FilePath -> EngineData -> IO ()`.

`app/Main.hs` is not on the test suite's source path, so this task is verified
by compiling the binary and by Task 5's live report, not by a unit test. Keep it
to the smallest possible wiring.

- [ ] **Step 1: Add the import**

Next to `import           Lips.Kernel.Engine.Overlap    (renderRuleOverlap, ruleOverlaps)`:

```haskell
import           Lips.Kernel.Engine.Reach      (droppedValues, renderDroppedValue)
```

- [ ] **Step 2: Add the assertion, next to `assertRulesOrthogonal`**

```haskell
-- | Deduce-or-fail applied to the engine's own reading: a word the language
-- binds and then discards makes a program line look load-bearing while
-- changing nothing, and no later stage can notice (the module it realizes is
-- perfectly valid). So it is rejected here, where the engine is still
-- rejectable. Two honest ways out: carry the word (read it with <value> or the
-- aligned capture), or state that it carries no value of its own by reading the
-- line as a concept -- which `check` then reports as decoration.
assertValuesReach :: FilePath -> EngineData -> IO ()
assertValuesReach file eng =
  case droppedValues (edPatterns eng) (edRules eng) of
    []  -> pure ()
    dvs -> die (validationReport file
      ("it reads words from the program and then discards them:\n"
        <> T.unlines (map (("  - " <>) . renderDroppedValue) dvs)))
```

- [ ] **Step 3: Call it at the gate**

Directly after `assertRulesOrthogonal rep eng`:

```haskell
      assertValuesReach rep eng
```

- [ ] **Step 4: Verify the binary compiles and the suite is still green**

Run: `just test`
Expected: 337 examples, 0 failures.

Run: `nix build . --print-out-paths 2>&1 | tail -2`
Expected: a store path, no warnings (the flake sees only git-tracked files, so
`git add` first if the build reports a missing module).

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "generate: refuse an engine that reads a program word and discards it"
```

---

### Task 5: Report dropped words per program line in `check`

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Diagnose.hs`
- Modify: `kernel/app/Main.hs` (`renderDiagnosis`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `droppedValues` (Task 3).
- Produces: `diagDropped :: [(Int, Text, [Text])]` on `Diagnosis` — line
  number, the line's source text, and the hole names whose word reaches no
  output. Joined by pattern id, so the report names the line the author wrote
  instead of the pattern id the mint chose.

Committed engines keep working: this is a REPORT. `checkLoose` still fails only
on unreadable lines and open demands, so `just check-expect` stays green while
`examples/hello.http.lips` now names its defect.

- [ ] **Step 1: Write the failing test**

Add inside `describe "diagnose (authoring view over .lang, pure)"` in
`kernel/test/Spec.hs`:

```haskell
    it "names a line whose word the engine reads and discards" $ do
      let engD = EngineData
            { edPatterns =
                [ patOne "p3" [TLit "write", TLit "the", TLit "server", TLit "in", THole "lang"]
                    Steer [SLit "server.language"] [SHole "lang"] ]
            , edRules = [ MapRule "r3" Steer ["server", "language"]
                            [ Emit ["environment", "etc", "builder", "text"]
                                   (VStr [PLit "buildGoModule"]) ] ]
            , edDemands = []
            }
          d = diagnose "f" engD "write the server in go"
      diagDropped d `shouldBe` [(1, "write the server in go", ["lang"])]

    it "reports no dropped word when the rule reads the value" $ do
      let engK = EngineData
            { edPatterns =
                [ patOne "p3" [TLit "write", TLit "the", TLit "server", TLit "in", THole "lang"]
                    Steer [SLit "server.language"] [SHole "lang"] ]
            , edRules = [ MapRule "r3" Steer ["server", "language"]
                            [ Emit ["environment", "etc", "builder", "text"]
                                   (VStr [PHole "value"]) ] ]
            , edDemands = []
            }
      diagDropped (diagnose "f" engK "write the server in go") `shouldBe` []
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-dv -o /tmp/lips-dv-spec`
Expected: `Variable not in scope: diagDropped`.

- [ ] **Step 3: Implement in `Diagnose.hs`**

Extend the module header's list of outcomes with one sentence, add the field,
fill it, and add the join. Concretely:

Add to the import block:

```haskell
import Lips.Kernel.Engine.Reach   (DroppedValue (..), droppedValues)
```

Add the field to `Diagnosis` (after `diagInert`):

```haskell
  , diagDropped :: [(Int, Text, [Text])] -- ^ lines whose bound words reach no output: line no, source text, hole names
```

Fill it in `diagnose`, in the record it builds:

```haskell
        , diagDropped = droppedLines (droppedValues (edPatterns eng) (edRules eng)) outcomes
```

Add below `inertLines`:

```haskell
-- | Join the engine's dropped words onto the program lines that produced them.
-- The engine names the defect by pattern id; the author needs the LINE they
-- wrote, so the report is keyed by line and lists the holes whose word governs
-- nothing. A line whose pattern drops no word never appears.
droppedLines :: [DroppedValue] -> [LineOutcome] -> [(Int, Text, [Text])]
droppedLines dvs outcomes =
  [ (n, txt, hs)
  | Matched n txt pid _ <- outcomes
  , let hs = [dvHole dv | dv <- dvs, dvPattern dv == pid]
  , not (null hs)
  ]
```

Also extend the module's header comment: after the INERT paragraph, add

```haskell
-- Plus the DISCARDED words: a line the language reads as an assertion whose
-- word no rule carries onward ('Lips.Kernel.Engine.Reach'). `generate` refuses
-- such an engine, so this reports the ones committed before the gate existed.
```

- [ ] **Step 4: Implement the report block in `Main.hs`**

In `renderDiagnosis`, add `droppedBlock` to the assembled list
(`... ++ inertBlock ++ droppedBlock ++ openBlock`) and define it beside
`inertBlock`:

```haskell
    -- A word the language binds and no rule carries: the line looks
    -- load-bearing and is not, so editing that word changes nothing. The gate
    -- refuses such an engine now; this names it for engines committed earlier.
    droppedBlock
      | null (diagDropped d) = []
      | otherwise =
          "" : ("read and discarded (" <> tshow (length (diagDropped d))
                  <> ") -- these words reach no output:")
              : [ "  line " <> tshow n <> "  \"" <> t <> "\"  <"
                    <> T.intercalate "> <" hs <> ">"
                | (n, t, hs) <- diagDropped d ]
```

- [ ] **Step 5: Run the tests and the live proof**

Run: `just test`
Expected: 339 examples, 0 failures, `-Wall` clean.

Run: `git add -A && nix run . -- check examples/hello.http.lips`
Expected: the report contains a `read and discarded (1)` block naming line 3
and `<lang>`, and the command still SUCCEEDS (the contract gate still passes).

Run: `just check-expect`
Expected: every example passes, exactly as before.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Kernel/Lang/Diagnose.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "diagnose: name the program words the engine reads and discards"
```

---

### Task 6: State the rule in the mint prompt

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs`

A capability (or prohibition) the model is told nothing about is a refusal
waiting to happen. State it once, where rules are described.

- [ ] **Step 1: Add the paragraph**

In the `RULES` section, directly after the line
`, "several options, that one rule emits them all, ';'-separated."`, insert:

```haskell
  , "EVERY WORD YOU READ MUST REACH OUTPUT: if a pattern binds a hole and a"
  , "fact/steer/... emit carries it, some rule matching that subject MUST use"
  , "it -- through <value>/<value.N> for a word in the assertion, or by naming"
  , "the aligned <capture> in an emit path or value. A rule that matches such a"
  , "decision and emits only constants is REJECTED: the program's word would"
  , "govern nothing, so editing it would change no output while the sentence"
  , "still looks load-bearing. If a word genuinely carries no value of its own,"
  , "read its line as a 'concept' instead (decoration, reported as such); if the"
  , "program needs it honored and you cannot, file a 'gap' rather than a rule"
  , "that ignores it."
```

- [ ] **Step 2: Verify**

Run: `just test`
Expected: 339 examples, 0 failures (the prompt is data; no test pins this text).

- [ ] **Step 3: Commit**

```bash
git add kernel/src/Lips/Generate/Minting.hs
git commit -m "mint prompt: a rule may not read a program word and discard it"
```

---

### Task 7: Record what landed

**Files:**
- Modify: `DESIGN.md` (ledger §13, Done section — add an entry beside "Static
  rule orthogonality" and "Inert lines are reported")
- Modify: `TODO.md` (item 1a)

- [ ] **Step 1: Write the ledger entry**

Add after the "Static rule orthogonality (critical pairs at the mint gate)"
entry:

```markdown
- **A discarded program word is a static defect (`droppedValues`).** A line lips
  READS is not thereby honored: a rule could match the fact it produces and emit
  only constants, so the program's word governed nothing and editing it changed
  no output. `examples/http` shipped exactly this (`p3` binds `<lang>`, `r3`
  emits the literal `buildGoModule`), and a mint filed it against itself while
  minting a CLI tool, naming this check as the honest fix: "the existing example
  works only because nobody edits that word".
  `Lips.Kernel.Engine.Reach.droppedValues` now decides it statically: for every
  template hole, run the pattern's own substitution with markers (so the check
  sees the segments `crystallize` will build, never a second copy of that rule),
  find the rules whose left-hand side unifies with the decision it feeds
  (`subjectsUnify`, extracted from the overlap check so one unification serves
  both), and ask whether any of them carries the word -- by reading the value
  (`valueUsesAssertion`: `<value>`/`<value.N>`) or by naming the aligned subject
  capture in an emit path or value. `generate` refuses such an engine at the
  gate, beside orthogonality; `check` reports it per program line for engines
  committed before the gate existed. Where alignment is undecidable the answer
  is "carried" (a literal rule segment means the word selects the rule; an
  unmapped emit is the build's existing loud failure), because the gate must
  pass every sound engine. This closes the enforcement half of the
  silent-demotion finding whose visibility half `diagInert` closed: a word is
  now either used, or declared decoration and reported. Two deliberate
  non-goals, recorded in `TODO.md`: a partial drop (a rule using `<value.1>` of
  a two-hole value) and a per-hole decorative report.
```

- [ ] **Step 2: Rewrite `TODO.md` item 1a**

Replace the item 1a paragraph with:

```markdown
   a. **Silent concept demotion (deduce-or-fail's blind spot).** Two halves
      landed (ledger §13): `diagInert` names lines that realize nothing, and
      `droppedValues` makes a word the language reads and then discards a static
      defect refused at the mint gate. Still open: (i) a PARTIAL drop -- a rule
      reading `<value.1>` of a value built from two holes silently drops the
      second, which needs a sound static token map from holes to positions;
      (ii) a per-hole decorative report, for a hole demoted to a `Concept` on a
      line that otherwise realizes (no committed engine emits a `Concept`, so
      this has no call site yet); (iii) the compiled artifact still records no
      dependency on the program lines its baked source came from, so an edit to
      one of them compiles to an unchanged binary. Candidate for (iii): record
      the source's line dependencies at mint and fail loud when one changes.
```

- [ ] **Step 3: Fix the dangling reference while here**

`TODO.md` item 1 and DESIGN.md both cite `docs/gaps/README.md`, deleted in
`ca09f97`. Append to the item 1 lead sentence: `` (the report was deleted with
`ca09f97`; read it with `git show ca09f97^:docs/gaps/README.md`) ``.

- [ ] **Step 4: Commit**

```bash
git add DESIGN.md TODO.md
git commit -m "ledger: record the dropped-value guard; TODO 1a narrowed to three open cases"
```

---

## Self-Review

**Spec coverage.** The gap being closed is finding 3 / finding 1 of the deleted
gap report, tracked as `TODO.md` item 1a: enforcement of "a word lips reads must
matter". Task 3 decides it, Task 4 enforces it at the only door engines enter,
Task 5 makes it visible for engines already committed, Task 6 tells the mint,
Task 7 records it. Tasks 1 and 2 are the two primitives Task 3 needs, each
independently testable.

**Placeholders.** None: every step carries the code or the exact command.

**Type consistency.** `valueUsesAssertion :: Value -> Bool` (Task 1) is used in
Task 3's `carries`. `subjectsUnify :: [Text] -> [Text] -> Bool` (Task 2) is used
in Task 3's `judge`. `droppedValues :: [Pattern] -> [MapRule] -> [DroppedValue]`
and `renderDroppedValue :: DroppedValue -> Text` (Task 3) are used in Task 4's
`assertValuesReach` and Task 5's `droppedLines`. `DroppedValue` field names
(`dvPattern`, `dvHole`, `dvWhy`) are used consistently in Tasks 3 and 5.

**Known consequence to accept before starting.** `examples/http` is provably
defective under this check. It keeps working (gate-only failure) and now says so
in `check`. Re-minting it will be REFUSED until either branching on a captured
word exists (`TODO.md` item 1c) or the mint reads that line as decoration. That
is the intended effect: the gap stops hiding.

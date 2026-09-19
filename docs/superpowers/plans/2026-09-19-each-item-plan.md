# An Item With Structure (`.each`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** an item of a list may carry several holes, so a sentence like `habit`
p9 stops freezing at the count its author happened to write:

```
given the log of "2026-01-01" for "run", "2026-01-02" for "read" and "2026-01-04" for "run", the habit "run" prints "#..#"
```

**Why the list hole alone does not close it** (checked in the committed engine,
2026-09-19): `habit` p9 emits ONE fact whose assertion is an eight-part value,
and `r8` reads the parts by position (`claim.<q>.feed "[ \"<value.1>\t<value.2>\"
\"<value.3>\t<value.4>\" \"<value.5>\t<value.6>\" ]"`). Both sides are frozen: the
template at three entries, the rule at six parts. The remedy has to turn each
entry into its OWN decision, which the rule side then aggregates into one Nix
list the way `filesystem.read` already aggregates (`claim.<id>.feed` is a Nix
list, TODO 1c).

**Architecture:** an item pattern is a nested pattern whose block is a HOLE, not
a run of lines.

- Spelling `p10.each.p9.e`: pattern `p10` reads one item of `p9`'s list hole `e`.
  It parses to `pParents = ["p9"]` plus a new `pItemHole = Just "e"`, so every
  existing scope mechanism (`ancestorsOf`, `holesInScope`, `scopedBindings`,
  the cycle and unbound-in-scope gates, `<k:key>` families) keeps working with
  no change: an item pattern IS nested under its parent.
- What differs is only the MATCH: crystallize matches the child's template
  against the item's tokens instead of against a following line. The child's
  `<n:index>` is the item's position; its captures shadow the parent's.
- Deduce-or-fail: an item no child reads fails the line, naming the item and the
  children that were tried. Two children reading one item is an ambiguity, as it
  is for lines.

**Tech Stack:** Haskell, hspec in `kernel/test/Spec.hs`, no new dependencies.

## Global Constraints

- The kernel stays domain-blind: no separator, no conjunction, no item count and
  no domain word in kernel code.
- One construct, two depths: a list hole with no `.each` child keeps binding the
  item as a value (what `examples/policy` uses). `.each` only adds structure.
- `-Wall` clean, `just test` between steps, single-line commits.
- Flakes see only tracked files: `git add` before `nix run`.

---

### Task 1: The Id and Its Guards

- [ ] Test: `p10.each.p9.e` parses to id `p10`, parent `p9`, item hole `e`, and
      round-trips through `patternToDecision` / `decisionToPattern`.
- [ ] Test: `.each` naming a hole the parent does not bind is refused, naming
      both pattern and hole.
- [ ] Test: `.each` naming a hole that is not a LIST hole is refused.
- [ ] Test: an item pattern with a self-reference or two parents is refused
      (an item has exactly one list it belongs to).

### Task 2: Items Are Matched, Not Lines

- [ ] Test: the `habit` p9 shape reads three entries, and the same pattern reads
      two and five, each entry its own decision with `<n:index>`.
- [ ] Test: the child sees the parent's captures (`<q>` in the child's subject).
- [ ] Test: an item no child reads fails loud, naming the item.
- [ ] Test: two children reading one item is reported as an ambiguity.
- [ ] Test: two lists in one sentence keep their own children (`board` p8).
- [ ] Test: decision ids stay line-anchored and distinct (`d9.1 .. d9.k`).

### Task 3: The Static Gates and the Editor

- [ ] Test: a demand over an item pattern's subject is answerable (the marker
      path runs through `holesInScope`, which already inherits the parent's).
- [ ] Item patterns are not offered as line completions in the LSP (they read an
      item, never a line).

### Task 4: Teach the Mint, Then Re-Mint `habit`

- [ ] `assets/mint/body.md`: the `.each` form beside the list hole, with the
      witness sentence as its example, and a test that the prompt states it.
- [ ] `lips generate examples/habit.lips` on opus-5, `--fresh`.
- [ ] The re-minted engine reads the witness at three entries AND at five, with
      `claim.<q>.feed` aggregated from the per-item facts.
- [ ] `just test`, `just check-expect`, `just test-draft`, `nix flake check -L`.
- [ ] DESIGN §13 entry extended; `TODO.md` 1c closed for the pattern side, with
      whatever remains stated in its own words.

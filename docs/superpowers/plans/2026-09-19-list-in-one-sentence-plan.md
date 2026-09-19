# A List Within One Sentence

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** one pattern reads a sentence that lists N items, for any N. Today every
list-shaped sentence is spelled once per item count, so `examples/policy` carries
24 arity clones (`pr1..pr4`, `px1..px4`, ...) and `it may run git, rg, ls, cat and
jq.` does not crystallize at all (measured 2026-09-19: `line 4  no match`).

**Why it is a kernel bug, not an engine defect:** the grammar the engine fills
must be closed and complete (invariant 3). An engine that enumerates arities is
an open list, and the arity it stops at is arbitrary. The same freeze hits the
witness sentences filed in `TODO.md` 1c (`habit` p9, `board` p8, `logscan` p5),
which is the second reason the remedy must be one construct, not two.

**Architecture:** one new template token, `TList`, plus one new nesting form.

- `<p.list:,|or>` binds a RUN of tokens exactly as `<p.words>` does (same
  backtracking), then splits the run on the separators the ENGINE declares. The
  kernel learns no English: `,` and `or` come from the engine, the way a block's
  marker comes from the parent's template today.
- With no further declaration each slice IS the value, which covers every
  `policy` sentence with one token of new syntax.
- When an item carries structure (`habit` p9's `<d> for "<h>"`), a child pattern
  parses one slice: `pe.each.p9.log`, nesting on the parent's HOLE the way
  `p.under.q` nests on the parent's line.
- Emits that mention the list hole repeat once per item; `<p:index>` is the
  1-based position, the same `SIndex` meaning `Nest.hs` already fills per line.

**Separator grammar, everything expressible:** a `|`-separated list; each item is
a bare word or a `"..."` span with the standard `\"` / `\\` escapes of
`Lips.Kernel.Surface`. So `<x.list:"|">` lists on a pipe, `<z.list:">">` on an
angle bracket, `<w.list:","|"and then">` on a two-token word. One quoting
convention for the whole language, never a second escape scheme.

**Tech Stack:** Haskell, hspec in `kernel/test/Spec.hs`, no new dependencies.

## Global Constraints

- The kernel stays domain-blind: no separator, no conjunction and no item count
  is ever named in kernel code.
- Deduce-or-fail: a run whose slices a child pattern cannot fully consume fails
  loud, naming the pattern; never a partial item.
- A quoted item is atomic: the quote is the mark that says "these characters are
  a value", so a separator inside it never splits.
- `-Wall` clean, `just test` between steps, single-line commits.
- Paths only through `Lips.Identity`. Flakes see only tracked files: `git add`
  before `nix run`.

---

### Task 1: A Hole Body Ends at the `>` Outside Quotes

`holeName` and `fusedSegs` find the closing `>` with a naive `breakOn ">"`, so a
separator containing `>` could not be written. Use the quote-aware helpers in
`Lips.Kernel.Surface` (the module whose header already records why the careful
rule became the only rule).

- [ ] Test: `<z.list:">">` parses as one list hole whose separator is `>`.
- [ ] Test: an ordinary shell redirect in a template (`cmd > file`) still reads
      as literals, and `<a><b>` still reads as a fused token.
- [ ] Implement; `just test` green.

### Task 2: `TList` — Parse, Render, Match, Split

- [ ] Test: `parsePatternBody` reads `it may never read <p.list:,|or> => ...`
      and `renderBody` round-trips it byte for byte.
- [ ] Test: `matchTemplate` on `it may never read a, b or c` binds the run, and
      the split yields `["a","b","c"]` (glued `,` stripped, standalone `or`
      consumed).
- [ ] Test: backtracking — `on the network it may reach <d.list:,|and> and
      nothing else` over `github.com and crates.io, and nothing else` yields
      exactly `["github.com","crates.io"]`.
- [ ] Test: a quoted item keeps its content (`"a, b"` stays one item).
- [ ] Test: a list hole with an empty separator list is refused at read time,
      naming `.words` as the form for an unsplit run.

### Task 3: Emits Repeat Per Item

- [ ] Test: `... => fact fs.deny.<p:index> "<p>"` on a three-item line emits
      `fs.deny.1`, `fs.deny.2`, `fs.deny.3`.
- [ ] Test: an emit that does NOT mention the list hole is emitted once.
- [ ] Test: `<p>` as a subject segment repeats too (`cmd.<p>.policy`).
- [ ] The clash check in `parseBody` must allow `<p:index>` for a LIST hole
      (the index OF that list) while still refusing it for a plain hole.

### Task 4: `.each` — An Item With Structure

- [ ] Test: `pe.each.p9.log :: <d> for "<h>" => ...` emits one decision per
      item, with the item's own captures and `<n:index>`.
- [ ] Test: two lists in one sentence stay apart (`board` p8's five inputs and
      three outputs), each child naming its own hole.
- [ ] Test: a slice the child cannot fully consume fails loud, naming pattern
      and slice.
- [ ] Test: the `.each` id round-trips through the `.lang` store, and an id
      naming a hole the parent does not bind is refused.

### Task 5: Re-Mint `policy`, Then The Ledger

- [ ] `lips generate examples/dev.policy.lips` on opus-5; the 30-pattern grammar
      should come back at 6 or so, with the arity clones gone.
- [ ] `just check-expect` holds against the committed `.expect`.
- [ ] `it may run git, rg, ls, cat and jq.` crystallizes without any kernel or
      grammar change — the completeness test.
- [ ] DESIGN §13 milestone entry; `TODO.md` 1c rewritten to point at the
      construct and to name `habit`/`board`/`logscan` as the remaining re-mints.

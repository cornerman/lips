# List Aggregation: B + C, No Block Construct

Status: approved design (supersedes the open questions in
`docs/superpowers/plans/2026-07-24-list-aggregation-plan.md` and its companion
`-open-questions.md`; all five open questions are resolved below).

## Why this was re-examined

A doubt surfaced about the line-centric, unordered semantics: "we cannot escape
it, and maybe we should not." The re-examination separated two premises that had
been bundled:

- **Premise one — the base is an unordered set of decisions.** Precedence is the
  strength lattice, never line position. This buys confluence (same base → same
  system, order-independent) and matches the realization target: a NixOS module
  is an attrset, which is unordered.
- **Premise two — one decision per line, no blocks.** This buys "text diff ≈ set
  diff" and flat authoring.

Premise one is honest to reality (Nix attrsets are unordered; Nix lists are
ordered, and order is already a *value* property). Premise two is what keeps
violating when a collection is richer than one line. The grammar churn is the
cost of premise two, not premise one.

**Imperative is out.** Making line position a precedence key would break
confluence (reorder a file, get a different system), muddle merge-by-strength,
and mismatch the target (you would flatten order away to realize into an
attrset). Order belongs only to lists, and lists are values, not the decision
algebra. The founding move — "intent is data, realize maps decisions to systems"
— is preserved; imperative reverts it to "intent is a program."

**The churn is converging.** After B+C land, the value grammar is complete over
the Nix value algebra minus computation, and the template grammar is complete
except for block aggregation, which the flat model deliberately avoids. The only
remaining expressiveness wall is glue (computation), a separate, deferred axis
(DESIGN.md §7). B+C are the last non-glue structural gaps for "many of X."

## The decision: two capabilities, no block construct

"Many of X" is delivered by two domain-blind kernel capabilities. The model
composes them into whatever collection shape fits a program; **the kernel
dictates no collection style** — no header requirement, no indent, no brackets,
no scoping. This is the design's end state of "do not assume shape": the
collection is an emergent view of N lines, not a construct.

### B — Append merge mode (merge physics)

Today merge (`Base.hs`) is replace-by-strength only; two decisions on one subject
at equal strength with differing assertions are a `Conflict`. B adds a second
merge mode, `Append`, **derived from the engine's option schema (data), never
carried on the decision**:

```
schemaMergeModes :: OptionSchema -> [Subject] -> Map Subject MergeMode
```

A subject whose schema leaf is `OTListOf _` resolves to `Append`; all others stay
`Replace`. Wildcard schema entries (`"*"`) are matched against the base's
concrete subjects with the existing `matchesPath` (`OptionType.hs`), so an
`attrsOf`-of-list works too. `Base.resolve` gains a `Merge Subject MergeMode`
argument (default empty → all `Replace`, byte-identical to today).

The kernel learns "this subject is a list" abstractly, never what is listed.
Domain-blind preserved (invariant 1).

`Append` semantics, scoped to a list-typed subject:

- Group by subject as today; **all top-strength decisions contribute** their
  elements. Lower strengths are shadowed as a whole — a stronger decision
  *replaces* the entire list (the override path, Q1 resolved: replace, not
  append-across-strengths).
- Equal strength + different assertion is **not a conflict**: it is aggregation.
  Equal strength + equal assertion (the same element twice) is kept as-is —
  append all, let the target dedup downstream (e.g. `systemPackages`). The kernel
  owns no dedup policy.
- Result for the subject is one synthetic decision whose assertion is the
  assembled `VList`, in assembly order.

**Cross-module list composition stays NixOS's job.** Replace-across-strengths
means a lips module beside a hand-written defaults module concatenates natively
(the coexistence defense). Append-across-strengths would special-case lists in
the merge algebra for a benefit NixOS already provides; one merge model wins.

### C — multi-token tail hole (capture/value grammar)

A hole variant `<value.tail>` binds the rest of a line's tokens as a `VList`,
each element coerced to the rule's element type. One line `install htop,
ripgrep, tmux.` → one decision, `VList [htop, ripgrep, tmux]` (token order
preserved). The spelling is kernel grammar (consistent with `<value.N>`);
the model chooses to use it; the program's item syntax is still minted by
the patterns. An unresolved or **empty tail fails loud** (deduce-or-fail, Q4).
This spans the capture layer (`Pattern.hs` template hole binding, extended to
bind a token tail) and the value layer (`Value.hs`, the `VList` result and
per-element coercion); exact module split is the implementation plan's call.

B and C compose: B is the cross-line merge; C is the within-line multi-capture.
Together they are the complete grammar for "many of X."

### D — collapsed (no block construct, no scoping)

A "block" / multiline collection is **not a third capability**. It is what B
does to N lines: each item line matches a pattern that emits a same-subject
decision (a one-element `VList`), and B aggregates them in source-line order.
`classifyLines` (`Crystallize.hs`) already classifies each line independently
with no cross-line state, so this needs zero new crystallize machinery — only B
on the merge side.

- **No header required.** The whole-program-is-one-list case is N item lines +
  B. A header, if the model wants one, is an optional `Concept` line (already
  handled: decorative, dropped before realize). The kernel never requires a
  header, never opens a scope for it.
- **No scoping.** Reusing a bare marker (`-`) across multiple lists in one file
  is handled by the model minting distinct item patterns (`- pkg <pkg>`, `-
  svc <svc>`); the marker carries the verb. This is complete (pattern matching
  already does it) but slightly less ergonomic. Scoping (a stateful matcher that
  tracks open scopes, with a header-as-scope-opener) would buy "state the verb
  once" ergonomics at the cost of a stateful matcher and a re-assumed shape.
  Deferred by YAGNI and the growth doctrine: no real program has demanded
  marker-reuse across lists yet.

This is the maximally shape-free reading of "do not assume shape": the kernel
offers B (aggregate) and C (tail), and imposes no collection shape.

## Order — assembly only, from provenance the kernel already has

Order is "sometimes" — lists are ordered (by assembly), scalars are unordered
(replace). Position is never a merge key; it is the assembly rule for `Append`
subjects, derived from `SourceLoc` the kernel already stamps.

- **Across lines:** `SourceLoc { locFile, locLine }` already anchors every human
  decision. `Append` assembles top-strength contributors ordered by
  `(locFile, locLine)`.
- **Within a line:** token order, preserved by the tail hole (C).
- **Override:** strength. A `Law` decision on a list subject replaces the whole
  list; equal-strength decisions append. Precedence is unchanged.

## Where assembly runs (architecture)

`realize` (`Realize.hs`) treats `unAssertion` as final Nix text — by realize
time, `fillValue` has already rendered each decision's value. So list assembly
(concatenating `VList`s, re-rendering once) runs **before realize**, on `Value`s,
not on rendered text. A small assembly step between `resolve` and `renderModule`
(or folded into `resolve` for `Append` subjects) takes, for each `Append`
subject, the top-strength contributors, parses each assertion's `Value`,
concatenates the `VList` element lists in assembly order, and yields one
synthetic decision carrying the assembled `VList`. Realize then renders it as a
single list assignment, unchanged. `resolve` gains schema awareness only through
the precomputed `MergeMode` map — it never sees `OptionType` semantics, only
"this subject appends."

## Completeness check

Every "many of X" case against B+C+flat+optional-Concept:

- Whole file is one list, no header: N item lines + B. ✓
- Header + items: optional `Concept` + B. ✓
- One line, many items: C tail hole. ✓
- Ordered list (`ExecStartPre`): B assembles by source-line order. ✓
- Record-valued elements (`ensureUsers`): `VAttr` (Done) + B appends. ✓
- `attrsOf` per-item keying: Done, orthogonal to B. ✓
- Cross-module composition: NixOS native (replace-across-strengths). ✓

No gap remains.

## Invariants preserved

1. `run` never calls a model. B+C are kernel physics; deterministic, offline.
2. Deduce-or-fail: empty tail fails loud; an unmet demand surfaces as a question.
3. Illegal states unrepresentable: `Append` mode is derived from schema, never on
   the decision; the rhs value grammar stays closed (computation still routes to
   glue). The canonical stored form stays one-decision-per-line — D produces N
   decisions (one per item line), identical in shape to today's flat lines; only
   the loose `.lips` form gains multiline authoring, and the loose form was
   never one-decision-per-line (dense lines already emit several; Concepts are
   decorative). Notation dissolves.
4. Workarounds become kernel physics: a mint that needs "many of X" now has B+C
   in the kernel, not a prompt plea.
5. Regeneration gated: the committed `.expect` contract must hold against the new
   engine's realized module; a break is a human decision (delete `.expect`,
   regenerate), never silent. `@gen:<id>` stamps travel on each contributor; the
   assembled decision's provenance is the contributor set, so the chain stays
   walkable to the metal. Regeneration canonicalizes before hashing.
6. Every minted line stamped `@gen:<id>`; re-hashes from `.generation`.

## Resolved open questions

| Q | Question | Resolution |
|---|---|---|
| Q1 | Strength mixing in an `Append` subject (Law over Stated) | **Replace** the whole list. `Append` is only same-strength aggregation. Cross-module composition is NixOS's job. |
| Q2 | Order among derived contributors | Human (by file, line) before derived (by rule id, then parent id). Rare in practice. |
| Q3 | Tail-hole spelling | `<value.tail>` (consistent with `<value.N>`). |
| Q4 | Empty tail | **Error** (deduce-or-fail, never guess). |
| Q5 | `Append` for `attrsOf`-of-list | Reachable via wildcard schema match; conformance test before claiming Done. |
| — | Block construct / scoping | **Collapsed.** No third capability; D is N lines + B. Scoping deferred until a real program demands marker-reuse. |
| — | Indentation | Whitespace stays a separator (foundational, shared with the tokenizer). Indent-style blocks not expressible; marker-style is. Achievable later via a tokenizer extension if a real program demands it. |

## What is explicitly NOT done

- No per-problem kernel branch. "Is this option a list" comes from the schema.
- No new ordering key on `Decision`. Order is assembly-only, from `SourceLoc`,
  scoped to `Append` subjects.
- No dedup policy in the kernel. Append all; the target dedups.
- No positional precedence. Strength stays the only precedence.
- No block construct, no scoping, no dictated collection syntax.

## Relationship to the existing plan and to peer work

This design supersedes the open questions in
`docs/superpowers/plans/2026-07-24-list-aggregation-plan.md` (all resolved
above). The plan's "two closures, one assembly rule" structure is retained; the
conceptual addition of this design is the explicit **D-collapse**: the plan did
not propose a block construct, but a "we want blocks" moment during review could
have introduced one. This spec closes that door on "do not assume shape"
grounds, recording that a block is an emergent view (N lines + B + optional
Concept), not a construct.

A peer lips session is landing orthogonal grammar-completeness work (H1–H4:
engine-path render escape-awareness, attrset hyphen keys, submodule field
type-checking, QuickCheck round-trip properties). That work closes already-built
grammars; it is independent of B+C and holds regardless. The peer session has
been told: take H4+H1+H2 (properties-first), hold H3 (submodule field
type-checking) because the B assembly step may want field checks on the
assembled list rather than each contributor, and do not start B/C against the
plan in TODO.md until this design lands.

## Milestone ledger impact (DESIGN.md §13)

On landing, move from "Missing" to "Done":

- "List aggregation across decisions (N lines -> one list-valued option)" (B).
- "Multi-token tail holes" (C), the within-line case.

Add as a Done sub-item: "Ordered list assembly by source provenance."

Do NOT add a block-construct milestone — D is collapsed by design.

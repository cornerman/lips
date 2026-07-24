# List Aggregation: Full Flexibility, Ordered

Status: design note (not yet built). Closes the two "Missing" holes in
`DESIGN.md` section 13 and the multi-token tail hole, so list-valued options
are fully expressive: across lines (B), within a line (C), and ordered.

## The problem, precisely

Merge today (`Base.hs`, `Decision.hs`): group by `Subject`, pick the top
`Strength`, replace; equal strength + different `Assertion` = `Conflict`.
`Assertion` is opaque text, compared by equality only. The base is an
*unordered* set; precedence is the strength lattice, never line position.

This makes three things inexpressible (all are kernel bugs under invariant 3,
completeness by construction — a missing grammar case is a kernel bug):

- **B — flat `listOf` from multiple lines.** Two decisions on the same subject
  are an equal-strength conflict, never a list-append. Example: several
  `install <pkg>.` lines cannot fold into one
  `environment.systemPackages = [ ... ]`. The `attrsOf` value-keying path
  (Done) only covers targets with an `attrsOf` surface; a flat `listOf` has none.
- **C — a variable-length list in one line.** A template hole binds exactly one
  token (or one quoted span); there is no "tokens N onward" slice
  (`DESIGN.md` Missing, multi-token tail). So `install htop, ripgrep, tmux.`
  cannot extract the tail.
- **Order.** Nix lists are ordered. Some lists care about order
  (`serviceConfig.ExecStartPre`); some do not (`systemPackages`). lips must
  carry order where the author means it, without making line position a general
  merge key (which would break the replace-by-strength invariant).

## Design constraints (do not break)

1. Kernel is domain-blind (AGENTS.md, "The Kernel Knows Nothing"). The kernel
   may learn "this subject is a list" only abstractly, never what is listed.
   Per-problem facts ("`environment.systemPackages` is a `listOf`") live in the
   engine's option schema (data), exactly as `${pkgs.<path>}` names a concrete
   thing the kernel never inspects.
2. Merge stays replace-by-strength. Position may never become a *precedence*
   key. Order is an *assembly* rule for lists, orthogonal to precedence.
3. Completeness by construction: close the grammar in the kernel, not in the
   prompt. No per-problem kernel branch; the test is "an unforeseen flat-list
   option works with no kernel change."
4. Existing engines realize byte-identically. The new mode is opt-in by schema;
   an empty list-type set is today's behavior.

## Proposal: two closures, one assembly rule

### Closure 1 — B: a list-contribution merge mode (kernel)

Add a second merge mode, `Append`, alongside today's `Replace`. Which mode a
subject uses is **derived from the option schema** (engine data), never carried
on the decision:

```
schemaMergeModes :: OptionSchema -> [Subject] -> Map Subject MergeMode
```

A subject whose schema leaf type is `OTListOf _` resolves to `Append`; all
others stay `Replace`. Wildcard schema entries (`"*"`) are matched against the
base's concrete subjects with the existing `matchesPath` (`OptionType.hs`), so
an `attrsOf`-of-list works too. `Base.resolve` gains a `Map Subject MergeMode`
argument (default empty → all `Replace`, byte-identical to today).

`Append` semantics, scoped to a list-typed subject:

- Group by subject as today, but **all top-strength decisions contribute** their
  elements; lower strengths are shadowed as a whole (a stronger decision
  *replaces* the entire list — the override path).
- Equal strength + different assertion is **not a conflict**: it is
  aggregation (the whole point). Equal strength + equal assertion (the same
  element twice) is kept as-is — append all, let the target dedup downstream
  (e.g. `systemPackages`). This keeps the kernel honest about order and avoids a
  dedup policy the kernel has no business owning.
- Result for the subject is one synthetic decision whose assertion is the
  assembled `VList`, in assembly order.

The kernel knows `OTListOf` means "list, append", nothing about the element
type's meaning. Domain-blind preserved.

### Closure 2 — C: a tail hole in the value/capture grammar (kernel)

Extend the hole grammar with a tail form `<value*>` (or `<value.tail>`) that
binds the rest of the line's tokens as a `VList`, each element coerced to the
rule's element type. Fill produces a `VList` of the captured tokens in token
order. This is a `Value`/`Capture` grammar extension (`Engine/Value.hs`,
`Capture.hs`), not a prompt fix. An unresolved or empty tail fails loud, like
any hole.

With C, one line `install htop, ripgrep, tmux.` produces one decision whose
assertion is `VList [htop, ripgrep, tmux]` (token order preserved). With B,
another line `install curl.` produces `VList [curl]`, and B appends both:
`VList [htop, ripgrep, tmux, curl]`.

B and C compose: B is the cross-line merge; C is the within-line multi-capture.
Together they are the complete grammar for "many of X."

### The assembly rule — order, for free, from provenance the kernel already has

Order comes from **provenance the kernel already records**, with no new
ordering dimension on the decision:

- **Across lines:** `SourceLoc { locFile, locLine }` (`Decision.hs`) already
  anchors every human decision. `Append` assembles top-strength contributors
  ordered by `(locFile, locLine)`. This reuses existing provenance; it does
  not add position to the decision algebra. The base stays an unordered set
  for *precedence*; position is only the *assembly* key for lists.
- **Within a line:** token order, preserved by the tail hole (C).
- **Override:** strength. A `Law` decision on a list subject replaces the whole
  list; equal-strength decisions append. Precedence is unchanged.

So order is "sometimes" — exactly the intuition: lists are ordered (by
assembly), scalars are unordered (replace). Position is never a merge key; it is
the assembly rule for `Append` subjects, derived from `SourceLoc` the kernel
already stamps.

### Where assembly runs (architecture)

`realize` (`Realize.hs`) treats `unAssertion` as final Nix text — by realize
time, `fillValue` has already rendered each decision's value. So list assembly
(concatenating `VList`s, re-rendering once) must run **before realize**, on
`Value`s, not on rendered text. Cleanest: a small assembly step between
`resolve` and `renderModule` (or folded into `resolve` for `Append` subjects)
that, for each `Append` subject, takes the top-strength contributors, parses
each assertion's `Value`, concatenates the `VList` element lists in assembly
order, and yields one synthetic decision carrying the assembled `VList`.
Realize then renders it as a single list assignment, unchanged. `resolve`
gains schema awareness only through the precomputed `MergeMode` map — it still
never sees `OptionType` semantics, only "this subject appends."

### `.expect` and regeneration (invariants 4–5)

A list aggregation change is a real semantic change. The committed `.expect`
contract must hold against the new engine's realized module; a break is a human
decision (delete `.expect`, regenerate), never silent. The `@gen:<id>` stamps
travel on each contributor; the assembled decision's provenance is the
contributor set, so the chain stays walkable to the metal. Regeneration
canonicalizes (sorted subjects, line-ordered list elements) before hashing, so
a trivial re-edit does not churn ids (Survey E:193, already the doctrine).

## What is explicitly NOT done

- No per-problem kernel branch. "Is this option a list" comes from the schema.
- No new ordering key on `Decision`. Order is derived `SourceLoc`, scoped to
  `Append` subjects.
- No dedup policy in the kernel. Append all; the target dedups.
- No positional precedence. Strength stays the only precedence.

## Open questions to resolve before building

1. **Strength mixing within an `Append` subject.** A `Law` "packages = [a]"
   over `Stated` "install b": replace (whole list = [a]) is the proposal. Confirm
   "stronger replaces the whole list" beats "stronger appends too." Recommend:
   replace — it is the clean override, and matches the scalar semantics.
2. **Derived (rule-produced) contributors.** `Append` contributors from human
   lines carry `SourceLoc`; derived ones carry `Derived ids rule`. Order among
   derived contributors (and derived vs. human) needs a stable key. Recommend:
   human (by line) before derived (by rule id then parent id); rare in practice.
3. **Tail-hole spelling.** `<value*>` vs `<value.tail>` vs `<value...>`. Pick
   one; `<value.tail>` reads least ambiguously against `<value.N>`.
4. **Empty tail.** `<value.tail>` matching zero tokens: error (a line that says
   "many" must name at least one), or allowed (an empty-list assertion)?
   Recommend: error, consistent with "deduce-or-fail, never guess."
5. **`Append` for `attrsOf`-of-list.** Confirmed reachable via wildcard schema
   match; needs a conformance test before claiming Done.

## Milestone ledger impact (DESIGN.md section 13)

On landing, move from "Missing" to "Done":
- "List aggregation across decisions (N lines -> one list-valued option)" (B).
- "Multi-token tail holes" (C), the within-line case.

Add: "Ordered list assembly by source provenance" as a Done sub-item of the
list-aggregation milestone.

# Engine Synthesis: Plan for Minting the Engine's Back Half

Status: designed, ready to implement. Companion to
`2026-07-18-lipsidea-design.md` (spec v2, section 13: the central gap) and
`2026-07-18-crystallization-plan.md`.

## Why This Matters

Crystallization made the language (the engine's front half) generated data.
The back half -- obligation-to-mechanism rules and demands -- is still
hand-written Haskell (`Engine.Feed`), so lips only works for feed-shaped
programs. This milestone makes the back half data too, minted by the same
`generate` call, interpreted by generic kernel executors. After it, `generate`
works for any problem whose mechanisms are NixOS option assignments, and
`Engine.Feed` is deleted (a simplification: less code, more generality).

## Design

### One artifact: `.lang` becomes the whole engine

The minted file carries three decision groups, same canonical text, one file
so regeneration is atomic and the halves cannot drift:

    lang.pattern.<id>   -- front half: loose line -> decision (as before)
    engine.rule.<id>    -- back half: decision -> ground option assignments
    engine.demand.<id>  -- back half: required subject + question

### Rule data shape

A minted rule matches one (kind, subject) and emits ground NixOS option
assignments. Body sub-grammar inside the assertion:

    match <kind> <subject> => <optionPath> "<rhs>" ; <optionPath> "<rhs>" ...

`<rhs>` may contain the hole `<value>`, filled verbatim with the matched
decision's assertion text. Example (the feed engine as data):

    match fact feed.cadence => systemd.timers.ledger-ingest.timerConfig.OnCalendar "\"<value>\""

Interpretation is a generic executor (`toRule`): match kind+subject, emit
`Meta` decisions; the refiner stamps provenance as always.

Deliberate restriction: a minted rule emits only ground (`Meta`) decisions, so
minted rule sets terminate in one pass by construction -- no cascade, no
budget anxiety. The kernel's general `Rule` still supports cascades for
hand-written engines; minted engines earn cascades in a later milestone if a
real program needs them (YAGNI).

### Demand data shape

    demand <subject> "<question>"

Satisfied when any decision in the base has that subject (same semantics as
the hand-written `Demand`).

### Generate: the model mints the whole engine

The vocabulary hint (`Feed.vocabulary`) disappears: the model now invents the
intermediate subjects itself. Closure is checked, not trusted -- the
validation loop already catches every way the halves can miss each other:

- a pattern producing a decision no rule maps -> `Unmapped` (anti-MDA guard),
- a rule demanding a subject the program never states -> open question,
- a loose line no pattern matches -> `NoPattern`,
- overlapping patterns or rules -> `Overlapping`/`Overlap`.

New validation step: the realized module must parse as Nix
(`nix-instantiate --parse`) at generate time, closing the garbage-rhs hole
(a minted rule emitting syntactically invalid Nix).

Known accepted gap: a later value edit can inject characters that break the
Nix rendering (e.g. a quote in a path). Generate-time validation covers the
minted shapes with the actual program; a hostile edit fails at
`nixos-rebuild`, outside the loop. Escaping-by-construction is future work.

### Run

`run` loads the whole engine from `.lang` (patterns + rules + demands),
crystallizes, and drives the same pipeline with interpreted rules. Still pure,
still no model, still fail-loud.

## Implementation Steps (TDD, worktree)

1. `Lips.Engine.Data`: `MapRule`, `DemandSpec`, `toRule`, `toDemand`;
   body render/parse. Tests: round-trip, interpretation fires and emits.
2. `Lips.Lang.Lang`: `readLang`/`renderLang` handle the three groups,
   returning an `EngineData { patterns, rules, demands }`. Round-trip test.
3. Rewrite the corpus test against a data engine; delete `Engine.Feed`.
4. `Lips.Generate.Minting`: prompt teaches the full engine format (no
   vocabulary parameter); parser accepts pattern, rule, and demand lines,
   each confidence-prefixed.
5. CLI: generate validates (crystallize + run + nix parse) and writes one
   `.lang`; run loads the data engine. Delete the Feed import.
6. Live end-to-end: regenerate `examples/feed.loose` (model mints the whole
   engine); then a NON-feed program (e.g. a nightly backup job) to prove
   generality. Commit both as examples.

## Out of Scope

Cascading minted rules, escaping-by-construction for values, resampling
wiring, corpus enforcement on regenerate, migration, `lips dev`.

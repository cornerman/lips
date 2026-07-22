# Language as a Configurable Module: Reuse by Instancing

Status: planned, not started. Companion to `2026-07-18-lipsidea-design.md`
(spec v2, milestone ledger section 13). Written so the work resumes from this
document alone. Supersedes the earlier "shared-language corpus" sketch that
lived only in conversation: instancing rides Nix, not a lips-level corpus.

## Why This Matters

Today one program owns one private engine: `backup.loose` mints
`backup.loose.lang`, and the CLI derives the engine path by string
concatenation (`Main.loadLangOrDie`: `file <> ".lang"`). So a language cannot
be reused, and worse, the mint bakes one instance's identity into what should
be the reusable grammar. Look at the committed rule:

    r1 ... => services.restic.backups.ledger.paths "[ \"<value.1>\" ]" ; ...

The attribute key `ledger` was read out of the program's paths (`/var/lib/ledger`)
and frozen into the grammar. The grammar is parametric in the *values*
(`<value.N>`) but fixed in the *instance name*. Two backups need two full mints.

## The Model (settled by discussion)

A lips **language is one configurable NixOS module**, induced by generalizing a
small set of example programs. This is ordinary abstraction: you do not write N
programs for N cases, you write one configurable thing; the examples are how you
discover the right parameterization, and the deliverable is the single
configurable module.

Three facts, one set of holes:

1. **A pattern is the anti-unification (least general generalization) of the
   program lines it covers.** Align the example lines; tokens that agree stay
   literal (keywords), positions that disagree become holes. One example is
   under-determined (its own LGG; `daily` could be keyword or value); the second
   example forces the decision by diverging. This is deduce-or-fail at the
   grammar layer: a hole appears only where the evidence demands it, never by
   guess. It also grounds the design's "generalization radius" knob (spec
   Section 5) in evidence instead of steering prose.

2. **The holes are the module's option surface.** The slots found by
   generalizing the examples *are* the parameters a caller fills. Induction and
   configurability produce the same holes. YAGNI falls out for free: the option
   surface is exactly as wide as the examples diverged, never a speculative flag
   nobody demonstrated. The examples are the interface's justification.

3. **An instance is a configuration of that module.** The realized artifact is
   already an `attrsOf`-submodule instance
   (`services.restic.backups.<key>.*`); only the key was frozen. Bind the key to
   the program's own name and each program becomes one instance of an ordinary
   importable module. Multiplicity is then Nix's `attrsOf`, not a lips
   mechanism: a second backup is `services.restic.backups.home = { ... };` in
   plain Nix, merging natively beside the lips-generated instance.

Consequence: "do we need multiple programs?" splits. For reuse/multiplicity,
no (Nix instancing covers it). For defining the language well, yes (several
examples are how holes are correctly separated from keywords). You need enough
`.loose` examples to pin the grammar; past those, further instances are call
sites, authored as a thin `.loose` line or as a Nix option-set, indifferently,
because a configurable program takes its configuration from anywhere.

## Identity and File Layout

`<basename>.<language>`: the extension names the shared language, the basename
names the unique instance (guaranteed unique by the filesystem). `.loose` was
dead decoration; it is replaced by the domain extension.

| level | files | committed? |
|---|---|---|
| Language (shared by every `*.backup`) | `backup.lang` (grammar), `backup.generation` (mint record), `backup.expect` (behavioral contract) | yes |
| Instance (one per program) | `one.backup` (program), `one.backup.decisions` (crystal witness, derived) | program yes; `.decisions` gitignored |

`.expect` moves to language level: today's assertion `expect
services.restic.backups.ledger.paths from backup.job#1` is relational
(option-from-subject, value-independent). Once the instance key is a parameter,
the whole contract is a statement about the *grammar*, checked per program at
its own key. Per-program `.expect` dissolves into one `backup.expect`.

`.generation` stays a single record (embedding the whole example set and the
prompt), because generate re-mints the whole grammar from the whole example set
in one event. Every `.lang` line stamps the one event id; invariant 6 holds
unchanged. (The append-only event-log idea floated in discussion is dropped as
YAGNI: whole-corpus re-mint needs only one current record.)

## The `<self>` Binding (the one kernel change)

Rules reach the instance key through a reserved value hole, `<self>`, bound by
the imperative shell to the program basename. It is domain-blind, structural
like `<value>`/`<value.N>` (the solution's own identity, not a domain fact), so
it respects "The Kernel Knows Nothing".

It slots exactly where the option schema already carries a `"*"` wildcard
segment (the ledger's option-schema grounding models `attrsOf`-submodule
instance names as `"*"`). So the mint has a grounded, domain-blind rule: an
`attrsOf` instance segment is filled by `<self>`, never by a content-derived
name. That is what removes the `ledger` leak. Coexistence of two same-language
instances works from the start (distinct basenames, native Nix merge); no
deferral needed.

## Each Mechanism

- **generate** takes multiple programs: `lips generate <program>...` (all
  sharing one extension; a mixed set fails loud). The model sees the whole
  example set and generalizes; the harness gates by requiring every example to
  crystallize and to satisfy the committed `backup.expect`. One example still
  works (weak case: radius falls back to model judgement). Writes `backup.lang`
  + `backup.generation` + `backup.expect`. Option-schema grounding is unchanged.
- **print / run / check** change only in lookup: resolve `<ext>.lang` by
  extension; `<self>` = basename fills the schema wildcard; each program is its
  own importable, coexisting module. All deterministic, no model (invariant 1
  intact).

## Open Mechanism Decisions (recommended answers)

1. **How generate generalizes.** Model-generalizes-then-corpus-gates (feed all
   examples, model emits the grammar, harness rejects unless every example
   crystallizes) vs deterministic anti-unification in the kernel.
   *Recommend model + corpus gate for Phase 1* (smallest change; the corpus is
   the pin). Deterministic LGG is a later kernel capability if the model proves
   an unreliable generalizer.
2. **Where `backup.lang` is found.** Same directory as the program vs a search
   path. *Recommend same directory* (KISS/YAGNI; add a search path only once a
   grammar is shared across projects).

## Invariant Check (spec Section 13 / AGENTS.md)

Strengthened, not bent: run stays model-free (1); the `ledger` leak is fixed in
the *format* via `<self>`, not the prompt (4, workarounds become physics);
regeneration is now gated on a real multi-instance corpus (5, stronger);
provenance is unchanged single-record (6). Advances the Partial "cross-program
corpus" item and adds the new reuse capability; leaves "multi-language
composition" (its dual: many languages in one Solution) untouched.

## Phasing

1. **Reuse (this plan):** extension→language lookup; `.expect`/`.generation` to
   language level; multi-file generate with corpus gate; `<self>` value hole
   filling the `attrsOf` wildcard; replace the frozen `ledger` key.
2. **Later, if real:** deterministic anti-unification; a language search path;
   `.loose`-authored vs Nix-authored instance ergonomics.

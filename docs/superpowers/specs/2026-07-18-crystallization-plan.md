# Crystallization: Plan for the AI-Free Edit Loop

Status: planned, not started. Companion to `2026-07-18-lipsidea-design.md`
(spec v2), detailing the next prototype milestone. Written so the work can be
resumed from this document alone.

## Why This Matters

Crystallization is the step that delivers the whole point of lips: edit the
program and re-run it deterministically, with no model call. The design (spec
section 5) states the loop as "generate once, then the engine accepts edits
within the language without AI." That property does not exist yet.

## Current State (commit 72ee018)

The deterministic spine and the reading half of `generate` are built and
tested (33 examples, `-Wall` clean), in `kernel/`:

- Kernel calculus: `Lips.Kernel.{Decision,Base,Refine,Demand,Reader,Realize,Run}`.
- `run` pipeline with the anti-MDA guard (`Unmapped` fails loud).
- `generate` reading half: `Lips.Generate.{Reading,Harness}` plus `callPi` in
  `app/Main.hs`, routing the model call through `pi -p` (default
  `anthropic/claude-opus-4-8`).
- One hand-written engine, `Lips.Engine.Feed`, and examples under
  `kernel/examples/`.

The loop today is: `loose text --(model, every invocation)--> canonical
decisions --(deterministic)--> NixOS module`.

## The Gap

The target loop is: `generate ONCE --> {grammar + engine} frozen`, then `edit
+ run` stays deterministic until the program escapes the language, at which
point it re-enters `generate`. Two pieces are missing.

1. No frozen loose-text grammar. `Reader` parses the canonical form
   deterministically, but the loose-to-canonical mapping is the uncrystallized
   model call. The pattern set and morphology table the spec names are neither
   extracted nor stored.
2. No generated engine. The rules and demands in `Engine.Feed` are
   hand-written, not produced by `generate`. This is the separately-deferred
   engine-synthesis half and is out of scope for this milestone.

This milestone addresses gap 1 only: crystallize a deterministic reader for
loose text. Engine synthesis (gap 2) stays hand-written.

## What Crystallization Produces

`generate` must emit, alongside the admitted decisions, a stored language
artifact: the patterns it used to read each loose line, plus the morphology
table, as data in the same decision material. This artifact is the "engine's
language" the language sketch describes as a meta-decision base.

A pattern records how a class of loose lines maps to a canonical decision:

- a match template over the loose text, with holes (for example
  `every <row> becomes exactly one <entity>`),
- the resulting decision's kind and subject path, with the holes bound into
  subject or assertion,
- the strength (stated for human lines),
- the source pattern's own provenance, so a reader error names the pattern.

The morphology table is the versioned normalization already named in the
sketch (lowercase plus singularization), stored as data, not code.

## The Loop After This Milestone

    lips generate <loose>   # AI: writes <loose>.decisions AND <loose>.lang (the crystallized grammar)
    lips read <loose>       # deterministic: re-reads loose text using <loose>.lang, no model
    lips run <decisions>    # deterministic: decisions -> NixOS module (unchanged)

`read` is the new deterministic front door. It applies the stored patterns to
the loose text and produces the canonical decision base. Its outcomes mirror
`run`'s discipline:

- a loose line matched by exactly one pattern reads deterministically,
- a line matched by no pattern is a parse rejection (the only outcome that
  re-enters `generate`),
- a line matched by more than one pattern is a pattern-overlap error
  (orthogonality, the same guard `Refine` already enforces for rules),
- ambiguous hole binding (two normalizations of a name) is an open question,
  never a guess.

Edits within the language (value edits, instance edits, recombination, per
spec section 5's edit-tolerance contract) then flow through `read` with zero
model calls. Only a genuinely new pattern shape rejects into `generate`.

## Design Decisions to Settle Before Coding

1. Pattern-match formalism. The sketch and Survey A point to Statix-style
   constraints or K-style rewriting. For the prototype, the minimal shape is a
   token template with named holes matched against a normalized token stream.
   Recommendation: start with linear templates over normalized tokens; defer
   anything richer until a real program needs it (YAGNI).
2. Storage form of `<loose>.lang`. It must be the same diffable decision text
   the `Reader` already handles, so patterns are `meta` decisions with a
   defined subject convention (for example `pattern.<id>`). Recommendation:
   reuse the canonical form; add a pattern sub-grammar inside the assertion, or
   model each pattern as several decisions (template, kind, subject-binding).
   Settle which during design.
3. How `generate` emits patterns. The model, when reading each line, must also
   report the pattern it used, generalized to holes. Recommendation: extend the
   system prompt so each reply line carries both the canonical decision and the
   pattern that produced it; the harness admits patterns under the same
   confidence and unanimity rules as decisions.
4. Determinism of `read` vs `generate`. `read` must be a pure function of
   (loose text, `<loose>.lang`). Confirm the morphology table fully determines
   normalization so no model is consulted.
5. Regeneration and the corpus. A regenerated `.lang` must still read the
   existing program (and any saved loose corpus). Tie this to the existing
   generation record and the spec's corpus pinning.

## Implementation Plan (TDD, small commits)

Work on a branch, worktree under `.worktrees/`, as before.

1. Types: `Lips.Lang.Pattern` (template, holes, target kind/subject binding)
   and `Lips.Lang.Morphology` (the normalization table). Pure. Tests for
   normalization and hole binding.
2. Deterministic reader: `Lips.Lang.Read.readLoose :: Morphology -> [Pattern]
   -> Text -> Either [ReadError] Base`, with the four outcomes above. Tests
   mirror `Run`'s outcome tests, including the overlap guard.
3. Storage: extend `Lips.Kernel.Reader` (or a sibling) to serialize and parse
   `<loose>.lang` in canonical decision form; round-trip property.
4. Generate emits patterns: extend `Lips.Generate.Reading` system prompt and
   parser so the model reports patterns; admit them through the harness; write
   `<loose>.lang` in `app/Main.hs`.
5. CLI: add `lips read <loose>`; wire `generate` to also write `<loose>.lang`.
6. End-to-end: `generate` a loose program once, then edit it (value and
   instance edits) and confirm `read` re-reads it with no model call and the
   result still `run`s to valid Nix. Add this as a corpus test.

## Out of Scope

Engine synthesis (generating rules and demands), resampling wired into the CLI
(`--samples`), and migration of a changed language. Each is its own milestone.

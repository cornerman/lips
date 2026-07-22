# Crystallization: Plan for the AI-Free Edit Loop

Status: designed, ready to implement. Companion to
`DESIGN.md` (spec v2), detailing the next prototype
milestone. Written so the work can be resumed from this document alone.

## Why This Matters

Crystallization delivers the whole point of lips: edit the program and re-run
it deterministically, with no model call. The design (spec section 5) states
the loop as "generate once, then the engine accepts edits within the language
without AI." This milestone builds that property.

## Terminology (settled)

- **generate** — the AI door, explicit and rare. The model mints the
  *language*: `<loose>.lang` (patterns + morphology). Later milestones extend
  it to mint the engine's rules. The only place a model is ever called.
- **crystallize** — deterministic template matching: loose text x `.lang` ->
  canonical decision base. A pure function; the language is the seed crystal,
  generate minted it, run lets the program crystallize around it. Runs inside
  every `run`, cached by content hash of (loose text, `.lang`).
- The contract in one sentence: **generate makes the language; crystallize
  applies it.** AI may invent grammar; only the kernel may assign meaning to
  the program text through it. `run` never calls the model.

## The Inversion (safety by construction)

The reading half built in commit 72ee018 trusts the model's canonical
decisions directly: model output is the reading. Crystallization inverts this.

**The model delivers only the grammar, never the meaning.**

    generate:  model emits .lang (patterns + morphology)   <- only model deliverable
               kernel crystallizes the loose text itself    <- deterministic
               cross-check: machine reading == model's claimed reading
               full run of the result to valid Nix
               any mismatch, gap, or overlap -> deduce-or-fail, nothing written

Consequences:

1. `.decisions` stops being a source artifact. It is the cached crystal,
   recomputable from loose text + `.lang`, safe to delete. Trusted inputs
   shrink to: the human's loose text (truth) and `.lang` (regenerable,
   pinned). The model's claimed reading is demoted to a cross-check input --
   machine-model unanimity, where one party is deterministic.
2. `lips run` takes the loose program directly (restores the original
   interface: `run engine <program>`). The user never touches `.decisions`.
3. The edit-tolerance contract (spec section 5) becomes a theorem, not a
   test: with linear token templates, any line obtained by re-instantiating a
   pattern's holes crystallizes by construction; and since a program is a
   decision *set*, reordering and recombination are closed by construction
   too. Fuzzing shrinks to a QuickCheck sanity property over hole
   re-instantiation (deterministic, no model).

## Where Crystallization Lives: Kernel vs Engine

    kernel  (fixed, problem-independent, the deliverable):
            generic executors -- pattern-matcher, merge/strength, refinement
            stepper, demand checker, realizer-to-Nix. Knows nothing about
            any problem domain.

    engine  (per-problem, generated, churns):
            front half:  the language  = .lang (patterns + morphology)
            back half:   the semantics = rules (obligation -> mechanism),
                         demands, defaults, coping, tests

`.lang` is part of the engine, not the kernel. The kernel contains a generic
template-matching executor; `.lang` is data parameterizing it, exactly as the
engine's refinement rules parameterize the generic refinement stepper.
Honest asymmetry after this milestone: the engine's back half stays
hand-written Haskell (`Engine.Feed`); the front half becomes generated data.
Making rules data too is the engine-synthesis milestone, out of scope here.

## The Loop After This Milestone

    lips generate <loose>   # AI mints <loose>.lang; kernel validates by
                            # crystallizing + cross-check + full run; writes
                            # .lang, .decisions (cache), .generation (record)
    lips run <loose>        # crystallize (cached, pure) -> refine -> realize

`run`'s crystallize stage has four fail-loud outcomes, mirroring the run
pipeline's discipline:

- a loose line matched by exactly one pattern crystallizes deterministically,
- a line matched by no pattern is a rejection naming the line -- the only
  outcome that re-enters `generate`,
- a line matched by more than one pattern is a pattern-overlap error
  (orthogonality, the same guard `Refine` enforces for rules),
- ambiguous hole binding (two normalizations of a name) is an open question,
  never a guess.

Run never generates. On rejection it names `lips generate` as the remedy and
stops. A convenience wrapper (`lips dev`) that asks before generating may
exist later without weakening `run`.

## Pattern Formalism (settled)

A pattern is a linear token template with named holes over normalized tokens:

    every <row> becomes exactly one <entity>

- Holes bind *names and values only*; the fixed tokens carry all mechanism
  semantics. This is the generalization-radius rule: an over-general match
  that binds an unknown concept flows into refine and dies loudly at the
  existing Unmapped guard -- over-generalization degrades to fail-loud, never
  to silent wrong meaning.
- Each pattern records: the template, the produced decision's kind and
  subject path (holes bound into subject or assertion), the strength (stated
  for human lines), and its own provenance, so a crystallize error names the
  pattern.
- Morphology: the versioned normalization table (lowercase, singularization)
  stored as data, not code. Normalization is total and deterministic; if two
  normalizations could claim a token, that is an open question, not a choice.
- Overlap checking: pairwise template unification over the actual program and
  corpus lines at generate-time, plus the runtime multi-match error. No
  universal overlap proof pretensions.

## Storage Form (settled)

`.lang` is canonical decision text, readable by the existing `Reader`:

- one `meta` decision per pattern, subject `lang.pattern.<id>`, the template
  sub-grammar inside the assertion (template => kind + subject binding),
- one `meta` decision per morphology entry, subject `lang.morph.<token>`.

Diffable, mergeable, same material as everything else.

## Corpus and Regeneration

The corpus pins (loose text, expected crystal) pairs. A regenerated `.lang`
must reproduce every pinned pair or generate fails showing the semantic diff
-- the reading-level instance of spec section 5's removed-test rule. Each
generate appends the current program and its crystal to the corpus and writes
the generation record (model, prompts, params, inputs).

## Implementation Plan (TDD, small commits)

Work on a branch, worktree under `.worktrees/`, as before.

1. Types: `Lips.Lang.Pattern` (template, holes, target kind/subject binding)
   and `Lips.Lang.Morphology` (normalization table). Pure. Tests for
   normalization and hole binding.
2. Crystallizer: `Lips.Lang.Crystallize.crystallize :: Morphology ->
   [Pattern] -> Text -> Either [CrystallizeError] Base` with the four
   outcomes. Tests mirror `Run`'s outcome tests, including the overlap guard.
   QuickCheck property: hole re-instantiation always crystallizes.
3. Storage: serialize and parse `.lang` in canonical decision form
   (round-trip property), reusing `Kernel.Reader`.
4. Generate inversion: system prompt asks for patterns + claimed reading;
   harness admits patterns; kernel crystallizes and cross-checks; write
   `.lang` + `.decisions` (cache) + `.generation`. Delete the direct
   trust path from 72ee018.
5. CLI: `lips run <loose>` = crystallize (with content-hash cache) -> refine
   -> realize; rejection messages name `lips generate`. `lips generate
   <loose>` per step 4.
6. End-to-end: generate `examples/feed.loose` once; then value-edit,
   instance-edit, and recombine it; confirm `run` absorbs all three with no
   model call and still realizes valid Nix. Pin as corpus test.

## Out of Scope

Engine synthesis (rules, demands, coping as generated data), resampling wired
into the CLI (`--samples`), migration of a changed language, `lips dev`.

# lipsidea Design (v2)

Status: approved concept design, second founding. v1 (git history of this
file) organized lipsidea as a spec-language with surface syntax; v2 re-founds
it on a decision calculus after the notation question dissolved. Evidence
base: the four surveys in `docs/superpowers/survey/` (cited as Survey A/B/C/D).

## Terminology

- **Decision**: the atom of the whole system. A tuple of subject, assertion,
  scope, strength, provenance, rationale.
- **Decision base**: an unordered set of decisions with defined merge
  semantics. Every artifact in lipsidea is one.
- **Kernel**: the decision calculus itself: decision shape, strength and
  merging, provenance, conflict, and the refinement relation. Tiny, fixed,
  maximally verified.
- **Language**: the problem-specific vocabulary a Solution is written in:
  concepts, obligation patterns, defaults, demands. Defined as meta-decisions.
- **Engine**: the living mechanism layer under a language: its
  obligation-to-mechanism mappings, runtime strategies, coping logic, and
  derived tooling. Engines churn; Solutions do not.
- **Solution**: the human-authored decision base for one problem. The stable
  artifact.
- **System**: kernel + languages + engines + compiler + Nix realization.
- **Glue**: a decision whose assertion contains a computation. Legal, marked,
  rigor-downgraded.
- **Application kind**: a platform's runnable unit. Canonical kind: a NixOS
  module.
- **Generate**: the only AI step: building or evolving the engine for a
  program. Running the engine is deterministic and AI-free.

## 1. Thesis

AI produces software faster than humans can review mechanism-level diffs.
The human artifact must therefore move up to intent: dense, precise, small,
and stable. Execution must stay deterministic, because a model guessing at
realization time reintroduces the unreviewable gap.

lipsidea's structural commitment: **zero LLM inference between a Solution and
its realized system.** AI participates massively, but only at authoring time,
and only by producing decision bases that are checkable artifacts. Survey D
confirms the position is unoccupied: every 2023-2026 spec-driven tool (Spec
Kit, Kiro, Tessl, BMad, OpenAI's "spec is the new code") places an LLM
exactly where lipsidea places a compiler; Tessl regenerates different code
from an unchanged spec.

The deliverable form of lipsidea is a rigorous specification of the kernel
calculus plus a conformance suite, not a blessed runtime.

## 2. The Decision Calculus

Lisp's founding move was: code is data, and eval maps data to values.
lipsidea's founding move is: **intent is data, and realize maps decisions to
systems.** Lisp stayed "just code" because its atom is a computational form.
lipsidea's atom is an asserted meaning:

    decision = (subject, assertion, scope, strength, provenance, rationale)

Kernel semantics, all of them:

1. **Merge.** A decision base is a set. Decisions about the same subject
   merge by strength: System defaults are weak decisions; Solution decisions
   override them. Delta-over-defaults is not a feature but a consequence.
   (The NixOS priority mechanism promoted from library convention to kernel
   physics; Survey D names this promotion as Nix's single most credible fix.)
2. **Conflict.** Two incompatible decisions of equal strength are a compile
   error carrying both provenances. Silence is never an option.
3. **Provenance.** Every decision knows its origin; every derived decision
   links to the decisions and mapping rules that produced it. Provenance is
   kernel data, not tooling garnish (Survey D, the `<unknown-file>` lesson).
4. **Refinement.** Realization applies language mappings to a decision base,
   producing another decision base, repeatedly, until only ground decisions
   remain (emitted artifacts plus Nix wiring). Refinement must be
   deterministic and confluent: same base, same system, always. Precedents
   for deterministic rewriting at scale: K Framework backends, Statix's
   stability theorem, Nix's module fixpoint (Surveys A, D).
5. **Demands.** A meta-decision may demand that some decision exist ("an
   application of kind service must decide persistence"). An unmet demand is
   an **open question**, a first-class artifact in the base. A Solution is
   complete when no demands are open.

Every refinement stage is again a decision base: inspectable, diffable,
provenance-linked. The owner reviews the top; an auditor can walk any
derivation chain to the metal, mechanically. This staged reviewability is
the direct answer to the unreviewable-AI-diff problem.

**Notation dissolves.** There is no surface syntax to design. The canonical
stored form is plain diffable text, roughly one decision per line, so that
text diff approximates set diff. Tables, per-concern views, prose renderings,
and editors are derived projections of the base. This takes the text side of
the MPS tension (Survey A) while keeping projectional-style tooling as
read-mostly views.

## 3. Decision Kinds

A small closed set of kernel-level kinds; languages refine them:

- **Concepts and facts**: the domain ontology. "Concept Account has balance:
  Money." "Bank data arrives as CSV, daily."
- **Obligations**: oblige / forbid / allow. "Every bank row is recorded as
  exactly one Transaction." Obligation patterns are what engines map to
  mechanisms; an obligation no language can map is a compile error, never a
  guess. This single rule is the anti-MDA guard (Survey B: intent-looking
  models without execution semantics die as wall decoration).
- **Assumptions**: assume / expect, thrown at the System for interrogation.
  The System must answer each with a status: **guaranteed** (by
  construction), **verified** (proof or model check), **tested** (property
  or fuzz evidence), or **open**, with counterexamples where false. Review
  happens by interrogation as much as by reading.
- **Steering decisions**: prose specs, prompts, and invariants addressed to
  the AI engine-developers. First-class in the base, authoring-time only,
  zero role at realization.
- **Glue**: a decision whose assertion contains a computation, syntactically
  marked, blast radius visible in its type (Survey D's freeformType lesson
  inverted). Glue is simultaneously the expressiveness escape (nothing is
  inexpressible) and the rigor boundary (Section 7).
- **Meta-decisions**: everything that defines a language and its engine:
  concepts introduced, obligation patterns, defaults (weak decisions),
  demands, mechanism mappings, coping strategies. Languages are decision
  bases too; the tower is uniform all the way down (the Racket #lang lesson,
  Survey A, transplanted from code to decisions).

## 4. The Inverted Development Model

Conventional software: the application churns while infrastructure
ossifies. lipsidea inverts this. **The Solution is the stable artifact; the
engine churns freely.**

The human writes only the high-level picture: the workflow, the domain, the
obligations. The Solution defines everything that must be defined, no more
and no less, and both directions are machine-checked: "no less" through open
demands, "no more" through redundancy errors when a decision asserts what
the System already knew. The governing invariant survives from v1: **a
Solution may contain nothing the System could have known.**

Developing a feature means: the human changes decisions; AI (with developer
support) evolves the engine until the new decisions realize. Engine rewriting
and rethinking is always allowed and often required; the engine is re-thought
with every feature, and it co-evolves with the problem's language as the
problem deepens. This is safe because Solutions contain zero mechanism, so
nothing above the engine can break. Discipline replaces caution:

- **Orthogonality is enforced.** Engine features must compose without
  overlap; overlap is flagged mechanically, not left to taste.
- **Engine code is tested and fuzzed by definition.** Every engine feature
  carries auto-derived test obligations and fuzz targets; a feature without
  them does not lint. This guarantee is structural, not aspirational
  (Survey C: conformance and differential testing are compute-bound, not
  expertise-bound; SQLite's 590:1 and Csmith are the precedents).

## 5. The Generate/Run Loop

The entire interface:

    1. write program        any text; "hello" is already (probably) a valid program
    2. lips generate        the only AI step: build/evolve the engine for this program
    3. lips run <program>   deterministic, repeatable forever
    4. edit program
         engine still accepts it  ->  step 3, no AI involved
         engine rejects it        ->  step 2, regenerate

**Two-phase validity.** Generate-time is permissive: the AI must give the
text a defined meaning or surface open questions. Run-time is strict: the
engine's language defines exactly what it accepts. "Valid program" is a
property of the pair (program, engine).

**The language grows exactly as fast as the problem.** The program comes
first; the language and engine crystallize around it at generate-time.
Edits within the current language cost zero AI; the engine evolves only when
the Solution escapes it. Day one there is no engine: the first generate over
a one-line program produces the first one. The uber framework accretes from
real usage, which is also the economics defense (Section 9, item 2) made
operational.

**Generate deduces or fails.** For every decision the engine needs, generate
either deduces it from the program and its facts, or fails, surfacing the gap
as open questions. Failing with questions is the success mode for ambiguity;
a guess is the one forbidden output. This holds at three independent layers:

1. **Structurally**: an unmapped obligation or ambiguous reading cannot
   compile, so a guess has no way to land silently.
2. **In the harness**: the generator must attach a confidence to every
   deduced decision, and the deterministic harness accepts only certainty.
   Anything below falls short and is demoted to an open question that
   carries the candidate answer ("I believe X; confirm or correct"), never
   auto-applied. Deducibility can additionally be tested mechanically by
   resampling: a deduction that is genuinely forced by the inputs comes back
   unanimous; divergence across samples is detected ambiguity.
3. **At the source**: the generator agent's operating prompt carries
   deduce-or-fail as a top-priority, non-negotiable directive. That prompt
   is itself part of the System: a versioned, reviewable artifact, not an
   incantation.

**Run absorbs edits within the language.** Generate produces a compiler for
the crystallized language, not for one frozen program, so an edited program
runs without AI as long as it stays inside the language. Run is a
deterministic pipeline with four outcomes: parse rejection (a line no
pattern reads, named precisely; the only outcome that re-enters generate),
open question (an unmet demand, asked verbatim from the language's demand
table; answered by adding a line, still no AI), conflict (equal-strength
contradiction, both provenances cited; fixed in the program), or
realization. Even interrogation is deterministic; only minting new patterns
needs a model. The design knob is the generalization radius: how far beyond
the literal program generate abstracts (mechanisms parameterize over
pattern holes; concept sets stay closed). Too narrow and every edit
regenerates; too wide and speculative language accretes. Steering decisions
tune it.

**Reasonable changes must keep working.** The radius is a contract, not
taste: reasonable means edits that change decisions, not kinds of intent,
and the language must be closed under three edit classes with zero AI:
value edits (any literal to another of its type), instance edits (add,
remove, duplicate instances of known concepts and patterns), and
recombination (known patterns applied to known concepts in new
combinations; enforced orthogonality is what makes this closure hold).
Only a genuinely new pattern shape may reject into regenerate. Enforcement
is by definition: the corpus extends to program-mutation fuzzing, where
generate derives mutation tests over the program itself and asserts run
survives each class. An engine whose language breaks under reasonable
edits does not lint.

**The generation event is pinned.** Whether generate succeeds, and what it
deduces, may depend on which model runs it; that ambiguity is accepted: you
generate once, then you go with the result. In exchange, every engine
carries its generation record, committed with it: exact model identity and
version, the full prompts (including the operating prompt above), sampling
parameters, and the complete inputs (program, facts, steering). With locally
pinned weights and greedy sampling the record replays bit-for-bit; with
hosted models it is an audit trail. Either way the trust chain is unbroken,
because an engine's authority never derives from who generated it, only
from the corpus and checks it passes; the record explains provenance, the
corpus grants legitimacy.

**Regeneration safety holds by definition.** The engine's test corpus
(Section 4: tested and fuzzed by definition) is the semantic pin. A
regenerated engine must pass the accumulated corpus before it replaces its
predecessor. Tests are removed only when they contradict changed
requirements, so the removed-test set IS the semantic diff a reviewer reads;
engine internals stay free to be rewritten wildly underneath. A supposedly
stable test that contradicts the program indicts the program, not the test.
Assumption decisions (Section 3) live in the same fabric: they are
re-answered against every new engine, and a downgrade of status (guaranteed
to tested, verified to open) is a loud, reviewable event.

## 6. The Heile-Welt Contract

The engine promises the Solution author an intact world: a stable simulation
in which the language's invariants simply hold, including those reality does
not guarantee. Networks fail, APIs flake, data arrives twice, clocks skew;
coping strategies (retry, reconciliation, idempotence, compensation) are
engine obligations, never Solution content. TCP builds reliable streams on
unreliable packets; transactions build atomicity on crashing disks; lipsidea
generalizes this into a design law.

Consequently **workarounds are unrepresentable in a Solution.** There is
nothing to work around in a world that is whole; any pressure toward a
workaround is, structurally, a feature request against the engine. Survey B
ranks escape-hatch decay through accumulated workarounds as the number-one
killer of every prior intent-level attempt (CASE, MDA, Helm, low-code);
lipsidea makes that decay impossible at the level where it kills and routes
the pressure to the level built to absorb it.

## 7. Rigor Allocation

The reviewer's metric is comprehension per minute; proof burden never lands
on the Solution author. Survey C's evidence (seL4 at 50 proof lines per code
line; IronFleet at 3.7 person-years despite SMT automation; Amazon's TLA+ at
two to three weeks to learn) fixes where each rigor level is affordable:

| Layer | Rigor | Precedent |
|---|---|---|
| Language and engine mappings | SMT-automated proof or model checking, paid once by the engine author, plus mandatory auto-test/fuzz (Section 4) | HACL* in Firefox; SQLite; Csmith |
| Solution, language path | Decidable checks only: instant, total, no proof visible | Dhall, CUE, Elm |
| Solution, glue path | Marked; property and conformance testing, never silent trust | Agda TERMINATING, Koka div |
| Kernel calculus and compiler | Conformance suite; full proof if resourced | WASM spec+testsuite, CompCert |

Assumption decisions (Section 3) are the query interface over this table:
each answer's status names which layer's guarantee it rests on.

## 8. Perfect Developer Experience, by Construction

Every minted language ships with complete derived tooling: checker,
completion, hover documentation, formatter, views, and option search are
zero-cost exports of the same meta-decisions the compiler checks (Survey D's
search.nixos.org model; Survey A's MPS aspect checklist, minus projectional
storage). Autocompletion is perfect in principle because the engine knows
every concept, every default, and every open demand; the editor is a view of
the decision base plus its unmet demands. AI may assist authoring, but the
clarity is structural: what can be said, what is missing, and what conflicts
are all derivable facts, not conventions.

## 9. Failure-Mode Defenses

Survey B's ranked taxonomy, mapped to the design property that blocks each:

1. **Escape-hatch decay** → workarounds unrepresentable in Solutions
   (Section 6); glue lives inside the typed kernel; compilation is
   one-directional; generated output is disposable, never hand-edited.
2. **Economics before maturity** (STEPS, Eve, Dark) → the System must serve
   one owner at small scale immediately; no adoption threshold is
   load-bearing.
3. **Vendor and research lock-in** (Wolfram, Intentional, Dark) → open
   compile target (NixOS module), public kernel spec, conformance suite
   instead of a proprietary runtime.
4. **Loss of human legibility** (UML as decoration) → the Solution is the
   sole source of truth with defined realization semantics; drift cannot
   open because only the decision base compiles.
5. **All-or-nothing adoption** (STEPS, Dark, early Eve) → one Solution
   realizes as one ordinary NixOS module beside hand-written modules.
6. **Platform death by owner neglect** (HyperCard) → the realization layer
   (Nix/NixOS) has independent governance.
7. **The natural-language trap** (4GLs; Inform 7's narrowness) → decisions
   are formal and dense, aimed at software-literate owners; no fake English.
8. **Interface research blocking a sound core** (Eve) → canonical form is
   plain text; views are derived conveniences, not prerequisites.

The anti-MDA guard is restated here because it is load-bearing: an
obligation without a defined mechanism mapping fails compilation. The System
grows by absorbing new obligation patterns; guessing is not in the
architecture.

## 10. Realization Target

A Solution realizes as target-language artifacts plus Nix expressions that
build, wire, and deploy them; the canonical application kind is a NixOS
module. Nix is the deterministic realizer, not the logic runtime.

Nix is chosen for completeness, not convenience: everything is definable
declaratively with it, any language's toolchain, any package, any service
topology, any system state. The engine's mechanism space is therefore
unbounded by construction: whatever an engine needs to emit (a Rust service,
a Python pipeline, a kernel tweak, a fleet of containers) is reachable as
derivations plus module wiring. lipsidea inherits universality from Nix
instead of building it, which is what makes "fully expressive from day one"
hold at the realization layer, as marked glue makes it hold at the language
layer. Completeness twice, both times deterministic. The NixOS
module system is the architecture's twenty-year production precedent (typed,
mergeable, per-domain vocabulary over one general substrate, zero LLM;
Survey D verified its mechanics firsthand), and terranix proves the
machinery retargets beyond NixOS.

## 11. Open Questions

- **Canonical text form**: the concrete decision-per-line format, under the
  constraint that text diff approximates set diff. Owned by the sketch phase.
- **Calculus formalization**: the strength lattice, the refinement relation's
  confluence proof obligations, scoping of subjects. Owned by the prototype
  design.
- **Language/engine migration**: when a language's semantics change, how
  existing Solutions migrate (decision-preserving transformations, versioned
  demands).
- **Engine orthogonality check**: the concrete mechanism that flags
  overlapping engine features.
- ~~Naming~~: resolved. The project is **lips**: Lisp rearranged (same
  letters, one level up) and the organ where intent leaves the human as
  speech. Branded `lips-lang` where the bare word is taken.

## 12. Phases

1. **Design doc** (this document).
2. **Paper walk-through**: one feature end-to-end, e.g. "bank sends duplicate
   rows": assumption thrown, answer 'open', engine evolution, new guarantee,
   stable Solution. All refinement stages written out as decision bases,
   and the generate/run loop traced at each step. This doubles as the first
   draft of the canonical text form.
3. **Language sketch**: one example application spanning three languages
   (record-keeping core, ingestion pipeline, CLI) as a full decision base,
   plus the meta-decision base of one language.
4. **Prototype**: kernel calculus, one engine, reference compiler emitting
   artifacts plus Nix wiring, realized as a NixOS module on a real machine.
   The reference implementation is non-privileged; the kernel spec and
   conformance suite remain the source of truth.

## 13. Milestone Ledger (done / remaining)

A legible snapshot of build state so it need not be re-derived. "Done" means
built and tested in `kernel/` on `main`; "partial" means the mechanism exists
but the loop around it is incomplete; "missing" means specced, not built.

### Done

- **Kernel calculus.** `Decision`, decision base with merge-by-strength and
  conflict-with-both-provenances, refinement to fixpoint with
  orthogonality-by-construction and stamped provenance, demands and open
  questions, realization to a NixOS module. Seed conformance suite pins each.
- **Canonical stored form.** Diffable one-decision-per-line text; reader
  round-trips renderer.
- **Deterministic run pipeline.** resolve -> demands -> refine -> realize, with
  the anti-MDA guard (any unmapped ground decision fails loud). Output verified
  to parse as valid Nix.
- **Language crystallization (the AI-free edit loop).** `generate` mints the
  engine's front half (the language, `.lang`) as patterns; the model delivers
  grammar only, the kernel derives meaning by deterministic template matching
  (`crystallize`) and validates by a full run before writing anything. `run`
  takes the loose program directly; value and instance edits flow through with
  no model (verified offline). Escaping edits and missing language fail loud.
- **Generate boundary plumbing.** Model call routed through `pi` print mode;
  deduce-or-fail confidence threshold; generation record written per event.
- **Engine synthesis (was the central gap).** `generate` mints the whole
  engine as data in one `.lang` file: patterns (front half) plus rules
  (`match <kind> <subject> => option assignments`, with `<value>`/`<value.N>`
  holes) and demands (back half), interpreted by generic kernel executors
  (`Engine.Data`); the hand-written `Engine.Feed` is deleted. No domain
  vocabulary is compiled in; the model invents subjects, and closure is
  checked, not trusted (unmapped decision, unmet demand, uncovered line, or
  invalid Nix -- `nix-instantiate --parse` at mint time -- each rejects the
  engine). Proven live on two domains: the feed and a non-feed restic backup
  job, both minted by opus, both then absorbing value edits offline.
  Deliberate restriction: minted rules emit only ground decisions (one
  refinement pass, no cascades until a real program needs them).

- **Closed rhs value language.** A minted rule's rhs is a typed value (string
  with holes and `${pkgs...}` refs only, list, bool, int), never Nix text:
  computation and string injection are unrepresentable, discharging the
  structural layer of deduce-or-fail where the prompt alone had carried it.

### Partial

- **Deduce-or-fail via resampling.** The harness `unanimous`/`coreOf` check is
  built and tested, but `generate` samples the model once; only the confidence
  threshold gates admission. Missing: `--samples` wiring so a deduction must
  recur identically across samples.
- **Corpus pinning.** A corpus regression test exists and the generation record
  is written, but the `generate` command does not enforce "a regenerated
  `.lang` reproduces every pinned (loose, crystal) pair or fails showing the
  diff."
- **Glue.** `Glue` exists as a `Kind`, but its rigor downgrade (marked glue ->
  property testing, visible blast radius) is not implemented.

### Missing

- **Live NixOS deployment.** A realized module has never been deployed on a real
  machine (`wolf`) beside hand-written modules. The coexistence defense (one
  Solution = one ordinary module, not all-or-nothing) is untested against a
  running system.
- **Language migration.** When `.lang` regenerates to a different shape, there
  is no diff or migration path for existing programs.
- **Multi-language composition.** The sketch composes three languages in one
  decision base; the prototype runs one engine. Composing several
  engines/languages in one Solution is unbuilt.
- **Guarantee lifecycle.** The walk-through's assumption `OPEN -> GUARANTEED`
  flow and the "verify a vocabulary once, inherit cheaply" rigor allocation
  have no code.
- **Heile-Welt coping.** The kernel's promise to supply stable strategies for
  what reality cannot guarantee has no mechanism yet.
- **`lips dev`.** Convenience wrapper (run, ask before generating). Minor.

### Shortest Summary

The deterministic spine, the language-crystallization loop, and whole-engine
synthesis are real and tested: lips now mints an engine for an unseen domain
and absorbs edits offline. A **live NixOS deployment** is the missing proof
that it survives a real system. Everything else is hardening or breadth.

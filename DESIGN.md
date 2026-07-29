# lips Design

Status: approved concept design. lips is founded on a decision calculus.
Evidence base: the four surveys in `docs/superpowers/survey/` (cited as
Survey A/B/C/D).

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
  artifact. (The shipped name for it is **program**, the `.lips` file; this
  document's older sections say Solution and `lipsidea` says lips. `AGENTS.md`
  carries the terminology the code uses.)
- **System**: kernel + languages + engines + compiler + Nix realization.
- **Glue**: a decision whose assertion contains a computation. Legal, marked,
  rigor-downgraded.
- **Application kind**: a platform's runnable unit. Canonical kind: a NixOS
  module.
- **Generate**: the only AI step: building or evolving the engine for a
  program. Running the engine is deterministic and AI-free.

(Name collision, for the record: "decision calculus" also names John D. C.
Little's 1970 manager-facing modelling method in *Management Science* 16(8).
Different field, unrelated content.)

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

**Merge runs before refinement, and nothing lets a rule's applicability depend
on a refinement result.** Both halves are load-bearing. Priority-ordered
rewriting, where a higher rule pre-empts a lower one and the pre-emption is
decided mid-reduction, has no automatically well-defined semantics: Baeten,
Bergstra and Klop, "Term Rewriting Systems with Priorities" (RTA 1987), had to
restrict the class of systems to recover soundness. lips has priorities
(strength) and rewriting (refinement) but keeps them in separate phases:
`resolve` settles every subject by strength first, `refine` then rewrites a
settled base by matching alone. Any future convenience that lets strength be
read or reassigned during refinement walks into the 1987 problem and must be
refused (Survey F, seam 1).

**The lattice objection, and the answer.** CUE forbids overrides outright: its
values form a lattice, combination is unification, and its authors argue that
with override-based systems (GCL, Jsonnet, HCL, Kustomize) "finding a
declaration for a concrete field value does not guarantee a final answer", so a
reader must chase inheritance chains. The empirical rebuttal is NixOS itself:
prioritized merge is not a thought experiment but the twenty-year production
substrate of a whole distribution, and it works at a scale no lattice-only
configuration language has reached. What makes chasing painful in the systems
CUE names is not priority, it is missing provenance: they can tell you the
winning value but not who lost, where, and why. lips carries provenance as
kernel data (item 3), so the chain CUE fears is not chased by hand but listed
mechanically: for any subject, the winner, every loser, and the source line of
each. Nix's own worst override pain, the `<unknown-file>` message (Survey D),
is exactly the case where its provenance is absent, which is the same claim
from the other side. Priorities are affordable when provenance is total.

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
    3. lips compile         deterministic, repeatable forever; emits a dir + flake
                            and prints the `nix run`/`nix build` commands to run it
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
- ~~**Engine orthogonality check**~~: RESOLVED for both layers, at the `generate`
  gate (`Lips.Kernel.Engine.Overlap`; ledger §13). Rules: critical-pair analysis
  over their left-hand sides. Patterns: a product walk over the two token
  templates, which answers "could one line match both" exactly, since a template
  is a sequence over three forms (literal, one-token hole, multi-token hole) and a
  multi-token hole may stay or advance at each step. A template that repeats a
  hole name is skipped rather than approximated (the repeat constrains two
  positions to one word, which the walk does not track, and a false rejection
  would refuse a sound engine); the dynamic `Overlapping` check still covers it.
- ~~**Branching on a captured word**~~: resolved as permanently out of scope,
  and the resolution is a distinction, not a mechanism. A word in a program
  either FILLS A VALUE (a port, a path, a message), which belongs in a hole so
  edits flow with no regeneration, or it SELECTS A MECHANISM (which builder,
  which service), which belongs in the pattern template as a LITERAL. No value
  in the closed grammar can carry a builder choice, and branching a rule on a
  captured word is computation, so the mechanism-selecting word cannot be a
  hole; spelled literally, editing it stops the line matching, `check` fails
  loud with "grow the language", and a fresh mint picks the mechanism the new
  word asks for. Regeneration IS the branch, and the `.lang` is disposable by
  design, so nothing is lost. The `droppedValues` gate (§13) makes the wrong
  shape unrepresentable in practice: a hole bound and then ignored is refused,
  which is what used to let an engine keep `buildGoModule` after the program
  said `rust`. Verified offline before deciding: a hand-written engine spelling
  `in go` literally is clean under the gate and crystallizes 2 of 2 lines, and
  the same program edited to `rust` reports `no match` and exits 1 naming
  `lips generate`.
- **Conflict explanation**: today a conflict names two competing decisions. A
  derived contradiction several refinement steps down needs the *minimal set
  of program lines* that cannot hold together. Model-based diagnosis solved
  this (Reiter 1987; Junker's QuickXplain, AAAI 2004) and strength already
  supplies the preference order the algorithm needs. Survey F, seam 3.
- **Does an obligation survive an override?** Merge groups by subject and
  ignores kind, so a stronger decision erases a weaker one wholesale, taking
  any obligation attached to that subject with it. Nickel's rule is the
  opposite: a contract on a field constrains whatever later overrides it, so
  `{foo | Number = 1} & {foo | force = "bar"}` fails. Deliberately unresolved:
  no minted engine emits `Oblige`/`Forbid`/`Invariant` yet (they all emit
  `Fact`), so building override-surviving obligations now would be
  speculative. Recorded so the first engine that emits an obligation is
  recognized as the moment to decide. Survey F, seam 2.
- **Does specificity beat generality?** Strength is *lex superior* only (a
  higher authority wins). Defeasible deontic logic also has *lex specialis*
  (the more specific norm wins), which is what an author may expect when a
  per-instance decision meets a language-wide default. Either adopt it as
  physics or record the refusal; leaving it undecided invites surprise.
  Survey F, seam 4.
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

- **One name grammar: an artifact name composes literal text with `<self>` and
  `<capture>`.** A name was a whole token in three places, so `<self>-core` --
  a second build beside the instance's own -- could not exist. `parseRef`
  refused `${artifact.<self>-core}` outright (the refusal a `claude-sonnet-5`
  mint of `examples/board.lips` hit on its wrapper rule), while `bindSelf` and
  `bindSelfValue` matched `<self>` by whole-token equality, so the emit path
  `artifact.<self>-core.builder` PARSED (a path segment is opaque text) and
  never filled. The grammar now lives once, in `Kernel/Capture.hs`
  (`nameParse`, `nameTokens`, `fillName`): a name is literal identifier text
  with `<token>` occurrences embedded, filled by occurrence wherever the
  grammar admits a name -- emit-path segments, path literals, artifact-ref
  names, in a string or as a whole value. `<self>` resolves per instance and a
  capture per rule match, each pass leaving the other's tokens standing, so the
  two share the fill helper and not the map. `valueCaptures` scans every
  occurrence, so the mint-time gate catches an unbound capture embedded in a
  name. Third bug, silent and pre-existing: nothing stopped an unfilled name
  from reaching the module, since `artifactEntries` spliced any name segment
  verbatim and the dangling-reference check compares names as TEXT, so an
  unfilled ref matched its unfilled group and a module was emitted containing
  `<self>-core = pkgs.buildGoModule {`. `realize` now fails `RBadArtifact`
  naming the unbound token. The asymmetry was the bug: a capture already filled
  embedded, `<self>` only whole, an artifact name neither -- and by "a
  capability is complete only when it works everywhere the grammar admits it"
  that is kernel physics, not a prompt problem (invariant 4). Extends
  `TODO.md` item 1d; the prompt now offers the composed name, since a
  capability the model is told nothing about is dead capability.

- **Inert lines are reported (`diagInert`).** A line the language reads and then
  drops realizes nothing, so editing it changes no output and nothing said so.
  `Concept` is the only kind `realize` drops, so a `Concept`-only line is exactly
  the inert case; `diagnose` now lists them and `check`/`compile` print them
  under "decorative, realizing nothing -- editing these changes no output". A
  heading is legitimately decorative, but so is a line a mint quietly declined to
  honor, and only the author can tell which; naming both is the honest move.
  This closes the visibility half of the silent-demotion finding
  (gap report finding 1, `git show ca09f97^:docs/gaps/README.md`).
  Since the three CLI mints landed (f0e8d13) it fires on real engines:
  `board` reports 2 decorative lines, `habit` 3, `logscan` 4 of its 5 -- which
  turned the report from a formality into the loudest open question in the
  repo (see "Verified breakages", concept escape).

- **The reasoning level is pinned (`--thinking`, default `high`).** `generate`
  passed no thinking flag, so pi's default applied, inherited from the caller's
  environment, steering the mint without entering `.generation` or `genId` -- the
  same hole `-nc` closed for ambient context files. It is now always passed
  explicitly and recorded as a `thinking:` line, so it enters the id. Unlike the
  model (deliberately not baked in: omitted, then read back), an omitted
  thinking level cannot be read back reliably, so explicit-always is the fix.
  Default `high` because a mint acts once against an exacting grammar and a
  refusal costs a whole round.

- **Captures are first-class: a capture keys a build and fills a value.** A
  `<name>` capture reached the emit PATH only, so a rule could key an nginx
  vhost by a program value but could not key a BUILD by one, and could not carry
  the captured key into a value at all. Both are now physics: `parseRef` admits
  `${artifact.<capture>}` beside a literal name and `<self>`,
  `bindCaptureValue` (`Kernel/Engine/Value.hs`) resolves a capture used as an
  artifact NAME the way `bindSelfValue` resolves `<self>`, and `toRule`'s `pick`
  resolves a value hole that names a bound capture, so one rule matching
  `cmd.<name>.msg` may emit `artifact.<name>.builder`,
  `artifact.<name>.args.name "<name>"` and `environment.systemPackages
  "[ ${artifact.<name>} ]"`. This is what makes a program that NAMES the thing
  it builds expressible: `install a command greet that prints "..."` realizes to
  an `artifact.greet` keyed by the program's own word, so editing the sentence
  renames the command and changes its output through `compile`, with no model.
  Before this the only spelling that worked keyed the build off `<self>`, i.e.
  off the FILENAME, so the program's first value was decorative.
  Two findings drove it, both filed by a mint against itself, on three separate
  programs (gap report findings 1 and 2,
  `git show ca09f97^:docs/gaps/README.md`): the model reached for
  `artifact.<cmd>` and `args.name "<cmd>"` every time, because that is the
  natural engine, and the kernel refused. Per invariant 4 the fix belonged in
  the kernel, not in a prompt telling the model to avoid the shape; the prompt
  paragraph that did so was reverted in the same branch.
  Placement decision: `parseValue` cannot judge a hole name, since it never sees
  a subject, so it now accepts any identifier hole, and `parseRuleBody` rejects
  the unbound ones where the subject IS in hand -- one door, the one every
  minted engine enters, naming the rule and the offending capture. A sibling
  static check in `Engine/Overlap.hs` was built first and then deleted as
  redundant surface (every production rule is parsed).
  Verified by seven conformance tests (value fill, artifact-ref fill, round
  trip, unbound rejection at the rule parser, identifier-hole acceptance at
  `parseValue`, non-identifier rejection), 304 examples green, `-Wall` clean,
  all nine committed examples compiling to BYTE-IDENTICAL modules (diffed old
  binary against new), and proven live end to end: a hand-written
  capture-keyed engine realizes `pkgs.writeShellApplication { name = "greet";
  text = "echo hello from lips"; }`, `nix run` prints the program's text, and
  editing the program to `install a command hello that prints "captures are
  first-class"` re-realizes to a renamed command with new output, offline.

- **Static rule orthogonality (critical pairs at the mint gate).** `generate`
  now rejects an engine whose rules could claim one decision, before the engine
  is written. `Lips.Kernel.Engine.Overlap.ruleOverlaps` treats each rule's
  left-hand side as what it is -- a kind plus a flat, fixed-length subject
  pattern over literals and `<name>` captures -- and asks the classical
  critical-pair question: do two left-hand sides unify? This is the static
  sibling of `Lips.Kernel.Refine`'s `Overlap`, which is dynamic and therefore
  blind to an ambiguity no decision in the corpus witnesses: two rules on
  `route.<path>.status` and `route.<name>.status` are indistinguishable for
  every route that could exist, yet a corpus stating no route refines clean and
  ships the defect, which then fails at compile time on an author's machine in a
  program that did nothing wrong. Unification, not a positionwise comparison,
  because a repeated capture constrains: `x.<a>.<a>` matches only equal trailing
  segments, so pairing it with `x.p.q` is NOT an overlap and reporting one would
  reject a sound engine (a false rejection costs as much as a missed defect,
  since a mint gate must pass every sound engine). The report names both rules
  and the unified subject family that witnesses the clash
  (`rules r1 and r2 both match route.<path>.status`), which is what the model
  needs on the regenerate door. The mint prompt now states rule orthogonality
  beside the pattern orthogonality it already stated, so the model is told the
  rule and the kernel enforces it (a structural guard, with the prompt as
  convergence help, never as the guarantee). Verified by ten conformance tests
  (literal/literal, capture/literal, capture/capture witness naming, kind
  separation, length separation, the non-linear false-positive case both ways,
  pair enumeration, and an overlap no base witnesses) and empirically against
  all seven committed engines, which are all orthogonal, so the gate rejects
  nothing that works today. Closes the §11 open question of the same name;
  theory and citation in `docs/superpowers/survey/f-decision-calculus-theory.md`
  (seam 1).

- **A discarded program word is a static defect (`droppedValues`).** A line lips
  READS is not thereby honored: a rule may match the fact it produces and emit
  only constants, so the program's word governs nothing and editing it changes no
  output, while the sentence still reads as load-bearing. A mint filed this
  against itself while minting a CLI tool -- "the same rule would wrongly still
  emit buildGoModule ... the existing example works only because nobody edits
  that word" -- and named this check as the honest fix.
  `Lips.Kernel.Engine.Reach.droppedValues` decides it statically, per template
  hole: run the pattern's own substitution with markers (so the check sees the
  very segments `crystallize` will build, never a second copy of that rule), find
  the rules whose left-hand side unifies with the decision the hole feeds
  (`subjectsUnify`, extracted from the overlap check so one unification answers
  both questions), and ask whether any of them carries the word -- by reading the
  decision's value (`valueUsesAssertion`: `<value>`/`<value.N>`) or by naming the
  aligned subject capture in an emit path or value. A hole no realizing emit
  mentions at all is reported too: that word dies at crystallize.
  `generate` refuses such an engine at the gate beside orthogonality; `check` and
  `compile` report it per PROGRAM LINE (`diagInert`'s sibling `diagDropped`), so
  the engines committed before the gate existed name their own defect where the
  author can see it. Where alignment is not statically decidable the answer is
  "carried", since the gate must pass every sound engine: a literal rule segment
  means the word selects the rule (so it governs), an emit no rule matches is the
  build's existing loud failure, and a segment mixing literal text with a hole is
  treated as a plain variable.
  This closes the enforcement half of the silent-demotion finding whose
  visibility half `diagInert` closed: a word the language reads is now either
  used, or declared decoration and reported as such. Verified by eleven
  conformance tests (both real repros, presence-match and indexed-hole and
  subject-capture non-defects, a literal rule segment, an unmentioned hole, a
  decorative hole, no matching rule, and the rendered message) plus two diagnose
  tests, 339 examples green, `-Wall` clean, and empirically over all nine
  committed engines: seven clean, and three defects named, one of them previously
  unknown. `examples/http` reads `go` into a steer whose rule emits the literal
  `buildGoModule`; the untracked `board` mint does the same; and `examples/postgres`
  binds `<dbname>` in *provision a user named app who owns the app database* and
  emits it nowhere, while its rule asserts the constant `ensureDBOwnership =
  true` (which in NixOS means "the database named after the user"), so a program
  naming a different database would realize wrongly and silently. All three are
  now open capability questions instead of silent engine bugs, tracked in
  `TODO.md` item 1a; two deliberate non-goals are recorded there too (a partial
  drop, where a rule reads `<value.1>` of a value built from two holes, and a
  per-hole decorative report).

- **A mechanism-selecting word is a template literal (TODO 1c closed).** The
  prompt told the mint to "replace EVERY program value with a hole", which is
  right for a value and wrong for a word naming a mechanism: told to hole every
  varying word, a mint bound `<lang>` from *write the tool in go*, then had no
  way to branch a builder on it and emitted the constant `buildGoModule`, so the
  word became decoration. That is finding 3's silent bug, and its cause was one
  over-general sentence in the prompt. The sentence now splits the two cases,
  and the `MECHANISM` bullet carries the consequence: a mechanism-selecting word
  stays a LITERAL token of the template, editing it stops the line matching, and
  regeneration is the branch. The gate's refusal message names all three
  remedies (use the word, spell it literally, read it as a concept), since a
  refusal that does not say what to write costs a whole round. No kernel change:
  the shape was always expressible (`examples/postgres`'s `p1` is an all-literal
  template feeding a constant rule) and the `droppedValues` gate now makes the
  dishonest alternative unrepresentable. The prompt-invariant guard pins both
  halves of the split, so neither can drift back out silently. See §11,
  "Branching on a captured word".

- **The mint is grounded by one schema lookup tool.** A mint may confirm an
  option path and type instead of recalling it, through exactly one tool,
  `query_options`, registered by a pi extension lips ships and loads per run
  (`assets/mint-tools.ts`, loaded with `-e`, so a user's own pi never gains it).
  It shells out to the read-only `lips options <query>` verb, so the model reads
  exactly what a human reads and no second renderer can drift.
  `Lips.Kernel.OptionType.answerQuery` adapts the answer's granularity to the
  match set, which is the one part measured rather than reasoned: a cap-40
  alphabetical slice HIDES the answer ("nginx" matches 1514 paths whose first 40
  alphabetically are other services that merely mention nginx, with
  `services.nginx` absent), so a large match set answers instead with the
  namespaces holding the matches, ranked by match count, which puts
  `services.nginx` first, `services.borgbackup` first for "backup", and
  `services.postgresql` first for "postgres". `nearOptions` reuses the same rule
  to answer a wrong path with the real leaves beside it. The mint invocation is
  hermetic by explicit subtraction (`-nbt --no-extensions --no-skills
  --no-prompt-templates -nc`) plus the one deliberate extension, with
  `LIPS_MINT_TARGET` passed explicitly so a mint for one world can never be
  answered from another world's schema. Every call and answer is recovered from
  pi's `agent_end` messages (`Lips.Generate.PiJson.prTranscript`) into a
  `--- tool transcript ---` section of the record, hence into `genId`: what the
  mint was TOLD is an input, and invariant 6 admits no unrecorded input.
  No tool judges an engine, and none runs anything: informing is safe to expose,
  deciding is not, and the gate that decides runs once, offline, in Haskell after
  the model is done. The prompt states the limit in the same breath as the tool
  ("grounds NAMES, never VALUES"), so verifiable names do not license invented
  values. Because both the prompt and the record's shape changed, every future
  `@gen` stamp differs from the ones committed before this landed; existing
  records still re-hash, since `genId` reads the committed file.

- **Mint expression channels: `report` and `gap`.** The mint speaks to the
  human in two channels beside the engine, both riding the heredoc block
  syntax `source` already used (`Lips.Generate.Minting.mkBlock` dispatches on
  the keyword). `report` is required, exactly one per mint: plain-language
  prose explaining the language just built, rendered by
  `Lips.Generate.Readme.renderReadme` to `<language>/README.md`
  (`Lips.Identity.readmePath`), opening with a line saying every mint
  overwrites it. A mint that ships no report is refused by a structural guard
  in `generate`, so the channel cannot rot into an optional pleasantry.
  `gap` (zero or more) names a kernel capability the mint lacked, the line it
  blocked and a repro; gaps print on the success path (as slugs, pointing at
  the README) and in the refusal (in full, tagged "this is a lips bug, not
  your program"). Neither channel is gated by confidence: `Minting` exports
  `carriesEngineMeaning` as the single place that says which items the
  threshold governs, so a future item kind cannot slip under it by omission.
  A gap is invariant 4 made mechanical -- a mint needing gymnastics files a
  kernel bug rather than working around the physics. Not built: the
  regeneration context (showing a re-mint the previous engine, report and
  contract) from the same plan, deliberately deferred while a mint acts
  exactly once. Plan:
  `docs/superpowers/plans/2026-07-26-mint-expression-channels-plan.md`.

- **CLI: `--lang`, sharing a language across directories.** `compile` and
  `check` gain an optional `--lang DIR` flag that redirects only where
  they READ the four committed language files (`.lang`/`.expect`/
  `.generation`/`artifacts/`); derived output (`out/<instance>.decisions`,
  the compiled module dir) still lands under the program's OWN directory, so
  a borrowing program never writes into the lending one. `DIR`'s basename
  must equal the program's own declared language (from its `.lips`
  filename) or it fails loud naming both sides, before any file IO against
  `DIR` runs -- deduce-or-fail, the same posture as a missing `.lang`.
  `generate` and `lsp` are untouched: a shared language is always minted
  beside the programs that grow it. `Lips.Identity` gains a pure resolver
  (`resolveLangDir`) and explicit-directory path functions (`langPathIn`,
  `expectPathIn`, `generationPathIn`, `artifactsPathIn`); `Lips.Cli`'s
  `Check` verb becomes a `CheckOpts` record (mirroring `CompileOpts`) so both
  parse the flag identically. Verified by conformance tests (the resolver's
  match/mismatch/trailing-slash cases, both subcommands' CLI parsing) and a
  manual end-to-end run (a program copied into its own directory with no
  sibling language folder fails loud without the flag, succeeds and writes
  only local output with `--lang` pointing at a shared one, and a
  mismatched folder name is rejected naming both sides). Spec:
  `docs/superpowers/specs/2026-07-26-lang-dir-flag-design.md` (flag was later
  renamed from `--lang-dir` to `--lang` for symmetry with `--out`).

- **CLI: optparse-applicative parser, tab-completion for free.** `lips`'s
  argument parsing (`Lips.Generate.Args`'s hand-rolled loop, including the
  `looksLikeModel` heuristic that guessed whether a bare positional was a
  model id or a program file) is replaced by `Lips.Cli`, a single
  `optparse-applicative` `Parser Command` covering all four verbs
  (`generate`, `compile`, `check`, `lsp` -- `lsp` was reachable before but
  absent from `--help`; now consistent). `-m/--model` is the only way to name
  a model; short aliases `-t/--target`, `-o/--out`, `-v/--verbose` are added
  (`--renew` stays long-only, a deliberate rare action). Because completion
  scripts derive from the same `Parser` that parses real invocations, they
  cannot drift the way a hand-maintained static script would --
  `installShellCompletion` (nix packaging) ships bash/zsh/fish completions
  generated from the built binary at package build time (`makeWrapper
  --argv0 lips`, so `getProgName` -- used by both `--help` and the generated
  completion scripts' function/compdef names -- reports `lips`, not the
  wrapper's real target `.lips-unwrapped`). No change to any
  `report`/`reportHead` domain error (they are downstream of a successful
  parse). Spec: `docs/superpowers/specs/2026-07-25-cli-completion-design.md`.

- **Run axis: running is not a lips verb, it is `nix` over the compiled dir.**
  `compile` emits `flake.nix` + `default.nix` (+ `artifact.nix` when there are
  artifacts) and prints the exact stock `nix` commands the program's shape
  supports: `nix run/shell …#artifact.<name>` (exec/shell the bare binary) and
  `nix run …#vm` (throwaway QEMU boot of the whole system), with `nix build
  …#vm` as the no-KVM "does it build" check. No `container` rung: running a real
  init is inherently privileged, so nspawn was fragile and bought nothing `vm`
  does not; a portable OCI image is a future PACKAGE-axis output (`dockerTools`),
  not a run rung. The `run` verb and its VM-boot Haskell (`runVm`/`bootVm`/`vmExpr`/
  `runEvalOnly`) are deleted; the boot logic is now data in the flake.
  `default.nix` is byte-identical, so `vm-smoke`/`artifact-vm` are unaffected.
  Clash-proof by construction (rungs top-level, artifacts under
  `artifact.<name>`). Spec: `docs/superpowers/specs/2026-07-24-run-axis-design.md`.

- **Option-schema grounding: field-check @listOf@-submodule attrset elements (H3).**
  A rule that fills a @list of (submodule)@ option (e.g.
  @services.postgresql.ensureUsers@) with a list of attrsets now has each
  element's fields type-checked against the submodule's @*@@-wildcard leaves
  (@ensureUsers.*.ensureDBOwnership :: boolean@, @.*.name :: string@), which
  nixpkgs' @optionsJSON@ does list and the schema already carries. Previously
  the element type @OTOther "(submodule)"@ was the unconstrained catch-all, so
  a mistyped field (@ensureDBOwnership = "true"@ -- a string for a bool) slipped
  the gate and surfaced only at @nix eval@, less targeted and with no mint
  guidance. Now @checkEmits@ (the one door minted engines enter, @generate@;
  the run path stays schema-free -- invariant 1) steps into each @VAttr@
  element of a @VList@ rhs and @valueMatches@@ each field against its leaf type,
  reusing the existing scalar checker (so hole-filled fields -- @VHole HBool@,
  @VStr [PHole]@ -- check correctly). This is the pre-assembly placement
  (decided with the list-aggregation design): @assembleSubject@ is
  element-preserving (it concatenates @VList@ elements, never merges two
  @VAttr@s into one or splits one), so pre-assembly field-checking is complete
  -- nothing assembly does can introduce a field-type error absent from a
  fragment, and post-assembly would only re-check the same elements while
  dragging the schema into run. A submodule whose fields the schema does NOT
  list has no leaves to check against and degrades to unconstrained, which is
  correct (completeness by construction: the kernel cannot constrain what the
  schema does not, never a guess). @VTail@ is untouched: a tail-of-tokens rhs
  into a @listOf@ is already gated by @valueMatches@@'s missing @VTail@ arm.
  Verified by a conformance test (a string @ensureDBOwnership@ is flagged; a
  bool passes; a leafless submodule degrades to unconstrained) and proven live
  at the real door: @generate@ against the pinned nixpkgs schema rejects an
  engine emitting @ensureDBOwnership = "true"@, naming rule r2, where it
  previously slipped to @nix eval@. 221/221, @-Wall@ clean, all 9 examples
  @check@ clean.

  Follow-up (polish with regenerate-loop leverage): each failing field is now
  its OWN @TypeMismatch@ (no new error variant) at @path ++ [fieldName]@ -- so
  the message names the exact offending field
  (@services.postgresql.ensureUsers.ensureDBOwnership@, not the whole list) and
  its leaf type, in the human wording the model and nixpkgs use (@boolean@, not
  the Haskell @OTBool@), via a one-line @renderOptionType@ helper. The whole-
  element @TypeMismatch@ at the option path is kept for the non-submodule /
  scalar case (a non-@VAttr@ element into a @OTListOf@ scalar); the two are
  mutually exclusive for a submodule list (@OTOther@ catch-all makes
  @valueMatches@ pass, so only the field check fires). Proven live at the real
  door: @generate@ now reports @rule r2: option
  services.postgresql.ensureUsers.ensureDBOwnership has type boolean but the
  rule fills it with an incompatible value@. These messages feed the regenerate
  door, so the specificity improves loop convergence, not just a human's
  reading. 239/239.

- **Realize refuses an unfilled @<value.tail>@ (fail loud, not a literal).**
  The list-aggregation C work added @VTail@, a tail hole whose rhs fills to
  a @VList@ of the program value's tokens. @fillValue@ always converts
  @VTail@ -> @VList@ at the refine door, and a non-firing rule stores no
  decision, so an unfilled tail is unreachable in production. But the plan
  claimed an @RMalformed@ at realize's parse, and that claim was optimistic:
  @parseValue "<value.tail>"@ succeeds (returns @VTail@), so
  @renderRealized@'s catch-all would emit the literal @<value.tail>@ into the
  module -- the silent-wrong-config failure mode invariant #2 (fail loud,
  never guess) exists to prevent. The guard is now structural, not trusted to
  "currently unreachable": @realize@'s option-parse door rejects a @VTail@
  value with @RMalformed@, so any future path that lets an unfilled tail reach
  realize fails through the error channel rather than emitting a bogus string.
  (The error, not a crash: @renderRealized@ returns @Text@, so the guard lives
  at the @Either@-returning parse door, not in the renderer.) Verified 219/219,
  @-Wall@ clean, all 9 examples @check@ clean.

- **List aggregation (B + C, no block construct).** N sibling lines fold into
  one list-valued option, and one line may carry many items, with no block
  construct, no dictated collection syntax, and no new ordering key on the
  decision. (B) An `Append` merge mode alongside `Replace`, derived from the
  rule emits (a subject whose rule emits a `VList` rhs appends; the option
  schema is the authority but lives only at generate, and `checkEmits` already
  guarantees the rhs value-shape matches the option type, so run stays
  nixpkgs-free). `Append` assembles the top-strength contributors' `VList`
  elements in source-line order (human by `(file,line)` before derived by
  parent line) into one synthetic decision whose provenance links every
  contributor; replace-across-strengths holds (a stronger list replaces the
  whole list; `Append` is only same-strength aggregation). Cross-module list
  composition stays NixOS's job. (C) A template tail hole `<name.tail>` binds
  the rest of a line's tokens, and a value tail hole `<value.tail>` makes a rhs
  that fills to a `VList` of the program value's tokens (trailing punctuation
  stripped); an empty tail fails loud. A multiline collection is N flat lines
  whose patterns share a list subject; a header, if wanted, is an optional
  `Concept`. Prerequisite refactor (R1): Meta assertions are stored canonically
  (`renderValue`, round-trippable) and `realize` is the single canonical→Nix
  render point, which also completed the round-trip and replaced a quote-aware
  text artifact-ref scanner with Value-based detection. Domain-blind preserved
  (invariant 1); the canonical stored form stays one-decision-per-line. Design:
  `docs/superpowers/specs/2026-07-24-list-aggregation-design.md`.

- **Round-trip closure of the value and engine-path grammars.** The closed
  grammars now satisfy `parse . render = id` over generated inputs, pinned by
  QuickCheck properties (the meta-gap that let holes survive). Three holes the
  properties surfaced are closed. (1) Engine-path *render* is escape-aware:
  `renderAttrPath` (`Lips.Kernel.Engine.Data`) escapes `.` and `\` in a path
  segment, mirroring the base `joinSubject`, and is used by `renderEmit`,
  `renderRuleBody`/`renderDemandBody` (subjects), and `Expect.dotted` (option
  path and from-subject) -- so a literal dotted key
  (`environment.etc."my.route".text`) round-trips where plain `intercalate`.
  shredded it into two segments. This is the symmetric sibling of the prior
  quote-aware *parse* fix: parse normalizes a quoted key to bare, render escapes
  a literal dot. Existing engines are byte-identical (plain segments render
  unchanged). (2) Attrset keys accept `-` and `'` (`pAttrKey` now matches
  `Realize.isBareIdent`), so a hyphenated submodule field is a valid `VAttr` key.
  (3) A `VPath` value inside an attrset (`{ n = ../a; }`) round-trips: `pPath`
  now stops at `;` and `}` (attrset terminators) as well as `]` and whitespace,
  instead of folding the field separator into the path (rejected by
  `validPathLit`). The value round-trip property (`parseValue . renderValue ==
  id`) now generates `VAttr` (incl. hyphen keys) -- the constructor landed last
  milestone but was absent from the generator, which is why hyphen keys slipped;
  a parallel rule/expect dotted-segment round-trip property pins the engine
  path layer. Verified 195/195, `-Wall` clean, all 9 examples `check` clean.

- **Quote-aware attribute-path split (rule + expect).** The engine path split
  (a rule emit path, an expect option path, and the demand/rule subjects) is
  now quote/escape-aware, the engine analogue of the base
  'Lips.Kernel.Reader.splitSubject'. A model may write an @attrsOf@ key in
  Nix-attr-path form, quoted (@locations."/".proxyPass@) or bare
  (@locations./.proxyPass@); 'splitAttrPath' (in 'Lips.Kernel.Engine.Data')
  takes a quoted segment literally (no split on a dot inside the quotes) and
  strips the surrounding quotes, so both spellings parse to the SAME segment
  @/@. A backslash escapes the next char (@\"@, @\\@, @\.@); an unterminated
  quote fails loud. The canonical stored form stays BARE (the kernel quotes on
  realize via 'quoteSeg'), so every existing engine round-trips byte-identically;
  the fix is lenient on input, canonical on output. This closes the asymmetry
  between the realize side ('quoteSeg', which escaped a special-char key) and
  the eval-check side ('Expect.quote', which wrapped a quoted segment a second
  time into @""/""@ -- a Nix syntax error): a model that wrote a quoted key
  in the expect but a bare key in the rule (or split across them) crashed the
  gate with an inscrutable syntax error instead of a clear mismatch. Naively
  making 'Expect.quote' escape like 'quoteSeg' would have made the check look
  up the WRONG key (@"/"@, quote-slash-quote) that the realize side also
  emits for a quoted rule key, so a config serving the wrong route would pass
  the gate SILENTLY -- the wrong fix. Normalizing at the only door minted
  engines enter keeps rule and expect agreeing on the key without a prompt
  plea and without masking (this is invariant 4: a mint that reliably slips is
  fixed in the kernel/format, not the prompt). The 'Lips.Kernel.Engine.Value'
  attrset constructor and the realize 'quoteSeg' are untouched. Verified by the
  conformance suite (quoted-key rule/expect parse to the bare segment,
  unterminated quote rejected, dot-in-quoted-key stays one segment) and proven
  live: a proxy engine written with a quoted @"/"@ location in both rule and
  expect realizes to the correct @services.nginx.virtualHosts.<self>.locations."/".proxyPass@
  and its contract passes, where it previously crashed the eval with a syntax
  error.

- **Value grammar: attrsets (listOf-submodule rhs).** The closed rhs value
  algebra gains an attrset constructor `VAttr [(Text, Value)]`, so a rule can
  fill a `listOf`-submodule option whose elements are records — the shape
  `services.postgresql.ensureUsers = [ { name = "..."; ensureDBOwnership = true; } ]`
  that was previously unrepresentable. Keys are bare ASCII identifiers only
  (closed, injection-safe: a non-identifier or quoted key is rejected, so a
  program value can never alter the attrset's shape); values are full `Value`s,
  so a hole inside a field fills and escapes like any other. `parseValue`,
  `renderValue`/`renderRealized` (nixpkgs-conventional trailing `;` per field,
  `{}` for empty), `fillValue` (recurses), and `valueRefsDerivation` (recurses,
  so a `${pkgs...}`/`${artifact...}` ref nested in a field is still detected)
  cover the new form. No other layer moves: option-schema grounding already
  typed `list of submodule` as `OTListOf (OTOther "submodule")`, whose
  elements are unconstrained, so a `VList [VAttr ...]` grounds clean with zero
  `OptionType` change — the kernel reaches the concrete (record-valued) shape by
  the same closed grammar it always had, now with one more constructor. This is
  invariant 3 (completeness by construction) in action: a missing grammar case
  was a kernel bug, fixed in the kernel not the prompt; the model is one-shot
  and blind, so the grammar must accept the record form NixOS options
  everywhere demand. Verified by the conformance suite (parse, round-trip,
  fill-and-escape, key rejection, computation rejection, nested-ref detection,
  `OTListOf OTOther` grounding) and proven live end to end: `appdb.postgres.lips`
  mints an engine whose r3 emits the attrset and `check` passes, the postgres
  provisioning that was blocked before now realizes to `services.postgresql.
  ensureUsers = [ { name = "app"; ensureDBOwnership = true; } ]`.

- **Realization target (NixOS / home-manager).** The world an engine targets is
  per-problem knowledge that lives in the option paths its rules emit, decided
  at mint time; the kernel stays world-blind (`realize` emits only
  `{ config, lib, pkgs, ... }: { <path> = <value> }`). `lips generate
  [--target nixos|home-manager]` (default nixos) steers the mint prompt into
  that world's namespace (`Minting.worldSection`) and grounds the minted option
  paths against that world's `optionsJSON` (nixpkgs NixOS manual vs
  home-manager `docs-json`, baked as `LIPS_NIXPKGS_FLAKE` / `LIPS_HM_FLAKE`; only
  generate ever builds a schema, so compile/check stay nixpkgs-free). The
  world is recorded in `.generation` (`target:` line) and so enters `genId`; a
  re-mint for a different world is a distinct, `.expect`-gated event. `compile`
  reads the recorded world and emits the matching flake: nixos gets
  `apps.vm` + `packages.vm`, home-manager gets the module and an import hint (no
  machine to boot). No home-manager eval harness
  was needed because the `.expect` gate is world-blind (it applies the bare
  module with stubbed args and reads assigned values, never evaluating a world's
  module system). The flake helper `lib.modulesFromDir { pkgs; dir; }` exposes
  each `*.lips` in a directory under `nixosModules.<instance>` /
  `homeManagerModules.<instance>` by its recorded world, built by a `compile`
  derivation. `Lips.Nix.Target` holds the closed `Target` type; `Lips.Cli`
  the flag parser (`optparse-applicative`, since the CLI migration above).
  Design in
  `docs/superpowers/specs/2026-07-22-realization-target-design.md` (its §10-11
  cover kubenix/terranix as further targets and the target-vs-solution-kind
  axis: `nix run`/`shell`/`develop` are a different axis — a new realize output
  shape, not a namespace). Caveat proven live: an option present in BOTH worlds
  (`services.restic.backups`) yields identical module text, so `--target` does
  no structural filtering there — only the recorded world and runtime differ;
  lips cannot read intent, so targeting a system-concern program at
  home-manager is a human error it will faithfully realize.

- **Re-bless flag (`generate --renew`).** Ignore the committed `.expect` and
  rewrite it from this mint, so a deliberate behavior change is one command
  instead of `rm .expect && generate`. Every correctness gate (crystallize,
  option grounding, realize, nix-parse) and the behavioral gate still run, so a
  bad mint still writes nothing; the rewritten `.expect` diff stays the semantic
  changelog (invariant 5 preserved: explicit human decision, never silent). The
  refusal message names it.

- **Grammar completeness: typed hole inside a string.** Inside a Nix string the
  value is text, so a redundant `:type` on a hole (`<value:int>`,
  `<value.N:int>`) is meaningless there; the value grammar now degrades it
  losslessly to the plain hole rather than rejecting it (a form the mint writes
  naturally when it wants a number). A real option-type mismatch is still caught
  by option grounding, so nothing weakens. This is invariant 4 in action:
  a mint that reliably slips is fixed in the kernel/format, not the prompt —
  the model is one-shot and blind, so detection is the kernel's job and the
  grammar should accept the model's natural output.

- **Language reuse across instances (language as a configurable module).** A
  program is named `<instance>.<language>.lips`: the uniform `.lips` marker is
  the editor / language-server handle (one extension every tool associates on),
  the segment before it names a shared language, and what precedes that is the
  instance (optional -- `backup.lips` is the singleton shorthand, its instance
  defaulting to the language). A language is one configurable NixOS module
  induced by anti-unifying several example programs (divergences become both
  the accepted holes and the option surface, empirically confirmed: two backup
  examples generalized the overfit literal `daily` of one into a `<period>`
  hole). An instance is a configuration keyed by the `<self>` value hole, which
  the shell binds to the instance name and which fills the option schema's
  `attrsOf` `"*"` wildcard -- so multiplicity rides Nix's native module merge,
  not a lips mechanism (`services.restic.backups.ledger.*` and `...photos.*`
  coexist). `.lang`/`.expect`/`.generation`/`.direction` are language-level
  (named by the language); the three the machine writes live, with `artifacts/`,
  in a folder named after the language beside the programs
  (`examples/backup/backup.lang`), while the human-written `.direction` stays at
  the top level with the programs (`examples/backup.direction`) -- the layout's
  single rule is that a listing shows what a human owns and nothing else, so
  authorship, not scope, decides where a file sits. Everything
  derived goes under that folder's `out/` (`out/ledger.decisions`, the compiled
  module dir `out/ledger/`), which lips makes self-ignoring by writing
  `out/.gitignore` holding `*`. The split is the readable form of the project's
  central claim: a directory listing shows the human-owned `*.lips` programs and
  nothing else, and the path alone says whether a file is owned, minted, or
  derived. `.decisions` is per instance; `generate` takes several
  programs and gates the whole set (crystallize + committed `.expect`) as the
  regeneration corpus. Kernel additions: the `<self>` binding in rule emit
  paths, rule rhs values (a `<self>` string piece and a `${artifact.<self>}`
  reference, so a rule names the program's own build/app), and expect paths,
  plus path-value stringifying in the expect eval; the rest is
  shell (`Lips.Identity`, CLI, LSP lookup) and the mint prompt (teach `<self>`
  and generalize-across-programs). Proven live (opus-4-8 + KVM): the backup
  language minted from `ledger`+`photos`, feed and http migrated, all four
  programs `check` clean, `vm-smoke` and `artifact-vm` green. Full design in
  `docs/superpowers/plans/2026-07-22-language-as-configurable-module-plan.md`.

- **Option-schema grounding (generate acceptance).** `generate` checks every
  minted rule's option path and value type against the pinned nixpkgs
  `optionsJSON` and rejects a rule that names a nonexistent or mistyped option,
  deterministically and offline (deduce-or-fail at the NixOS layer). The check
  is domain-blind: `Lips.Kernel.OptionType` consumes a generic typed
  `OptionSchema` (with `"*"` wildcard segments for `attrsOf`-submodule instance
  names and prefix-acceptance for free-form/submodule descents); the
  NixOS-specific `optionsJSON` shape and type-string wording live in
  `Lips.Nix.Options`, so a different target (terranix) adds a sibling module.
  `generate` builds the schema lazily from the pinned nixpkgs baked into the
  packaged binary as a plain rev string (`LIPS_NIXPKGS_FLAKE`), so nixpkgs
  never enters `compile`/`run`/`check`'s closure; the one-time build is
  announced. `LIPS_OPTIONS_JSON` overrides it (the suite passes an offline
  fixture). `artifact.*` build-group emits are exempt (they
  realize as a derivation, not an option). Verified against the committed
  backup, feed, and hello-server engines. This is steal #1 of the
  Compiled-AI/NixOS prior-art scan (`survey/e-compiled-ai-paradigm-and-nixos-targeting.md`).

- **Artifacts (program-derived source, built and run in the config).** A
  Solution whose realization *builds a program from generated source* and runs
  it, distinct from glue. Complete by inheritance from nixpkgs: a builder is a
  *name* (`rustPlatform.buildRustPackage`, `buildGoModule`, ...), never an
  enumerated case, so any language works with zero kernel change. An artifact
  is a subject-path group (`artifact.<name>.builder`, `artifact.<name>.args.*`);
  realize gathers each group into a `let artifact = { <name> = pkgs.<builder>
  { <args> }; }` block, referenced by the `${artifact.<name>}` value piece
  (a name, injection-closed; a dangling reference fails loud). Generated source
  lives in committed sibling files under `<program>.artifacts/<name>/`, staged
  at `./artifacts/<name>` beside the realized module for evaluation and boot
  (option 1 of the plan). `generate` mints the engine plus source (a heredoc
  `source` block), and validates the ROUND-TRIPPED engine plus the behavioral
  gate before writing anything; the AI touches only generate. Proven live end
  to end and pinned as the `artifact-vm` flake check:
  `examples/hello-server.loose` -> opus mints a Go engine + `main.go` ->
  realize -> `buildGoModule` compiles it offline -> the `hello` service boots
  in a VM and answers `curl :8080` with the program's text. Full design in
  `docs/superpowers/plans/2026-07-21-artifacts-plan.md`.
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
- **Multi-fact patterns (a dense line states several facts).** A pattern emits
  one OR MORE decisions per matched line, `;`-separated in the `.lang` body
  (mirroring the rule back half): `http server in <lang> on port <port>` fixes
  both `server.language` and `http.port` from one line. A line matches exactly
  one pattern, so before this a demand on the second fact of a dense line could
  never be met -- generate then wrongly told the author to state a value the
  program already carried. The base is keyed by decision id, so a multi-emit
  line gives each decision a distinct `d<n>.<k>` id (a sole emit keeps the bare
  `d<n>`, so older single-emit engines read and render byte-identically). The
  quote-aware ` ; ` split lets an assertion contain `; `. Verified end to end:
  the dense line crystallizes to two decisions and realizes both options.
- **Decorative heading lines (a `concept` groups and explains).** A `Concept`
  decision is decorative vocabulary: a heading or label (`http routes:`) that
  groups the lines under it and, at mint time, tells the model what those lines
  mean, but carries no obligation to realize. `run` drops it before realize, so
  it neither trips the anti-MDA guard (unlike `Fact`/`Oblige`/... which must
  still map) nor leaks into the module as an option. The mint gives the grouped
  items a shared subject prefix (`route.<path>.*`), so the group is legible in
  the output. Domain-blind: the kernel knows only that a `Concept` does not
  realize, never what "routes" are. Verified end to end on the full
  `http server + routes` program: heading absorbed, dense server line and both
  dense route lines realized. (Per-item value-keying -- several routes in ONE
  program, each keyed by its path -- is the "value-keyed options" milestone
  below; cross-program instance reuse is the "language as a configurable
  module" work above.)
- **Value-keyed options (a per-item attrsOf key from a program value).** A rule
  subject segment written `<name>` is a capture that binds any concrete segment
  (`route.<path>.status` matches `route./hello.status`), and the captured key
  fills every `<name>` occurrence in the emit path -- a whole segment
  (`environment.etc.<path>.text`) or embedded in a composed one
  (`environment.etc.http-routes-<path>.text`); an unresolved `<name>` fails
  loud rather than emitting a colliding literal. The same capture primitive
  (`Kernel/Capture`: match, fill) resolves subjects wherever the model writes
  them -- rules, expects (a family `expect ... from route.<path>.status`
  expands to one concrete check per route against each program's base), and
  demands (a family demand is met by any matching item) -- so the capability is
  complete across every stage, not just rules. A captured key may itself contain
  a dot (an HTTP route `/file.json`): crystallize builds the subject from the
  pattern's structure (a hole value is one atomic segment, never re-split), and
  the canonical `.decisions` form escapes a literal dot (`\.`) so the base
  round-trips losslessly; realize quotes the segment (`environment.etc."http/file.json".text`). So N sibling decisions from ONE program
  (several routes, mounts, vhosts) fan a SINGLE rule out to N distinct option
  slots keyed by their own value, riding the target's native `attrsOf` merge --
  the per-item analogue of the language-level `<self>` instance key. The pattern
  side already emits value-bearing subjects (`peSubject` holes), so the change
  is confined to the rule side: `toRule` gains subject-family matching with
  capture bindings and emit-path fill (`Kernel/Engine/Data.hs`), and `realize`
  string-quotes a path segment that is not a bare Nix identifier
  (`environment.etc."httpserver/hello".text`). Nothing else moves: a capture
  matches only a schema `"*"` placeholder, so keying a non-`attrsOf` option is
  rejected at generate (`UnknownOption`) -- a free correctness guard -- and the
  value grammar, crystallize, and pattern layers are untouched. Existing
  engines realize byte-identically (instance names stay bare). The mint prompt
  teaches the model to key into a REAL `attrsOf` option instead of folding
  items into one fixed option or inventing a table item kind. A capture reaches
  the emit path only; the value still comes from `<value>`/`<value.N>`. Verified
  end to end (crystallize -> refine -> realize): two routes fan out to two
  path-keyed `environment.etc` entries.
- **Generate boundary plumbing.** Model call routed through `pi` print mode;
  deduce-or-fail confidence threshold, exposed as `lips generate
  [--confidence <0..1>] [model] <program>` (default 0.7, pinned into the
  generation record so it enters the event id); generation record written per
  event.
- **No model baked in.** lips picks no default model: `[model]` is optional and
  when omitted `--model` is not passed, so pi's own configured default applies
  (the model is an environment choice, not a fact of the deliverable). The call
  uses `pi --mode json`; the model pi actually used is read back from the event
  stream and recorded in `.generation`, so provenance and `genId` stay concrete
  without a vendor model in the source. Parsing lives in
  `Lips.Generate.PiJson` (the sole `aeson` user, in the Generate tier; the
  kernel stays base+containers+text). A repo-wide default or reading pi's config
  were rejected: omit-and-read-back is the narrowest mechanism.
- **Generate failure feedback (info-only, no dialogue).** When `generate`
  cannot write an engine it prints a classified, plain-language report to the
  command output -- the one channel the user reads -- with what went wrong and
  what to do, no jargon, no files. Two causes: lines lips could not read (a
  kernel/engine mechanism may be missing -> report them) and items the model
  could not derive (the program underspecifies them -> state the detail in the
  program). No clarification dialogue: the program is the sole source of truth,
  so the remedy is always to edit the program, never to answer a question.
  Rejected/shelved: an `ask` channel (would be a dialogue), autofix (a possible
  future opt-in mode; skipped to stay simple, and it needs no persisted file),
  and a `.gap` artifact (kept to on-screen only).
- **Engine synthesis (was the central gap).** `generate` mints the whole
  engine as data in one `.lang` file: patterns (front half) plus rules
  (`match <kind> <subject> => option assignments`, with `<value>`/`<value.N>`
  holes) and demands (back half), interpreted by generic kernel executors
  (`Kernel.Engine.Data`); the hand-written `Engine.Feed` is deleted. No domain
  vocabulary is compiled in; the model invents subjects, and closure is
  checked, not trusted (unmapped decision, unmet demand, uncovered line, or
  invalid Nix -- `nix-instantiate --parse` at mint time -- each rejects the
  engine). Proven live on two domains: the feed and a non-feed restic backup
  job, both minted by opus, both then absorbing value edits offline.
  Deliberate restriction: minted rules emit only ground decisions (one
  refinement pass, no cascades until a real program needs them).

- **Generation-event provenance.** Every minted engine line is stamped
  `@gen:<id>`, the content id of its `.generation` record; records are
  committed beside the engine (no longer gitignored) and the stamp is
  mechanically checkable by re-hashing the record. Regenerating the examples
  under this scheme surfaced live drift (the model switched to the stock
  restic module and exposed two decisions the old engine had smuggled:
  credentials location and a literal schedule), which moved into the program
  — backup.loose is now three lines and every line is witnessed by the VM
  smoke test.

- **Closed rhs value language.** A minted rule's rhs is a typed value (string
  with holes and `${pkgs...}` refs only, list, bool, int), never Nix text:
  computation and string injection are unrepresentable, discharging the
  structural layer of deduce-or-fail where the prompt alone had carried it.

- **Realization smoke test (VM).** A permanent flake check
  (`checks.vm-smoke`): the committed backup Solution is realized
  deterministically (no model) and the module boots in a NixOS VM beside stock
  modules; the minted timer is live and the service carries the program's
  values verbatim. The coexistence defense (one Solution = one ordinary
  importable module) is now a machine-checked guarantee, not a demo.

- **Behavioral gate on regeneration.** Each program carries a committed
  `<program>.expect` contract: relational assertions binding a NixOS option
  path to a program value (`expect <option.path> from <subject>[#n]`), judged
  by containment against the module evaluated with `nix eval` (self-contained,
  offline; the full module system and runtime truth stay with `vm-smoke`).
  `generate` mints the assertions alongside the engine and refuses an engine
  whose realized module violates the contract; on regeneration the *committed*
  contract governs (the stable spec), on first generation the minted one
  bootstraps it. A violation is the decision surface: fix the regression, or
  delete `.expect` and regenerate to re-bless. The binding is relational, not
  a frozen literal, so a legitimate value edit moves both sides together
  (edit-tolerance) while a drift that relocates or drops the value trips the
  gate. `lips check <program>` runs it deterministically; `just check-expect`
  guards every example. `Lips.Kernel.Expect` holds the pure core.

- **Two-tier module layout.** Inside `kernel/src/Lips/`, the tree names the
  tier: `Kernel/` is deterministic physics and holds all substrate, including
  `Kernel/Engine/` (the engine *format* and generic interpreter plus the
  closed value language) and `Kernel/Lang/` (crystallization: patterns and
  template matching). `Generate/` is the sole non-deterministic tier, the AI
  boundary. So there are two real tiers, not four peers. There is no
  per-problem engine *code*: an engine is data (`.lang`); the only
  engine-related code is the domain-blind interpreter in `Kernel/Engine/`.
  (The `.lang` store module is `Kernel.Lang.Store`, renamed from the earlier
  doubled `Kernel.Lang.Lang`.)

- **Repository layout and tooling.** `kernel/` is the pure deliverable (the
  calculus reference implementation `src/`, the CLI `app/`, the conformance
  suite `test/`, and its module-map README). Everything not deliverable sits
  above it: `examples/` (demonstration programs plus their minted `.lang` and
  `.generation`), `docs/`, the root `README.md` (developer entry point: the
  loop, try-it, what-is-the-program), the `flake.nix` (build / dev shell with
  ghc+just / checks), and the `justfile` (command index: build, test, check,
  run, generate, vm-smoke, shell, clean). `.envrc` enters the dev shell via
  direnv. The root `README.md` is the developer entry point (try-it, the
  generate/run/check loop, artifact table + flow diagram, traceability);
  `AGENTS.md` (symlinked `CLAUDE.md`) carries what agents need beyond it:
  exact terminology, the six invariants (run never calls a model;
  deduce-or-fail; illegal states unrepresentable; workarounds become kernel
  physics; `.expect` gates regeneration; `@gen` stamps re-hash), and working
  conventions (worktrees, TDD, ff-merge, ledger upkeep, flake sees only
  git-tracked files, `pi` gateway deliberately outside the dev shell). The flake lives at the root, not in `kernel/`, because a flake
  cannot reference a sibling `examples/` and because it is project
  infrastructure, not part of the deliverable. Recipes use `.` (git flake
  semantics) so untracked runtime dirs stay out of the flake tree.
  `.gitignore` covers `.direnv/`, `result`, `*.decisions` (the crystal cache
  is derived, never source).

- **Fail-loud hardening (kernel review, 2026-07-22).** A pass over the kernel
  and generate tiers closed every reachable crash and silent-drop, so the
  deterministic paths always fail through a typed channel. (1) Rule rewrite is
  fallible: a value hole that outruns its program value (a `<value.N>` past the
  token count, a wrong-typed hole) is `RewriteFailed`, not an `error`, so an
  edit that shortens a value fails loud on `compile`. (2) Every minted item is
  keyword-led (`pattern|match|demand|expect`); a pattern template may begin
  with any domain word without being misdispatched, and an unknown item form is
  rejected. (3) A `.expect` naming an option a rule fills with a package or
  artifact reference is rejected (`uncheckableExpects`), since such an option
  is a derivation the stubbed check eval cannot force (and `tryEval` does not
  catch a missing attribute). (4) `readLang` reads in one line-aware pass:
  unrecognized engine lines fail loud (no silent drop) and body errors name
  their real source line. (5) `realize` returns a typed `RealizeError`
  (dangling `${artifact}` reference, malformed artifact group), surfaced as the
  `Unrealizable` run outcome, never a crash. (6) The unused resampling harness
  (`unanimous`/`admit`/`coreOf`) was removed as speculative: `generate` samples
  once, and `Confidence` is all that remains of that module. The conformance
  suite is `-Wall` clean and no test uses `shouldThrow` any more.

- **Editor tooling from `.lang` (first rung done).** The authoring view is a
  pure function of (language, program): `diagnose` (`Kernel/Lang/Diagnose.hs`)
  classifies every program line through the one shared matcher
  (`classifyLines`, so a diagnostic never disagrees with what `run` does) --
  matched (which pattern, which subject), unread (escapes the language), or
  ambiguous (several patterns) -- then lists the demands left open by what the
  program states, then coverage. `lips check` now runs this as a pure,
  offline first phase (no Nix, no AI) before the `.expect` behavioral gate, so
  authoring is never blind: an unread line names `generate`, an open question
  names the missing detail, a clean program proceeds to the gate. This is the
  CLI-first rung of the comprehension-per-minute promise.

  The language-server rung also landed: `lips lsp` (`Lsp/Server.hs`, a minimal
  stdio JSON-RPC server; `Lsp/Derive.hs`, its pure core) gives completion and
  live diagnostics in any editor. It is domain-blind and needs no per-language
  setup: one process serves every lips program from the `<file>.lang` beside
  it -- completion items are the language's pattern templates as snippets
  (holes become numbered tab-stops), diagnostics are the same `diagnose`
  output surfaced as squiggles (an unread line is an error, an open question a
  warning). Client glue for neovim/vim/vscode/helix is in `editors/`. `Derive`
  is pure (no aeson, kernel-clean); only the server shell uses aeson, confined
  like `Generate.PiJson`. Percent-decoding of `file://` URIs landed with the
  server (`uriToPath`, pinned by tests over spaces and non-ASCII). Remaining
  polish: hover and go-to for a line's produced subject, and as-you-type
  completion tuning.

- **Readable generate refusals.** A refusal now names its remedy instead of
  dumping grammar. Three coordinated moves. (1) The `--confidence` hint is
  derived from the lowest dropped confidence, so it can no longer echo the bar
  the user just used. (2) A `because "<reason>"` line (keyed by the same id as
  the item it explains, `ItemNote`, dropped from the engine) lets the model
  attach a plain-language reason to any low-confidence item; the refusal prints
  it under the refused line. (3) The prompt routes a missing PROGRAM FACT to a
  high-confidence `demand` (plus the pattern that reads its answer) rather than
  a guessed value, and generate surfaces an unmet demand as the human-authored
  question (`OpenQuestions` -> "answer each in <file>, then run generate
  again") instead of the lips-bug wording. Guessable values (free defaults,
  synthesized build inputs) stay low-confidence with a because-note.

- **LSP contextual completion (partials).** The language server used to ignore
  the cursor and return every pattern as a whole-sentence snippet with no
  `textEdit`, so accepting a completion mid-sentence duplicated the prefix and
  threw away any hole value already typed. `textDocument/completion` now reads
  the cursor position and the buffer line, matches the typed prefix against
  each pattern's template (`Lips.Lsp.Derive.completionItemsAt`, pure), and offers
  only patterns whose template still has something left to complete.
  Already-typed holes fill as literals; only holes still to type become
  numbered tab-stops (by hole name, so a repeated hole stays in sync). A
  fragment at the cursor (the cursor mid-word) completes positionally: it fills
  the literal it is a prefix of (so `dr` completes `drops`) or binds the hole
  at that position. Each item carries a `textEdit` spanning the typed prefix
  (from the first non-space column to the cursor), so accepting replaces the
  prefix with the whole sentence cleanly, and `isIncomplete` is true so the
  client re-requests as the user types. An empty line reaches the old
  whole-sentence behavior through the same renderer. The match reuses the
  template grammar and adds no per-program knowledge, so the kernel stays
  domain-blind (invariant 1); the pure core is testable without a socket and
  the wire shell stays a thin mapper. Verified 226/226, `-Wall` clean, and live
  over stdio against `backup.lang` (filled `source` preserved as a literal,
  `ba` completes `back`, a fully-matched line offers nothing).

- **Value grammar: package-derivation holes (`<value:pkg>`, `<value.tail:pkg>`).**
  The closed rhs value algebra gains a hole whose filled value is a
  `pkgs.<token>` *derivation*, not a string or scalar. This bridges the two
  universes the grammar kept separate: a hole fills to a *value* (a string,
  number, list of strings), a `${pkgs.<path>}` *reference* names a *literal*
  derivation. A program that names packages ("install npm, yarn, bun") had no
  path from a name token to a derivation, so the model tried `${pkgs.<value>}`
  and the kernel honestly rejected it (a ref path is a literal name, never a
  hole); the only alternative emitted strings, the wrong type for an option
  like `environment.systemPackages`. The fix is one new `HoleType` constructor,
  `HPkg`, and a typed tail. A bare `<value:pkg>` (or `<value.N:pkg>`) fills one
  token to a `VRef (RPkg ("pkgs":segs))`; `VTail` generalizes from `VTail Text`
  to `VTail (Maybe HoleType) Text`, so `<value.tail:pkg>` fills a line of names
  to a `VList` of `pkgs.<name>` derivations (bare `<value.tail>` keeps its
  string-token behavior; the other typed tails come free by symmetry with the
  bare hole). Injection-safety is unchanged in spirit: the token is split on
  `.` and every segment gated by `okSeg`, so program text can never alter the
  path shape (a space, operator, `${`, or non-identifier fails loud). Domain-
  blindness holds: `environment.systemPackages` is `OTListOf (OTOther
  "package")`, and a `VList [VRef ...]` matches via the existing `OTOther _
  -> True` arm with no new `OptionType`, so the kernel still never learns
  "package". The one downstream correction the primitive exposed: a pkg hole
  and a typed tail reference a derivation, so `valueRefsDerivation` now reads
  `VHole HPkg _` and `VTail (Just _) _` as `True` (both fell through to `False`
  before), keeping `uncheckableExpects` honest. Verified 229/229, `-Wall` clean;
  an end-to-end test realizes `install htop, ripgrep.` + `install tmux.` to
  `environment.systemPackages = [ pkgs.htop pkgs.ripgrep pkgs.tmux ];`.
- **Staged sources: a path the module names must be there.** A relative path
  literal is the one value a realized module cannot vouch for itself: nix
  resolves it against the module directory, i.e. against the tree lips stages
  beside the module (an artifact's minted source). Two mints proved the hole,
  both past every gate with `check` reporting success: the `habit` mint emitted
  `args.src ./artifacts/<name>` but wrote its source under the literal directory
  `<name>`, and renaming the command in `board.lips` left the filled path
  `./artifacts/kb` pointing at a tree staged only for `board`. Both died inside
  nix with `path '/nix/store/...-source/artifacts/habit' does not exist`, naming
  neither lips, the program, the artifact, nor a remedy, and only at the user's
  `nix run`. The fix is domain-blind and needs no builder knowledge:
  `realizeStagedPaths` reports every relative path in the ground base with the
  decision that named it (structural, from the parsed `Value` via `valuePaths`,
  so a quoted `"./x"` string is a string), `runBaseStaged` projects it from the
  same `runGround` the module and `artifact.nix` come from, and `stagedGate`
  (`Main.hs`) requires each path to exist in a real staging into a temp dir --
  the territory nix will see, not a guess at how a path maps to the language
  folder. It runs at `check` (so `compile` inherits it) and at `generate` over
  the in-memory minted sources, so a mint whose source tree and path disagree is
  refused instead of committed. An absolute path is the host's to have, so it is
  not checked. Remedy named in the message is regeneration, since minted source
  is never hand-edited (invariant 4). Verified 341/341, `-Wall` clean; both
  repros refused, the other eleven examples unchanged.

- **A demand no pattern can answer is a static defect.** `openQuestions` judges
  a demand against the crystallized base, so only a subject the language's own
  patterns emit can ever satisfy one; subject matching is segment-for-segment
  (`matchSubject`). Two `habit` mints in a row wrote `demand command` beside a
  pattern emitting `command.<name>`, one segment short, so the demand stood open
  for every program and lips told the author to state a fact the program already
  stated (`install the tool as the command habit.`) -- a mint defect wearing an
  author's error message. `Kernel/Engine/Answerable.hs` refuses it statically:
  each demand subject must unify (`subjectsUnify`) with a subject family some
  pattern emits, derived by running the pattern's own substitution
  (`applyPattern` with each hole standing as its own capture), so the check sees
  exactly the subjects crystallize will build. Wired in at `generate`
  (`assertDemandsAnswerable`, beside the orthogonality and dropped-value gates)
  and at `check`, where it replaces the misleading "answer them in the program"
  action for an engine already committed. Domain-blind: it asks only whether the
  engine's own shape could ever produce the subject, never what it means. The
  prompt states the rule too, but the guard is what holds (invariant 4: two
  identical mint failures mean a prompt plea is not the fix). Verified 346/346,
  `-Wall` clean; the third `habit` mint then wrote `demand habit.command.<name>`
  and passed every gate.

- **Three CLI tools, minted and committed.** `examples/{board,habit,logscan}`
  (f0e8d13) plus `greet` (ca09f97) make four committed CLI engines, the shape
  TODO 1 was opened for. Each keys its artifact by the command name the program
  gives it (`fact tool.<name>` / `habit.command.<name>`), builds with
  `buildGoModule` (`vendorHash = null`, a `version` constant) over a minted Go
  source tree, and lands it in `home.packages`; program values reach the tool at
  runtime through the environment (`board`: `home.sessionVariables`) or a config
  file (`habit`: `xdg.configFile`), never baked into the source, so editing the
  program takes effect without regeneration. Verified per engine: `check` green,
  `nix eval …#artifact.<name>.drvPath` instantiates, and each binary runs
  (`logscan` filters `{"a":"1"}` by `a=1`; `habit` prints a heatmap from a TSV
  named by the program). What they cost: two gates the mints themselves
  provoked (staged sources, answerable demands), both now physics.

- **The multi-token capture (`<name.words>`).** A template hole may bind several
  tokens, anywhere in the template: it takes the fewest tokens it can and the
  rest of the template decides, growing the capture when the rest then fails, so
  `back up <src.words> to <dst>` reads `back up a to b to c` as `src = "a to b"`.
  Without the backtracking a line inside the language would be reported as
  outside it, which is a grammar bug rather than a program defect. The search is
  over a line's handful of tokens and laziness stops it at the first success, so
  matching stays total, deterministic and cheap. This is the second of the
  enumerated capture forms (completeness plan, Target 2) and it subsumes the old
  end-of-line-only `<name.tail>`, whose spelling is retired; the mint prompt now
  offers it, since a capability the model is never told about is dead capability.

- **Source fills: a program word inside baked source.** An artifact's source tree
  is minted once and committed verbatim, so a value that had to appear *inside*
  the code froze there: a command name was spelled twice, once in the program and
  once, dead, in `go.mod`. A live mint answered that with shell smuggled through a
  build argument (a `postInstall` loop renaming the binary), exactly the
  workaround the value grammar exists to forbid, so by invariant 4 the hole
  belongs in the format. Two halves that must agree: the engine declares
  `artifact.<name>.fill.<marker>` whose rhs is an ordinary value (so every hole
  mechanism already applies and computation stays unrepresentable), and the source
  names `@marker@`, the nixpkgs `substituteAll` spelling, narrow enough that a
  decorator or a Makefile prefix is not read as a marker. `Lips.Kernel.Source`
  checks both directions -- a declared fill no file names would let the program's
  word govern nothing, a marker no fill declares would ship `@marker@` into the
  compiled program -- and substitutes in ONE pass, so a fill's own text is never
  rescanned and a program value cannot inject a marker. Filling happens where the
  tree is staged (compile and the gates), never in the committed tree: the
  committed source keeps its markers and stays the template it is, while the
  compiled source is derived like every other output. A fill carries text (a
  literal string or number), never a reference: lips fills offline, so no store
  path is available. Proven end to end: a Go program whose `go.mod` says
  `module @name@` and whose body prints `@msg@` builds and runs with the
  program's own words. Still missing: a REPEATING structure inside source (one
  block per route), which a marker cannot express -- filed as a gap, never faked.
  Beside it, an artifact section the kernel does not know (a mint's `arg` for
  `args`) is now refused instead of silently dropped.

- **Static pattern overlap.** The sibling of the rule check, at the same gate and
  for the same reason: `crystallize` reports `Overlapping` only for a line some
  program states, so two templates no example separates ship inside the engine and
  fail later on the author's own program. A product walk over the two templates
  decides it exactly (see §11), and the first path that reaches both ends is the
  witness the refusal prints, as a line shape. The multi-token hole made this
  urgent: it reads lines of every length, so it overlaps almost any template with
  the same prefix. Verified against the corpus: all 11 committed engines are
  orthogonal at the pattern layer, so the check refuses nothing that works today.

### Partial
- **Behavioral gate: remaining.** The gate (see Done) now runs at every
  deterministic verb, not just `generate`: `check` is the gate alone and
  `compile` gates (it calls `checkLoose`) before it writes, so neither
  materializes a module that dropped a pinned value. (`run` is gone; running is
  stock `nix` over the compiled dir, which is past every gate.) Two holes are
  open, both verified: the gate is a NO-OP for a language whose `.expect` is
  absent or empty (`greet`, `logscan`), and the deploy path
  `lib.modulesFromDir` copies only the `.lang` into its compile derivation, so
  the contract is silently skipped there -- see "Verified breakages" below.
  This makes the safe path the obvious path
  (Failproof): the headline offline verb no longer emits a silently-wrong
  module. Nix is the compile target, so the gate's `nix eval` is no new
  dependency (every invocation already runs through nix; the output is only
  meaningful where nix runs) and the emitted module stays bit-identical and
  deterministic -- the gate only refuses a bad one. Assertions name concrete
  option paths, so a legitimate mechanism swap always re-blesses
  (mechanism-independent assertions would need the unbuilt
  vocabulary/ontology). A cross-program corpus still does not typecheck because
  engines are per-problem (`feed.loose.lang` and `backup.loose.lang` are
  independent); the gate is per-program by design.
- **Glue.** `Glue` exists as a `Kind`, but its rigor downgrade (marked glue ->
  property testing, visible blast radius) is not implemented. This is the wall
  behind the expressiveness frontier: the closed rhs value language forbids
  computation by construction (which is what makes injection unrepresentable),
  so an engine can *reference* a prebuilt package (`${pkgs.cudaPackages...}`,
  `${pkgs.someGuiApp}`) but cannot inline a bespoke build (compiling a CUDA
  kernel inline). Concretely: GPU/GUI domains are reachable now
  for prebuilt stacks (they are just more NixOS options, bools, lists, and
  package refs, all of which the value language expresses). What is blocked
  without glue is a *computed value inside the decision layer*, not building a
  program: building a custom program from its own source is the artifacts path
  below, which is first-class and does not need glue. Glue and artifacts are
  separate axes; glue is deferred as far as possible.

### Verified Breakages (Broken Promises, Review of 2026-07-29)

Each item was reproduced against `main` at 95e80f7 and states the promise it
breaks. They are tracked as work in `TODO.md` ("Verified breakages"); listed
here because a ledger that only records wins is a map of a different territory.

Seven of the nine are FIXED (2026-07-29, branch `breakages`), each with the test
that was missing; the entries stay, since the promise each one broke is what the
test now pins. Still open, both by decision rather than by code: the vacuous
gate on an artifact-only engine, and the concept escape.

- FIXED: the singleton `<language>.lips` shorthand in `nix/modulesFromDir.nix`.
  The Nix copy of the rule stays (an output ATTRIBUTE NAME must be known at eval
  time, so asking the binary would mean import-from-derivation), but it is now
  the same rule, marked as a duplicate, and `lipsModules-eval` forces BOTH
  worlds' modules -- forcing only `nixosModules` is how the break survived,
  since all four singleton programs are home-manager ones.
- FIXED: `artifact.nix` is emitted with the module's own `let artifact = { ... }`
  shape, so a sibling reference resolves (`rec` alone would not have: a
  reference renders bare as `artifact.<name>`, so the NAME must be in scope).
- FIXED: `renderModule` and `realizeArtifactFile` both collect artifact
  references from artifact args as well as option values (`artifactArgRefs`).
- FIXED: one quote-aware splitter in `Lips.Kernel.Surface`, used by the pattern
  side and the rule side, so `" ; "` and `" => "` inside a value are content.
- FIXED: `bindSelfExpect` fills by occurrence via `fillName`, so `<self>-core`
  binds in a contract path exactly as it does in a rule.
- FIXED: `Lips.Identity.requireProgram` refuses a program path without the
  `.lips` marker, checked at the one door every verb reads a program through.
- FIXED (this review's simplifications): `Lips.Kernel.Run` exports one
  `Realization` from one pipeline run (it ran three times for three questions,
  and `compile` a fourth time through `check`); the four `*Replace` wrappers are
  test helpers; `kindText`/`kindTable`/`strengthText` live beside their type in
  `Kernel/Decision.hs` and the quoting/punctuation rules in
  `Kernel/Surface.hs`; the CLI uses `directory`/`unix` calls instead of shelling
  out to `mktemp`/`mkdir`/`cp`, cleans its temp dirs up, and no longer swallows
  a staging error.

- **`nix flake check` is red: `lib.modulesFromDir` cannot read a singleton
  program.** `nix/modulesFromDir.nix` splits a filename on `.` and takes
  element 0 as the instance and element 1 as the language, so `board.lips` is
  read as instance `board` in language `lips` and the check dies with
  `Path 'examples/lips/lips.lang' does not exist`. The singleton shorthand
  `<language>.lips` is documented in README and implemented in
  `Lips.Identity`, so this is the Nix copy of that naming rule drifting from
  the Haskell one -- the DRY failure the layout rule exists to prevent. The
  `lipsModules-eval` check therefore fails for four committed examples
  (`board`, `greet`, `habit`, `logscan`), which TODO item 0 recorded as green.

- **A compiled `artifact.nix` cannot reference a sibling artifact.**
  `realizeArtifactFile` emits a plain `{ ... }` attrset, so an artifact arg
  holding `${artifact.<other>}` renders as the undefined variable
  `artifact.<other>`; the module works only because a Nix `let` is recursive.
  This breaks the ledger's own claim that `artifact.nix` holds "the exact same
  derivation the module let-binds", and it breaks exactly the core-plus-wrapper
  shape the "one name grammar" milestone was built for. One-word fix (`rec`),
  no test covers it.

- **A dangling artifact reference inside an artifact ARG reaches the module.**
  `renderModule` collects `valueArtifactNames` from option assignments only, so
  `RDangling` never sees an artifact's own args. A wrapper naming a build
  nothing defines realizes cleanly and dies inside nix with
  `attribute '<name>' missing` -- the raw, remedy-free failure the staged-source
  gate was built to end.

- **A rule rhs may not contain `" ; "`.** `parseRuleBody` splits emits with a
  naive `T.splitOn " ; "`, while the pattern side has a quote-aware
  `splitEmits` for the same job (whose comment names this defect and leaves it
  standing). A shell text like `"cd /x ; ls"` -- ordinary in a
  `writeShellApplication` -- fails to parse, and the message blames an
  "unterminated string". A missing grammar case is a kernel bug (invariant 3).

- DECIDED (2026-07-29): **the deploy path is gate-free by design, and now says
  so.** `compile` takes `--no-contract`, which `lib.modulesFromDir`, `vm-smoke`
  and `artifact-vm` pass: the gate evaluates the realized module with `nix`, and
  a compile inside a nix build has no nix to evaluate with (recursive nix is not
  available). Everything that needs no nix still runs there -- crystallization,
  the open questions, the staged-source check -- so the derivation refuses a
  program its language cannot read. The contract is checked where it lives, in
  the repo, by `lips check`. The point of the flag is that the skip is stated at
  the call site instead of being an unstated consequence of not staging the
  `.expect` file.

- FIXED (2026-07-29): **an artifact-only engine can pin its values, and every
  artifact must instantiate.** An assertion may now name an artifact slot
  (`expect artifact.greet.args.text from cmd.greet.msg`), judged by the kernel
  against the ground base rather than by `nix` -- an arg is a literal there, and a
  builder consumes it, so it is no attribute of the module or of the resulting
  derivation. Separately, the flake check `lipsArtifacts-eval` forces every
  committed artifact's `drvPath`, which instantiates without building, so a
  malformed builder arg set fails in CI instead of at a user's `nix run`. Both
  keep `check` offline and nixpkgs-free (TODO 1e records the rejected homes).

- **The behavioral gate is vacuous where it is needed most (superseded by the
  entry above; kept for the record).** `runExpects`
  returns success on an empty contract, and `uncheckableExpects` forbids an
  assertion on a derivation-valued option, so an artifact-only engine has
  nothing to pin: `greet` and `logscan` report "all 0 checks pass" and
  regeneration is ungated for them (invariant 5 holds only formally). This is
  the same hole TODO 1e names from the artifact side.

- FIXED (2026-07-29): **the source-specification gate closes the concept
  escape.** Reproduced first, which narrowed it: rewording a concept line breaks
  its all-literal pattern and is already reported as unmatched, and adding a line
  is unmatched too -- the silent case is DELETION. `examples/logscan.lips` with
  line 2 removed crystallized cleanly and reported "all 0 checks pass", while the
  built Go source went on filtering by that rule.
  The gate: where a language BAKES source (a committed `<language>/artifacts/`
  tree), the lines that produced `Concept` decisions are part of that source's
  specification, so a concept the mint saw and the program no longer states fails
  loud, naming the line and offering `lips generate`. What the program said at
  mint time is read from the committed `.generation` record, which stores the
  corpus verbatim -- so the check is offline, deterministic and needs no new file
  and no re-mint (`Lips.Generate.Record.recordedProgram`,
  `Lips.Kernel.Lang.Diagnose.retiredConcepts`). A language with no baked source
  is untouched: a concept there is a heading, and a heading must stay freely
  editable. Known gap, recorded rather than papered over: a program the record
  holds no section for (added or renamed after the mint) has nothing to compare
  and is skipped.

- **The concept escape, as found (superseded by the entry above): a mint may
  declare the program decorative.**
  `droppedValues` exempts a hole that reaches a `Concept`, since a mint
  DECLARING decoration is honest. `logscan` shows the cost: 4 of its 5 lines are
  concepts and the whole behavior lives in the baked Go source, so editing
  "keep a line only when every field named on the command line equals the value
  given with it" changes nothing, and `check` still reports success. The
  program stops being the source of truth, which is the thesis (section 1).
  The visibility is there (`diagInert` prints the lines); what is missing is a
  judgment, and it is deliberately unresolved because the kernel may not count
  domain words.

- **`<self>` binds only as a whole segment in a `.expect` path.**
  `bindSelfExpect` compares a segment to `"<self>"` literally instead of using
  the shared `fillName`, so a composed name (`<self>-core`) never binds and the
  assertion silently reads a `null`. The "one name grammar" milestone claims the
  grammar resolves "wherever the grammar admits a name"; the expect layer is the
  one place it does not.

- **A program file's extension is never checked.** `Lips.Identity` derives the
  language from the second-to-last extension, so `x.backup.txt` is happily read
  as language `backup` and `examples/backup/backup.lang` as a program in
  language `backup`. The `.lips` marker is documented as the constant handle;
  refusing anything else is a one-line, fail-loud check.

### Missing

- **Live host deployment.** The VM smoke test proves the module class; wiring
  one realized module into `~/nixos` on `wolf` is now reduced to "import one
  file" and remains optional symbolism.
- **Artifacts: deferred pieces.** The core landed (see Done), and a program value
  now reaches inside baked source through a *fill* (see Done: "Source fills").
  Still open: a REPEATING structure inside source (one code block per route, per
  mount) has no hole form, since a fill replaces a marker and cannot repeat a
  block, so a per-item body still needs regeneration; dependency-fetching builders (a
  `cargoHash`/`vendorHash` over fetched crates) move the fetch to generate and
  are untried (the proven path is no-dependency source, e.g. Go stdlib with
  `vendorHash = null`); container/registry push stays Heile-Welt coping. A
  build needing *arbitrary* Nix (custom overlays, hand-built derivation graphs)
  remains glue, deferred.
- **Run axis (DONE, kept here for its design record; the summary entry is in
  Done above). Running is not a lips verb; it is stock `nix` over the
  compiled dir.** `lips compile [--out <dir>] <program>` is the deterministic
  compiler (verify the committed contract -> crystallize -> realize -> a
  DIRECTORY, default `<program without .lips>/`). It writes `default.nix` (the
  module, for `imports`/deploy), any staged `artifacts/`, a `flake.nix` (the
  addressable entry), and, when the program declares artifacts, an
  `artifact.nix` (the buildable derivations, extracted from the SAME ground
  base as the module by `realizeArtifactFile`, so a compiled flake addresses
  exactly the derivations the module `let`-binds). `default.nix` stays
  byte-identical to before (the module render path is untouched), so the
  `vm-smoke`/`artifact-vm` VM checks, which import it directly, are unaffected.
  The behavioral gate runs first and writes nothing on a violation. After a
  successful compile it PRINTS the exact `nix` commands the program's shape
  supports (deduce-or-fail: no impossible command is ever shown). The `run`
  command, `runVm`, `bootVm`, `vmExpr`, and home-manager `runEvalOnly` are
  deleted -- net negative code, the VM-boot logic now lives as data in the
  emitted flake.
  The four rungs are stock `nix` over the dir (commands use `path:<dir>#…`
  because the dir is derived/gitignored and `path:` copies it verbatim, past
  flake's git rules): `nix run …#artifact.<name>` (exec: the artifact binary,
  bare -- no init, so no service/env), `nix shell …#artifact.<name>` (the
  binary on PATH), and `nix run …#vm` (a throwaway QEMU boot of the whole
  system, real systemd, all services). `nix build …#vm` produces the boot
  script without booting -- building needs no KVM, so it is the cheap "does the
  whole system build" check. The fourth rung is `nix develop <dir>`
  (`devShells.default`, so it needs no attribute): a `pkgs.mkShell` holding the
  packages the program adds to the system PATH, plus its artifacts. Like `vm`
  it is DERIVED from the module, never declared -- the program says nothing
  about a shell, so the rung is always present. Its content comes from
  subtracting a bare NixOS eval's `environment.systemPackages` (which already
  carries the whole base system: systemd, grub, coreutils) from the program's
  own list; both evals carry the same `stateVersion` stub so the subtraction
  stays symmetric. Proven live: `ledger.backup` yields `restic-ledger` (the
  service's own wrapper, repo and credentials baked in) and `hello.http` yields
  `helloserver`, so the shell is a useful witness for a plain system module
  too, with no machine booted. home-manager gets no shell rung for the same
  reason it gets no `vm`: `compile` never evaluates a home config. A `container` (systemd-nspawn) rung was considered
  and REJECTED: running a real init is inherently privileged (root, machined/
  nsresourced, networking), so a light rootless "run the system" does not exist;
  a hand-rolled nspawn was fragile and bought nothing `vm` does not, and the
  robust path (`extra-container`) is a dependency needing sudo. Lightweight
  witnessing is the artifact rungs' job; a portable OCI image (nginx, a Go
  server) is a future PACKAGE-axis output built with `dockerTools`, a
  distribution artifact, not a run rung.
  Clash-proof by construction: the rung app `vm` is top-level while artifacts
  live under `artifact.<name>`, so a domain artifact named `vm` can never
  collide. Nixpkgs is resolved ambiently (`flake:nixpkgs`
  registry), so compile pins/fetches nothing and stays bit-identical -- the
  same Heile-Welt softness the old `<nixpkgs>` VM boot carried; the world is
  resolved at `nix run` time. `home-manager` (no machine) emits the module and
  an import hint, no vm. Full design in
  `docs/superpowers/specs/2026-07-24-run-axis-design.md`.
  Out of scope, named as separate future axes: the PACKAGE axis (Docker image,
  ISO, standalone binary -- an artifact always needs a consumer, so "build to
  nowhere" is a non-thing; each distribution format is its own realize output
  shape) and the DEPLOY axis (import `default.nix` into `~/nixos` on `wolf`,
  persistent and privileged -- the headline missing proof).
- **Direction file (DONE, kept here for its design record).** Optional owner taste for the mint: per-language
  `<language>.direction`, plain text, appended to the minting prompt when
  present. Sharp boundary: the program states what must be true; direction
  states what to prefer (mechanism taste: restic vs rsync, no docker, secrets
  via env files). Direction never carries obligations -- anything that must
  hold belongs in the program (a decision) or `.expect` (an assertion); the
  appended guard states this rule to the model ("PREFERENCE, not requirement;
  never override a value the program states"). Pinned for free: direction
  enters the system prompt, which the `.generation` record embeds verbatim, so
  it enters `genId`. `compile`/`run`/`check` never see it. Also softens mechanism
  churn across regenerations (same taste, stable mechanisms). Pure composition
  in `Minting.promptWithDirection`; `generate` reads `<language>.direction` and
  passes the composed prompt to both `callPi` and `record`; `Record` unchanged.
  A repo-wide direction file was rejected (ambiguous search root, comes from
  nowhere); ambient `AGENTS.md` is deliberately excluded (the mint is hermetic
  via `pi -nc`), so this per-language file is the sole owner-taste channel.
- **Gap report (`<program>.gap`).** When generate refuses because physics is
  missing (deduce-or-fail on an inexpressible need), the refusal must be a
  shippable artifact, not a mood: refused lines, the missing capability
  (which extension point: value form, emission type, realization target), a
  minimal reproducing program, model + prompt fingerprint. A compiler bug
  report for the kernel, machine-readable, pinned. Cheap; do soon.
- **Kernel modules (shared verified capabilities).** Successor of the
  vocabulary milestone under a better name: loadable units OF the guarantee
  regime, not plugins around it. A module extends closed grammars at declared
  algebraic extension points (new value form like `${secret.<name>}`, new
  emission type, new realization target), never hooks internals; ships its
  own conformance tests + properties in suite format, and loading is gated on
  them (untested = refused, loud); orthogonality by construction (two modules
  claiming one extension point = conflict); versioned + content-hashed, and a
  `.lang` declares the capabilities it uses, keeping the trust chain
  (program -> engine -> modules -> kernel core) mechanically checkable. Trust
  gradient: kernel core (tiny, universal) -> modules (domain-general, same
  rigor) -> engines (per-problem, data) -> glue (marked low-rigor pocket).
  Permanently forbidden: per-problem code and unchecked surface; a classic
  plugin API is refused on principle (largest possible interface; would
  reopen the hole the value grammar closed and let workarounds bypass kernel
  growth). In-tree Haskell modules behind the one suite until a second
  consumer exists (YAGNI on loadability).
- **Grammar completeness (complete by construction).** The kernel must refuse a
  program only for deduce-or-fail, a computation need (-> glue), or reality
  (Heile-Welt) -- never for a missing grammar case. Each closed grammar is
  designed complete over its domain. Order: value completeness, then template
  completeness, then glue. First driver: the nginx gap report. Full design in
  `docs/superpowers/plans/2026-07-20-completeness-plan.md`.
  - Value completeness: DONE (8ffd70d). `Value` now covers the Nix value
    algebra minus computation -- string, list, bool, int, float, path, null --
    and a typed hole `<value:int|bool|float|path>` (and `<value.N:...>`) fills
    a non-string option from a program token, coerced and fail-loud, injection
    still closed. Deferred: `VAttr` literal (nested attrsets are expressible as
    deeper option paths). Unblocks the int-typed port. Extended (da84ab3): a
    `${pkgs.<path>}`/`${artifact.<name>}` reference is now a first-class value
    (`VRef`), not only a string piece, so a list of derivations (an
    `environment.systemPackages`, a `writeShellApplication` `runtimeInputs`) is
    expressible as `[ ${pkgs.curl} ${artifact.<name>} ]`. Persistence and
    realization diverge here for the first time: `renderValue` keeps the
    canonical `${...}` form (so `.lang` round-trips through `parseValue`), while
    a new `renderRealized` emits the bare `pkgs.curl`/`artifact.weather` the Nix
    module needs (a list holds derivations, not interpolations). `realize`'s
    `artifactRefs` became quote-aware to catch a bare `artifact.<name>` list
    element while still ignoring the literal token inside a string.
  - Template completeness: DONE for the enumerated capture forms. The tokenizer
    is quote-aware (d4c4468): a `"..."` span is one token whose surface is its
    inner text (quotes dropped, spaces kept), so a normal hole captures a quoted
    value, and a template `"<body>"` reads as a capturing hole. The multi-token
    hole `<name.words>` closes the second form: it binds one or more tokens
    anywhere in the template, ending where the template's next literal matches,
    so an unquoted several-word value needs no quotes (the end-of-template case
    generalizes the former `<name.tail>`, its only spelling now). Bullets need no
    block machinery: `-` is just a literal token, and each item stays a distinct
    decision by putting its own value (the path) in the subject. Deferred, with
    the reason: true parent-child block aggregation (a decision that owns a
    list), because subject-keyed items already carry every bulleted list the
    corpus states, and `Append` aggregates them.
  - Glue: TODO. The one documented incompleteness (computation).
- **Language migration.** When `.lang` regenerates to a different shape, there
  is no diff or migration path for existing programs.
- **Multi-language composition.** The sketch composes three languages in one
  decision base; the prototype runs one engine. Composing several
  engines/languages in one Solution is unbuilt. (Dual of language reuse above:
  many languages in one Solution, vs many instances of one language.)
- **Guarantee lifecycle.** The walk-through's assumption `OPEN -> GUARANTEED`
  flow and the "verify a vocabulary once, inherit cheaply" rigor allocation
  have no code.
- **Heile-Welt coping.** The kernel's promise to supply stable strategies for
  what reality cannot guarantee has no mechanism yet. The determinism boundary
  is at the *config* line: the kernel deterministically emits correct NixOS
  configuration, but cannot guarantee the world cooperates (a GPU is present,
  the driver loads, a display is attached). Such reality mismatches surface at
  `nixos-rebuild`/runtime, not as a kernel property, and headless VM checks
  cannot assert them (no GPU/display in CI), leaving the behavioral corpus
  thinner for those domains.
- **`lips dev`.** Convenience wrapper (run, ask before generating). Minor.

### Doctrine (settled by discussion, no code implied)

- **The mint prompt stays domain-blind; the program is the only truth.**
  `Minting.systemPrompt` is System-tier: it carries general mint doctrine
  (act-once, holes for every value, closed value grammar, orthogonality,
  deduce-or-fail), never per-problem knowledge. A domain convention baked into
  it (an `HTTP TEXT ROUTES` block hardcoding nginx status/content-type
  defaults) was caught as overfitting and a truth-outside-the-program leak, and
  reverted. Per-problem realization knowledge belongs in the minted engine
  (`.lang`) for that program, or -- if it recurs -- in a kernel module with its
  own tests, never in the prompt. Since value + template completeness landed,
  the model can express such realizations (e.g. nginx `locations.<p>.return`)
  from the program itself.
- **Three explicit instruction channels, none ambient.** AGENTS.md instructs
  agents working on the repo; `Minting.systemPrompt` instructs the mint
  (mint-relevant truths promoted from AGENTS.md: act-once so every value
  becomes a hole, engine is pure data with no code escape, refusal beats
  invention, no value-grammar workarounds); `.direction` files carry owner
  taste per program. The mint is hermetic: `callPi` passes `-nc` because pi
  otherwise injects ambient AGENTS.md/CLAUDE.md (global + walking up from
  cwd) -- unpinned inputs that entered neither the record nor `genId` (bug,
  fixed 7a1b313).
- **Completeness by construction.** Closed grammars are made complete over
  their domains, not grown feature by feature: the value grammar targets the
  whole Nix value algebra minus computation, the template grammar a small
  complete capture algebra. Computation is the single deliberate hole, routed
  to glue. A missing grammar case is a kernel bug, not an acceptable refusal.
- **Expressiveness gaps route through three doors, never a plugin API.**
  Per-problem computation -> marked glue (in the Solution, visible blast
  radius); mechanism reach -> nixpkgs/flakes (an engine emitting the options
  of an existing module IS the plugin, maintained elsewhere); substrate
  expressiveness -> kernel physics (tested, permanent, conformance-suited),
  optionally packaged as a kernel module.
- **Cross-repo escalation (using lips outside the lips repo).** generate
  refuses -> gap report travels upstream -> kernel grows under the suite ->
  downstream bumps its flake input and regenerates (committed `.expect`
  gates). Interim unblocks, in dignity order: restate within current physics
  (backup.loose gained its credentials line this way); hand-write the missing
  piece as an ordinary NixOS module BESIDE the lips one (the coexistence
  defense used as intended); local kernel-module overlay under the same
  rigor gate.
- **Forking is safe by design.** lips is defined by the calculus + conformance
  suite, not the repo; the reference implementation is non-privileged. A fork
  that keeps the suite green IS lips (`inputs.lips.url = github:you/lips`);
  fork-as-overlay (patch + tests, rebased, upstreamed, then deleted) is the
  sanctioned fast path; only editing the suite itself mints a dialect.

### Shortest Summary

The deterministic spine, the language-crystallization loop, and whole-engine
synthesis are real and tested: lips now mints an engine for an unseen domain
and absorbs edits offline. A **live NixOS deployment** is the missing proof
that it survives a real system. Everything else is hardening or breadth.

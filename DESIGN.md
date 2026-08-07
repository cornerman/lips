# lips Design

Status: approved concept design. lips is founded on a decision calculus.
Evidence base: the surveys in `docs/superpowers/survey/` (cited as
Survey A through G).

## Terminology

- **Decision**: the atom of the whole system. A tuple of subject, assertion,
  scope, strength, provenance, rationale.
- **Decision base**: an unordered set of decisions with defined merge
  semantics. Every artifact in lips is one.
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
  document's older sections say Solution and code says lips. `AGENTS.md`
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

lips's structural commitment: **zero LLM inference between a Solution and
its realized system.** AI participates massively, but only at authoring time,
and only by producing decision bases that are checkable artifacts. Survey D
confirms the position is unoccupied: every 2023-2026 spec-driven tool (Spec
Kit, Kiro, Tessl, BMad, OpenAI's "spec is the new code") places an LLM
exactly where lips places a compiler; Tessl regenerates different code
from an unchanged spec.

The deliverable form of lips is a rigorous specification of the kernel
calculus plus a conformance suite, not a blessed runtime.

## Position in the Field

By 2026 the thesis above is measured rather than argued. Sonar's 2026 survey
of 1,100+ developers finds 96 percent of developers not fully trusting the
accuracy of AI-generated code while only 48 percent verify before committing,
with AI writing some 42 percent of committed code; 61 percent report code that
"looks correct but isn't reliable", and 38 percent find reviewing it costlier
than reviewing human code, the burden Werner Vogels named *verification debt*.
Time spent on toil did not fall; it moved from writing to reviewing (Survey G,
§1). The binding constraint is review capacity per unit of derived artifact.

Three schools answer that constraint, and they differ in where they place
trust (Survey G, §2):

1. **Automate the review** (Anthropic's Code Review, SonarQube AI Code
   Assurance, CodeQL): keep the artifact large, raise the throughput of
   looking at it.
2. **Prove the output** (Axiom Math, 200 million dollars at a 1.6 billion
   valuation in March 2026, emitting Lean proofs): make the artifact
   machine-checkable against a formal statement, and inherit the problem of
   writing and trusting that statement.
3. **Shrink the reviewed artifact** (spec-driven development in Böckeler's
   three levels: spec-first, spec-anchored, spec-as-source): review intent,
   derive mechanism.

lips is in the third school and, per Surveys D, E and G, its only
deterministic member. The move that separates it is not writing specs; it is
that the model's output is a **compiler**, not code. An engine is reviewed
once and amortized over every later compile of every program in its language,
whereas every other tool in this school re-guesses the artifact on each run.

The category's strongest published objection also predates lips, and lips is
built as the answer to it. Böckeler observes that spec-as-source is
model-driven development returning, and that MDD died because hand-built
code generators cost more than they returned; LLMs remove that cost but pay in
non-determinism, so the wave risks "the downsides of both MDD and LLMs:
inflexibility *and* non-determinism". lips takes neither horn: it keeps MDD's
parseable DSL, real compiler, and author tooling (the LSP, generated per
language with no configuration), and it makes the generator disposable, a page
of pure data minted per problem and re-minted whenever the domain moves. What
this buys is contingent on economics rather than physics: it holds only while
a mint stays cheap and a language converges, which is why the mint-decay curve
is an open question (§11).

The premise of that objection needs one correction, and it moves the ground
under lips from analogy to evidence (Survey J). Model-driven engineering did
not die, it narrowed. Hutchinson, Whittle and Rouncefield, surveying 450
practitioners and interviewing 22 more, report that developers "rarely use it
to generate whole systems; rather, they apply it to develop key parts of a
system often using domain-specific modeling languages developed specifically
for the purpose", and that "adoption largely depends on social and
organizational factors" (IEEE Software, 2014). Petre's fifty-engineer study
found zero of fifty using UML the way its promoters described (ICSE 2013).
What failed was one universal notation with a hand-editable middle layer and a
per-domain generator somebody had to maintain; what works is exactly lips's
shape, partial generation through a purpose-built language. The mint removes
the cost that kept that shape rare, and the organizational finding is the part
no technical property answers (§13, "Limits of scale").

This position does not decay as models improve. The claim is reproducibility,
not accuracy: a perfect model that emits a different valid implementation on
each run still destroys diffs, bisection, review, and audit. Determinism is a
property no model quality supplies.

## 2. The Decision Calculus

Lisp's founding move was: code is data, and eval maps data to values.
lips's founding move is: **intent is data, and realize maps decisions to
systems.** Lisp stayed "just code" because its atom is a computational form.
lips's atom is an asserted meaning:

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

**The snippet-engine objection, and the answer.** The critique: a minted
engine is patterns with holes mapping matched lines to `path = value`
assignments, so lips is a glorified snippet engine. The resemblance is real
and conceded: a rule's right-hand side is a closed value grammar,
template-shaped by construction, and a one-program, never-edited language
would earn the label. The analogy breaks on everything that happens around
the templates. A snippet has no notion of being wrong: paste one with a bad
value and the output is silently bad, while the kernel has four outcomes and
three are refusals (parse rejection, open question, conflict with both
provenances). Ownership is inverted: with snippets you own and hand-edit the
output forever; here the output is disposable and the program re-realizes
bit-identically without a model. Snippets do not compose; decision bases
merge by strength with collision detection and total provenance. Snippets
have no contract; an engine is admitted only if it compiles every program
and its tests hold, and regeneration is gated on the accumulated corpus.
And closure under reasonable edits is a checked property (Section 5), not
whatever happens to have been typed. The compact form: by this argument a
compiler is a glorified macro processor, since both turn short text into
long text; the claim ignores everything between the two texts. The
templates are the least interesting part; the point is the kernel that
decides when they may not fire.

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

**Correctness, by theory.** Each kernel mechanism instantiates a body of
theory that formalized it independently, decades before lips (Survey F):
merge by strength is belief merging (Konieczny and Pino Pérez's IC
postulates name the exact properties `resolve` must have), refinement to a
fixpoint is term rewriting (critical pairs decide overlap, and
`Engine.Overlap` computes them at the `generate` gate, so an admitted
engine's orthogonality is a checked theorem rather than a reviewer's
impression), conflict reporting is model-based diagnosis (Reiter 1987), and
oblige/forbid/allow is deontic logic. The sharpest published attack on the
combination, that rewriting plus priorities has no automatically
well-defined semantics (Baeten/Bergstra/Klop 1987), is answered by the
phase-separation invariant above. The correctness claim is therefore not
"we tested it": every mechanism either coincides with a result the
literature proved, or the deviation is recorded in §11 with the reason.
The remaining formal debts are recorded the same way: termination of
refinement is enforced by a step budget (fail fast), not proved, and the
IC-postulate audit is open (`TODO.md`, survey-F section). A
critique-resistant calculus is one whose gaps are named, not one that
claims none.

**Completeness, by definition.** For any decision base the kernel produces
exactly one of three outcomes: a settled base (every subject has one
winner), a conflict (equal strength, incompatible assertions, both
provenances named), or an open question (an unmet demand). Deduce-or-fail
removes the fourth, silent outcome by construction. Completeness does not
mean the kernel can say everything; it means every gap falls in exactly
one of two places. A sentence the closed grammar cannot hold is a kernel
bug, and the grammar grows as physics to admit it; a fact about the world
the kernel does not know is the engine's job, held as minted, disposable
data. The dividing test is stated in AGENTS.md and repeated here because
it is the completeness criterion: a program, or a language, that nobody
foresaw works without a kernel change.

**Correctness, in practice.** NixOS is the existence proof that prioritized
merge carries a production system for twenty years at distribution scale.
What decayed in every shipped strength calculus (CSS specificity plus
`!important`, Drools `salience`, XACML combining algorithms) was an
authored priority number: any author could raise the integer at any site
until their value won, so the number stopped encoding authority and became
a debugging tool. lips makes that decay unrepresentable rather than
discouraged: strength is structural (system default < engine default <
program) and no surface exists for a program or an engine to write a
number. Total provenance (item 3) closes the other practical hole the
override critics price in, as argued above.

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
ossifies. lips inverts this. **The Solution is the stable artifact; the
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
unreliable packets; transactions build atomicity on crashing disks; lips
generalizes this into a design law.

Consequently **workarounds are unrepresentable in a Solution.** There is
nothing to work around in a world that is whole; any pressure toward a
workaround is, structurally, a feature request against the engine. Survey B
ranks escape-hatch decay through accumulated workarounds as the number-one
killer of every prior intent-level attempt (CASE, MDA, Helm, low-code);
lips makes that decay impossible at the level where it kills and routes
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
derivations plus module wiring. lips inherits universality from Nix
instead of building it, which is what makes "fully expressive from day one"
hold at the realization layer, as marked glue makes it hold at the language
layer. Completeness twice, both times deterministic. The NixOS
module system is the architecture's twenty-year production precedent (typed,
mergeable, per-domain vocabulary over one general substrate, zero LLM;
Survey D verified its mechanics firsthand), and terranix proves the
machinery retargets beyond NixOS.

### Why the Substrate Does Not Move

Three layers are distinct, and conflating them is what makes "is lips only for
Nix people?" look like an open question when it is not.

- **Substrate**: Nix itself (evaluator, module system, hermetic build).
  Permanent.
- **World**: the option vocabulary a rule names (nixos, home-manager, kubenix,
  terranix). Open axis, no kernel change, see the scaling law below.
- **Surface**: what the author sees and must know. For a non-NixOS world it is
  that world's own artifact (kubenix YAML for `kubectl`, `config.tf.json` for
  `tofu`), so Nix can run underneath an author who never learns it.

The substrate is fixed for a reason stronger than convenience. A NixOS
configuration is an unordered set of `path = value` assignments merged by path
with priorities, which is the decision calculus in different words. Realizing
is therefore close to a homomorphism: merge in the calculus, emit, and the
target composes the result the same way. A substrate composing differently
(ordered steps, last-write-wins, no priorities) would need an adapter that
knows how *that* target composes, and the only place such knowledge could live
is the kernel, which is precisely what the kernel must never learn. Nix is the
semantic mirror of the calculus, so leaving it costs kernel purity, not just
effort.

The mirror is currently used in shape and not in mechanism: nothing in
`kernel/src` emits `mkDefault` or `mkForce`, so lips resolves strength itself
and emits already-merged assignments. Section 11 records the consequence as an
open question, since emitting priorities is what would let a lips module merge
with a hand-written one rather than sit beside it.

What no substrate change would buy: convergent targets (a live API that must be
polled and reconciled) stay out of reach by design, because lips renders
desired state and hands applying to the tool that owns it, exactly as terranix
does; and application source stays limited by the absence of a vocabulary, not
by Nix. Reconsidering the substrate becomes correct only on a falsifiable
trigger: a schema-bearing world whose Nix bridge would cost more than emitting
its format directly (unlikely, since rendering YAML or JSON from Nix is
trivial), authors who must compile where `nix` cannot run (answerable with a
static Nix before it is answerable with a second backend), or Nix evaluation
measured as the bottleneck at real program counts. None is close.

## The Vocabulary Scaling Law

What makes a fourteen-line engine produce a working system is not the kernel's
cleverness but the vocabulary underneath it. When an engine emits
`services.restic.backups.<name>.paths`, that name's meaning, type and behavior
are defined and tested by nixpkgs; the mint confirms the name through the
schema tool instead of inventing it, and the engine only selects and fills.
Section 13 already states this in the small ("a hole is grounded from outside
or by plurality"). Stated in the large it is a scaling law (Survey G, §4):

> lips reaches exactly as far as some external, named, typed vocabulary of
> mechanism reaches.

Everything the corpus does well sits inside such a vocabulary; everything it
does poorly sits outside one. Two consequences, both strategic:

- **Breadth comes from new worlds, not new physics.** home-manager, kubenix
  and terranix landed with no kernel change, because each is one more
  vocabulary the same grammar can name. Every schema-bearing world is a
  candidate on those terms, and the kernel must learn none of them.
- **Application code is reachable only where a framework has already turned
  itself into configuration.** Where it has not, no vocabulary grounds the
  baked source and the entire correctness burden falls on claims, which is a
  research bet and is labelled one below (§13, "Limits of scale").

The law is cheaply falsifiable: mint into a schema-bearing world that is not
infrastructure. Zero kernel changes confirms the axis is open; any kernel
change the attempt demands measures how much of nixpkgs's shape the kernel
silently assumes.

## The Logic Axis: A Forced Paradigm

The session that settled this, with the rejected alternatives and the reasoning
behind each, is recorded in
`docs/superpowers/decisions/2026-08-02-the-logic-axis.md`; the evidence is in
Surveys G through K.

Configuration is grounded because nixpkgs vouches for every name a rule emits.
Program logic has no such vocabulary, so it escapes today into baked source: a
Go file the mint writes once, complete but grounded by nothing, traceable to no
program line, and demonstrably unstable across mints (see "A re-mint rewrites
behavior the program never mentions", §13). This section records the direction
chosen for that axis, why it was forced rather than preferred, and what stays
open.

The physics is now partly built. The falsifier ran and passed
(`docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`: 24 lines of
clauses for 70 of Go, every clause traceable, claims in 121 ms with no build),
and the plan it earned is `docs/superpowers/plans/2026-08-04-logic-axis-plan.md`.
Landed: the closed clause grammar (`Kernel/Sexp.hs`), a clause as a rule's rhs
(`VSexp`), the vocabulary and contracts as data (`assets/runtime/scheme/`), the
subset gate (`Kernel/Clause/Gate.hs`), clause assembly with provenance walked
back to program lines (`Realize.realizeClauses`), and runtime covering
(`Kernel/Clause/Catalogue.hs`). Not yet built: the compiled site, offline clause
claims, the mint, and several sites per program.

**What was rejected first, because the reason generalizes.** The tempting move
is to let the kernel own a grammar for computation, a small lambda or term
calculus complete by construction. Nix refutes it by example: Nix can build
anything and never understands a line of C++, because what it owns is the
derivation interface (a name, typed inputs, a builder reference, an output
hash) while bodies stay opaque. A kernel that owns computation pays for a
programming language the substrate already proves unnecessary, and the project
has exactly one word for that (see AGENTS.md on the complexity daemon).

**The shape that remains.** A unit of logic is a pure, first-order definition
given by NON-OVERLAPPING PATTERN CLAUSES over NAMED EXTERNAL PRIMITIVES, with
general recursion, no effects and no higher-order values. Every part is forced
by a commitment already made:

- Clauses keyed by a name, unioned across decisions, because that IS the
  decision base (Survey H finds the same algebra in Rego's rule composition,
  DMN's hit policies and Catala's prioritized defaults; a candidate that
  composes by DAG or by textual order, like dbt, fails for that reason alone).
- Non-overlapping, because `Refine.hs` already makes it so: "at most one rule
  ever fires per decision, rewriting is a function, hence confluent for free".
  Static orthogonality is what replaces Prolog's clause order and cut, so the
  paradigm is logic programming's representation without its search.
- Pure and first-order, because that is what makes a clause testable alone in
  the sandbox, renderable into any host, and readable at review.
- Named primitives, because the kernel must not define computation; a leaf is
  grounded exactly as `${pkgs.<path>}` is.
- General recursion, because completeness is non-negotiable, and it is
  inherited (Herbrand-Godel recursion equations) rather than built.

Constrained first-order functional programming and deterministic Horn clauses
are the same object here, argued from two traditions (Survey K).

**Execution is serialization, not interpretation, and not translation.** A
clause is emitted as a safe subset of an existing Lisp, so the structure lips
checks and the text a runtime runs are the same object: emitting is a bijection,
pinned by a round-trip test (`parse . render = id`), and the host's own compiler
supplies speed and typing. No runtime of lips's own ships. A kernel interpreter
survives only as an offline test oracle, which is what makes per-clause claims
cheap.

**Why not a printer per host, settled.** lips owns printers already (`renderValue`
for Nix, `renderSexp` for the clause grammar), so the question is never printer or
no printer. It is serializer or translator. A serializer maps a structure onto a
syntax that already is that structure, so no choice is made and the round trip
proves it. A translator into Go or Rust must choose: a match or an if-chain, what
is owned, which name each temporary gets. Those choices are semantics that appear
in no clause the gate checked, and no round trip can recover them, since reading
the output back would need a parser for the host language.

The cost that decides it is not maintenance. Printing into a typed host drags
types into the clause language, so a contract would have to carry a real
signature (what WIT exists for) instead of an arity and a sentence. That is a new
axis, not a printer.

And what a printer would buy is already reachable. A host's LIBRARIES arrive as a
contract whose adapter is a package that host built, named and never read, which
is the derivation-interface lesson one level up and costs one directory under
`assets/runtime/`. Host PERFORMANCE matters for nothing in the corpus and would
be measured before it counted. Host FAMILIARITY is a social argument and the one
honest item on the list. So the trade is a permanent semantic gap against a
four-line adapter declaration.

The falsifiable trigger to reopen it, stated so nobody reopens it on taste: a
program whose LOGIC must run inside a host that can neither host a Lisp nor be
reached by name. Kawa covers the JVM, Hoot covers the browser through Wasm,
Chicken and Gambit cover native binaries, so the real candidates are eBPF, a GPU
shader, an EVM contract, a spreadsheet cell. If one arrives, the safety net that
would make a translator admissible is differential claim checking: run every
claim on every site. Not a proof of equivalence, but it holds the translator to
the program's own stated observables, and it catches adapter drift a proof would
not.

Two obligations come with emitting, both from Survey K, and both fall on lips
rather than on the host: exhaustiveness must be checked in the kernel, since
among Go, Rust, Haskell, JavaScript and Python only Rust refuses a
non-exhaustive match (GHC's warning is off by default, Go has no check at all);
and stratification must be a mint-time gate over the clause set if negation is
ever admitted, distinct from the runtime step budget that already turns a
runaway rewrite into a loud `Nonterminating` error. General recursion forfeits
decidable termination on purpose, so that budget is the permanent answer rather
than a placeholder.

**What the axis buys.** Per-line ownership of behavior, so provenance reaches
into logic and the `Derived [parent] rule` chain becomes a proof tree naming
program lines rather than generated code, which is the one documented
model-driven failure that no AI capability touches (Survey J). Per-clause tests
that run offline with no VM. A small blast radius on re-mint. The honest gap,
recorded rather than argued away: no controlled study shows that such
explanations measurably help humans, and the proof tree only stays the review
artifact while `.expect` remains the acceptance gate, since a human editing
rendered output puts the CASE-tool graveyard back in play.

**What it does not buy.** Nothing external vouches for a rule you invented five
minutes ago; contracts do, and only contracts. The guarantee on this axis is
therefore weaker than on the configuration axis, by construction rather than by
omission.

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
- **How do runtime facts enter (open predicates)?** The logic axis needs one
  concept the calculus lacks: a predicate whose facts arrive when the program
  RUNS, not when it compiles. That boundary is Datalog's EDB/IDB split read
  sideways in time, and the incremental-view-maintenance line (DDlog,
  differential dataflow) states the soundness condition lips would inherit: a
  clause reading an open predicate must otherwise be pure, or recomputation is
  unsound (Survey K). This is the only genuinely new physics the axis needs,
  which is why it is worth stating before anything is built.
- **Where do primitive signatures come from?** The artifact-axis analogue of
  choosing nixpkgs. Candidates weighed in Survey K: a host language's own
  package index (rejected, since it silently picks the render target), protobuf
  or GraphQL (shape without effects), and WIT, the WebAssembly Component Model
  interface language, which "defines only contracts between components" and so
  names behavior without naming an implementation language. Undecided.
- **The mint-decay curve is unmeasured**: the whole economic case (see
  "Position in the field") rests on the ratio of edits that merely `compile` to
  edits that need a fresh mint, falling over time on one real, growing program.
  Decay toward zero means the thesis scales and the rest is engineering; a
  plateau means the language is not converging, which no kernel work repairs.
  Nothing in the repo records it, and recording it is cheap: dogfood one real
  system and count.
- **Brownfield adoption has no path**: every intent-level system in Survey B
  died on adoption into an existing codebase, and lips offers only coexistence
  (a hand-written module beside a lips one, §13 doctrine). That defense is
  real and may suffice, since Nix modules compose by construction, but it has
  never been exercised on a system of any size. The priority question below is
  its first concrete lever.
- **Should a realized assignment carry a priority?** lips resolves strength in
  the calculus and emits plain `path = value`, so a lips module and a
  hand-written module asserting the same path collide at eval instead of
  merging. Emitting `mkDefault` (or a priority derived from the decision's
  strength) would make coexistence a defined merge with a stated winner, which
  is the cheapest brownfield lever available and the first real use of the
  calculus-to-module-system correspondence (§10). Against it: a second place
  where strength is interpreted, and a realized module that no longer reads as
  the plain truth of the program. Undecided; no committed example yet needs a
  lips path overridden from outside.
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

- **A rule reads one part, not the value.** "Does this rule read the matched
  assertion?" was one yes/no answer for the whole rule, so a rule reading
  `<value.1>` of a value built from two holes counted as carrying both and the
  second word was dropped with every gate green. A several-part value stores one
  quoted part per hole, so part N is hole N by construction: `Engine.Value`
  now answers `assertionUses` (whole, by position, or the tail) instead of a
  boolean, and `Engine.Reach` asks whether the rule reads the part the word
  sits in. Two siblings fell out of the same map, refused by a new gate
  (`Engine.Parts`, wired as `partsExist`): an out-of-range `<value.N>`, loud at
  realize but only once a program states such a line, and a `<value.tail>` over
  a several-part value, which splits each part into words again and is silently
  wrong every time. A ONE-part value is left alone, since its word count is the
  program's, not the pattern's -- reading a word of it by position is the honest
  way to take a many-word value apart. Proven against the real binary by
  mutating `examples/backup`: both shapes refused, the committed engine clean.
- **A key hole stands for a whole subject, so a nested family is as long as the
  subjects it builds.** `<k:key>` carries the subject of the block head, several
  segments, but the two static gates expanded it to a one-segment placeholder,
  so a pattern emitting `<k:key>.target` under a head emitting `button.<n:index>`
  had the TWO-segment family `<k>.target`. Subject comparison is length-sensitive
  (`subjectsUnify`), which made the mint gate refuse `demand button.<n>.target` --
  the only demand an author can state, and one the pattern answers -- while the
  reach gate found no rule at all for a word under a keyed block, so a rule
  replacing that word with a constant passed. Two of five `examples/website`
  mints died on the first half, which by invariant 4 makes it physics rather
  than a prompt problem. `Lang.Nest.scopedBindings` now expands a key hole to the
  head's own emitted subject, recursively and per parent, and both
  `Engine.Answerable` and `Engine.Landing` (hence `Engine.Reach` and
  `Engine.Typing`) read their bindings from it. Two limits stated rather than
  guessed: a pattern nested under itself has one family per depth, so only the
  shallowest is named, and a key that can reach no head yields no family, since
  no line can scope to such a pattern anyway.
- **The logic axis, physics half: behaviour is clauses, and a clause is a
  decision.** The falsifier ran first and passed
  (`docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`): 24 lines
  of clauses for 70 of Go, 8 of 8 traceable against roughly 15 of 76, three
  inventions turned into demands, one vanished for want of a knob to invent, and
  one reversed to the faithful reading of the author's own word "every". The
  plan it earned is `docs/superpowers/plans/2026-08-04-logic-axis-plan.md`; six of
  its ten tasks are landed. Emitting is serialization, not translation: `SExp`
  round-trips (`parse . render = id`), so the object the gate checks is the object
  a runtime runs. The kernel holds no word of any language: the defining word,
  the binders, the base procedures and the contracts all arrive from
  `assets/runtime/scheme/`, pinned by a test that hands the gate a vocabulary
  saying `defn` and watches it accept what the shipped one refuses. Capabilities
  bind by NAME at link time, so nothing higher-order is needed, one core serves
  several runtimes, and a claim links an in-memory adapter to run a whole program
  offline (8 claims, 121 ms, no build, no VM). Runtime choice is arithmetic over
  data (`coveringRuntime`), never a model's decision, and it fails rather than
  guesses in both directions. All ten tasks landed; several sites per program is
  shape only, and two is a loud refusal rather than a silent choice.
- **A claim is grounded like a clause, and must reach every clause.** The gate
  ran over clauses alone, so a claim could name anything: a minted
  `(system "echo ...")` spawned a shell inside the claim build and reported `ok`.
  One walk now judges both (`gateClaim`), differing only in ground set -- a claim
  may also name an OBSERVATION (`emitted`), which exists while a claim is judging
  and which no real run provides, so a clause naming it is still refused.
  Reachability is the other half: requiring that *some* claim exist is satisfied
  by a claim naming none of the program's own definitions, so
  `unobservedClauses` follows calls from each claim into the clauses it reaches
  and refuses an engine leaving any definition outside that set. It found three
  of the six validation scenarios claiming only pure helpers, with the entry --
  the actual program -- unobserved; all three were re-minted against a prompt
  that now teaches claiming the entry, and two fresh programs (`redact`,
  `chunk`) chose that shape unprompted on the first try.
- **What a clause defines is one answer.** `paramCount` returns `Nothing` for a
  constant, because a constant is not a procedure of no arguments: a second copy
  of the question said `0`, so a core defining `main` as a number satisfied the
  runtime's entry and produced a binary that died on first run (`Wrong type to
  apply: 5`) with every gate green. The gate refuses calling a constant from
  inside the core for the same reason.
- **A clause subject is exactly `clause.<name>`.** `clause.main` and
  `clause.main.extra` are different subjects, so merge saw no conflict, both
  passed the gate as definitions of `main`, and the notation silently took the
  last -- proven against the real binary. A deeper path is now refused by name.
- **The runtime owns its own words.** The defining word left the gate earlier;
  the claim protocol has now followed it. `load`, `feed-args`, `feed-lines`,
  `claim`, `claims-done` and the list constructor are declared per runtime
  (`harness-*`), so the kernel keeps the SHAPES -- a file is loaded by name, a
  claim is judged by id, expression and expected value -- and holds no word of
  any notation. A runtime is a DIRECTORY under `assets/runtime/` holding a
  `runtime` file, discovered rather than listed, so adding one needs no code.
- **Grounding is counted and the unvouched is named, on every check.** Every
  assertion is vouched by the target schema, by the contract set, by the author
  who stated an observable, or by nothing. `Lips.Kernel.Grounding` counts the four
  classes, names the members of the last, and the caller that stages measures how
  many lines each staged tree holds (the kernel is pure and owns no filesystem, so
  a path would otherwise read as one harmless word). It classifies nothing by
  shape, because guessing which strings are really programs is the invention lips
  refuses. The corpus as measured: 14 of 21 programs fully vouched, 6 carrying
  unvouched text and every one of those an artifact, 5 with a staged tree
  (`logscan` 80 lines, `hello.http` 66, `board` 41, `function` 25, `habit`), and
  `greet` carrying the value-scale case, four words of mint-chosen bash. A number
  nobody watches is how seventy lines of Go arrive in a five-line program.
- **Hover: the machinery a sentence becomes, in place.** lips' claim is that the
  plain sentence is the whole artifact and everything else is derived -- and until
  now the derived part was only readable by compiling. `textDocument/hover`
  (`Lsp.Derive.hoverAt`, pure) answers per line: the pattern that read it (with
  its typed template), the decisions it states, and every option those decisions
  realize with the values filled in. It is ONE rewrite step of the matching
  rules, the same `toRule` that `refine` runs, so a hover cannot promise what the
  build will not do; a rule that cannot fit the value shows the build's own
  complaint instead. `<self>` is bound to the program's instance name, passed in
  by the server (path knowledge stays in `Lips.Identity`), so the paths shown are
  the real ones -- `artifact.hello.fill.port`, not `artifact.<self>.fill.port`. A
  `Concept` line says it realizes nothing rather than showing an empty list, and
  an unread line says so, since a hover is the first thing an author reaches for.
  Verified live over stdio against `hello.http`: four sentences, four
  realizations, including the Go build args, the systemd unit and the claim.

- **A word's type is the engine's answer, so the editor can state it and check
  it.** An author writing a sentence knows what a word MEANS; only the engine
  knows what it must BE. That fact was derivable and unused: a hole's type is
  fixed by the rhs position spending it (`<value:int>` -> int, a hole inside a
  string -> text, `<value.tail:pkg>` -> package, a capture filling an emit path
  -> name), and reading it needs no nix, no schema and no model.

  Three pieces, bottom up. `Engine.Value.valueHoleTypes` answers for one rhs
  (the grammar module owns the grammar question), over a closed `WordType`.
  `Engine.Landing` holds the join that finds the position -- which emit carries
  a word, its part index in a several-part assertion, the subject family, the
  rules matching it -- extracted from `Engine.Reach`, which now reads a landing
  instead of computing its own: one place knows how a word reaches a rule, and
  the marker/`applyPattern` substitution is not copied. `Engine.Typing` joins
  the two, and takes the NARROWEST position spending the word: a string hole
  escapes rather than coerces, so it constrains nothing and never contradicts a
  coercion (the committed `http` engine writes its port into Go source AND into
  `allowedTCPPorts`, so the honest answer is int, not text). Where two positions
  genuinely contradict, or no rule spends the word, it is SILENT: a wrong type
  reads to the author as their own mistake when it is the engine's.

  The editor spends it twice. A completion labels each hole with its type
  (`serve on port <port:int>`) and carries the same in the LSP `detail` field,
  while the inserted snippet stays `${1:port}` -- accepting never leaves a type
  in the program. And `diagnose` gained `diagUnfit`: for every matched line it
  runs one rewrite step of the rules matching its decisions, which is exactly
  what `refine` runs (the same `toRule`), so a word the option cannot take is
  named ON ITS LINE while it is typed, by the same function the build judges
  with. `<self>` is bound to a stand-in there, because the check judges the
  author's word and an emit path lips cannot fill is the mint gate's business.
  Both the CLI table (a `does not fit` block) and the LSP (an error diagnostic)
  read that one field, so they cannot disagree.

  One neighbour fixed by what this made visible: a `RewriteFailed` was reported
  as "the setup lips built is broken, not your program" with `lips generate` as
  the remedy, which is the wrong blame for its commonest cause. It now names
  both possible causes and both remedies, and the per-line report says which
  line stated the word.

- **One voice, and a mint you can watch.** Every byte lips prints is decided in
  `Lips.Cli.Output`, not at forty call sites: four glyphs (`·` a phase running,
  `✓` one that held, `✗` one that failed, `→` the remedy), dim and bold, no
  hues, and all styling dropped when stderr is not a terminal or `NO_COLOR` is
  set -- with the words identical either way, so a piped run reads as the log of
  an interactive one. Each verb is now the same sequence of named phases
  (crystallize, contract, claims, write; plus schema, mint, artifacts for
  `generate`), each with its own duration, and the clock on the live line is the
  motion, so lips needs no spinner alphabet.

  The mint stopped being a silent wall. `callPi` streams pi's `--mode json`
  events instead of reading the whole reply at the end, so a tool call shows as
  it is made and the live line reports what the model is doing; a working model
  and a hung one no longer look identical for minutes. One pure function
  (`Lips.Generate.PiJson.progressEvent`) turns an event into what to show, so
  the display is unit-tested and no tool is named in the code -- a mint tool
  added later is displayed without touching it. `--verbose` shows everything
  sent (system prompt, direction, corpus) and everything received (prose as it
  streams, untruncated arguments and answers). The full stream still feeds
  `parsePiReply`, so the record and `genId` are unchanged.

  stdout now carries only what a machine asked for (an `options` answer, a
  diagnosis table); progress, verdicts and remedies go to stderr. `generate` no
  longer dumps the realized module to stdout: `compile` writes the directory,
  and the dump was pages of duplicate noise. Both streams are line-buffered, so
  a progress line can no longer land in the middle of an answer.

- **Draft validation: the mint can check itself before it answers.** `generate`
  called the model once and judged the result afterwards, so everything except
  option NAMES had to be right blind, in one forward pass over an 854-line
  prompt. Now a second tool, `check_draft`, runs lips' own gates over the lines
  the model is about to answer with and reports the first gate that rejects
  them, in the exact words the human refusal uses (spec:
  `docs/superpowers/specs/2026-08-01-draft-validation-design.md`).

  The backing command is `lips check --draft`, a flag rather than a new verb:
  `check` already means "verify an engine against a contract, offline, no AI",
  and a draft is the same act on a different INPUT. It reads the reply format on
  stdin -- not `.lang`, so the thing checked is the thing shipped -- and
  materializes a throwaway language folder (`Lips.Generate.Draft`, pure: it
  decides the folder's contents, the shell writes them). `--draft` and `--lang`
  are mutually exclusive by construction, since they name two different engines.

  The five schema-free engine gates moved into one pure function
  (`Lips.Kernel.Engine.Gate.engineViolations`) with three callers: `generate`
  before accepting a mint, `check` over a committed engine, and the draft path.
  That closes a real hole beside serving the tool -- a committed `.lang` was
  never re-verified for orthogonality, so an unsound engine reported its
  ambiguity as the AUTHOR's unreadable line. The schema gate stays out of
  `check` (it needs an option document, and `check` stays nixpkgs-free); the
  draft path runs it itself, on the mint side where `generate` already built
  one and hands over its path.

  Two things are deliberately NOT run, and the output says so: the claim gate
  and the artifact build. A machine claim boots a VM, so a per-call cost of
  minutes and a hard failure without KVM would be a false RED blocking the model
  from validating at all. "Not verified" is stated, never rendered as verified.
  The governing contract is generate's rule, not the tool's: the committed
  `.expect` on a regeneration, the draft's own expects on a first mint or under
  `--renew`, exported so the two cannot drift into a false green. Nothing
  enforces that the tool is used: the deciding gate is unchanged, so the feature
  is strictly non-worse than before.

  MEASURED, on the goal itself rather than the mechanism. One artifact- and
  claim-bearing language (the `hello.http` program, minted fresh as `.tinyweb`),
  sonnet-5, three runs. With the tool: SUCCEEDED, after 10 `check_draft` calls
  beside 9 `query_options` calls; the tool caught a dropped value (a `<text>`
  hole reaching no decision -- the silent-demotion class), a malformed rule, and
  a program that stopped crystallizing, each fixed in-turn. Without the tool,
  twice: both FAILED, once on an `${artifact.x}/bin/x` path the build does not
  contain (a gate the tool does not run, so no claim is made for it) and once on
  the expect gate, which the tool DOES run and would have shown in-turn. One
  sample per arm, so this is evidence, not proof.

  Two kernel fixes the live runs forced, both in the spirit of invariant 4.
  (i) A claim id was rendered as a bare nix attribute name, so an engine keying
  its claims by `<n:index>` produced `1 = pkgs.testers.nixosTest ...`, a syntax
  error three layers down a nix trace; ids are now always quoted, which is legal
  for every id and needs no rule about which are "safe". (ii) Told its draft was
  clean, sonnet-5 wanted to SAY so, and one narrating sentence in the reply
  fails the strict item parser (the same shape TODO 3 records for opus-4-5). The
  reminder now rides on the tool's own last words, where the temptation is
  created, rather than on another plea in the prompt.

- **The meaning dimension: observable claims, and a specification that stays
  causal.** Every gate lips had read the MAP (the module text); none observed the
  TERRITORY. So a program whose behaviour lives in baked source could state a
  sentence, have it minted into code, and have that code drift with every gate
  green. Two mechanisms, landed together (spec:
  `docs/superpowers/specs/2026-07-31-meaning-dimension-design.md`).

  CLAIMS are a reserved emit head beside `artifact.<name>`, with a closed section
  set the engine fills and cannot extend: `claim.<id>.run` (may hold
  `${artifact.<name>}`), `.stdin`, `.stdout`, `.exit` (default 0). The rhs stays
  in the closed value grammar, so a claim cannot compute. The WITNESS comes from
  the author, as an ordinary sentence read by an ordinary pattern -- nothing is
  invented, and the mint is told to file a gap rather than guess one. Comparison
  is EXACT, byte for byte, with exactly one trailing newline stripped from the
  observed output (containment is what let a minted `"200\n404"` pass as
  `"200n404"`). The PLACE is derived, never declared: a command naming only
  artifacts becomes a plain derivation in the nix sandbox, anything else a
  `testers.nixosTest` that boots the realized module. `compile` writes
  `claims.nix` beside `artifact.nix` and prints a `#claims` rung; `check` builds
  it, so what CI runs and what an author runs cannot drift. A claim that cannot
  run (a machine claim without KVM) FAILS naming the remedy, never skips.
  `.expect` pins claim slots through the artifact-slot mechanism it already had,
  so a re-mint that drops the author's example trips the existing gate with no
  new gate. `generate` SAYS SO where an engine bakes source and states no claim
  (a refusal at first; softened to a warning, see below), and refuses a machine
  claim in a world with no machine to boot; it RUNS every
  claim before writing anything, against the pinned nixpkgs. The LSP warns,
  advisory, on a concept-only line where the language bakes source and the
  program states no observable.

  SOURCE-LINE PROVENANCE closes the other half. The diagnosis in TODO was out of
  date and is corrected here: rewording a concept line was ALREADY loud (its
  pattern is all-literal, so the line goes unmatched), and `retiredConcepts`
  already compared subject AND text, so a reword swallowed by a hole was caught
  too. What was genuinely open was the recorded-section escape -- a program the
  `.generation` record holds no section for (added or renamed after the mint) was
  silently SKIPPED. Now a baked-source language whose record cannot be read fails
  loud, and an unrecorded program must state only concepts the mint saw in some
  program of the language, so sibling reuse stays free while a sentence the
  source was never written from is refused. The judgment is pure
  (`Diagnose.sourceSpecVerdict`, `Record.recordedPrograms`), so the conformance
  suite reaches it instead of only the CLI.

  What the first two real mints taught, each a kernel fix rather than a prompt
  plea (invariant 4): (i) `.expect` compared a program value against the RAW
  canonical assertion while the program side was already decoded, so a stated
  value carrying a quote -- a JSON witness `{"a":"1"}`, stored as
  `"{\"a\":\"1\"}"` -- could never be pinned; both sides now compare as VALUES.
  (ii) A several-part value pinned as one text can be unsatisfiable by
  construction (the rule joins the parts its own way, a newline between two stdin
  lines, while the program side renders them space-joined); that read exactly
  like a value that failed to arrive, so the refusal now names the remedy (one
  assertion per part, `#1`, `#2`). (iii) `pkgs.nixosTest` is an alias nixpkgs now
  refuses outright, so a machine claim rendered that way died at evaluation
  before it ever booted -- found only by actually booting one, which is the same
  lesson the artifact build gate taught.

  Evidence, not assertion: `examples/logscan.lips` and `examples/hello.http.lips`
  each state a worked example and were re-minted against it; breaking a witness
  produces `claim filter: stdout was '{"a":"1"}', expected '{"a":"2"}'` from a
  real build, and a synthetic machine claim boots a VM, observes
  `systemctl is-active`, and fails the same way when the observation is wrong.

  Known and deliberate, recorded rather than papered over. A tool whose behaviour
  depends on HOST STATE cannot be observed in a sandbox: `board` reads an
  absolute board file its module never creates, so only its failure is
  observable, and `habit` guards a missing log so only its usage error is. Both
  are left without witnesses; the honest remedy is a program that can be FED
  (a path argument, stdin), which is a design change belonging with the plurality
  work (TODO 7), not a thin error-path claim dressed as verification. And the
  preamble's "prefer an observable over the program's own binary" nudge has a
  cost the `http` re-mint made visible: the mint added a `-check` mode to its own
  Go source and observed the handler in the sandbox rather than the booted
  service, so the port and the unit wiring stay unobserved while the response
  body is genuinely checked. Cheap and honest as far as it goes, and narrower
  than a reader might assume.

  One consequence to know: for a claim-bearing program `check` needs an ambient
  nixpkgs (the compiled flake resolves `flake:nixpkgs`, as every other rung
  does), and a machine claim makes `check` boot a VM. A claim-free program is
  untouched and `check` stays nixpkgs-free for it.

  SOFTENED, deliberately: the missing observable is now SAID in generate's
  report (beside the gaps list, naming each baked file) instead of killing the
  mint. A witness can only come from the author's own example, so a refusal
  threw away an engine that was otherwise correct and left the author with
  nothing to state the example against -- and it made `board`, `habit`,
  `function` and `website` unre-mintable until each first gained a witness. The
  pull toward claims now lives where it can be graceful: the prompt asks the
  mint to read every line for an example and to file a GAP where the program
  offers none, and the report repeats it. This is a considered exception to
  "structural guards beat prompt pleas" (invariant 2), which governs what lips
  READS; here the input simply does not carry the fact, and no guard can conjure
  it.

- **`meta.mainProgram` is stamped from the base's own `bin/<x>` reference, never
  guessed.** `nix run`/`nix develop`'s default program lookup assumes
  `bin/<pname>`; a builder is free to name its output differently (a `go.mod`'s
  own `module`, a Cargo `[[bin]]` name), so the assumption silently breaks
  whenever the two diverge -- `examples/website`'s Go module is `site`, its
  artifact's `pname` is `website`, so `nix develop`'s shell held no `website`
  command (only `site`), and the printed `nix run .../artifact.website` line
  overpromised the same way. `realize` already resolves the true in-build path
  for every option value referencing `${artifact.<name>}/bin/<x>` (that is how
  `ExecStart` gets its real path); a new `mainPrograms` pass in `Realize.hs`
  reuses exactly that resolution and stamps `meta.mainProgram` on the matching
  artifact entry, in both the module and the standalone `artifact.nix`. Fires
  only when a base names EXACTLY one `bin/<x>` for an artifact (never zero,
  never a guess between two); ambiguous or silent bases leave nix's unchanged
  default in place. No kernel branch on a language: it repeats a name the base's
  own decisions already spell out, the same way a `${pkgs.<path>}` reference is
  forwarded without the kernel understanding it. A plain `lips compile` of
  `examples/website` (no `generate`, no `.expect` change) now produces
  `meta.mainProgram = "site";`.

- **A symbol is a token's own text: only a sentence terminator is kernel noise**
  (closes TODO 7; commits `pattern: a symbol belongs to its token`, `mint: a
  template must write the symbols`, `function: re-mint`). The old physics ran
  `stripTrailingPunct` (the set `.,;:!?`) over EVERY token, on the program side
  in `tokenizeLine` and on the template side in `parseTplTok`, so a language
  could not make a symbol mean anything: `content:` and `content` were the same
  token. The loss was silent and it reached the committed engine, since a `.lang`
  is re-rendered from parsed patterns -- the `function` mint wrote
  `function println_to_stdout(<param>: String)` and the file recorded
  `(<param> string)`. Worse, the value then carried the symbol the template had
  dropped: under the stale engine the fused hole bound `param` = `x:` and staged
  `func println_to_stdout(x: string)`, invalid Go that only the flake's
  `lipsArtifacts-build` caught.

  The set was a fact about English prose living in a domain-blind kernel, so it
  went. Punctuation is now part of the token, compared literally, and
  `normalizeToken` only lowercases; a template that writes a symbol requires it,
  and a hole binds its token verbatim (a rule building a list still strips per
  token in `Engine/Value.fillV`, which is where a separator the author wrote is
  spent). The single exception is `stripTerminator`: the trailing punctuation of
  the LAST token of a line or template, shed on both sides, so a sentence-final
  period needs no template token and a mint that glues it onto the last hole
  (`<when>.`) still yields the hole. One rule, symmetric, and the terminator is
  the only place the kernel names a punctuation character at all.

  Cost paid: `examples/function` was re-minted and its `.expect` re-blessed (the
  new engine holes the function name and the declared type, closing its own
  `declared-type-mapping` gap). Every other committed engine crystallizes and
  checks unchanged, because no other minted template carried a symbol. A
  sonnet-5 mint of the same program regressed it (echo lines instead of a built
  binary), which is the evidence TODO 4's sweep wanted: keep opus where sonnet
  regresses.

- **A subject segment holds no spaces, and the prompt says so (`examples/website`
  committed).** The round-trip gate refuses a subject keyed by a multi-word
  capture, and three mints in a row walked into it: the grammar alone gives the
  mint no way to deduce the rule, so the mint doctrine now states it and names
  the remedy (key by `<n:index>`, carry the words in the assertion where quoting
  protects them), pinned by the prompt-invariant guard. The re-minted `website`
  language keys nothing by a label, checks green (5 of 5 lines, all contracts),
  builds its Go artifact under `lipsArtifacts-build`, and files an honest gap
  (`repeating-canvas-button`: source fills substitute text once, so no fill can
  repeat a block of markup per canvas). Same run closed a smaller lie: an
  accepted mint now deletes the `.gap` an earlier refused attempt left in the
  language folder, which otherwise advertises a refusal that no longer exists.

- **Blocks (pattern nesting): the last piece of template completeness.** A
  program line can now state a block, and a line inside it sees the block it sits
  in. Three invented languages drove it, each failing differently under the old
  physics: two nginx vhosts each stating a `/` location collided on one subject,
  so lips told the author to delete one of two correct lines while calling the two
  `host <domain>:` headers decoration; a release pipeline whose fourth step
  repeated its second realized three steps from four lines at exit 0, invisible to
  `diagInert` (per kind) and `diagDropped` (per hole); and a program naming two
  anonymous scrape targets could not be written at all, because nothing in the
  domain names a target and position is the only identity there is.

  The TODO framing ("true parent-child block aggregation -- a decision that owns
  a list") was wrong, and saying so is the point: `Append` already assembles a
  list from N same-option contributors in source order, so no decision needs to
  own one. What was missing was SCOPE. So the atom, merge, refine, realize,
  `.expect` and the canonical `.decisions` text are untouched; a block is a
  crystallize-time scope (`kernel/src/Lips/Kernel/Lang/Nest.hs`).

  How it is spelled. Nesting is a relation between PATTERNS, carried in the
  subject path (`lang.pattern.p3.under.p2`, mint side `p3.under.p2 pattern ...`),
  and a child line belongs to the nearest preceding line that matched its parent
  pattern. Its binding environment is its own captures over its ancestors',
  own shadowing. Two structure-bound holes fill from shape rather than from a
  token: `<n:index>`, the line's position among the items of its block (so an
  anonymous record keeps an identity and a repeated item stays distinct), and
  `<k:key>`, the subject of the line that opens the block (so keys compose).
  A pattern may name several parents, tried in order, which is what unbounded
  depth needs: `n1.under.n1.under.n0` reads an item inside an item of its own
  shape, rooting in the header otherwise, and `<k:key>` makes the keys accumulate
  (`tree.File.New.Item`), so two branches may share a node name.

  There is NO surface convention, and that is deliberate: the kernel must not
  dictate a collection syntax any more than it may name a domain word, so it
  never learns that `-` or `:` marks anything. The language's own words mark a
  block, through the parent's template. Leading whitespace carries meaning in
  exactly one place, a pattern that names itself as a parent, since nothing else
  can say how deep an item sits; every committed program is flat, so every one of
  them compiles to a byte-identical module (verified).

  Rejected spellings, with reasons: a body prefix (`under p2 :: <template>`),
  because it must be read out of free template text and a template legitimately
  starting with the word "under" would then be refused -- a missing template case,
  which invariant 3 calls a kernel bug; and a separate `nest p3 under p2` item,
  because it lets one pattern carry two conflicting parents, where the id makes
  the chain structural.

  Refused at the gate, inside `readLang` so `generate`, `compile`, `check` and
  `lsp` all inherit it: a parent id no pattern defines, a nesting cycle through
  two or more patterns, an emit hole bound by neither the pattern nor every block
  it can sit in (the INTERSECTION over possible parents, since the line attaches
  to whichever it finds), and `<k:key>` in a pattern that heads no block. The
  static gates that run a pattern's own substitution (`Reach.droppedValues`,
  `Answerable.emittedFamilies`) now bind every hole in scope, since `applyPattern`
  is total only over a complete binding map.

  Proof: `examples/gateway.vhost.lips`, minted live (`anthropic/claude-sonnet-5`),
  and the mint reached for `p3.under.p2` on its own. Two more hosts were then
  added with no model, `check` still green. The report also stopped lying: a line
  that opens a block is no longer listed as "decorative, realizing nothing --
  editing these changes no output", because editing it changes every option its
  items realize.

- **A program word may not become a Nix path.** Found by `nix flake check` on the
  first engine ever to write `<value:path>` (the vhost mint, for an nginx document
  root): a bare Nix path means "copy this location into the store", so pure
  evaluation refuses an absolute one, and a directory the program names lives on
  the running machine, not in the store. Nothing downstream could catch it -- the
  realized module is valid Nix and evaluates until something forces the path, so
  the failure surfaces as an opaque nix error far from the rule that caused it.
  Now refused at the mint gate (`assertNoPathHoles` over
  `Engine.Value.valuePathHoles`), with the fix named: a path-typed option accepts
  a string, so write `"\"<value>\""`. A Nix path stays what the ENGINE writes as a
  literal (`./artifacts/<name>`). The prompt states the rule too, since a fresh
  `pi` process has no memory of the refusal and re-minted the same rule verbatim
  until told; the guard is what makes it impossible, the prompt is what makes it
  unnecessary.

- **A line that restates an earlier one is named.** Found while trialling blocks:
  two program lines crystallizing to an identical decision (same subject, same
  assertion) merge into one, and nothing could see it -- `diagInert` works per
  kind, `diagDropped` per hole, and a whole absorbed line is neither. Reported per
  line (`Crystallize.restatements`, `Diagnosis.diagRestated`), not refused,
  because merge doctrine and the committed edit-tolerance property both hold that
  two statements of one fact ARE one fact; what was missing was saying so out
  loud.

- **Live host deployment.** The headline missing proof (§13 "Shortest
  Summary"): `examples/logscan.lips`'s already-minted engine (a JSON-log
  filter CLI, target `home-manager`, needing no `pi`/model call to reuse) is
  imported into `~/nixos`, a real machine's own NixOS + home-manager
  configuration, via the public `lib.modulesFromDir` helper -- not a VM, not
  this repo. `lips check` and `lips compile` ran clean, `nixos-rebuild build`
  proved it before anything live changed, and `nixos-rebuild switch` is now
  applied: `logscan` runs from a real user's PATH on a real system, committed
  in that repo (`b3ed547`). This is the coexistence defense (DESIGN §9, item
  5) made real rather than asserted: one Solution realized as one ordinary
  home-manager module, imported beside a repo's own hand-written modules, on
  hardware. The attempt paid for itself before it ever switched: see the
  entry directly below ("A public `nixosModules`/`homeManagerModules` value
  is now actually importable") for the real bug it surfaced and fixed, which
  no VM-only check had ever caught.

- **A public `nixosModules`/`homeManagerModules` value is now actually
  importable, as documented.** Found by the first real live deployment (a
  home-manager module nested inside a NixOS host on a real machine, not this
  repo's own VM checks): `imports = [ lips.nixosModules.<instance> ]`, the
  README's own literal example, crashed with
  `the option '...__ignoreNulls' does not exist` -- a NixOS-internal
  bookkeeping attribute of the DERIVATION `modulesFromDir` handed back, read
  as if it were config. Root cause: nixpkgs' `lib/modules.nix` `loadModule`
  dispatches `isFunction` -> call it, else `isAttrs` -> if `_type or "module"
  == "module"` (the DEFAULT when absent) treat the value AS LITERAL MODULE
  CONTENT, else `import (toString m)`. A derivation is `isAttrs` and carries
  no `_type` (only an unrelated `type = "derivation"`), so it always took the
  "literal content" branch, never the `import` branch that would have worked.
  This repo's OWN `vm-smoke`/`artifact-vm` checks already carried the fix as a
  silent local workaround (`imports = [ "${realized}" ]`, commented there:
  "a bare derivation in imports is misread as an inline attrset module") --
  it was simply never propagated to the PUBLIC `nix/modulesFromDir.nix`
  helper, so external consumers hit the bug fresh, and no check here could
  have caught it: `lipsModules-eval` only did `test -f ${p}/default.nix`; a
  file existing on disk says nothing about whether NixOS's module loader can
  read it. Fixed at the source: `byTarget` now exposes `"${v.module}"` (a
  plain string) instead of the bare derivation `v.module` -- a string is
  `isAttrs`/`isFunction`/`isList` false, so it correctly falls to `import`,
  which resolves a directory string to its `default.nix` exactly as a literal
  `./dir` path would. String interpolation of an already-string value is a
  no-op, so the three internal consumers (`lipsModules-eval`,
  `lipsArtifacts-eval`, `lipsArtifacts-build`), which all read `${p}/...`
  paths, are unaffected. `lipsModules-eval` is strengthened to match: for
  every committed example it now instantiates (never builds, same technique
  as `lipsArtifacts-eval`'s drvPath-forcing) a REAL `nixosSystem` or
  `homeManagerConfiguration` over the exact PUBLIC value an external
  consumer's flake would get, with a minimal hardware/home stub supplying the
  generic boilerplate (root filesystem, bootloader, username, state version)
  no committed example states an opinion on -- so a future regression of this
  exact class fails here, in seconds, instead of on someone's real machine.
  No README change needed: `imports = [ lips.nixosModules.ledger ]` was
  always the intended contract, and it is now simply true. Verified: 394/394,
  `-Wall` clean, all four `check-expect` programs unchanged, `lipsModules-eval`
  / `lipsArtifacts-eval` / `lipsArtifacts-build` all green, and the exact
  failure reproduced against the OLD code (bare derivation) before the fix,
  confirmed gone after it.

- **The mint prompt is reviewable prose, not escaped Haskell string literals.**
  The prompt accreted over many milestones as `T.unlines`/string-literal blocks
  inside `Lips.Generate.Minting`, which is how it ended up stating the same
  prohibition three times and made every worked example expensive to write and
  hard to read (docs/superpowers/plans/2026-07-26-mint-prompt-rewrite-plan.md).
  It now lives as markdown under `assets/mint/` (`body.md` the world-neutral
  body, `nixos.md`/`home-manager.md` the two world preambles, `direction.md`
  the advisory-direction wrapper), embedded at compile time with `file-embed`
  (`Data.FileEmbed.embedStringFile`); `Minting.systemPromptFor` composes them,
  unchanged as a public surface. The migration landed byte-identical first (an
  empty diff against the old rendered prompt, so the embedding mechanism could
  not be blamed for any later wording change), then the body was rewritten
  section by section: where the mint sits and what it owns; the seven pipeline
  stages it programs, named the way a refusal names them; how to work with the
  one grounding tool (`query_options`) and its names-not-values limit; the
  output contract (including the `report`/`gap` blocks the "mint expression
  channels" milestone added, folded in for the first time rather than
  described separately); one reference subsection per construct, each
  prohibition stated exactly once; design guidance on what makes a language
  worth writing against; two full worked examples in synthetic domains (a
  job-queue watcher, a from-source greeter), neither restic nor nginx, so no
  mint inherits a real repo engine as a default; and a closing self-review
  checklist. A new suite guard (`fencedBlocks` + `parseEngineCandidates` over
  every ` ```lips-engine ` block in the prompt) makes a stale worked example
  impossible to ship silently: it caught two real mistakes while the examples
  were being drafted (a malformed multi-token-hole reference, a missing
  inner-quote on a fill value). The pinned-clause test
  ("generate prompt is a pinned artifact") is rewritten to the new load-bearing
  sentences, keeping the ones that matter across the rewrite (`act exactly
  once`, `replace every program VALUE with a hole`, `refusal beats invention`,
  `query_options`, the report and gap requirements). Every future `@gen` stamp
  changes as a direct consequence (the prompt is part of `genId`), which is
  expected, not a regression: a differently-worded prompt is a different
  generation event by the calculus's own definition (spec section 5, "the
  generation event is pinned"). Verified: 394/394, `-Wall` clean, the packaged
  flake build and `checks.kernel-tests` both green (proving the embed path
  resolves identically under a direct `ghc -isrc` invocation from `kernel/`
  and inside the flake's build derivation, where `assets/` is copied as a
  sibling of the copied `kernel/` tree so the same relative `../assets/mint/*`
  path resolves in both places). Not done in this pass, deliberately: no
  example under `examples/` was re-minted against the new prompt (that is a
  separate, explicit action -- `generate --renew` on each -- left for whoever
  reviews the new wording; every existing `.generation` record, and its
  `@gen` stamps, remain valid against the OLD prompt they recorded).

- **Reserved value-hole names cannot be a subject capture.** A rule subject may
  name a capture with any word (`cmd.<port>.msg`), and a rule rhs may reference
  either that capture or the reserved `<value>`/`<value.N>` (the ground
  decision's own assertion) -- two different vocabularies that look identical,
  which TODO 1f named as a confusion "a weaker model reliably" makes. The
  existing unbound-capture check ("Captures are first-class", below) already
  catches a rhs hole the subject never bound, but it could not catch the
  sharper case: a subject capture literally NAMED `<value>` (a natural word
  choice, since it IS the value the mint is capturing) parsed with no error at
  all, because `captureName` has no reserved words. Downstream, `pick`'s first
  clause matches the literal string "value" unconditionally, before ever
  consulting the capture map -- so the rhs silently read the decision's
  assertion instead of the captured subject segment the mint clearly intended,
  with nothing anywhere naming the collision (confirmed live: `parseRuleBody`
  accepted `match fact cmd.<value>.msg => a.b "<value>"` cleanly, and `refine`
  filled it from the assertion, never the capture). `parseRuleBody` now rejects
  a subject capture named `value` or shaped `value.N` at the same door the
  unbound-capture check already uses, naming the collision and suggesting a
  rename, before the unbound check ever runs -- so the reserved word can no
  longer be silently shadowed, only cleanly refused. No committed example was
  affected (none names a subject capture `<value>`). Closes TODO item 1f.
  Verified: 393/393, `-Wall` clean, `check` still green on all 13 examples.

- **Gap report file writer (`<language>.gap`).** `generate` refusing was, until
  now, only on-screen text: a mint that fails in a downstream repo had nothing
  to commit, paste, or send upstream. `generate` now writes
  `Lips.Identity.gapPath` (`<language>.gap`, beside `.lang`/`.expect`/`.generation`)
  on every refusal, never on a successful mint (where a mint-reported `gap`
  already lands inside `readmePath`'s README -- see "Mint expression channels"
  below). The file carries the refused lines (grammar errors), the
  underspecified items (below the confidence threshold), every mint-reported
  `Gap` verbatim (each already names its own blocked line and repro, per that
  channel's own contract), and the full generation record -- model, target,
  thinking, confidence, system prompt, program corpus, tool transcript, raw
  reply -- fingerprinted with the same `genId` a successful `.generation`
  uses, from the same in-scope values (`Lips.Generate.Record.record`), so a
  refusal is pinned exactly as an acceptance would have been. The on-screen
  refusal now names the file's path. This operationalizes the cross-repo
  escalation workflow the doctrine section already named as the intended use
  (generate refuses -> gap report travels upstream -> kernel grows under the
  suite -> downstream regenerates): before this, step one had no artifact to
  travel. No kernel change -- this is Generate-tier plumbing over data the
  mint and the record already produced. Closes TODO item 3. Verified: `-Wall`
  clean, full suite green (390/390, one new test pinning `gapPath`'s naming
  alongside `readmePath`'s), and the whole CLI binary compiles clean end to
  end.

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

- **The reasoning level is pinned (`--thinking`, default `medium`).** `generate`
  passed no thinking flag, so pi's default applied, inherited from the caller's
  environment, steering the mint without entering `.generation` or `genId` -- the
  same hole `-nc` closed for ambient context files. It is now always passed
  explicitly and recorded as a `thinking:` line, so it enters the id. Unlike the
  model (deliberately not baked in: omitted, then read back), an omitted
  thinking level cannot be read back reliably, so explicit-always is the fix.

  The default was `high` on the reasoning that a refused mint costs a whole
  round. Measurement (2026-08-05) moved it. A mint's cost is turns times
  per-turn latency, and lips is under 1% of it: one `check_draft` takes ~0.95s
  inside a six-minute mint, so the model is over 99%. Reasoning level moves
  per-turn latency, and the same program minted in 6m22s at `high` against
  4m17s at `medium` -- same number of drafts, behaviourally identical engine,
  a third of the time saved. Turn COUNT is the larger factor (one program took
  23 drafts before the prompt was corrected and 3 after), and it is bought with
  a clearer prompt rather than with more reasoning. Raise it per run when a
  program is genuinely hard; the level is recorded either way.

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
  `TODO.md` item 3a; two deliberate non-goals are recorded there too (a partial
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

- **The mint is grounded by a schema lookup tool.** A mint may confirm an
  option path and type instead of recalling it, through the tool
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

- **Third realization target (kubenix).** `lips generate --target kubenix`
  mints into `kubernetes.resources.<kindPlural>.<self>.*` and `compile` renders
  Kubernetes manifests. Zero kernel change, as the target axis promised: the
  three knobs are `assets/mint/kubenix.md` (the world preamble),
  `Lips.Nix.Kubenix` (the grounding schema) and `Lips.Nix.Flake` (the rungs),
  plus one dispatcher, `Lips.Nix.Schema.schemaFor`, so the two grounding call
  sites cannot disagree about a world. Grounding is real, not nominal: lips
  builds a 31478-entry `optionsJSON` with `nixosOptionsDoc` over an empty
  `kubenix.evalModules` (pinned `LIPS_KUBENIX_FLAKE`, ~4 minutes once, then
  cached), and reshapes it three ways, each a kubenix fact and none a kernel
  one: RE-KEY the typed tree `kubernetes.api.resources.*` onto the alias every
  kubenix module writes; DROP every inner node, because `checkEmits` accepts any
  path descending into a declared option and kubenix declares its inner nodes
  free-form (`attribute set of (attribute set)`), so keeping them would make
  every misspelled field admissible; UNWRAP `null or <type>`, since almost every
  Kubernetes field is optional and would otherwise degrade to `OTOther`.
  `lips options --target kubenix 'kubernetes.resources.services.*.spec.ports'`
  answers with typed leaves. The compiled flake exposes `kubenixModules.default`
  and both of kubenix's OWN rendered outputs (`resultYAML`, `result`), so lips
  converts nothing: `nix run …#manifest > manifests.yaml` writes,
  `nix build …#manifest` checks (kubenix refuses an unknown or mistyped field at
  evaluation -- a second gate independent of grounding), `nix develop` gives a
  `kubectl` shell. No apply rung: a lips-written script mutating a live cluster
  buys nothing over an explicit pipe. Proven live by two committed examples in
  two languages: `examples/web.deploy.lips` (Deployment + Service, namespace,
  container and service ports) and `examples/report.cron.lips` (CronJob,
  schedule, history limits, deadline), both rendering real YAML. Three findings
  fixed on the way, each one a third world made visible. (1) The module header
  and several messages named "NixOS" from domain-blind layers (`Realize`,
  `OptionType.renderOptionError`). (2) `modulesFromDir` decided a program's world
  by testing for the single string `target: home-manager`, so a kubenix program
  was labeled nixos; it now reads the recorded slug and exposes
  `kubenixModules.<instance>`, and `lipsModules-eval` instantiates each one
  through `kubenix.evalModules` (forcing `resultYAML.drvPath`), the
  manifest-world equivalent of forcing a `toplevel`. (3) The bug underneath:
  reads followed the AMBIENT locale encoding while writes were pinned to UTF-8,
  so inside a nix build (no `LANG`) reading a `.generation` -- which embeds the
  mint prompt, em dashes included -- threw, `tryRead` turned the throw into
  "absent", and `compile` silently emitted a NixOS flake for a kubenix program.
  Fixed at the root (`setLocaleEncoding utf8`) and made loud: a record that
  exists but cannot be read now dies instead of defaulting to a world. The
  standing lesson, paid again: a silent fallback beats a crash only until its
  plausible-looking output reaches a human. Design in
  `docs/superpowers/specs/2026-07-30-kubenix-terranix-targets-design.md`; its
  phase 2 (terranix) is designed but unbuilt, and its grounding weakness is
  recorded in `TODO.md` rather than hidden.

- **Fourth realization target (terranix).** `lips generate --target terranix`
  mints into `resource.<type>.<self>.*`, `data.*`, `provider.*`, `output.*` and
  `compile` renders a Terraform `config.tf.json`. Zero kernel change again, and
  cheaper than kubenix: the schema needs no reshaping (`schemaFor Terranix` is
  plain `parseNixOptionsJson`) and the harness is six lines of flake text
  (`packages.config` = terranix's own `lib.terranixConfiguration`,
  `apps.config` printing it, an `opentofu` shell). Proven live by
  `examples/assets.bucket.lips`, whose three sentences render an
  `aws_s3_bucket`, an `aws_s3_bucket_versioning` pointing at it, and an output
  reporting the generated name.

  Two of the world's own facts had to be discovered rather than assumed.
  terranix's published `lib.terranixOptions` is the WRONG grounding door: its
  `jq` pass deletes `resource`, `data`, `provider`, `output` and every other core
  namespace, because it exists to document a *user's* modules. So lips evaluates
  terranix's core modules itself (`core/terraform-options.nix` plus `modules`,
  the `lib.extend` its own `core/default.nix` uses) and runs `nixosOptionsDoc`
  over the result: 46 entries, seconds, one mechanism shared with the other
  worlds. And grounding here is WEAK by construction, which the design states
  instead of hiding: `resource` and its siblings are one free-form "magic merge"
  valueType, so the schema confirms the top-level namespace (a misspelled
  `resourse` is still refused) and nothing below it. The `terranix.md` preamble
  says so to the mint in those words, and `TODO.md` carries the remedy
  (`terraform providers schema -json`, a per-provider fetch at generate time).

  Rejected, and recorded so it is not re-asked: an HCL (`.tf`) rung beside the
  JSON, by analogy with kubenix's YAML. The analogy does not hold. kubenix
  DECLARES `resultYAML` itself, so exposing it converted nothing, whereas
  terranix renders JSON only -- and `config.tf.json` is native configuration
  (`tofu validate` accepts the rendered file as-is), so nothing is missing but
  readability. Worse, the conversion is ill-posed rather than merely
  unimplemented: Terraform's JSON syntax lets a name like
  `versioning_configuration` be either a nested block or an object attribute, and
  only the PROVIDER SCHEMA says which -- the same per-provider, per-version pin
  the grounding remedy needs. The one converter in nixpkgs, `json2hcl`, emits
  HCL1, which OpenTofu rejects outright on our own rendered config ("Argument
  names must not be quoted"). So an HCL rung would mean lips owning a format
  writer that guesses, and printing a rung it must label "do not apply".

  Three fixes the fourth world forced, each generic, none per-world. (1) The
  lookup and the gate DISAGREED about free-form regions: `checkEmits` accepts a
  path descending into a declared free-form option, while `answerQuery` answered
  "no option matches" -- telling a mint its legal path was a typo. `Answer` gains
  `Freeform`, naming the nearest declared ancestor and saying what it costs
  ("every path under it is accepted, and none of them is checked"). This was a
  latent bug in every world, not a terranix one: NixOS free-form `settings`
  options had the same split answer. (2) The same pass tightened the gate:
  descending below a MODELLED leaf (a `string`, an `int`) was accepted, so a
  whole namespace of invented fields could hide under one real scalar option.
  Only an unmodelled type can have children the schema omits. All 15 committed
  engines were re-grounded against the pinned schemas to prove the tightening
  breaks nothing. (3) A Terraform reference is written `"${aws_s3_bucket.x.id}"`,
  which collides with lips's own `${...}`; the grammar already expressed it as an
  escaped literal (`\${…}`, realizing to a Nix string whose text is the
  reference), but the refusal never said so, so the first mint filed it as a
  capability gap. The message now names the escape -- deduce-or-fail means a
  refusal states the remedy. Beside those, the world-neutral prompt body said
  "NixOS module" nine times; with two non-NixOS worlds shipping, that is a leak,
  and a test now pins the body to name no world at all.

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
  announced. Two overrides, in order of explicitness: `--schema <flakeref>`
  builds this world's schema from another flake, and `LIPS_OPTIONS_JSON`
  supplies a prebuilt document (the suite passes an offline fixture). Which
  schema grounded a mint is recorded: `generate` resolves the source once,
  before the model call, and writes a `schema:` line into `.generation` -- a
  flakeref as the locked url `nix flake metadata` reports (never the floating
  ref the caller typed), a supplied document as `options-json:<hash>` of its
  bytes. So the grounding is an input of the generation event like the model,
  the prompt and the thinking level, and it enters the event id; the pin the
  record names is exactly the one the gate judged against, since resolution
  happens once and the path is handed to the gate. `artifact.*` build-group emits are exempt (they
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

- **The two dishonest engines re-minted (2026-07-30).** `examples/http` and
  `examples/postgres` each named their own defect under the dropped-value guard;
  both are re-minted (claude-sonnet-5) and the defect is gone. `http` now reads
  the mechanism-selecting line ("in go, standard library only") as a fact with a
  literal assertion instead of binding a hole it discards, carries the response
  text INTO the Go source through a fill, and fills `module @NAME@` in `go.mod`
  from the service name so the binary is really called what
  `ExecStart = "${artifact.hello}/bin/hello"` says (verified: the built binary
  serves the program's text on the program's port). `postgres` now reads *who owns
  the app database* as one fact carrying both words (`"<user> <db>"`) and spends
  both, so the owned database governs `ensureDatabases` instead of being dropped.
  Both re-blessed their contract (`--renew`): a re-mint renames subjects, and the
  contract names subjects, so invariant 5 fires by construction -- the observable
  option paths were compared by hand before blessing.
  Three defects the re-mints exposed, each now a guard: a `source` block whose
  artifact name is still a hole (two mints in a row wrote `<self>`, which makes a
  directory literally called `<self>`) is refused at the mint gate; the minted
  `artifacts/` tree is REPLACED rather than added to (the first re-mint left a dead
  `helloserver/` beside its new `hello/`); and a staged copy is made writable,
  since a fill writes into it and a language folder read from the nix store is
  read-only (this broke `lipsArtifacts-eval`, a compile inside a derivation).

- **Repeating source: not needed, closed by evidence (`examples/api.web.lips`,
  as minted in 8393727; the example itself realizes differently today, see the
  note at the end of this entry).**
  The open question was how N items (routes, mounts) reach a built program when a
  fill replaces one marker and cannot repeat a code block. A compile-time repeat
  block was designed and REJECTED: it needs a second templating layer inside
  source, with per-language comment syntax for its own markers, and it rebuilds
  the binary whenever the program's data changes. The answer the corpus gives
  instead: the program's per-item data is DATA, so it reaches the program through
  the config, and the source stays generic. Minted live for a three-route server
  (claude-sonnet-5): each bullet crystallizes to its own value-keyed options
  (`environment.etc.http-routes<path>/status.text` and `.../body.text`, ordinary
  attrsOf aggregation across bullets), and the Go source scans that directory at
  startup and registers a handler per entry it finds. Adding a fourth route
  changes only the config -- no rebuild, no regeneration -- which a repeated code
  block could not claim. The mint reached this itself and filed no gap for it. So
  the rule of thumb is now doctrine: source holds STRUCTURE (the algorithm, the
  format, the protocol), a fill carries a compile-time CONSTANT into it (the
  binary's own name in `go.mod`), and everything the program enumerates stays a
  table in the config.
  Two defects the experiment exposed, both fixed: two rules emitting to one
  option path is a conflict, so several words of one line that must land in ONE
  option value are ONE fact spent with `<value.N>` (the prompt now says so); and
  the transport quoting swallowed a non-transport escape, silently turning a
  minted `"200\n404"` into `"200n404"` -- valid output, wrong text, invisible to
  every gate. Only `\"` and `\\` are transport escapes now; anything else passes
  through to the value grammar, which reads `\n` as a newline.
  Where the witness lives now (2026-07-30): `api.web.lips` stopped naming an
  implementation language, and the free mint answered three fixed-body routes with
  nginx `locations.<path>.extraConfig` instead of a built program -- a valid answer
  the example is entitled to give. The doctrine is unaffected either way (routes
  are data in the config, no code block repeats), and the built-program witness is
  the tree at 8393727, not a live example. An example demonstrates what it is; it
  is not held to a shape to serve as a proof.

- **A program never names its implementation language (2026-07-30).** Five
  example programs carried `write the server/tool in go, using only the standard
  library with no external dependencies` -- mechanism, and mechanism belongs in
  `<language>.direction` or nowhere, since the program states what must be true.
  The line was provably inert: three engines read it as a `concept`, and `http`
  had already been re-minted once because it BOUND the word and discarded it (the
  `droppedValues` guard exists because of that line). `examples/greet.lips` names
  no language and mints fine, so nothing needed replacing: the line is simply
  gone, with no direction file compensating for it. The kernel never learns a
  language either way -- it reaches `buildGoModule` as a name inherited from
  nixpkgs.
  What the free mints then chose, which is the interesting part: `logscan` and
  `http` came back Go; `board` and `habit` came back as a shell script under
  `stdenv.mkDerivation`; `web` dropped the built program entirely for nginx
  `locations.<path>.extraConfig`. So an unpinned mechanism really does churn
  across regenerations, exactly as the direction-file entry predicts, and the
  churn is a gated, reviewable event (each re-mint re-blessed its `.expect`), not
  a silent one. Two mints were refused by their own contract before one passed,
  and the `web` mint filed a real gap on the way (`<value.N>` cannot carry a
  multi-word tail, closed by the several-part value entry below). The `http` mint churned twice: the first pass named
  `bin/hello` in `ExecStart` while `go.mod` said `module server`, which only
  `lipsArtifacts-build` caught (closed since: `generate` now runs that build
  itself, see "The artifact build gate" below); the accepted pass builds an artifact called `http-echo` and carries the
  port and the response text in `systemd.services.hello.environment` instead of
  source fills, so editing either no longer rebuilds the binary.

- **A path inside a build must exist (`lipsArtifacts-build`).** Instantiating an
  artifact proves the build is well-formed and says nothing about what it
  produces, and a binary's name is decided by the SOURCE, not by the derivation.
  An http mint that left `module app` in `go.mod` shipped a unit whose
  `ExecStart = "${artifact.hello}/bin/hello"` named a file the build does not
  contain: green `lips check`, green `lipsArtifacts-eval`, a service that cannot
  start, discoverable only by running the binary. The new flake check builds every
  committed artifact and asserts every `${artifact.<name>}<suffix>` the realized
  module interpolates really exists under it. Verified in both directions: green on
  the corpus, and red (naming the missing path and the store path) when the http
  engine's `ExecStart` is pointed at a binary the build has not got. It lives in
  the flake, not in `check`, for the same reason as the eval check: `check` stays
  offline and nixpkgs-free, and only a flake already has nixpkgs.

- **The artifact build gate: `generate` builds what it minted and looks inside
  it.** The flake check above catches this defect one commit too late -- it runs
  over the COMMITTED corpus, so the bad engine is already in the tree, and
  catching it depends on somebody remembering to run `nix flake check`. A gate
  that depends on remembering is not a gate, so `generate` now performs it
  itself, as its last and only *observing* gate: it stages `artifact.nix` beside
  the filled source tree exactly as `compile` writes them, builds each
  `artifact.<name>` against the pinned nixpkgs, and requires every path the
  output names inside one to be there. A mint that fails is refused whole:
  nothing is written, so no bad engine reaches the tree.

  Why observation and not analysis: what a build CONTAINS is decided by its
  source (a `go.mod` module line, a Cargo `name`), never by the derivation, so
  the only way to know is to look. Teaching lips what each builder names its
  output would be an open list the kernel enumerates, which the doctrine forbids.
  This is why the gate lives in `generate` alone: it is already online and
  already builds a pinned nixpkgs for grounding, while `compile` and `check`
  stay offline and nixpkgs-free. Kernel-side the pairs come from
  `realizeArtifactPaths`, structurally from each parsed `Value` (the flake check
  regexes module text instead), so `Realization` carries `rlArtPaths` beside
  `rlStaged`: the twin one level in -- a staged path must exist BESIDE the
  module, an artifact path INSIDE the build.

  The nixpkgs it builds against is lips's own baked pin, one authority for every
  world, because builders live in nixpkgs while a world's schema pin may name
  home-manager, kubenix or terranix -- or no flake at all (`LIPS_OPTIONS_JSON`
  pins by content). Resolved only when a mint declares an artifact, so a
  configuration-only mint pays nothing and needs no pin.

  Verified in both directions with a stub model gateway (a canned engine handed
  to `generate` through a `pi` on `PATH`, so the plumbing is exercised offline
  and for free): green writes the engine, and an engine whose `ExecStart` names
  `/bin/greetd` beside a source building `greet` is refused, naming the artifact,
  the path, the option that named it, the store path and the remedy. The same
  run found a defect in the mint prompt's own worked example, which wrote
  `vendorHash "\"null\""` -- the STRING "null", which nix refuses with *hash
  'null' does not include a type*. Every committed engine happens to write the
  bare `null`, so the corpus was green while the example taught an unbuildable
  artifact; the prompt now says so outright. The flake check stays, since it
  guards a different thing: corpus rot with no re-mint involved (a kernel change,
  a re-blessed `.expect`).

- **Set or list: how a list option aggregates repeats.** Two program lines can
  contribute the same element to one list option (`ensureDatabases` got
  `[ "app" "app" ]` from *provision a database named app* plus *a user who owns the
  app database*). Both readings are real in the target world -- naming a package
  twice names it once, while a list whose repetition carries meaning keeps both --
  and the kernel cannot tell them apart, since that is knowledge about the option.
  So the grammar carries both and the ENGINE chooses: a `merge <option.path>
  set|list` declaration, stored like every other engine line
  (`engine.merge.<id>`), capture-aware so one line covers a value-keyed family.
  The default is `set`, which is the reading the decision base already takes when
  it merges a subject: two statements of one fact are one fact. `Append` assembly
  therefore dedups unless the engine declares that option a `list`. Kernel-side
  this is `assembleWith` taking the predicate; `assembleSubject` is the set
  default. Rejected: deducing set-ness from the option type (nixpkgs types do not
  mark it) and dedup as a global kernel law (that decides a semantic question about
  a target world the kernel may not know).

- **The fused capture (a hole inside a token).** A hole could only be a whole
  whitespace token, so a value pressed against punctuation was unreadable: the
  first program written in a call syntax (`println_to_stdout("hallo")`) minted a
  pattern whose emit hole nothing could bind, and the mint gate refused it with
  "emits `<text>`, which neither it nor every block it can sit in binds". No
  re-mint could fix that -- a template had no way to say it -- so it was a
  missing grammar case, i.e. a kernel bug (`TFused [FusedSeg]`, third of the
  enumerated capture forms). A fused token's literal pieces must appear in the
  token and each of its holes binds the non-empty run of characters between
  them, shortest first with backtracking, exactly as the multi-token hole works
  one level up; literals still compare case-insensitively and the capture is the
  surface text. Two consequences fell out. A quoted span is now atomic wherever
  it STARTS, not only at the head of a token, or `println("hallo du")` would
  split in two; and a fused hole may not be `<name.words>` (that spans
  whitespace, which one token cannot), which the `.lang` reader refuses by name.
  Static overlap stays exact: two fused templates meet through the same product
  walk one level down, over characters instead of words. The kernel learns no
  call syntax from this -- it learns only to stop requiring a space around a
  hole -- and the mint prompt now offers the form, since a capability the model
  is never told about is dead capability.

- **Every decision a line states must re-read from its canonical line.** A
  minted engine keyed a button by its label, the program's label was two words
  (`button "drück mich":`), and the decision came out as
  `d4 concept button.drück mich stated "..."` -- whitespace separates the fields
  of a decision line, so `readDecision` then read `mich` as a strength and
  failed. Every gate was green while `out/*.decisions` had stopped being readable
  text, which quietly removes the ground under "regeneration is gated": the guard
  compares against a document lips can no longer parse. The `.lang` had a
  round-trip gate and pattern OUTPUT had none, so `crystallize` now renders each
  decision it builds, reads it back, and insists on the identical decision
  (`CrystError.Unreadable`, reported per line with the reader's own complaint).
  The check is the round trip itself, not a list of forbidden characters, so it
  closes over the whole canonical grammar and over every field added later; it is
  offline, domain-blind, and every deterministic verb inherits it through
  `crystallize`. The remedy it names is the engine's, not the program's: key such
  an item by `<n:index>`, which the grammar already has. Three suite fixtures had
  the same defect and were corrected with it. The verdict is a line outcome, not
  a second pass: `classifyLines` emits `Illegible` where it would have emitted
  `Matched`, so the per-line table, the LSP diagnostic and `crystallize`'s error
  all read one classification and cannot disagree (the report used to print `ok`
  for the very line the file then failed on). The line's block frame is recorded
  anyway, so an illegible block head stays one defect instead of orphaning every
  child under it.

- **A several-part value quotes its parts, so `<value.N>` reads a part.** When
  several program words must land in ONE option (a route's status and its body, a
  button's label and its target), doctrine puts them in one assertion and lets
  the rule spend them positionally. The stored text was the parts joined by
  spaces, so the boundary between them was gone: a two-word part shifted every
  later index and the last part fell off the end. The `web` mint filed this
  itself as gap `multiword-route-body`; `examples/website` then hit it for real,
  and it is invisible to the dropped-value guard because every word IS spent --
  into the wrong hole. So `applyPattern` now quotes every part of an assertion
  built from SEVERAL holes, and `Surface.valueTokens` is the inverse (one part per
  hole, whatever a part contains, escapes undone by `parseQuoted`);
  `Surface.valueText` joins them for a rule reading the whole value, so the
  quoting stays an encoding a rule never sees. An assertion of ONE hole is
  untouched, which is what a rule building a LIST out of one many-word value
  reads. One lexer, not two: the quoting convention is `Surface`'s, the same one
  every stored lips line uses. Verified: a two-word route body realizes
  `return 200 'hello world';` where it used to realize `return 200 'hello';`, and
  the whole corpus checks unchanged (no committed engine's output moves, since
  their parts are single words). Not covered: nothing yet refuses a rule that
  reads only part 1 of a two-part value, or a `<value.tail>` over a several-part
  value (TODO 3a(i)) -- the static map those need is now trivial, since part N is
  hole N by construction.
- **Plurality is what makes a baked-source hole mean anything** (2026-08-02,
  `examples/website`). The committed website engine carried a hole that meant
  nothing: `on click: <action.words> in canvas <target>` accepted any sentence,
  and the mint spent the words into an HTML `title=` tooltip while the click
  behaviour sat hardcoded in a 40-line `paint()`. Writing `on click: send an
  email` matched, realized, and repainted, with every gate green. The cause was
  not the seam. The program declared ONE button, so a hole and a constant were
  observationally identical and the mint folded the words into the source, which
  under that program was the correct reading; its own report said so
  ("a lips engine cannot synthesise behaviour from prose"). The program was
  enriched to three buttons whose actions differ (repaint, erase, download) and
  re-minted with opus-5. Same physics, no kernel change, first attempt: the hole
  DISAPPEARED, replaced by three literal patterns each emitting a constant
  (`=> fact <k:key>.action "paint"` / `"clear"` / `"download"`), so the enum
  lives in the pattern set rather than in a hole; the baked source grew a real
  dispatch (`var actions = { paint: paint, clear: erase, download: save }`) over
  indexed env vars with a `{{range .Buttons}}` loop, 111 to 220 lines; all 9
  program lines crystallize with no `Concept` (the old five had one, plus an
  action decision that was never stated at all); and `on click: send an email`
  is now REFUSED (`line 11 no match`, remedy named). Flexibility went down and
  understanding went up, which is one event, not two: a language understands
  exactly the distinctions it refuses to collapse. Doctrine below.
- **A program that can be FED can be observed** (2026-08-03, `examples/board`,
  `examples/habit`). Both read an absolute HOST path their module never creates,
  so the only thing observable in the nix sandbox was a failure, and neither
  could state a witness -- which, since the observable gate landed, also meant
  neither could be re-minted (the prerequisite on the re-mint sweep). The remedy
  was a program edit, no kernel change: `board` reads the file named on the
  command line or standard input, `habit` takes the habit as its first argument
  and the log as an optional second, and its row spans the log's own earliest to
  latest date instead of "the last 365 days" ending today, so what the witness
  observes no longer depends on the clock. Both programs gained the plurality the
  website work argued for: three columns of which one is empty and one holds two
  cards, two contrasted mark characters. Each states one witness sentence, and
  generate observed both claims in the sandbox. Evidence that a claim is not
  decoration: the FIRST `habit` mint built source printing `#.` where the program
  says `#..#`, and generate refused it -- a minted-source defect every other gate
  passed. Model datapoint for the sweep: `board` minted clean with sonnet-5
  (which called `check_draft` three times); `habit` did not -- sonnet's passing
  attempt installed the same script twice (`$out/bin/<self>` AND
  `$out/bin/<value>`) so the claim's path would exist, while opus-5 built one Go
  binary named by the program's own word. Both models filed the same new gap
  under two slugs (`fixed-arity-witness`, `witness-entry-count`): a witness
  sentence listing N items has no repeating hole form, so the pattern is frozen
  at the arity the example happens to use.

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

- **A re-mint rewrites behavior the program never mentions** (found 2026-08-02,
  reproducible from files already in the tree). `examples/logscan` is five
  lines. Commit 885a900 added one of them, the worked example pinning
  `{"a":"1"}` against `a=1`, and re-minted. Comparing the committed
  `artifacts/logscan/main.go` with the previous mint's copy under `out/` shows
  the two differ in what the program DOES, not in how it reads: field matching
  gained numeric coercion through a new `asString` helper, so `a=1` now matches
  `{"a":1}` as well as `{"a":"1"}`; the bad-argument exit code moved from 1 to
  2 with new message text; the scanner's maximum line length moved from 10MB to
  16MB; argument splitting changed from `SplitN` to `Cut`. No program line asks
  for any of it, and the added example asks for a string match only.

  The promise this breaks is the one the whole loop rests on, that a mint
  RESTATES intent and invents nothing (deduce-or-fail; "lips never guesses").
  Every gate stays green while it happens: `.expect` pins option values, the
  claim observes the stated example, and neither looks at behavior nobody
  stated. An audit of the same file finds roughly fifteen of its 76 lines
  traceable to the five sentences; the rest is invented policy, including a
  silent `continue` on malformed JSON, which contradicts fail-loud doctrine
  under a green suite.

  RESOLVED for this program, 2026-08-04: `examples/logscan` was re-minted as
  CLAUSES and its 76 lines of Go are deleted from the repo. Five clauses replace
  them, each naming the sentence that caused it, and the grounding counter reports
  "1 option assignment, 5 clauses, 0 unvouched assertions" where it once reported
  80 lines vouched by nothing. The behaviour it drifted on is now pinned: the
  witness holds and a bad argument still exits 1. The measurements above are kept
  as the evidence that motivated the logic axis, in the past tense they now
  deserve; the two engines that produced them are committed under
  `experiments/logscan-mints/`.

  Two entries elsewhere name the same defect from other directions: the
  artifact-axis hole in "Silent concept demotion" (a compiled artifact records
  no dependency on the program lines its baked source came from), and the one
  AI-era failure the model-driven-engineering literature could not observe,
  non-determinism reintroduced at the generation step (Survey J). The remedy
  direction is "The Logic Axis" above, whose central gate is that a clause with
  no parent program line is refused; until that exists, the defect is open by
  design rather than by oversight.

### Missing
- **Artifacts: deferred pieces.** The core landed (see Done), a program value
  reaches inside baked source through a *fill*, and repeating source is settled as
  unnecessary (both in Done). Still open: dependency-fetching builders (a
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
  stays symmetric. The same subtraction one option over (`systemd.services`
  attribute names) yields the units the program ADDS, and each gets its own
  shell, `nix develop …#service-<unit>`: the tools plus that unit's
  `environment`, so testing a service by hand needs no manual `export` of what
  the module already states. This is the one thing the bare artifact rungs
  cannot give (no init, so no service env); it stays a SHELL, not a run rung --
  lips never emulates systemd, so `User`, `StateDirectory`, `EnvironmentFile`
  and the rest remain `vm`'s business, and the human runs the command. The name
  is flat (`service-<unit>`, not nested `service.<unit>`) because a nested set
  is not a flake leaf and `nix flake show` then refuses to list the units;
  prefixing is injective and never yields `default`, so a minted unit name
  cannot collide with the tools shell. Proven live: `ledger.backup` yields `restic-ledger` (the
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
    generalizes the former `<name.tail>`, its only spelling now). The FUSED hole
    closes the third form (see "The fused capture" in Done): literal text and
    holes inside one token, which is how a value pressed against punctuation --
    `println("<text>")`, `--port=<n>` -- is read at all. Blocks closed
    the last piece (see "Blocks" in Done): the deferred framing was wrong -- what
    was missing was never a decision that owns a list, but a line's ability to see
    the block it sits in.
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

### Limits of Scale (what the corpus does not show)

The ledger above measures physics, and the physics is nearly complete over its
chosen domain. It measures no size. Twenty programs of four to nine lines,
engines of ten to fourteen lines, and artifacts of one source file are the
whole evidence base, so every statement about large systems is extrapolation
from small points and is recorded here as such.

- **Intent does not compress.** A large application carries irreducible
  detail; lips relocates it from code into program lines rather than removing
  it. Scale therefore arrives as many small languages composing in one
  configuration, not as one large grammar, which makes the language the unit
  of scale (the analogue of a module).
- **Cross-language composition is accidental.** Two languages meet today only
  by realizing into the same option namespace. No decision refers across a
  language boundary, so contracts between languages have no representation.
  This is the missing physics for systems of several languages, and it is not
  yet needed by any committed example.
- **Engine churn is safe for modules, not for baked source.** "Solutions
  contain zero mechanism, so nothing above the engine can break" (§4) holds
  for the emitted module, whose every path is grounded in nixpkgs. A re-mint
  rewrites baked source outright, so on the artifact axis only claims hold
  behavior in place, and claims are two, single-shot, with three of five
  baked-source programs stating no observable at all (`TODO.md`, item 1).
  Growing artifact size before claim density therefore reproduces the
  untrusted-artifact problem lips exists to abolish.
- **Minting is whole-engine.** Engine size multiplies the cost and the blast
  radius of every new sentence, gated only where `.expect` pins something (and
  not at all where `.expect` is empty). Invisible at a page; dominant at
  hundreds of rules.

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
- **No per-program source written by a model (settled 2026-08-04, gated).** A
  blob is admissible only where it is NOT per program and reviewed once (an
  adapter under `assets/runtime/`, serving every program), or where it is somebody
  else's package reached by name. Behaviour a program states goes in clauses.
  Where no contract covers the capability the behaviour needs -- files, clocks,
  sockets, as `experiments/validate` measured with `rotate` -- baked source stays
  admissible, because refusing it would refuse the program rather than the
  mechanism. What is NOT admissible either way is behaviour nothing observes:
  `generate` now REFUSES an engine that bakes source with no claim, and one that
  mints clauses with no claim over them, naming the one sentence that fixes it.
  `logscan` spent months as the counter-example (76 lines of Go, roughly fifteen
  traceable, two mints disagreeing about what the program did, every gate green)
  and is now clauses.
  The escape for a genuine one-off is a VALUE, never a file: `greet`'s four words
  of bash are bounded by sitting in one assertion attached to one program line,
  where a staged tree has no such bound and grew to 76 lines. Two grades deserve
  different trust: AUTHOR glue, whose foreign text is in the program, is
  legitimate without qualification; MINT glue, where the model chose it (`echo` in
  `greet`), is admissible but counted (`Lips.Kernel.Grounding`) and pinned by a
  claim, since it is exactly what a re-mint rewrites.
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
- **A hole is grounded from outside or by plurality, never by wishing.** Two
  regimes, and they ground a hole differently. A hole reaching a TARGET OPTION
  is grounded externally: nixpkgs defines what `networking.firewall.allowedTCPPorts`
  does and the schema pin checks the name, so ONE occurrence is fine and a port
  named once is real. A hole reaching BAKED SOURCE has no such anchor, and
  plurality inside the program is the only static evidence that it is causal:
  shown one instance, a mint may fold it into a constant and should, since a
  hole nothing varies is a lie; shown two that differ, a single hardcoded
  behaviour cannot serve both and a dispatch must appear. So a behaviour word
  earns its hole by being contrasted, and an engine minted from a one-instance
  program is honest about one instance only. Consequence for authors: to teach
  a language a distinction, write the distinction, do not describe it. This is
  why more program richness, not more prompt or more direction, is what deepens
  an engine -- direction is advisory taste and cannot make a sentence causal.
  Corollary already visible in the corpus: `logscan` demotes 4 of 5 lines to
  `Concept` and every one of them is a singleton behaviour sentence.
- **Forking is safe by design.** lips is defined by the calculus + conformance
  suite, not the repo; the reference implementation is non-privileged. A fork
  that keeps the suite green IS lips (`inputs.lips.url = github:you/lips`);
  fork-as-overlay (patch + tests, rebased, upstreamed, then deleted) is the
  sanctioned fast path; only editing the suite itself mints a dialect.

### Shortest Summary

The deterministic spine, the language-crystallization loop, and whole-engine
synthesis are real and tested: lips now mints an engine for an unseen domain
and absorbs edits offline. A **live host deployment** has now run and
switched on a real machine (§13, "Live host deployment"), which is also what
surfaced and closed the one bug a VM-only test suite could not see (the same
section, "nixosModules/homeManagerModules ... now actually importable").
Everything else is hardening or breadth.

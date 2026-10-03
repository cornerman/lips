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

By 2026 the thesis above is measured rather than argued. Sonar's 2026 State of
Code Developer Survey (1,149 professional developers, fieldwork October 2025)
finds 96 percent of developers not fully trusting the functional accuracy of
AI-generated code while only 48 percent always check it before committing,
with some 42 percent of their code AI-generated or assisted; 61 percent report code that
"looks correct but isn't reliable", and 38 percent find reviewing it costlier
than reviewing human code, the burden AWS CTO Werner Vogels named *verification
debt* at re:Invent in December 2025.
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
not die, it narrowed. Whittle, Hutchinson and Rouncefield, surveying 450
practitioners and interviewing 22 more, report that developers "rarely use it
to generate whole systems; rather, they apply it to develop key parts of a
system often using domain-specific modeling languages developed specifically
for the purpose", and that "adoption largely depends on social and
organizational factors" ("The State of Practice in Model-Driven Engineering",
IEEE Software 31(3):79-85, 2014, doi:10.1109/MS.2013.65). Petre's
fifty-engineer study found zero of fifty using UML the way its promoters
described ("UML in practice", ICSE 2013, doi:10.1109/ICSE.2013.6606618).
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
The remaining formal debt is recorded the same way: termination of
refinement is enforced by a step budget (fail fast), not proved. A
critique-resistant calculus is one whose gaps are named, not one that
claims none.

**The IC-postulate audit.** Konieczny and Pino Pérez's postulates for merging
under integrity constraints (IC0-IC8, *Merging Information under Constraints: A
Logical Framework*, Journal of Logic and Computation 12, 2002; summarised in the
Stanford Encyclopedia entry "Belief Merging and Judgment Aggregation") are
stated for a profile of EQUALLY RELIABLE propositional bases. lips is a
different animal in three stated ways, and the audit is the honest mapping
rather than a claim of membership.

First, the reading. A lips base is not a profile of agents: each decision
carries a STRENGTH (system default < engine default < program), so `resolve` is
a *prioritized* merge, and the strength order is the whole point. Second, there
are no integrity constraints: `IC` is the tautology, since what a target world
permits is checked by option grounding at `generate`, not by merge. Third, the
"language" has no connectives -- an assertion is opaque text under a subject, so
two decisions interact only when their subjects are equal, and assertions are
compared as TEXT.

Under that reading: IC0, IC7 and IC8 are vacuous (they constrain the behaviour
under a non-trivial `IC`). IC1 holds in a stronger form than stated -- `resolve`
returns one winner per subject, so its result is consistent by construction --
but with a deliberate difference in the failure case: an IC operator always
returns something consistent, while `resolve` REFUSES an equal-strength
disagreement and names both provenances, because arbitrating it would be the
silent choice lips exists to prevent. IC2 holds: a profile with no
disagreement resolves to exactly itself. IC3 (irrelevance of syntax) holds only
SYNTACTICALLY -- two assertions that mean the same and read differently count as
dissent, which is the price of a domain-blind kernel that cannot know what a
value means. IC4, the fairness postulate, is deliberately violated, and this is
what "prioritized" means: strength gives one decision priority over another, so
lips is neither an IC majority operator nor an IC arbitration operator in their
sense. (Maj) is violated for the same reason and on purpose -- repeating a
decision changes nothing, since a base is a SET and authority is not a vote
count.

IC5 and IC6 hold for `Replace` subjects, the scalar default: when the winners of
two bases agree, merging the bases keeps exactly those winners. IC6 FAILS for an
`Append` subject, and that is the stated exception -- laying two bases together
assembles `[x, y]` where each alone assembled `[x]` and `[y]`, so the merged
result does not entail either. Aggregation is a list-building operation, not a
selection among alternatives, which is precisely why it is a separate merge mode
derived from the engine rather than the default reading.

What the suite pins, over arbitrary generated bases rather than worked examples,
is the property the calculus actually rests on: *merge is a set operation*.
`resolve` is invariant under permutation of the base (commutativity), under how
the base is split before being laid together (associativity), and under laying a
base over itself (idempotence); the `Append` mode obeys the same laws, since it
sorts its contributors by id rather than taking them as they arrive
(`kernel/test/Spec.hs`, "merge algebra").

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
  word asks for. Regeneration IS the branch, and the engine is disposable by
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
- ~~**Is lips robust against reformulation?**~~ ANSWERED as a stated
  position, not as a mechanism (raised 2026-08-11 by an outside reader, whose
  words were: something has to be losing semantics or flexibility somewhere).
  lips is deliberately NOT robust against paraphrase, and that rigidity is what
  the deterministic compiler costs. Reading a reworded line as the same line
  means a model decides at read time, which makes `compile` nondeterministic and
  takes the reviewable artifact, the edit-and-recompile loop and reproducibility
  with it. The fuzziness has exactly one door, `generate`; behind it, matching is
  literal token by token, normalized only by lowercasing (`normalizeToken`, no
  morphology, punctuation belongs to the token). A reworded line therefore fails
  loud (`no match`, exit 1, naming `lips generate`), never silently.

  Where the flexibility went, rather than vanished: the value/mechanism
  distinction above ("Branching on a captured word"). A word that FILLS A VALUE
  sits in a hole and is edited freely with no mint; a word that SELECTS A
  MECHANISM is a template literal, and rewording it costs a mint. Regeneration
  is the branch a flexible language would take at read time.

  Three honest costs, none of them repaired by this answer. (i) Paraphrase by
  accumulating patterns does not scale for free: two patterns that could match
  one line are refused statically (`Engine.Overlap`), so synonyms spelled with
  different literals are cheap while near-paraphrases collide, and
  `grammarIsFrozen` prices one pattern change as a mint over every world of the
  language. (ii) The one SILENT case is a sentence whose words never reach the
  artifact: a behaviour sentence is a specification for the mint, so rewording it
  without re-minting leaves every gate green (backlog item "Silent concept
  demotion" (ii), where it is recorded as having no static remedy; claims
  falsify by observation instead). (iii) Whatever the grammar does not cover is
  refused, not approximated -- invariant 2. Nothing is lost there, but nothing is
  sayable either until the next mint.

  The falsifiable half is the next entry: if paraphrase pressure decays on a
  real growing program, the objection is practically answered; if it plateaus,
  the objection wins and no kernel work repairs it. The one argument available
  in the meantime is not evidence: the language inherits its vocabulary from the
  author's own prompts, so the pressure is bounded by how one author speaks
  about one domain, not by what the natural language allows.
- ~~**Can a parameter be a sub-prompt rather than a constant?**~~ ANSWERED by
  subtraction (2026-08-11): yes, and it needs no kernel physics. The model runs
  in the RUNTIME OF THE BUILT PROGRAM, reached by name like any other package,
  so lips only ever sees a string value on a program line and invariant 1 holds
  untouched. Two residues, both existing items: a claim over such a program
  cannot state an exact observable, and a paragraph-length prompt has no
  multi-line value form, since a capture ends at the line.
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
- ~~**Does specificity beat generality?**~~ RESOLVED 2026-08-05, as a refusal.
  Strength stays *lex superior* only (a higher authority wins); *lex specialis*
  (the more specific norm wins) is not adopted, for three reasons. It has no
  meaning here except "a longer subject path shadows a shorter one", which is
  the defect refused by name five days earlier (§13, "A clause subject is
  exactly `clause.<name>`"): `clause.main.extra` silently took over
  `clause.main`, and both passed every gate. What an author actually means by
  specificity in a configuration -- a per-instance decision beating a
  language-wide default -- is already lex superior, since a program's decision
  is `Stated` and a default is not, so the expectation is served without a
  second rule. And it would cost the set law: under lex specialis the winner
  for one subject would depend on which OTHER subjects the base holds, so
  `resolve` would stop being a per-subject function of the set (§2, the IC
  audit). Subjects that differ are independent, and a base that wants a
  narrower rule states it under the narrower subject. Survey F, seam 4.
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

- **A compiled directory runs the nixpkgs its rules were grounded against.**
  A mint grounds its rules against the `schema:` pin it records in
  `.generation`, while a compiled directory's `flake.nix` said
  `inputs.nixpkgs.url = "flake:nixpkgs"`, so nothing related the two: on
  2026-09-18 `examples/policy` was admitted by nono 0.68.0 and its render
  judged by the 0.74.0 the registry resolved (TODO 2a). Now
  `Lips.Nix.Flake.compiledNixpkgs` reads the world's pin out of the record's
  header (`Generate.Record.worldSchemaPin`, every record shape) and `flakeText`
  writes it verbatim as the nixpkgs input, `?narHash=` included; nix accepts
  that url and refuses a wrong hash ("NAR hash mismatch"). The flake's
  `description` says which nixpkgs it names. `check`'s claim gates build the
  same flake, so they observe the nixpkgs the mint's own gates observed, and
  `worldGate` writes its pin into the flake instead of passing
  `--override-input`. `compile` still fetches nothing and stays bit-identical:
  the pin is text in the committed record.

  Prevention, not comparison: with the evaluator equal to the grounding there
  is nothing left to warn about. The trigger is domain-blind: a world whose
  `schema-pin:` header names the substrate var `LIPS_NIXPKGS_FLAKE` grounds on
  the nixpkgs the flake skeleton imports, which is the only case where the two
  are the same flake. So nixos and nono pin with no world-file change and no
  re-mint (9 example languages: cron, function, hello, http, logscan,
  packages, policy, timer and website, each compiled with the branch binary),
  and a house world declaring the same header pins too. Everything else stays `flake:nixpkgs` and says so: a record
  that predates the pin (9 languages, e.g. `backup`), a document pinned by
  content (`options-json:`), and a world whose pin names another flake
  (home-manager). Measured 2026-10 with the branch binary:
  `compile dev.policy.lips` writes the pin; `nix flake metadata` reports rev
  61b7c44 even over a stale `flake.lock` that held a32edd7; nono there is
  0.68.0, and `#profile` builds and validates.

  Declined, with reasons: comparing revs in `lib.modulesFromDir` (a consumer
  following unstable differs on almost every eval, so a warning there is noise;
  README now says an imported module evaluates under the importer's nixpkgs),
  and per-option fingerprints (they cannot work for nono, whose schema is
  top-level only). Still open in TODO 2a: kubenix and terranix inputs float,
  and a mint's builds ignore `--schema`.

- **A world's own gate runs at mint time.** A world file may now carry an
  optional `--- gate ---` slot: one derivation, written in the scope of the
  `packages` slot, whose successful build is the world's own verdict over a
  render. `flakeText` emits it as `packages.<system>.gate`, a name lips owns as it
  owns `claims` and `site`, and a world without the slot compiles byte-identical
  (checked by compiling all 23 example programs with the binary before and after,
  `diff -r` empty). `examples/nono.world` declares `(builds system).profile`,
  the build that runs `nono profile validate`, and moves to `format: 2`, so a lips
  that predates the slot answers "upgrade lips" instead of "unknown slot gate".
  The four shipped worlds stay at format 1 and declare no gate.

  `Lips.Gate.worldGate` writes the directory exactly as `compile` does (one
  writer, `Lips.Stage.writeCompiled`, now shared by both) and builds `#gate`
  with `--override-input nixpkgs` set to the locked `LIPS_NIXPKGS_FLAKE`. The
  validator is therefore the nono the schema came from (0.68.0), never the one the
  ambient registry happens to resolve (0.74.0 on 2026-09-18, TODO 2a). `generate`
  runs it per program after the contract, beside the artifact and claim gates.
  `check --draft` runs it too, so a model reads the validator's refusal inside its
  own call. The first nono mint was accepted broken and cost $0.74 to discover
  it; the same refusal is now one resubmission. `check` and `compile` stay
  nixpkgs-free and do not run it; the world's own `#profile` build still refuses
  an invalid render where it is used.

  Measured by hand, 2026-10-03: a one-line nono draft whose command entry carries
  no `sandbox` object is refused in 6.3s, carrying nono's own words ("data did
  not match any variant of untagged enum CommandFromConfig"); adding
  `sandbox.fs_read "[ ]"` passes in 1.8s. `just test-draft` now pins both
  directions.

  MEASURED, one opus-5 patch re-mint of `examples/dev.policy.lips` into the
  gated `nono` world, 2026-10-03: 33s, 1 submission, $0.19. The reply patched
  only the report (`d1`), the rules came back identical apart from their stamps,
  and the mint printed the gate as a step of its own ("the nono world's own
  gate", 0.6s), the first live run of the mint-side path. A misfired first
  attempt without `-t nono` minted a nixos lowering instead ($0.29, deleted
  before commit); `-t` defaults to nixos even for a language committed
  only in nono, which surprised its operator once.

  CI half: `lipsModules-eval` compiles every attribute `modulesFromDir` produces,
  found by looking, so `nonoModules` is no longer outside the net. The new check
  `lipsWorld-gates` imports each compiled directory's `flake.nix`, calls its
  `outputs` with this flake's own inputs, chosen by the argument names the
  outputs function asks for, and BUILDS every `packages.<system>.gate`. It
  refuses to pass with zero gates. No world is named in either check.

  Deliberately not done: only `nixpkgs` is overridden, so a world whose flake
  has other inputs (kubenix, terranix) would build its gate against an unpinned
  input. Those worlds declare no gate yet (TODO 6). nixos has no cheap gate to
  declare, since its only candidate is a system build.

- **A list within one sentence (`<p.list:,|or>`).** A template hole may bind a
  run of tokens and cut it into ITEMS on the separators the engine declares;
  every emit mentioning the hole is produced once per item, with `<p>` the item
  and `<p:index>` its position. One pattern then reads the sentence at any item
  count. Before it, a list-shaped sentence had to be spelled once per count:
  `examples/policy` carried 24 arity clones (`pr1..pr4`, `px1..px4`, ...) and
  refused `it may run git, rg, ls, cat and jq.` outright. An enumerated arity is
  an open list with an arbitrary stop, so this was a missing grammar case, not a
  program defect (the same freeze TODO 1c files for witness sentences).

  The kernel learns no conjunction: `,` and `or` come from the engine, as a
  block's marker does. Separators are a `|`-separated list whose items are bare
  words or `"..."` spans with `Lips.Kernel.Surface`'s escapes, so a language may
  list on a pipe (`<c.list:"|">`), on an angle bracket or on two words
  (`<c.list:","|"and then">`) with no second escaping scheme. A quoted item is
  atomic, since the quote is the mark that says "these characters are a value";
  a word separator has no glued form, so `/etc/curator or /etc/shadow` cuts once.
  A comma the sentence itself carries after the last item is punctuation, not an
  empty item.

  MEASURED, one opus-5 `--fresh` re-mint of `examples/dev.policy.lips` into
  `nono`, 2026-09-19: 3m04s, 8 turns, 13,994 output tokens, $0.73. The grammar
  came back at 8 patterns instead of 30, with every arity clone gone and three
  separators declared (`<p.list:,|and|or>`). The committed `.expect` (7 checks)
  was untouched and still holds, so invariant 5's gate passed on the re-mint,
  and `it may run git, rg, ls, cat, jq, fd and sed.` crystallizes with no kernel
  and no grammar change -- the completeness test for the construct.

  THE SECOND DEPTH, landed the same day: an ITEM PATTERN `p10.each.p9.e` reads
  ONE item of `p9`'s list hole `e`, so an item may bind several holes. It is a
  nested pattern whose block is a HOLE rather than a run of lines, which is why
  it cost no new scope machinery: the parent stays in `pParents`, so scope,
  `<k:key>` families, the cycle gate and the unbound-in-scope gate read it as
  any other child. What differs is where its tokens come from. Its `<n:index>`
  is the item's position, its captures shadow the parent's, and an item no child
  reads fails the line naming that item (`NoItemPattern`) -- deduce-or-fail at
  item scale, since half a list read is worse than none. Two guards keep the
  form honest: an item pattern must name a LIST hole of its parent
  (`NotAListHole`), and nothing may nest under an item (`BlockUnderItem`), which
  reads part of a line and therefore heads no block.

  MEASURED, one opus-5 `--fresh` re-mint of `examples/habit.lips` into
  `home-manager`, 2026-09-19: 8m00s, 32,506 output tokens, $1.29. It used both
  depths unprompted by anything but the paragraph in `assets/mint/body.md`:
  `p9` cuts the entries, `p10.each.p9.e` reads `<d> for <h>` into
  `witness.<q>.entry.<n:index>`, and `r10` aggregates those per-entry facts into
  `claim.<q>.feed` -- the Append path that already assembles
  `filesystem.read`. The witness now reads at ANY entry count, verified by
  running it: a two-entry and a five-entry `habit` program each crystallize and
  each pass their clause claim, which builds the tool and compares its real
  output (`#.` and `#.#..#`).

  WHAT IT COST, recorded because invariant 5 fired exactly as designed: the
  first re-mint (8m00s, 35,262 output tokens, $1.48) kept the committed
  `.expect`, which pinned the printed output to PART 8 of the old eight-part
  witness fact. The mint padded the new assertion with seven copies of `<q>` to
  hold that position and filed the gap `contract-part-shape` itself ("it is ugly
  and it carries no meaning"). A contract about a fact that no longer exists is
  a human decision, so the `.expect` was deleted (the documented re-bless) and
  the language re-minted; the second engine carries no padding.

- **A world lips never heard of, minted without touching lips.**
  `examples/nono.world` targets nono (https://nono.sh), a capability-based
  sandbox that runs an agent under a JSON policy and has no Nix module
  anywhere: `lips options nono` finds nothing in nixpkgs and nothing in
  home-manager, only the package. The world file sits beside the program, where
  `Lips.World.Resolve` looks first, so nothing in `kernel/` or `assets/worlds/`
  changed and the README's claim that an unforeseen world costs no lips change
  has its first committed instance.

  Grounding comes from the tool's own published schema. The `--- schema ---`
  slot runs `nono profile schema` out of the pinned nixpkgs and a jq pass keeps
  the 28 top-level sections, mapping JSON Schema types onto the type wording
  `Lips.Nix.Options` classifies. It is WEAK on purpose, as in terranix: the
  lookup confirms a section and calls every field below it free-form. What
  holds the deeper names to account is nono's own validator, which
  `--- builds ---` runs over the rendered profile, and which names an unknown
  field (49 of the 51 object definitions in that schema are
  `additionalProperties: false`).

  MEASURED, two opus-5 mints of `examples/dev.policy.lips` (7 permission
  sentences), 2026-09-18. The first took 3m49s, 17,373 output tokens and $0.74,
  and was accepted; `nix build path:...#profile` then failed, because nono
  refuses a `from.<caller>` entry carrying only an `invocation_policy` ("data
  did not match any variant of untagged enum CommandFromConfig") and refuses an
  `approve` entry with no approval backend (`missing_approval_backend`). Both
  are facts about the world, so the remedy went into the world's preamble and
  not into the output (invariant 4). The patch mint that followed cost 60s,
  4,153 output tokens and $0.33, and moved three lines (`r1`, `r5`, `d1`):
  `r5` now emits an empty `sandbox` object per command, `r1` declares the
  terminal approval backend once. Total $1.07, against $3 to $4 for a
  service-shaped nixos mint.

  THE GAP this leaves, stated because it is why an invalid engine was accepted
  (CLOSED 2026-10-03, "A world's own gate runs at mint time" above):
  `generate` never builds a world's `builds` slot, so the validator is a
  build-time gate, not a mint gate. `nix flake check`'s `lipsModules-eval`
  enumerates the four shipped world attributes by name, so a local world's
  `nonoModules` sits outside it as well. The validator runs today only when a
  human runs `nix build path:examples/policy/out/dev/nono#profile`.

- **Where the rules make something RUN, one claim must boot -- and it caught the
  broken example on the first try.** `examples/website` shipped a unit that could
  not start for eight days with every gate green: `StandardOutput=file:` into a
  `StateDirectory=` that systemd creates only after it opens that file
  (reproduced outside lips in a NixOS test carrying nothing but that pair). No
  static gate can see it -- an expect compares the value the rule wrote, and a
  clause claim runs a definition with no systemd around it -- and the kernel may
  not learn what an option MEANS (an open list the doctrine forbids).

  The steering that produced it was in world DATA, so that is where the fix went:
  `assets/worlds/nixos.world`'s preamble said "prefer an observable over the
  program's own binary" (true for a binary, and it left the unit wiring
  unobserved). It now adds the exception -- when the rules wire a unit, a timer or
  a served port, one claim's command must reach the SYSTEM (`systemctl is-active`,
  a curl against the port), and the boot is worth paying for. No kernel change:
  `PlaceMachine` claims, the VM gate and the KVM refusal all existed already;
  what was missing was a mint being told when to use them.

  MEASURED, three opus-5 mints of `examples/website.lips`, 2026-08-20:

  1. **Blind re-mint, old steering** (before this change): emitted the same
     failing `StandardOutput`/`StateDirectory` pair, accepted, 17m44s, 80,945
     output tokens, $3.10. A defect no gate reports does not fix itself.
  2. **New steering, `--fresh`**: emitted a machine claim, the gate booted a VM,
     the claim FAILED (`claim serving: exit was 7` -- darkhttpd rejecting its own
     `--addr`, the same wiring that failed on 2026-08-12), and generate REFUSED to
     write anything. 17m14s, 81,022 output, $3.23, recorded as
     `verdict: refused at claims: 2 claims`. The hole is closed: a wiring that
     cannot start can no longer be committed.
  3. **New steering plus a `website.direction`** naming the mechanism taste that
     was missing (serve with `services.nginx`, and let a unit's command write its
     own file rather than routing stdout into a path): ACCEPTED, booted, 24m40s,
     110,257 output, $4.20. `nix flake check` is green for the first time since
     2026-08-12, `artifact-vm` included -- the check that would have caught this
     all along, which was itself dead (it copied an artifacts tree the 2026-08-12
     re-mint had shed).

  What run 2 also settles: the round loop is still the missing piece. A refused
  mint costs a full round ($3.23 here, now recorded rather than guessed), and
  nothing carries the boot failure back into the next call -- the human does, as a
  direction file, which is exactly what run 3 shows working.

  A REVIEW CORRECTION, because the first version of this got the layering wrong.
  Run 3's direction file carried two sentences, and only one of them was taste.
  "Let a unit's command write its own file rather than routing stdout into a
  path" is a fact about systemd that holds for EVERY program minted into this
  world, and it sat in one program's taste file, where exactly one program could
  see it -- so the next program would pay a boot to rediscover it. It now sits in
  `nixos.world` beside the boot rule, and `website.direction` keeps only the
  mechanism preference (a module that builds its own config, over a hand-written
  listen argument), which is what direction is for.

  The deeper reason a human had to write either sentence is worth naming plainly:
  a refused mint teaches nobody. Run 2 spent $3.23 discovering a boot failure and
  nothing carried that finding into run 3 except a person typing it into a file.
  Direction was standing in for the missing round loop, which is a workaround, not
  a design -- and by the repo's own rule a workaround belongs in the physics. The
  price is now on the record (a refused round of this size: $3.23, 17 minutes).

  One honest wart in the accepted engine, filed by the mint itself rather than
  hidden (`inherited-contract-pins-darkhttpd`): the committed `.expect` still pins
  `services.darkhttpd.port` from the mechanism that is gone, so the nginx engine
  assigns that option too (darkhttpd stays disabled) to keep the inherited
  contract true. The mint named the remedy in its own report -- re-mint with
  `--compat none`, the human decision the compat door exists for -- rather than
  dropping a contract line on its own authority.
  CLOSED 2026-09-20 by exactly that remedy ("The website defect closes", below):
  `--fresh --compat none` rewrote the contract from the accepted engine, and no
  `darkhttpd` name survives in the grammar, the rules or the `.expect`.

- **`compile --watch`: the edit loop, and one key to grow the language.** Compile
  is deterministic, offline and takes milliseconds, so re-running it on every save
  costs nothing -- yet an author had to type it, which is what makes a loop feel
  slow even when the tool is fast. `--watch` (`-w`) polls the program, its
  `<language>.direction` and its engine (the shared grammar plus every world's
  rules -- `Lips.Identity.watchedFiles`, pure and tested) four times a second and
  compiles again on any change. Derived output is deliberately not watched: `out/`
  is what compile writes, and watching it would make the loop feed itself.

  When a line does not crystallize the loop prints the remedy it always printed,
  and then OFFERS it: `g` runs `lips generate` on the program, `q` quits. The
  offer appears ONLY after a failed pass, and `g` refuses on a green one, naming
  `--fresh` for the deliberate case (review correction, 2026-08-20: the first
  version printed the offer on every pass, which invites a model call nobody
  needs -- a green pass means the language reads every line, so growing it buys
  nothing, and an offer standing there spends money on a stray keypress).
  Invariant 1 is intact and the code says so where a reader would doubt it --
  compile never calls a model; the loop is a driver around two verbs, and the mint
  runs as a separate process with every gate of an ordinary mint. A failing pass
  does not end the loop (a program the language cannot read yet is the NORMAL
  state of an edit loop), while `compile` alone still exits nonzero, which is what
  CI reads.

  Two things measured rather than assumed. Polling, not inotify: the dev shell has
  no fsnotify, and half a dozen `stat` calls four times a second are invisible --
  a poll also cannot miss a file that does not exist yet, like the grammar the
  next mint will write. And `hWaitForInput` is the obvious call for "is a key
  waiting" and the wrong one: with `NoBuffering` it blocks past its timeout, so a
  file touched ten seconds in went unnoticed for thirty. `hReady` after a
  `threadDelay` answers now. Watch mode refuses loud when stdin is not a terminal,
  since single keypresses are the whole interface.

  Verified: 909/909, `-Wall` clean, and by hand in a pty -- a save triggers a
  second pass, `g` spawns the mint (which refuses cleanly in a shell without the
  packaged pins, and the loop carries on), `q` restores the terminal and stops.

- **The growth mint: a language grows by a PATCH, not by a rewrite.** Adding one
  sentence shape to a working language re-minted the whole engine, so the one act
  that leaves the zero-AI loop was also the most expensive one, and it recurs
  every time a language grows. `generate` against a language that already has a
  committed engine now renders that engine back into the reply format
  (`replyLinesOf`), hands it to the model as its basis (`assets/mint/patch.md`),
  and asks for a patch keyed by id: a new id adds, a known id replaces, an id the
  reply does not mention stays. `--fresh` rewrites.

  The patch is merged into a complete reply BEFORE anything reads it
  (`mergeReply`), so every gate, every render and every write below is untouched
  and knows nothing about patches -- the soundness argument is that the gates,
  not the rewrite, are what guard an engine, and they already run over the whole
  corpus. `check --draft` merges identically, told the basis directory through
  `LIPS_MINT_BASIS`, so what the model checks is what the gate will judge; a bare
  patch with no basis is still refused as an engine that cannot read its program.

  MEASURED, `examples/greet` grown from one line to three (a second command and a
  daily schedule), claude-sonnet-5, thinking medium, 2026-08-20, against errand
  1's fresh baseline for the ONE-line version:

  | | fresh (1 line) | patch (3 lines) |
  |---|---|---|
  | wall | 326.4s | 74.5s |
  | turns | 6 | 4 |
  | `submit_draft` calls | 4 | 1 |
  | output tokens | 26,598 | 3,765 |
  | cost | $0.43 | $0.068 |

  So a bigger program cost 4.4x less wall time, 7.1x fewer output tokens and 6.3x
  less money, because the model emitted the two lines it authored instead of
  restating the engine four times. Output is the side that is neither cached nor
  cheap (input arrived as 8 fresh tokens against 99k from cache), which is exactly
  what errand 1 predicted.

  Two decisions the implementation forced, both recorded because they are not
  obvious. (i) A patched engine is RE-STAMPED wholesale rather than keeping each
  untouched line's original `@gen:` id. The first attempt kept them, and `check`
  refused it correctly: a stamp means "the record beside me hashes to this", there
  is one record per world, and a kept stamp names a record that is no longer
  there. Re-stamping stays honest because the record stores the MERGED reply, so
  it really does contain every line the engine holds; where a line came from is
  carried by the new `basis:` line, which names the record this one grew out of
  (a chain), and by git. (ii) `basis:` is a sealed input in `.generation`, so a
  patch and a rewrite of the same reply are different events with different ids.

  Accepted cost, now visible rather than assumed: prompt and physics improvements
  stop reaching committed languages until someone runs `--fresh`, and the record
  says which basis produced each engine. One asymmetry of the stored form had to
  be undone to make any of it work: a pattern's stored assertion drops the
  `pattern` keyword the reader consumed, so `replyLinesOf` restores it from the
  subject -- without that, every inherited pattern comes back as a line no reply
  parser accepts and every program stops crystallizing (caught by the offline
  draft case now in `just test-draft`).

  Verified: 907/907, `-Wall` clean, `check` green on all 13 examples,
  `test-draft` green including two new cases (a patch with a basis holds, the
  same patch without one is refused).

- **A mint now says what it cost, and the first measurement says where the
  minutes go.** Every figure about a mint was hand-copied from whatever a
  terminal still showed: `Lips.Cli.Output` timed each phase for the live line and
  dropped the number, and pi reported turns, tokens and dollars in its json
  stream, which lips parsed for the reply and the transcript alone. So the one
  question the feedback cycle turns on -- what is slow, and why -- had no data.

  `generate` now writes `<language>/<world>/<lang>.timing` (a joint mint writes
  one at the language level, the scope its record and its refusal artifact
  already use): verdict, model, thinking level, total wall time, one line per
  phase, model turns, one line per tool with its call count, tokens by kind, and
  pi's own dollar figure. The file is UNSEALED and cannot be otherwise: the
  record's bytes hash to the id every minted line is stamped with (invariant 6),
  so a duration inside it would give two identical mints different ids and break
  every stamp. Sealed inputs in `.generation`, observed costs beside it.
  `verdictOf` derives the verdict from the phase log, so the file cannot disagree
  with the `✗` the terminal printed, and the write hangs off `finally`, so a mint
  refused by a gate -- which cost a whole round -- is recorded exactly as an
  accepted one is. A run that dies before the model answered writes nothing (no
  cost to report, and a lone `.timing` beside no engine would be a file about
  nothing).

  MEASURED, `examples/greet.lips` minted fresh for `nixos`, claude-sonnet-5,
  thinking medium, 2026-08-20: wall 326.4s, of which the mint phase 324.0s
  (99.4%) and everything lips does 2.1s -- which reproduces the earlier
  "lips is under 1%" figure on a second program. 6 turns, 1 `query_options`
  call, 4 `submit_draft` calls. Tokens: 12 fresh input, 205,148 cache-read,
  50,975 cache-write, and **26,598 output** for an engine of one pattern, one
  rule, one demand and one expect. Cost $0.43.

  The output figure is the finding. A one-rule language spent 26.6k output
  tokens because the whole engine is re-emitted on every draft, and output is
  the side that is neither cached nor cheap: input arrived almost entirely from
  cache (205k read against 12 fresh). That is the evidence behind the growth mint
  (`docs/superpowers/specs/2026-08-20-mint-feedback-cycle-design.md`): a patch
  keyed by id emits a few lines instead of a whole engine, and the prompt it
  grows from is the cached side.

  Verified: 899/899, `-Wall` clean, and the numbers above are read from the file
  the run wrote.

  SECOND DATAPOINT, and the first on a real artifact-bearing mint:
  `examples/website.lips` re-minted for `nixos`, claude-opus-5, thinking medium,
  2026-08-20. Wall 1063.6s (17m44s), of which the mint phase 1061.1s. 13 turns,
  13 `query_options` calls, 5 `submit_draft` calls. Tokens: 26 fresh input,
  780,437 cache-read, 109,338 cache-write, and **80,945 output**. Cost $3.10.
  So the shape `greet` showed holds at scale and gets worse: output grew 3x with
  the engine, fresh input stayed near zero, and the whole engine was emitted five
  times because each draft re-states it.

  That mint also measured something the stats file cannot see, and it is the
  reason the run was made: a blind re-mint does NOT converge on a defect no gate
  reports. The engine it replaced fails to boot (TODO, `StandardOutput=file:`
  opened before `StateDirectory` is created), and the fresh mint, told nothing
  about that failure, emitted the same pair again -- for $3.10. The re-mint was
  reverted, since a new engine with the same defect is churn. What that argues
  for is domain-blind and belongs in the preamble, not in a per-program file:
  where a program's own words describe a RUNNING service, its claim must observe
  the booted machine, which is what makes generate's claim gate boot a VM and
  refuse the engine inside the call that wrote it.

- **A house world's Nix is checked by nix, before anything is minted with it.**
  `Lips.World.parseWorld` was strict about STRUCTURE (an unknown header, an
  unknown slot, a newer format all refuse naming the offender) and blind to what
  the Nix-bearing slots hold, because they are pasted verbatim into the compiled
  flake and the schema expression. So a typo in a hand-written world file
  surfaced at nix naming the GENERATED `flake.nix`, a file the human never
  wrote, and only at the first compile. The built-ins were covered by the suite
  and the flake checks; a house world, which is the whole point of worlds being
  data, was covered by nothing.

  `lips world --check [<name>]` now hands every Nix-bearing slot (`schema`,
  `inputs`, `builds`, `packages`, `apps`, `devShells`) to `nix-instantiate
  --parse`: syntax only, offline, nothing evaluated and nothing fetched, and
  nix's own parser is the authority (lips owns no second one). Named, it checks
  one world; unnamed, every world reachable from here, which is the same default
  the listing takes -- including a local file that took a name lips ships, since
  a check that skipped it would call the directory sound.

  What makes the message worth reading is the slicing (`Lips.World.Check`,
  `nixSlices`, pure and unit-tested): a slot's lines land on THEIR OWN LINES of
  the file, every other line blanked, and the fragment's wrapper (`{`/`}` for
  the attrset slots, `let`/`in null` for `builds`, mirroring how
  `Lips.Nix.Flake.flakeText` embeds each) rides the marker lines that already
  fence the slot. So nix reports `house-k3s.world:37:51` with a real source
  excerpt, and the caller only swaps the scratch path for the real one. Every
  slice opens with `with {};`, because `--parse` also resolves variables
  statically and a slot legitimately reads names its surroundings bind
  (`nixpkgs`, `pkgsFor`, the world's own `builds`); under a `with` those lookups
  become dynamic, so an unbound name is no longer an error while a syntax error
  still is. Whether a name EXISTS is the compiled flake's question, answered at
  eval, where the scope is real.

  Deliberately NOT at compile time: compile is offline-and-deterministic over a
  hash-pinned copy that already compiled once, so a per-compile parse of an
  unchanged file buys nothing. The seam is authoring time, once.

  Testing splits along the nix boundary: the suite covers WHICH TEXT nix is
  handed (it cannot run nix -- its own build sandbox has none), and the
  `world-slots` flake check runs the real binary over the four shipped worlds
  plus a deliberately broken house world, asserting the refusal names the slot
  and the file's own line and column. `Lips.World.Resolve` grew
  `resolveWorldFrom` (resolution plus WHERE the world came from) so a message
  can name the file without a second place deciding local-versus-shipped.

- **The answer is a submitted draft.** Twice on 2026-08-09 a mint ran the draft
  tool over draft A and then answered with a different draft B, so lips refused
  B a minute later with the exact message the tool had already shown, and the
  whole one-shot call was wasted. The prompt had pleaded ("answer with those
  lines ALONE"); invariant 2 asks for a guard instead of a plea.

  REJECTED, and recorded so it is not revived: a fingerprint gate (the tool
  records a hash of every draft it validates, `generate` refuses a reply hashing
  to nothing recorded). It cannot save the call, because `pi -p` is one-shot and
  the model is gone by the time the hashes are compared. A bad unchecked reply is
  refused by the existing gates anyway; a sound unchecked one would be refused
  for process reasons alone, which is a pure loss.

  BUILT: the checked draft IS the answer. `check_draft` became `submit_draft`;
  `callPi` owns a scratch directory for the call and passes `LIPS_MINT_ANSWER`
  into the pi child; the tool runs the same `lips check --draft` loop and, when
  every program passes, writes those bytes to that path, overwriting an earlier
  clean submission. After pi exits, `generate` reads the file instead of the text
  reply: a missing file is `Report.noSubmission` (a mint that never submitted
  produced no engine), an empty one is `Report.emptySubmission` (a staging
  defect, reported as a lips bug). The reply FORMAT is untouched, so
  `parseEngineCandidates` reads the staged bytes exactly as it read the reply and
  every committed engine still checks byte-identically.

  What did not move: who judges. The tool REPORTS and stages; the deciding gates
  still run once, in Haskell, over the staged bytes, including the two
  `--draft` cannot run (claim gate, artifact build). What is stricter: a mint
  that never submits is refused, where a sound unchecked reply used to pass.
  What is deleted: two prompt pleas, structurally. "Answer with what you
  checked" is now identity by construction, and "never narrate" is moot because
  the text reply is inert -- a narrating sentence can no longer fail a mint.
  Invariant 6 holds unchanged: the submitted draft is the recorded reply (hashed
  into `genId`), and every submission attempt is a tool call in the transcript,
  which is hashed too. `just test-draft` pins the boundary from the other side:
  the `check --draft` VERB stages nothing even with `LIPS_MINT_ANSWER` set, so
  staging lives in the tool alone.

  Witnessed live on 2026-08-12, twice. A re-mint of `examples/greet.lips`
  (opus-5) submitted one clean draft and was then refused by the claim gate over
  the STAGED bytes, which is the boundary working as stated: a clean submission
  is not acceptance, because the claim gate and the artifact build run after the
  model is gone (the committed engine was left untouched). A throwaway
  home-manager mint (sonnet-5) showed the in-call retry the design was built
  for: submission 1 was refused in the model's own call (`unknown option
  home.sessionVariables.<name>`, the type in the pinned schema being an
  integer), the model looked the namespace up again, submission 2 passed, and
  the record's `--- raw reply ---` is byte-identical to that second submission.
  Under the old protocol the same defect would have cost the whole call.

- **One world's lowering travels as one value.** `Lips.Kernel.Run.run` took
  rules, demands and ignores as three positional arguments among eight, and the
  ignore milestone had just added the ninth to `runBase`, so no call site read
  as anything but an argument count. The trio is one thing (one world's
  lowering), so it is now one record, `Engine` in `Lips.Kernel.Engine.Data`
  beside `IgnoreSpec` -- the run-side twin of `EngineData`, which groups the
  same rulebook in its stored form. `run`, `runBase` and `runGround` take it;
  the next engine axis extends the record instead of the argument list. No
  behavior change, the 860-example suite unchanged.

- **A contract may state the whole text a rule assembles.** Where two worlds
  spell one fact differently, the pattern captures it in PARTS and each world's
  rule assembles its own notation (`"*-*-* <value.1>:<value.2>:00"` for a
  systemd calendar, `"<value.2> <value.1> * * *"` for a cron field). The
  contract could then say nothing true: a several-part value read whole is its
  parts joined by a space (`03 00`), which appears in no such notation, and
  part-containment (`contains "03"`) also passes for text that merely happens to
  hold `03`. Three live mints of `examples/nightly.timer.lips` refused to write
  the weak form, and the third filed the gap itself
  (`expect-cannot-assert-a-reformatted-value`) -- a model declining twice and
  then reporting the grammar as insufficient is the signal invariant 4 names: fix
  the format, not the prompt.

  The contract grammar gains one optional arm, `Lips.Kernel.Expect`:

      a2 expect systemd.timers.<self>.timerConfig.OnCalendar from job.schedule is "*-*-* <value.1>:<value.2>:00"

  `Surface.fillValueHoles` fills `<value>`/`<value.N>` from the stated value (a
  hole naming a part that is not there is a `Left`, so a template can never
  produce half a string), `expectedValue` resolves it, and the comparison is
  EQUALITY against the option's text -- containment would be weaker than the
  words. One predicate serves both judging paths, the evaluated option and the
  ground slot (an artifact arg, a claim section), so one line cannot mean two
  things. Without a template nothing moves: containment, exactly as before, and
  every committed `.expect` still holds.

  **Why restating the rule is not vacuous.** Inside one mint it falsifies
  nothing, and that is not what `.expect` is for: the contract this mint writes
  gates the NEXT one, so an engine that later drops the seconds, reorders the
  fields or changes the separator is refused. Same argument `--compat` rests on.

  **And the unholdable form is refused where it can still be fixed.**
  `unholdableExpects` (`Kernel/Engine/Gate.hs`, beside `partsExist`, whose part
  counts it borrows through `emitViews`) rejects an expect that reads a
  several-part fact whole while every rule filling its option assembles that
  option's text from the parts. Static and domain-blind: it asks how many parts
  a pattern fixes, never what a part means. It runs at the mint gate and on a
  committed engine, so the defect that cost three model calls a minute each is
  now named inside the call, with the two forms that can hold (`is "<template>"`,
  or `#N` where a world writes one part into an option of its own).

  Proven live on 2026-08-11: `generate -t nixos -t kubenix --compat none
  examples/nightly.timer.lips` (opus-5) wrote both worlds in one call, and each
  contract states its own assembled text --
  `is "*-*-* <value.1>:<value.2>:00"` for the systemd timer,
  `is "<value.2> <value.1> * * *"` for the CronJob. `just test-draft` carries the
  offline half: the unholdable form refused naming the remedy, and the template
  form checked against the evaluated module.

- **A world declares the facts it cannot place, and may not launder a dead one.**
  Some facts belong to only some worlds: a Kubernetes pod needs a container
  image, and a machine that runs the script directly has none. Measured on the
  first live joint mint -- kubenix demanded an image, correctly -- and then the
  program could not state one, because `runGround` refuses a ground decision no
  rule places, so NixOS reported the program unportable. A world's rules now
  declare it, as data, with the reason:

      0.9 i1 @nixos ignore fact job.image "a machine runs the script directly, so there is no image"

  The kernel rule keeps its shape (every ground decision is placed by a rule, is
  a concept, or is declared here) and gains one closed arm: `IgnoreSpec` in
  `Lips.Kernel.Engine.Data`, stored as `engine.ignore.<id>`, matched with
  `matchSubject` so a family declaration covers its members, and filtered in
  `runGround` beside the concepts. The kernel still knows nothing about images,
  containers or worlds. The REASON is required, because it is the artifact a
  human reviews; a declaration without one would be a silent drop with extra
  steps.

  **The guard is what makes it safe, and it was the whole question.** A world may
  ignore a fact only where ANOTHER world's rules place it
  (`Lips.Language.orphanIgnores`): then the declaration records a real asymmetry
  between two lowerings. A fact NO world places stays the refusal it has always
  been. So the mint cannot use `ignore` to skip work it does not feel like doing;
  to drop a fact anywhere it must spend it somewhere, in an option grounded
  against that world's schema. The check is only possible because one mint now
  writes every world, and it runs in `check`, in `generate`, and -- the one that
  matters -- in `check --draft`, the door the model itself checks through.
  Measured: with the draft door ungated, a draft that declared the same ignore in
  EVERY world passed, and the program's word reached no output anywhere. With it
  gated, that draft is refused naming both declarations, and `just test-draft`
  now carries the case.

  `concept` was the alternative, and it was measured before being rejected. A
  rule may already match a concept and realize it, so the asymmetry needed no
  kernel change at all -- but the drop is then expressed by SILENCE (a reviewer of
  `nixos/timer.rules` sees no trace), no guard is possible (a concept nobody
  realizes is legitimate, so anything could be marked one), and the diagnosis
  prints "decorative, realizing nothing" in the world that DOES realize it,
  because `wordDecorates` reads patterns and never rules. So `concept` keeps
  meaning "realizes nothing", and a rule matching one is now refused: with two
  ways to express one asymmetry, only one of them guarded, a mint would find the
  unguarded one.

  The live example is `examples/nightly.timer.lips`, committed 2026-08-11 once
  the contract could state a value its rule reformats (the entry above). Three
  earlier mints had refused to write that contract and the third filed the gap
  `expect-cannot-assert-a-reformatted-value`; with the `is "<template>"` form in
  the grammar and in the prompt, opus-5 minted both worlds in ONE call, first
  try: `timer.grammar` captures the time in parts, `nixos/timer.rules` assembles
  `OnCalendar` and declares `ignore fact job.image` with its reason,
  `kubenix/timer.rules` places the image and spells the schedule `00 03 * * *`,
  and each world's contract states the text its own rule assembles. The draft
  door stays gated in CI by `just test-draft`, where a fact both worlds ignore is
  refused.

- **`-t` repeats; the comma list is gone.** `generate -t nixos -t kubenix`
  replaces `--target nixos,kubenix`. The comma syntax needed a reader that split
  a string and so invented an error class of its own ("empty world name between
  its commas") on top of the real question, which world a name denotes. A
  repeated option carries occurrence order for free (`many` preserves it, and
  order is data here: every world after the first may only append to the
  grammar), completes per token, and needs no splitting: `Lips.Cli.targetsOpt` is
  `many` plus the default when the flag is absent. A name given twice denotes the
  same world, so it states no second position a caller could have meant and the
  first occurrence stands (`nub`) -- where the comma reader refused the repeat at
  the door. `--worlds DIR` is untouched: it answers WHERE world files are looked
  up, mirroring `--lang DIR`, while `-t` names WHICH world, once per occurrence.

- **One mint, many worlds: the call that discovers a cross-world defect is the
  one that may fix it.** Multi-world builds shipped with one model call per
  world, left to right, so the shared grammar was written by the FIRST call --
  a party that sees one world authoring the contract between all of them.
  Measured three times on `examples/nightly.timer.lips`: every mint wrote `fact
  job.schedule "<time>"`, spelling a daily 03:00 as one atom. NixOS accepts that
  (`OnCalendar` contains `03:00` verbatim); a Kubernetes CronJob does not
  (`0 3 * * *`), and nothing below the mint converts one into the other, by
  construction. So kubenix refused, correctly -- and the remedy the refusal
  prints ("re-mint every world together") ran the nixos call first with the same
  information as before and wrote the same coarse grammar. A remedy lips prints
  and cannot honour is invariant 4's case: fix the physics, not the wording.

  `generate --target a,b` is now ONE call for the language. It carries every
  world's preamble, each fenced into its own section (a preamble is absolute
  prose about one namespace, so two read as one text contradict each other), and
  answers with one engine: patterns and source blocks shared, rules, demands,
  merges and expects each tagged `@<world>`. `Lips.Generate.Minting.itemsFor`
  splits one reply into one engine per world over the shared grammar; ids are
  unique across the reply except a `because` note, which repeats the id it
  explains. `query_options` now takes the world it asks about (validated against
  the run's list, so a lookup can never be answered from another world's
  schema), and `check --draft` materializes every world the draft names and runs
  the committed verifier over each -- which is what lets a model see
  `<value.2> out of range` while it can still change the PATTERN.

  Measured before it was built (2026-08-09, hand-composed prompt, opus-5): the
  answer decomposed the time first try (`at <hh>:<mm>` into `fact job.schedule
  "<hh> <mm>"`, then `"*-*-* <value.1>:<value.2>:00"` for nixos and
  `"<value.2> <value.1> * * *"` for kubenix), tagged every item correctly, and
  leaked no option between worlds -- the one risk here that fails silently
  rather than loudly. `examples/install.packages.lips` is now minted for nixos
  and home-manager in one call, one grammar, one record, `environment.
  systemPackages` and `home.packages` from one program.

  Consequences the shape forces. Shared files have one author: the grammar, the
  `artifacts/` tree, the record and the account are written only by a call that
  saw every world, and freeze together when it did not
  (`sharedFileViolations`) -- which closed a live clobber where a second world's
  mint replaced `artifacts/` wholesale and deleted the source the first world's
  rules point at. One event writes ONE record, at the language level, pinning
  every world by name, hash and schema (`recordedWorldPin`); a world minted
  alone still writes its own, and a joint mint removes the stale per-world pair
  it supersedes, so a reader can never prefer a record that did not write the
  lines it stamps. The account is filed at the scope of the event, so no
  committed example moved. And an unanswered demand became a WORLD's fact
  (`unansweredReport`): demands live in a world's rules, so a program that
  satisfies nixos while leaving kubenix's image demand open fails kubenix alone.
  A conflict stays fatal, being refinement over the shared grammar.

  Two findings from the live runs are recorded rather than fixed. A mint told
  nothing invents where it should demand (it wrote `busybox:latest` at
  confidence 0.8, above the threshold, so it would have shipped); the prompt now
  says to demand, never invent. And an expect over a split fact must name its
  part (`from job.schedule#1`), since a several-part value read whole is its
  parts joined by a space, which no world's notation contains -- the contract
  gate caught exactly that on the first live joint mint of the timer.

- **One program, several worlds: a shared grammar plus one folder per world.**
  A language folder used to hold one engine for one world, so serving a program
  to both NixOS and Kubernetes meant two languages, two readings of the same
  sentences, and no way to say they were the same program. The engine format did
  not have to change to fix this: a `.lang` is a flat list of decisions keyed by
  subject, so the split already existed in the data. It is now a split in the
  filesystem too -- `<language>.grammar` (the `lang.*` patterns: how a program is
  READ, shared and identical in every world) at the language level, and
  `<language>/<world>/` holding everything that depends on where a program LANDS
  (`<language>.rules`, `.expect`, `.generation`, the world file copy, `README.md`,
  and a refused mint's `.gap`). `Lips.Kernel.Lang.Store.readLang` reads the two
  back as their concatenation, untouched; `Lips.Identity` is still the only place
  that knows the layout, and `Lips.Language.mintedWorlds` answers which worlds a
  folder holds by LOOKING (a subdirectory carrying this language's rules), so a
  folder and its truth cannot disagree. The marker is the rules rather than the
  record, because an engine written by hand carries no record and must still be
  a world lips finds.

  `generate --target a,b` was one run and one model call per world, left to
  right (superseded 2026-08-09 by the entry above, which makes it one call for
  the language: sequential minting left the shared grammar to a call that saw
  one world). Each
  world gets its own record, and `stampFaults` now takes the language's records
  as a LIST -- a line is sound when it names one of them, which is as strict as
  before (every id still has to come from a record that re-hashes). A mint that
  lands after another inherits the grammar in its prompt and may only APPEND to
  it; `appendOnlyViolations` compares decisions with the provenance set aside
  (the renderer stamps every line it writes, so the stamp is not the mint's to
  keep) and a changed pattern is refused showing both lines, with the remedy
  being a joint re-mint. `mergeGrammar` then writes the committed lines
  verbatim, so an inherited pattern keeps the bytes and the stamp of the mint
  that wrote it. Frozen exactly when some committed world will not be minted in
  the rest of the run (`grammarIsFrozen`), which frees a first mint and a
  re-mint of every world, and covers the second world of one run with the same
  test.

  `check` reports one verdict per world and `compile` writes one directory per
  world (`out/<instance>/<world>`), because a compiled module is a world's shape
  and one directory could hold only the last one written. A world a program does
  not reach fails ALONE: ground decisions no rule of that world places are its
  own defect, reported by `Lips.Report.unportableReport` (which never says "lips
  generate", because re-minting nixos cannot make a kubenix-only line land
  there), while every other failure stays fatal for the run -- a conflict or an
  unanswered demand is a fact about the PROGRAM, true in every world. The worlds
  that hold are still written, and the run still exits nonzero.

  Measured, not assumed: `examples/install.packages.lips` is minted for nixos
  beside home-manager, the grammar byte-identical across the two mints, and one
  compile writes `home.packages` and `environment.systemPackages` from one
  program. The first attempt, on `examples/nightly.timer.lips`, refused instead
  -- and the refusal is the finding. A shared grammar can only serve worlds that
  SPELL a value the same way: nixos wants `*-*-* 03:00:00`, a Kubernetes CronJob
  wants `0 3 * * *`, and nothing below the mint can convert one into the other
  (the value grammar has no computation, by construction). The first mint must
  therefore emit such a value in parts (a fused hole `<hour>:<minute>` and a
  multi-part assertion the rules spend with `<value.1>`), which is now stated in
  `assets/mint/shared.md` and given to any mint that has worlds after it. Three
  live mints of the timer still spelled the time whole and the kubenix mint
  refused, correctly, naming the gap. So the mechanism holds and the open
  question is the mint's: whether a first world can reliably write a grammar
  neutral enough for a world it has not seen.

- **Worlds are data: a `<world>.world` file, not four arms of a Haskell enum.**
  The world axis was the design's own counter-example: adding a world meant
  editing `Lips.Nix.Target`'s enum, six per-world Haskell sites (the mint
  preamble, the schema expression and its sub-path, the baked pin variable, the
  flake harness, the printed rungs, the claim places a world hosts) and the
  deploy helper's four output names -- an OPEN list the kernel enumerated,
  exactly what the kernel is forbidden to do about anything else. A world is now
  a data file: header lines (`world`, `module-attr`, `schema-pin`,
  `schema-flake`, `input-args`, `claims`, `format`) plus named slots
  (`preamble`, `schema`, `inputs`, `builds`, `packages`, `apps`, `devShells`,
  `rungs`, and since format 2 `gate`), parsed strictly by `Lips.World` -- an unknown key or slot names
  itself in the refusal, and a file declaring a newer `format:` says which lips
  to upgrade. The four lips ships live in `assets/worlds/*.world`, embedded, and
  a `<name>.world` beside a program (or under `--worlds DIR`) resolves the same
  way; built-in names are reserved, so `nixos` means one thing everywhere.
  `lips world` lists what is reachable from here, `lips world <name>` prints one
  -- the seed a house world starts from, and the way to restore a copy.

  The harness became a world-neutral skeleton (description, nixpkgs input,
  `forSystems`, the artifact/site/claims package entries) plus the world's slots
  placed verbatim, which is what makes `flakeText :: World -> Rungs -> Text`
  domain-blind; one simplification fell out on the way, `artifact.nix` is now
  always written (empty set when a program declares none), so the text carries no
  conditional at all. `Lips.Nix.Kubenix`'s three reshapings moved into
  kubenix.world's schema slot as jq, and `Lips.Nix.Schema` died with it: every
  world's document now parses with `parseNixOptionsJson`, and the slot's
  contract is that its `$out` IS the options.json, which killed `schemaSubPath`.
  The jq is witnessed by an offline flake check (`kubenix-schema`) reading the
  slot out of the world file, since grounding runs only at generate and CI never
  mints. That move also FIXED 78 fields: the Haskell classifier read
  `null or (list of signed integer)` as a plain integer (its scalar test matched
  the substring), so a correct list emit was refused; unwrapping first types
  them as lists. The known cosmetic delta is the other direction -- an
  unmodelled optional's refusal wording loses its `null or ` prefix.

  A world travels WITH the engine: generate copies the resolved file into the
  language folder and the record pins it by content hash (`world: <name>
  <hash>`, `format: 1`), both entering `genId`. compile reads that copy, never
  what lips ships, and refuses on a missing file (naming `lips world <name> >
  <path>` as the remedy) or a hash mismatch (naming both hashes). A record with
  no `format:` header is format 0 and is read by its `target:` slug, or as nixos
  when it has none -- not a fallback but the only reading its sealed bytes can
  have. `nix/modulesFromDir.nix` groups by the world file's own `module-attr:`,
  so a house world lands under its own flake output with no edit there. The test
  that this is finished: `Lips.Nix.Target` is deleted, and nothing in lips
  enumerates a world.

- **A clause takes contributions from several program lines.** A program whose
  lines are STATEMENTS (`examples/function`: a declaration and three calls) had
  no way to reach one entry point: a clause rhs is one s-expression per subject,
  so a second statement line was a merge conflict. The first live clause mint of
  `function` filed exactly that as the gap `clause-sequence` -- and worked around
  it by demoting the three calls to CLAIMS and minting `(define (main) (run-all
  (arguments)))`, a command printing its own argv. Every gate stayed green,
  because the rule that every word must reach output was satisfied by an
  observation rather than by behaviour. The remedy is the dual of list
  aggregation on a list-typed option, and reuses all of it: a rule writes a
  one-element LIST holding the whole definition (`clause.main "[ (define (main)
  (print-line \"#<value>\")) ]"`), `mergeModeOf` already reads a list rhs as
  `Append`, `assembleWith` already orders contributors by program line and links
  every one into the provenance, and the only new physics is
  `Clause.Gate.mergeDefinitions`, folding contributors into one definition whose
  body is theirs in order. Contributors must define the same name with the same
  parameters, or the fold is refused. A clause keeps its repeats whatever the
  engine declared, decided by the kernel rather than by the mint (`clauseRooted`
  in `assembleWith`): printing twice is not printing once, and collapsing a
  repeated statement would delete behaviour with every gate green. `function`
  re-minted to two clauses, no baked source, `(define (main) (print-line
  "hallo") (print-line "du") (print-line "!"))` carrying all three lines'
  provenance, and the built binary prints those three lines.
- **A mint deduces the observable; the author need not state one.** The
  obligation to observe baked source (`claimlessBakedSource`) counts claims in
  the ENGINE, and its refusal read as if the burden were the author's ("state an
  example in the program"). Measured against `examples/function.lips`
  unmodified -- four lines, no witness sentence -- opus-5 deduced four claims
  from the program's own words on the first try. So a witness sentence is not a
  precondition for re-minting a baked-source example, and a deduced claim is
  strictly stronger than a written one: it is keyed to the program's values
  (`expect claim.<f>-<n>.equals from call.<f>.<n>.text`), so editing a line moves
  the claim with it, where a prose example can drift out of sync.
- **A re-mint says when it re-grounds.** The schema pin is deliberately not
  sticky: a re-mint grounds against the pin the running binary carries (or
  `--schema`), never the one the committed record names, because fresh grounding
  is the point of re-minting and replaying an old event is impossible anyway
  (the model is nondeterministic). What that left was silence -- a newer lips
  re-grounded an engine and only the `.generation` diff said so, afterwards.
  `generate` now prints both pins when they differ, read back with
  `Generate.Record.recordedSchema`. One line of prose, no new state, and the
  record stays an audit trail rather than a lock.
- **The IC-postulate audit is written, and the set law is a theorem.** DESIGN §2
  now maps Konieczny and Pino Pérez's IC0-IC8 onto `Base.resolve` postulate by
  postulate, under a stated reading (strength makes it a PRIORITIZED merge, `IC`
  is the tautology, assertions are opaque text under a subject). The verdicts
  worth remembering: IC4 (fairness) is violated on purpose, since that is what
  priority means; IC3 holds only syntactically, the price of a domain-blind
  kernel; and IC6 fails for `Append`, the stated exception, because aggregation
  builds a list rather than selecting among alternatives. Four properties over
  arbitrary generated bases now pin what the calculus rests on -- permutation,
  splitting and self-union leave every winner unchanged, in both merge modes --
  so "merge is a set operation" stopped being a promise.
- **A word read as decoration is now said out loud.** `diagInert` works per
  LINE, so a hole demoted to a `Concept` on a line that otherwise realizes was
  invisible: the line is not inert (its other words reach options), and the drop
  gate deliberately excuses a hole reaching a concept the mint DECLARED. Nothing
  said the word governs nothing, which is exactly the silent concept demotion the
  ledger has listed as open since the reach gate landed.
  `Engine.Reach.decorativeValues` names it, `Diagnosis.diagDecorative` anchors it
  on the program line, and `check` prints it beside the inert and discarded
  blocks; the LSP paints it as a warning, never an error, since a heading is a
  legitimate reading and the remedy is the author's. Measured on the corpus at
  once: `board`'s two specification sentences (correct -- they specify baked
  source), and `function`'s declaration line, whose `<fname> <param> <ptype>` all
  land in a concept, which is the demotion the ledger recorded as a sonnet-5
  regression and could not see afterwards. The first draft also called three
  correct `vhost` lines decoration, because a block HEAD may emit nothing but a
  concept while every line inside keys its subject by the head's word -- so the
  judgment reads the landings of the pattern AND of every pattern nested under
  it.
- **Invariant 6 held all along, and is now checked.** The sixth invariant says
  every minted line is stamped `@gen:<id>` and the id must re-hash from the
  committed `.generation`; no code re-hashed anything, and the ledger recorded a
  belief that the schema pin had broken every stamp, which would have cost a
  fourteen-language re-mint sweep to repair. Measuring first refuted it: the
  stamp is `genId` over the record TEXT AS WRITTEN, and adding a field to
  `record` changes what future mints write, never the bytes already on disk. All
  20 committed engines and all 8 validation scenarios re-hash exactly, including
  the three whose records predate the `schema:` line entirely (`bucket`,
  `vhost`, `site`). The schema-pin entry below had said so at the time
  ("existing records still re-hash, since `genId` reads the committed file");
  the belief in a repo-wide breakage was written into the backlog anyway, and
  survived there for four days because nothing could answer it mechanically. So the gate landed green instead of after a sweep:
  `Generate.Record.stampFaults` re-hashes the record beside an engine and
  `check` refuses a stamp that disagrees, a line carrying none, or -- the
  inverse case, which needs no special rule for drafts -- a stamp with no record
  to name. `experiments/clause-site` lost the zeros it used to carry, since a
  placeholder id is exactly the lie the gate exists to catch. The lesson is the
  cheaper one: measure the claimed breakage before paying for the repair.
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
  `--compat none`, exported so the two cannot drift into a false green. Nothing
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

  One consequence to know: for a claim-bearing program `check` needs a nixpkgs
  (the one the compiled flake names, as every other rung does: the grounding
  pin where the world grounds on the substrate, else `flake:nixpkgs`), and a
  machine claim makes `check` boot a VM. A claim-free program is
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
  body, `nixos.md`/`home-manager.md` the two world preambles -- since moved into
  the world files' `preamble` slot by "worlds are data" above --, `direction.md`
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
  separate, explicit action -- `generate --compat none` on each -- left for whoever
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
  the witness work in `TODO.md`; the prompt now offers the composed name, since
  a capability the model is told nothing about is dead capability.

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
  now open capability questions instead of silent engine bugs, tracked under
  "CLI-tool physics" in `TODO.md`. The two that were deliberate non-goals there
  have since become gates: a partial drop, where a rule reads `<value.1>` of a
  value built from two holes, and the per-hole decorative report.

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
  `LIPS_MINT_WORLD` passed explicitly so a mint for one world can never be
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
  (`--compat` stays long-only, a deliberate rare action). Because completion
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
  three knobs were `assets/mint/kubenix.md` (the world preamble),
  `Lips.Nix.Kubenix` (the grounding schema) and `Lips.Nix.Flake` (the rungs),
  plus one dispatcher, `Lips.Nix.Schema.schemaFor`, so the two grounding call
  sites could not disagree about a world. (All four are gone with "worlds are
  data" above: those knobs are now slots of `assets/worlds/kubenix.world`.) Grounding is real, not nominal: lips
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

- **Re-bless lattice (`generate --compat full|backwards|forwards|none`).** One
  word used to hide two independent permissions: may a committed assertion
  VANISH, and may a freshly minted one JOIN. Naming both makes the switch four
  points instead of two. `full` (the default) grants neither, so the committed
  contract governs unchanged and a differently-worded re-mint still passes;
  `backwards` lets this run's extra checks join, so the contract can only grow;
  `forwards` lets a check leave, so it can only shrink; `none` rewrites it from
  this run (the old `--renew`, which is gone -- an old invocation fails loud
  rather than silently keeping the contract). Sameness is the option path plus
  the source it draws from, since the `a1`/`a2` ids are minted fresh every run.
  The guard that keeps `forwards` from letting the model choose which checks to
  skip: an assertion may leave only when NO rule in the new engine assigns its
  option path; a path still filled but no longer asserted refuses. Every
  correctness gate and the behavioral gate still run whatever the word, so a bad
  mint still writes nothing, and the `.expect` diff stays the semantic changelog
  (invariant 5: an explicit human decision, never silent). A refusal names the
  SMALLEST mode that would admit the change, which is why `checkValues` returns
  the failing assertions and not only their messages. The mode gates and does
  not mint: it stays out of `.generation` and `genId`.

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
  mechanically CHECKED by re-hashing the record (`check`, since 2026-08-05). Regenerating the examples
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
  path to a program value (`expect <option.path> from <subject>[#n]`, or
  `... is "<template>"` where a rule assembles the option's text, see the
  entry above), judged
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
  module, an artifact path INSIDE the build. What the gate deliberately does NOT
  check is whether such a path can RUN: a file under `bin/` that exists but is
  not executable has never been observed, so the check waits for the first one
  rather than being written against a guess.

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

- **Plurality dissolved the largest remaining blob: `http` stopped baking
  source** (2026-08-06, `examples/hello.http.lips`). The program was enriched
  from one blanket response to three contrasted routes (`/`, `/health`,
  `/version`, each with its own text) under a `routes:` heading, its witness
  sentence was dropped, and it was re-minted with opus-5 at `--compat none`.
  The 62 lines of Go are gone: the engine is nginx, one `location` per route,
  and the body rides `extraConfig` (`locations.*.return` is typed integer in
  this schema, so the text cannot ride there). The route pattern nests under the
  SERVICE-NAME line (`p4.under.p2`), not under the `routes:` heading, which
  answers the previous mint's own gap `cross-line-instance-key` with no kernel
  change: an item borrows the key its block head bound, so a route knows which
  server it belongs to. Its second gap, `per-item-claim-key`, dissolved with the
  source -- a pure-configuration language mints no claim, and the two expects
  pin the port and every route body. The witness sentence was unnecessary, as
  the `function` re-mint had already suggested: nothing asked for one and
  nothing refused its absence.
  The unit name is realized as `systemd.services.nginx.aliases =
  [ "hello.service" ]`, so `systemctl` reaches the author's word verbatim --
  a POSITIVE instance of the shape TODO 2b complains about, where the option
  the mint chose means what the sentence says, unlike postgres's
  `ensureDBOwnership` or web's `serverName`.
  Grounding after the re-mint: 7 option assignments, 0 unvouched assertions,
  19 mint-written words inside option strings (the three nginx snippets). Those
  words are MINT glue and no expect can read them -- an expect compares the
  option's string, never what nginx does with it -- so the flake gained
  `nginx-vm`, which boots the realized module and asks all three routes. The
  `artifact-vm` check, which watched this example precisely because it baked
  source, now follows `examples/website`, the largest baked tree left.
- **A seeded generator is a contract, so a re-mint cannot rewrite history**
  (2026-08-12, asked for by the first application-scale user, a football
  simulation). A simulation must vary while staying a pure function of its
  input, and the three ways to get there are not equal. Clauses the mint writes
  put the multiplier and the modulus in per-program source, where the next mint
  may rewrite them and every result ever recorded changes with them; a line in
  the program states arithmetic in words, which is the notation failure the
  logic axis exists to avoid; a contract is pure, not base notation, and
  reviewed once for every program, which is exactly the category `json-parse`
  occupies. So `random-step` joins `assets/runtime/scheme/contracts` with the
  RECURRENCE FIXED IN THE CONTRACT rather than per adapter (a 32-bit LCG, the
  value read off the high bits), because runtimes that step differently make a
  replay disagree with the run it reproduces. Unpredictability is explicitly
  not its job: a caller who needs it derives each seed outside, from a secret
  it keeps. Guile implements it in three lines of exact integer arithmetic; a
  second runtime is what will need a check pinning the shared sequence, and
  until one exists the pin is a downstream program's own claim.
- **`board` stopped baking source, the third no-blob conversion** (2026-08-12,
  `examples/board.lips`, `-t home-manager`, claude-opus-5, `--compat none`).
  The 40-line bash script that parsed the markdown board and rendered its
  columns is gone; the same behaviour is now 19 clauses (a hand-rolled
  string-cut based tokenizer, a recursive column/card walk, a right fold for
  the join) reached by one whole-program claim that feeds the worked example's
  five input lines and compares all three output lines byte for byte. Grounding
  after the re-mint: 1 option assignment, 19 clauses, 1 claim, 0 unvouched
  assertions, 0 mint-written words -- the prior engine's entire staged tree is
  gone with nothing replacing it as glue. Two gaps filed instead of worked
  around: `no-file-contract` (no contract opens a file, so "read the board from
  the file named on the command line" is honoured only for standard input, at
  reduced confidence on that rule) and `fixed-witness-count`, a third instance
  of the fixed-arity-witness shape (TODO 1c): the block form can free a
  witness's INPUT side but not its OUTPUT side, since `claim.<id>.equals` takes
  one expression, never an aggregate.
- **`habit` stopped baking source, the fourth no-blob conversion, and the
  largest yet** (2026-08-12, `examples/habit.lips`, `-t home-manager`,
  claude-opus-5, `--compat none`). The committed Go program parsed a
  tab-separated log, tracked one habit's logged days, and walked the
  earliest-to-latest date range printing a mark per day -- calendar arithmetic
  (month lengths, leap years) included. All of it is now 20 clauses: date
  parsing over `string-cut`, dates held as `(year month day)` lists compared
  structurally, and the day-by-day walk written as plain recursion
  (`next-day`, `days-in-month`, `leap-year?`). One whole-program claim feeds
  the three worked-example log lines, passes the habit name as the argument,
  and compares the printed marks exactly. Grounding after: 1 option
  assignment, 20 clauses, 1 claim, 0 unvouched assertions, 0 mint-written
  words. Filed the same two gaps `board` filed independently the same day
  (`no-file-contract`; here `one-line-item-list` for the witness-arity shape),
  which is evidence the gaps are structural to this class of program rather
  than an accident of one mint.
- **`website` stopped baking source, the fifth no-blob conversion and the
  largest, closing the sweep** (2026-08-12, `examples/website.lips`, `-t
  nixos`, claude-opus-5, `--compat none`; two mints -- the first wired
  `services.darkhttpd` with a malformed `--addr` and generate correctly
  refused to write anything, since its own booted-machine claim failed the
  same way a real deploy would). The committed 220-line Go program templated
  an HTML page from environment variables at every request; the page is
  static once the program is compiled (every canvas, button and click target
  is a program value known at compile time), so there is no server left to
  write: one clause, `main`, PRINTS the whole page -- markup and the
  click-handling JavaScript alike -- and a oneshot systemd unit redirects that
  output to a file `darkhttpd` then serves. Grounding after: 9 option
  assignments, 1 clause, 1 claim, 0 unvouched assertions, 7 mint-written words
  (the darkhttpd wiring). Three gaps, the most of any conversion so far:
  `angle-brackets-in-values` (a Nix value cannot hold literal `<...>` -- it
  reads as an unknown hole -- so markup has to be routed through a clause
  string, whose own hole marker is `#<...>`, even where a plain file would
  otherwise do); `no-stated-observable` (the program gives no example of the
  rendered page, so the one claim is a smoke test that `main` runs, not a
  witness of what it prints); and the sharpest, `browser-behaviour` -- no
  contract reaches a document, an element or a click, so the clauses can only
  PRINT the JavaScript that paints, erases and downloads a canvas, and nothing
  checks what that script does once a browser runs it. Unlike `no-file-
  contract`, this one is not obviously closed by adding a single contract: a
  browser event loop is a different execution model than the sandbox clauses
  run in, so it is left as a live gap rather than a design item (TODO, no-blob
  doctrine). With this landing, every committed program the no-blob sweep
  named is off staged source, and the gate the doctrine describes ("refuse a
  new staged tree") can land without refusing the corpus it ships with.
- **The corpus a model reads is the corpus a reader reads, and a JSON array is a
  list** (2026-08-12, both found by the first application-scale mint: a 26-line
  football program, minted into 37 clauses that play a match in 21 ms). Two
  defects, one cause: what the mint was shown did not match what the kernel
  reads.
  FIRST, `corpusText` sent the raw program text while every reader lips has
  skips a comment, so the model was asked whether every line it saw
  crystallizes and could not satisfy the question. Measured, not reasoned: with
  a seven-line header paragraph the mint spent FOURTEEN drafts writing concept
  patterns for prose and never converged; with the paragraph moved to
  `.direction`, the same model minted a working engine in one pass. The rule
  "a comment carries nothing" also lived in three copies (`Reader`,
  `Crystallize`, `Store`) and would have become four, so it is now
  `Reader.commentOrBlank` and the corpus is filtered through it. Stripping beats
  a plea in the prompt for a second reason: `.direction` is already the one
  labelled advisory channel, and two channels that both steer a mint can drift
  apart. Since the corpus is what enters `genId`, editing a comment now
  correctly leaves an engine valid, because it changed nothing readable.
  SECOND, the contract set could reach a record (`field-of`) and no array, so
  the mint encoded eleven players as eleven FIELDS `p1..p11`: honest under the
  physics it had, and unable to read any real roster. `elements-of` closes it as
  DATA (one pure contract, `vector->list` in guile, since guile-json maps an
  array to a vector and an object to an alist), and one converter is the whole
  addition because recursion over a list is already expressible, so no accessor
  family enters the vocabulary.

- **A dependency on another language is an atom, and a clause is named after its
  language** (2026-08-12, design in
  `docs/superpowers/decisions/2026-08-12-cross-program-composition.md`, driven by
  the `libero` falsifier). Physics half landed; the mint tool and the site union
  are not built yet.
  The defect it answers was silent, which is worse than missing: a program
  writing `contribution(p) := as defined by match.` had that line read as "the
  raw contribution field of the player record", every gate green, so one concept
  became two. Nothing in lips represented a reference across a language
  boundary, so there was no name to fail to resolve, and deduce-or-fail did not
  hold.
  A dependency is now a KIND (`Uses`, subject the language, assertion the
  instance) rather than a fact with a reserved subject, because the kernel may
  know a structural category and may not know a word in a subject path. The rest
  is inherited: two instances named for one language are an equal-strength
  disagreement that merge already refuses with both provenances, and realization
  ignores the kind.
  Clause names are namespaced BY CONSTRUCTION at mint time
  (`clause.match-duel`), never rewritten later: qualifying at realization would
  make the kernel decide which symbols in a body are call targets, and that is a
  translation, while emitting is a serialization pinned by `parse . render = id`.
  So the kernel checks (`clausesNamespaced`) and never transforms, which makes
  collision-freedom a theorem: two languages cannot share a prefix, and
  duplicates inside one already conflict.
  The entry needed no reserved name: `entry (<language>-main)` gives the runtime
  data a hole like every other value, `compile` fills it, and the runtime keeps
  ownership of the word.
  MIGRATION, recorded because it bends invariant 4: the eight committed clause
  engines (function, hello, logscan, website, board, habit, and libero's match
  and training) were migrated by a one-off script
  (`nix/migrate-clause-namespace.py`) rather than re-minted, since a re-mint
  rewrites behaviour a program never mentioned. Two bugs the script found are the
  argument for reviewing such a diff: a Scheme name may end in `?`, so a
  word-boundary charset silently skipped `keep?` and `matches?`; and an engine
  may use `clause.<name>` as a FACT subject too, so renaming the rules alone left
  them matching facts the grammar no longer produced. Every engine was
  re-verified afterwards by `lips check` (claims and expects), and `match` was
  A/B tested to byte-identical output.

- **A dependency travels on the realization, and composing links a core**
  (2026-08-12, second half of the composition work; the mint tool is still
  missing, so nothing yet PRODUCES a `Uses` decision from a program). A `Uses`
  decision realizes nothing: it names another program's base rather than an
  option, so `runGround` drops it exactly as it drops a `Concept` (a third sound
  way to reach no option, beside a world's declared ignore), and `rlUses` carries
  it to the caller. `composeWith` then links the imported cores ahead of the
  program's own, so a call resolves by NAME at link time, which is all a
  first-order clause world needs. Only the CORE travels: a dependency lends
  behaviour and never its module, or importing a language would silently deploy
  it. Resolution is spelled the way every program is
  (`<instance>.<language>.lips`, or the singleton when the instance IS the
  language), looked up beside the importer, and a missing file stops the run
  naming what it looked for rather than compiling a site with a hole in it.
  Composition happens before the gates, so a claim judges the site a run would
  link.

- **A mint can ask what a language exports, and a call into it grounds**
  (2026-08-12, third and last part of composition; end to end offline, no model
  involved). `Language.exportedClauses` reads what a language gives another
  (name plus arity, the arity taken from the definition's own parameter list so
  the two cannot drift), `lips exports [-t <world>] <language>` prints it one
  `name arity` line per clause, and the mint's third tool `query_language` reads
  that same list from the same binary, asked from beside the importer. No world
  is defaulted: exports live in a world's rules, so a language minted into
  several is a refusal that names them (`Language.soleWorld`), and an unminted
  one is an error rather than an empty list, since "exports nothing" reads as
  permission to define those names locally.
  THE PHYSICS THE FIXTURE FOUND: linking the cores afterwards is too late to
  ground a call, because the clause gate runs INSIDE realization. So a caller
  that composes lends the imported names to the vocabulary BEFORE the run
  (`Vocabulary.withLent`, fed by `Run.lentNames`), which is where the kernel
  already takes "what grounds a name in a clause" as injected data. The shell
  resolves the chain depth first with a cycle guard, since a dependency may name
  a language of its own. Arity deliberately does not travel: a lent name enters
  as a procedure, and a procedure declares no arity here, so a wrong-arity call
  is caught by the runtime the claim gate runs.
  Measured on a two-language fixture (`greet` lending `greet-hello` to `hi`),
  hand-written and checked through the draft door, so the whole path was proven
  with no mint: the call grounded, the claim ran the IMPORTED definition in
  guile, and a deliberately wrong claim reported `got=("hello")`.
  ONE MORE PIECE OF PHYSICS the fixture forced, and the reason a shared
  vocabulary could not exist before it: an ENTRY is a requirement of a site
  something STARTS. `planSite` demanded the runtime's entry from every core, so a
  program that installs no command -- which is exactly what a vocabulary language
  is -- was refused with "the guile runtime starts a program by calling
  player-main, and this program defines no clause of that name". Now the entry is
  demanded, and `main.scm` written, exactly when something references the site
  (`rlSiteName`); the core is still written and still claimed, because
  `claims.scm` is what observes it and `main.scm` is what would start it.
  TWO MORE GATE CORRECTIONS, both paid for by libero's `training` (three sonnet-5
  mints in a row, each ~12 minutes, each refused at the FINAL gate for the
  contract it had just written). First, a clause body and a site name are
  literals of the ground base and no attribute of any module, so an expect over
  one was sent to the nix eval, read a silent `null`, and refused a promise that
  was in fact exactly right ("effort still multiplies by 60"). `isGroundExpect`
  now covers every root lips owns (artifact, claim, clause, site); only a world's
  OPTIONS need the eval. Second, the draft door judged the GOVERNING contract
  (the committed `.expect`) and never the draft's own new promises, so a mint
  could not see its own contract fail: the door now also runs the ground half of
  the draft's own expects (`Gate.groundExpectFaults`, `DraftTree.dtOwnExpects`),
  which costs no nix. The old argument against self-grading still stands for an
  option assertion (the rule that fills it and the check that reads it come from
  one pen, so it is flattery), but a ground assertion naming a slot the
  realization does not have, or the wrong slot of its own claim, is
  self-CONTRADICTORY, and no amount of writing makes it pass.
  Also found and fixed here: the mint prompt still taught BARE clause names
  (`clause.main`, `(begin (main) (emitted))`) four days after the namespacing
  gate landed, so every future mint would have been refused inside its own draft
  door. A structural test now walks every `clause.` path in the prompt and
  requires the prefix, because a prose reminder rots exactly this way.

- **libero composes for real, and a missing primitive surfaced twice**
  (2026-08-21, the acceptance test for the whole composition line). `player`
  states one player's numbers and exports an accessor per field; `training` and
  `match` both name it in a sentence (`the players come from the player
  language.`) and call `player-contribution`, `player-rating`, `player-name`.
  The decisive number is a NEGATIVE one: `match/nixos/match.expect` is
  BYTE-UNCHANGED across a re-mint that moved a rule into another language and
  re-emitted all 40 clauses, and 20 matches between equal squads still average
  2.30 goals split 1.30/1.00, exactly as before the split. Same football,
  computed once instead of twice; no clause of `match` reads a player's JSON
  field any more (only the fixture's own `seed`).
  A MISSING PRIMITIVE, found by two mints independently: Scheme's `/` yields a
  RATIONAL (`(/ 95001 1000)` is `95001/1000`), so a program forbidden floats
  could not divide. `match`'s first engine hand-rolled a doubling `match-idiv`;
  `player` wrote repeated subtraction, LINEAR in the result, and filed the gap
  `no-exact-division`. Two workarounds for one gap is physics, not coincidence
  (invariant 4), so `quotient remainder modulo` are base notation now, and the
  prompt renders the whole base procedure list from the same asset -- an earlier
  mint had filed a FALSE gap for `number->string`, a name it already had.
  Mint cost, recorded: `player` 9m 60s sonnet-5 (first shape), then 13m 15s and
  21m 26s opus-5 high; `training` four attempts, 53 minutes, only opus accepted;
  `match` 24m 23s opus-5 high, accepted first try. Every sonnet refusal was the
  CONTRACT it wrote for itself, and two of the three were lips' fault (both now
  structural guards). Details in `libero/docs/composition-measurement.md`.

- **A league, and the chain that links it** (2026-08-29, libero's season slice;
  the first program whose behaviour comes from three languages). `season.lips`
  names ONE language -- `the meetings come from the match language.` -- and its
  compiled core holds three: its own clauses, match's, and player's, which
  arrive because match names player and `resolveImports` follows the chain depth
  first. No program states the transitive step. Four squads, one seed threaded
  through twelve fixtures, and the table's goal differences sum to zero.
  THE GROWTH MINT, measured on real languages rather than a fixture: adding four
  sentences to season (goals for, goals against, an ordered table, a wider
  report) cost 4m 28s, $0.92 and 21,369 output tokens as a patch of 64 lines by
  id, against 16m 04s, $2.82 and 75,549 tokens for the fresh mint of the same
  language. Growing `match` to serve season (`meeting(a, b, s)`,
  `squad-name(s)`) cost 5m 33s and a patch of 67 lines, against 24m 23s for the
  rewrite before it -- and its `.expect` and its measured balance (20 matches,
  home 1.30, away 1.00) survived both mints unchanged.
  A NEGATIVE RESULT worth keeping: the first `season.lips` stated the ordered
  table, both goal tallies and a statistical claim at once. Eleven drafts were
  refused and the mint never converged. The same slice, cut to fixtures, a
  result and points, minted at the third draft -- and the rest arrived four
  minutes later as a patch. State the smallest thing that can fail, then grow it;
  a program that asks for everything at once asks the mint to be right about
  everything at once.

- **A mint's wall clock IS its output tokens; how much of them is thinking is
  NOT established** (2026-08-29, five timing records plus six runs of one
  controlled patch). What holds firmly: throughput is flat at 72-83 tokens per
  second across mints differing thirtyfold in size (website 110,257 tokens in
  1478.8s; greet 3,765 in 74.5s), so turns, tool calls and prompt size do not
  appear in wall time; and cost decomposes as roughly 60 percent output, 35
  percent cache-write, 4 percent cache-read, with fresh input at 6-24 tokens
  because the prompt is fully cached.
  WHAT DOES NOT HOLD, recorded because the first version of this entry claimed it
  did: that lowering `--thinking` makes a patch cheaper. Six runs of ONE patch
  (libero's season table) spread from 14,615 to 46,246 output tokens, and the two
  runs at the SAME level differed by 2.2x (21,369 and 46,246, both high). The
  per-level numbers (high 46,246, medium 22,061, low 14,615) sit inside that
  spread, so the ordering is suggestive and unproven; separating it needs several
  runs per level, which nobody has spent yet.
  THE PROMPT-VERSUS-TOOL QUESTION, tested rather than argued. The hypothesis was
  that a tool call costs more than its round trip, because each tool result opens
  another turn and every turn opens another thinking block. Pasting the imported
  language's exports into `.direction` (which rides in the system prompt) did
  remove the tool calls -- zero queries against one in the control -- and the run
  was WORSE on every axis: 304s against 177s, 23,659 tokens against 14,615, seven
  submissions against four. One datapoint inside a 2.2x noise band proves
  nothing, which is exactly the point: the effect of front-loading, if any, is
  smaller than the variance between two identical mints. Tools stay, now for a
  measured reason rather than a guessed one. The schema tool also scales where a
  prompt cannot, since NixOS ships tens of thousands of options.

- **A patch mint may answer by changing nothing, and that answer is worth its
  price** (2026-09-20, `board` and `logscan`, claude-opus-5, patched not
  `--fresh`). Both were re-minted to free their witness sentence from the entry
  count its author happened to write, the follow-through the list hole and the
  item pattern were built for. Both diffs are `@gen:` stamps only: not one
  pattern and not one rule moved, and `lips check` stays green on each.
  WHY, in the mint's own words (`examples/board/home-manager/README.md`, gap
  `fixed-example-arity`): `board`'s input side would take a list hole, its output
  side cannot, because `claim.<id>.equals` is one expression rather than a
  list-typed option, so no per-item rule can contribute one expected line. It
  judged half-generality worse than the present symmetry and refused. `logscan`
  reached the same place from the other side: its first submission tried
  `<in.list:,|and>` and its accepted draft went back to the fixed `<in1> and
  <in2>`, since its expected output is a single line. So the remedy TODO 1c had
  only named is now specified by a mint that wanted it: a list-accepting expected
  output, the dual of `claim.<id>.feed`.
  TWO GAPS NOBODY HAD SEEN, both from `logscan`. `unassertable-site-command`: an
  expect over `site.<self>.command` is refused ("nothing realizes this slot"), so
  the word naming the installed command is pinned by no check, and a later mint
  could key the site off the filename with every gate green.
  `expect-quoting-mismatch`: a rule emits `claim.filter.equals "(list
  \"#<value.4>\")"` and the realized value escapes the substituted value's own
  quotes for the surrounding Nix string, while an expect's `is`-text substitutes
  the raw value, so no example containing a quote (every JSON one) can be
  asserted.
  THE PATCH PATH, measured a second and third time: board 122.9s / $0.43 / 7,462
  output tokens, logscan 195.1s / $0.71 / 15,165, against habit's comparable
  fresh mint at 418.0s / $1.29 / 32,506. Cheap enough that asking a mint a
  question is now a reasonable way to answer one.

- **The website defect closes, and the words move behind a fetch** (2026-09-20,
  claude-opus-5, `--fresh --compat none`, 944.8s / $3.00 / 78,245 output tokens,
  12 turns, 7 submissions, accepted on the first attempt). `darkhttpd` is gone
  from grammar, rules and contract, so the vestigial `services.darkhttpd.port`
  the old `.expect` pinned is gone with it (TODO -2a).
  THE WORLD CARRIES THE TRAP ON ITS OWN (TODO -2c, the open question this
  settles). With the systemd stdout trap stated only in `assets/worlds/nixos.world`
  and `website.direction` holding nothing but the nginx preference, the mint
  wrote `${site}/bin/website > /var/lib/website-www/index.html` inside a oneshot
  `script` that `install -d`s its own directory, and never `StandardOutput=file:`.
  It also followed the direction: `services.nginx.defaultHTTPListenPort`,
  `virtualHosts.<self>.root`, `.default`.
  WHAT GOT WEAKER, recorded because every gate is green over it. The engine's
  page is a fixed HTML+JS shell that fetches `/data/<kind>/<i>/<field>` in the
  browser, so the program's words reach `environment.etc.*` files served under
  the document root instead of the html itself. `curl /` therefore carries no
  program word, which is why the standing `artifact-vm` check (renamed
  `website-vm`, since no artifact is involved since 2026-08-12) failed on the
  unit name `website.service` and then on the word `leeren`. It now waits on the
  port the PROGRAM states rather than a unit name the engine chose, and asks
  `/data/button/2/label` for the word. The mint's own claim `serve` asserts only
  HTTP 200, so 57 mint-written words inside option strings are pinned by a smoke
  test (first reported as 70, which counted program words filled into those
  strings as the mint's; corrected when the count moved to the rule templates) -- the `browser-behaviour` gap it filed, one level worse than before.
  A SIDE EFFECT worth naming: the shell loops to 64 canvases and 64 buttons, so
  adding a button to `website.lips` needs no re-mint. The same arity question
  `board` refused to answer, answered here by data rather than by pattern.

- **The two expect-gate holes `logscan` filed close** (2026-09-20, TODO 1d;
  kernel only, no re-mint). Both had one cause: the two sides of a comparison
  ran different code.
  `unassertable-site-command` was an unbound `<self>`. `lips check` and the
  final gate bound it at their call sites (`bindSelfExpect` in `app/Main.hs`),
  and the draft door's `groundExpectFaults` call did not. So the draft door
  judged `site.<self>.command` against a ground base holding
  `site.logscan.command`, and it answered "nothing realizes this slot" for a line
  `check` passes. `expandExpects` now takes the instance name and binds `<self>`
  itself, and every gate expands before it judges, so no caller can skip the
  binding.
  `expect-quoting-mismatch` was two fill functions. A rule fills a clause's
  `#<value.N>` with `fillSexp`, which escapes a quote for the Scheme string. An
  expect template filled `<value.N>` raw with `fillValueHoles`. A template that
  carries the clause marker `#<` is now a clause template: `parseSexp`, then the
  same `fillSexp`, then `renderSexp`. It is written in the rule's own spelling
  (`is "(list \"#<value.4>\")"`), and a text-spelled template over a clause slot
  fails with that spelling named. Both repro lines from
  `examples/logscan/nixos/README.md` hold in `lips check` against the committed
  engine, and the mint prompt (`assets/mint/body.md`, Expects) teaches the clause
  spelling. The committed `logscan.expect` does not pin either value yet, since
  a contract is minted output: its next re-mint can add them.

- **An expected output that aggregates: `claim.<id>.equals-lines`** (2026-09-26,
  TODO 1c's kernel half; `board` re-minted as a patch, claude-opus-5, thinking
  medium, `--compat none`, 309.8s / $0.99 / 23,745 output tokens, 4
  submissions, accepted). The section is the dual of `feed`: a Nix list of
  strings the call must equal, in order, so rules contribute one expected line
  each and Append assembles them. `Lips.Kernel.Claim.Expected` is a sum
  (`Equals SExp | EqualsLines [Text]`), so a claim that states both, or neither,
  cannot be built. It is rendered through the runtime's own list word
  (`hList`), the way a feed is.
  TWO AGGREGATION DEFECTS SURFACED ON THE WAY, both fixed first. (i) ORDER:
  `Aggregate.sourceKey` broke ties by the id's TEXT, so on one line `d9.10`
  sorted before `d9.2`. A five-entry `habit` example (11 decisions on one line)
  had its feed scrambled to a4 a5 a1 a2 a3. That was invisible, because habit's
  logic ignores order, and it would have been fatal for printed lines. The
  tie-break is now `DecisionId`'s own numeric `Ord`, which `Decision.hs` already
  calls the one place order is decided. (ii) REPEATS: a claim's list sections
  were sets unless the engine declared `merge ... list`, so two fed lines
  `- milk` would have collapsed into one without anyone noticing. `assembleWith`
  now keeps a claim's repeats itself, as it already did for clauses.
  WHAT THE RE-MINT DID. `p8` reads `given the lines <l.list:,|and> print the
  lines <o.list:,|and>`. `r8` feeds one line per input item, `r9` contributes
  one `equals-lines` element per printed item, and a new `r10` states the call
  once. An 11-line example with a repeated card passes its claim with no
  re-mint. The same example with one expected line wrong is refused by
  `compile` (`FAIL board got=(... "done: a, b, c, d") want=(... "done: a,
  b, c")`).
  WHAT GOT WEAKER: `board.expect` went from 2 checks to 0. The mint argued that
  an expect over a claim slot only restates the rule, because the claim gate
  runs the program. That is sound here, but its report says "As before there
  are no expect lines", which is false (the old contract had a1 and a2).
  TWO KERNEL GAPS IT FILED (`item-pattern-orthogonality`), both closed after
  the mint. (a) `patternOverlaps` compared every pair of patterns, so two
  one-hole item patterns reading DIFFERENT list holes were refused as
  overlapping. It now compares only within one arena: line patterns with line
  patterns, and item patterns of one hole of a shared parent. (b) A list hole
  glued to text (`<l.list:,|and>,`) silently became a fused hole and stopped
  being a list. The mint prompt's own new example taught exactly that form,
  and a test checked only that it parsed. It is now refused by name, the way a
  fused `.words` hole is, and the example is unglued. `board`'s README still
  describes both gaps. It is minted output, so its next re-mint rewrites it.
- **A singleton call stays a hole; what a singleton costs is elsewhere**
  (2026-10-02, `experiments/plurality-function/`, the experiment TODO 3 left
  untried). `examples/function.lips` was minted fresh twice from the 02f28f4
  binary, both runs claude-opus-5, thinking medium, nixos, both accepted on the
  first verdict. The control kept the program as is (3 calls; 229.8s, $0.81,
  6 submissions). The variant cut it to ONE call (313.9s, $1.12, 11
  submissions). The prediction was that one call demotes the call text to a
  constant, and it DID NOT HOLD: the variant kept `<arg>` a hole, and an edit
  to `bye` prints `bye`. The words that are singletons in BOTH programs
  (function name, parameter name, type) flipped between hole and literal from
  one mint to the next, with no direction. The control made the NAME a literal
  and its type a hole; the variant did the reverse. Observed, n=1 per arm.
  What the singleton cost instead, found by offline edit probes (no model):
  (i) In the CONTROL, the uncontrasted type word `<ptype>` lands only in the
  message of a `die` branch that no readable program reaches, so `x: Int`
  compiles and prints `hallo`. That is the defect TODO 3 describes, on the
  singleton declaration of a program whose calls ARE contrasted, and the reach
  gate passes it, because the word does reach a clause. (ii) In the VARIANT,
  the contract `expect claim.main.equals-lines from call.<n>` refuses a second
  call (`should be [ "du" ], but is [ "hallo" ]`), although the built program
  prints both lines. With three calls, both extra checks compare against
  `hallo`. This fits `checkArtifactValues` judging a ground slot against the
  FIRST decision with its subject (`(a : _)`), one contributor of an
  Append-assembled slot. It is a likely kernel defect, inferred from probes,
  not yet pinned by a test, and with one call the mint's own gate cannot see
  it. (Fixed the next day: "A ground check reads its own line's contribution".) Corpus scan (`scan/Scan.hs`, built from the kernel's own matcher and
  `wordLandings`): 59 of 92 (pattern, hole) pairs are singletons, 9 land in
  clauses, and all 9 are honest (board's markers, columns and separator,
  habit's two marks, hello's two texts and its `<var>`). Across corpus and
  arms, 14 clause-landing singletons hold 1 defect, and the defect sits in the
  same syntactic position (a string in a `die` message) as three harmless
  ones. Separating them needs to know that a type word should govern
  behaviour, which is domain knowledge. So the counting diagnostic is NOT
  built: its exemption list would be an open list the kernel enumerates.

- **The no-blob doctrine is gated, and glue is marked** (2026-10-03, TODO 5;
  no mint run, no engine re-minted). Three changes, each structural, none
  naming a builder, a language or a world.
  NO MODEL-WRITTEN SOURCE. A mint whose reply carries a `source` block is
  refused whatever else it holds, at three doors: `generate` (before any gate
  that costs a build), the draft door (so the model hears it inside its own
  call), and `check`/`compile`, which refuse a language folder holding an
  `artifacts/` tree (no committed example has one, so the corpus is
  untouched). The refusal names every file and three remedies: clauses, an
  existing package by name, or a gap naming the missing contract. The mint
  prompt lost its source-block form and its worked Go example, and now says
  there is no source to fall back on. The parser still reads a `source` block
  so the refusal can name the files. Unconditional, by decision: a program
  whose behaviour needs a capability no contract offers (`rotate`, TODO 4)
  is refused until that contract exists, rather than admitted as a blob.
  GLUE IS MARKED AT EMIT. A rule emit into `artifact.<n>.args.*` (except
  `src`, a path naming a tree) is stamped kind `Glue` instead of `Meta`
  (`Engine.Data.toRule`). Position is the one thing the kernel knows about
  foreign text: no schema declares a builder argument. The anti-MDA guard
  admits `Glue` only when DERIVED, so a program-level glue decision no rule
  maps is still refused as unmapped. The GRADE is read from the emit's
  TEMPLATE (`Engine.Data.emitTemplate`, replaying the one rewrite the
  provenance names): literal text the mint wrote makes it MINT glue, a value
  made only of holes makes it AUTHOR glue. Grounding now prints `N glue
  assertions by the author (stated)` beside the unvouched count, and one line
  per glue assertion graded `glue (mint, unpinned)`, `glue (mint)` or `glue
  (author)`. Rejected: a `glue` mark the mint writes itself. It would be
  syntax the model omits exactly when omitting it escapes a gate.
  MINT GLUE MUST BE RUN BY A CLAIM. A mint glue assertion is pinned when some
  `claim.<id>.run` names its artifact, directly or through another artifact's
  arguments (a wrapper exec'ing a core). `generate` refuses a world whose
  mint glue no claim runs (a per-world failure; the other worlds are still
  written), the draft door refuses it too, and `check` only reports it,
  because the committed `greet` carries exactly that (`echo` in two
  `args.text`, no claim) and moving it costs a re-mint.
  A COUNT CORRECTED ON THE WAY. The "mint-written words inside option strings"
  number was computed on FILLED values, so program words filled into a string
  counted as the mint's. It is now counted in the rule template. `website`
  falls from 70 to 57, and `hello.http` stays at 19.
  LIMITS, by decision. Code inside an OPTION string (`systemd.services.*.script`,
  nginx `extraConfig`) is measured by that count, but neither marked nor gated:
  telling computation from prose there needs shape guessing. A word is still a
  whitespace token, so `echo \"<value>\"` counts as three mint words. The
  machinery that judged a staged tree went in the next errand (below, "The
  staged-source machinery is gone").

- **A ground check reads its own line's contribution** (2026-10-03, the
  defect the plurality experiment found). A slot several program lines feed (an
  Append-assembled claim section or clause) holds one ground decision PER LINE,
  and `checkArtifactValues` judged every check against the first of them
  (`(a : _)`). So a family check `expect claim.main.equals-lines from call.<n>`
  held at one call and refused two (`should be [ "du" ], but is [ "hallo" ]`)
  for a program the engine realized correctly, naming a re-mint as the remedy.
  A check now reads the slot decisions DESCENDING from its own `from`
  decision. Refinement names every product `<parent id>/<rule>#<i>`
  (`Lips.Kernel.Refine.stamp`), so descent is an id prefix at any depth, and
  the program base rides in beside the ground one (two call sites in
  `Lips.Gate`), because refinement consumes the `from` decision. Chosen over
  "any contributor holds", which misses the drop that matters: two lines that
  print the same word, with the second one's contribution gone, still match
  the first line's element, and clauses keep repeats on purpose. The old
  first-contributor reading stayed in as an instrumented fallback for one corpus
  run: `lips check` over all 23 programs plus both experiment arms (10 ground
  checks) reached it ZERO times. So it is now a loud refusal naming the check,
  its `from` and the slot ("nothing call.2 produced reaches this slot"), pinned
  by a test, and the mint meets it inside its own call through the draft door.
  Evidence: `just check-expect` green with the same 23 verdicts as before the
  change, `just test-draft` OK, 978 examples. Probes against the one-call
  variant: `S-two` and `S-three` now compile and print every call (before:
  refused by the contract), and `C-two` is unchanged. Stricter than before: a
  check whose `from` is a SIBLING of the slot's feeder (two emits of one
  pattern line, with the slot filled by the other one) used to pass whenever
  the value happened to appear in the slot. It is now refused, naming the
  decision to cite instead. No committed contract has that shape.

- **The staged-source machinery is gone** (2026-10-03, the errand the no-blob
  gate left; no mint run, no engine re-minted). With model-written source
  refused at every door, nothing could stage, fill or judge a source tree, so
  the code that did is deleted rather than kept as a branch no input reaches:
  source fills (`Lips.Kernel.Source`, `realizeArtifactFills`, `rlFills`, the
  `artifact.<n>.fill.*` section, which realize now refuses as unknown: an
  artifact has a builder and args), the source-specification gate
  (`Lips.Gate.sourceSpecGate`, `Diagnose.sourceSpecVerdict` and
  `retiredConcepts`, and the editor warning `unobservedDiags` that only fired
  where a language held a tree), the staged-tree grounding class (`gStaged`)
  and its size report (`stagedSizes`), copying a committed tree
  (`stageFromDisk`), and generate's checks on a minted tree
  (`unnamedSources`, `claimlessBakedSource`, the source half of the
  frozen-shared-files check). What the gates stage beside a module is now its
  site, so `writeCompiled`, `worldGate` and `claimGate` lost the staging
  arguments that only carried a tree. The `source` block PARSER stays, so the
  refusal can name the files. Compiled output is byte-identical to before for
  `website`, `greet`, `board`, `habit` and `hello.http`, and all 23 examples
  pass `check`. The suite went from 978 to 952 examples: 27 removed, each
  pinning deleted behaviour, and one added (a `fill` section is refused).

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
- **Glue.** `Glue` is MARKED where the kernel can see it, a rule emit into a
  builder's argument, and graded author or mint by its template. Mint glue must
  be run by a claim before `generate` accepts it (Done, "The no-blob doctrine is
  gated"). Text inside an option string is counted but not marked. Property
  testing over glue is not implemented. This is the wall
  behind the expressiveness frontier: the closed rhs value language forbids
  computation by construction (which is what makes injection unrepresentable),
  so an engine can *reference* a prebuilt package (`${pkgs.cudaPackages...}`,
  `${pkgs.someGuiApp}`) but cannot inline a bespoke build (compiling a CUDA
  kernel inline). Concretely: GPU/GUI domains are reachable now
  for prebuilt stacks (they are just more NixOS options, bools, lists, and
  package refs, all of which the value language expresses). What is blocked
  without glue is a *computed value inside the decision layer*. Building a
  program from model-written source is refused since 2026-10-03; behaviour
  goes in clauses. Glue and artifacts are
  separate axes; glue is deferred as far as possible.

### Verified Breakages (Broken Promises, Review of 2026-07-29)

Each item was reproduced against `main` at 95e80f7 and states the promise it
breaks; listed here because a ledger that only records wins is a map of a
different territory. The two still open are open BY DECISION, stated with each
entry, so neither is carried in `TODO.md` as work waiting to be done.

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
- **Artifacts: deferred pieces.** The core landed (see Done). Model-written
  source is refused since 2026-10-03, and the *fill* and staged-tree machinery
  is deleted (Done). Still open: dependency-fetching builders (a
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
  collide. Nixpkgs was resolved ambiently (`flake:nixpkgs`
  registry) when this landed; since 2026-10 a compiled flake names the
  record's grounding pin where it has one (see "A compiled directory runs the
  nixpkgs its rules were grounded against"), so compile still fetches nothing
  and stays bit-identical. `home-manager` (no machine) emits the module and
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
  - Glue: builder arguments are marked and mint glue is claim-gated (Done). A
    computed value inside the decision layer stays the one documented
    incompleteness.
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
  baked-source programs stating no observable at all (`TODO.md`, the witness
  item).
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
- **No per-program source written by a model (settled 2026-08-04, gated
  2026-10-03).** A blob is admissible only where it is NOT per program and
  reviewed once (an adapter under `assets/runtime/`, serving every program), or
  where it is somebody else's package reached by name. Behaviour a program
  states goes in clauses. A mint that writes source is REFUSED, at generate, at
  the draft door and at check, with no exception for a capability no contract
  covers (files, clocks, sockets, as `experiments/validate` measured with
  `rotate`). Such a program waits for the contract; it is not admitted as a
  blob, because refusing the mechanism is what makes the missing contract
  visible as a gap. `logscan` spent months as the counter-example (76 lines of
  Go, roughly fifteen traceable, two mints disagreeing about what the program
  did, every gate green) and is now clauses.
  The escape for a genuine one-off is a VALUE, never a file: `greet`'s four words
  of bash are bounded by sitting in one assertion attached to one program line,
  where a staged tree has no such bound and grew to 76 lines. Two grades deserve
  different trust, and the kernel tells them apart from the rule's template:
  AUTHOR glue, whose foreign text is in the program, is legitimate without
  qualification; MINT glue, where the model chose it (`echo` in `greet`), is
  marked kind `Glue`, counted (`Lips.Kernel.Grounding`), and refused at generate
  unless a claim runs its artifact, since it is exactly what a re-mint rewrites.
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
  Qualified 2026-10-02 (Done, "A singleton call stays a hole"): "may fold" is
  the accurate verb. opus-5, shown one call, did not fold it, and whether an
  uncontrasted word becomes a hole or a literal varied between two mints. What
  plurality reliably buys is a contrast that EXERCISES the hole. An
  uncontrasted hole can be kept and still govern nothing (a type word landing
  in dead code), which a count cannot tell from an honest one.
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

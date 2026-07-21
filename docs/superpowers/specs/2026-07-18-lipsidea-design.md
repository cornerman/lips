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
  `2026-07-21-artifacts-plan.md`.
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
  (`Kernel.Lang.Lang` is a cosmetic doubled name, the `.lang` store module;
  harmless, not yet renamed.)

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

### Partial

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
  like `Generate.PiJson`. Remaining polish: hover and go-to for a line's
  produced subject, as-you-type completion tuning, and percent-decoding of
  `file://` URIs (paths with spaces/non-ASCII are not handled yet).
- **Deduce-or-fail via resampling.** The harness `unanimous`/`coreOf` check is
  built and tested, and the confidence threshold is now a CLI flag, but
  `generate` still samples the model once. Missing: `--samples` wiring so a
  deduction must recur identically across samples.
- **Behavioral gate: remaining.** The gate (see Done) runs at `generate` and
  via `lips check`; it is not yet enforced inside `run`, where a deterministic
  re-check on every offline run would catch a program edit that breaks a
  pinned relation. Assertions name concrete option paths, so a legitimate
  mechanism swap always re-blesses (mechanism-independent assertions would
  need the unbuilt vocabulary/ontology). A cross-program corpus still does not
  typecheck because engines are per-problem (`feed.loose.lang` and
  `backup.loose.lang` are independent); the gate is per-program by design.
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

### Missing

- **Live host deployment.** The VM smoke test proves the module class; wiring
  one realized module into `~/nixos` on `wolf` is now reduced to "import one
  file" and remains optional symbolism.
- **Home-manager realization target.** A home-manager module and a NixOS module
  share one shape: `realize` already emits a domain-blind
  `{ config, lib, pkgs, ... }: { <path> = <value>; }`, so an engine that mints
  home-manager option paths (`programs.*`, `systemd.user.services.*`,
  `home.*`) yields a valid home-manager module today with zero kernel change
  (the "kernel knows nothing" law: the module form is universal, only the
  namespace differs). What is missing is a second realization *target*, not
  kernel work: (a) the run/check harness assumes NixOS (`nixosSystem` +
  qemu-vm boot; NixOS option eval), whereas home-manager evaluates through
  `homeManagerConfiguration` and activates by `home-manager switch` (no
  "boot"); (b) the target must enter generate as a pinned input (like the
  direction file), since the mint prompt is domain-blind and nothing currently
  tells the model which namespace to target; (c) the `.expect` gate and VM
  smoke need the parallel home-manager eval entry point. Same axis as the
  deferred run-modes/Solution-kinds work. Good fit for `wolf` (NixOS *and*
  home-manager), where a per-user Solution (a user timer, a configured program)
  lands in home-manager naturally.
- **Artifacts: deferred pieces.** The core landed (see Done). Still open:
  artifact source is a fixed blob baked at generate (not templated with holes),
  so a value that must appear *inside* the compiled program needs regeneration
  rather than flowing through `print`; dependency-fetching builders (a
  `cargoHash`/`vendorHash` over fetched crates) move the fetch to generate and
  are untried (the proven path is no-dependency source, e.g. Go stdlib with
  `vendorHash = null`); container/registry push stays Heile-Welt coping. A
  build needing *arbitrary* Nix (custom overlays, hand-built derivation graphs)
  remains glue, deferred.
- **Multi-token tail holes.** A template hole binds one token (or one quoted
  span); there is no "tokens N onward" slice. A live mint that joined a port
  and a multi-word message into one subject could not cleanly extract the tail
  and fell back to the whole value. Sibling-subject patterns avoid it; a tail
  hole is future value/template-completeness work.
- **Activation verb: DONE, as the `print`/`run` split.** The CLI now separates
  emitting from running (superseding the planned `lips up`): `lips print
  <program>` is the pure deterministic printer (crystallize -> realize ->
  module text on stdout); `lips run <program>` realizes and then literally runs
  it by wrapping the module in a nixosSystem and booting a headless local QEMU
  VM (impure, via ambient `<nixpkgs>` and the stock qemu-vm module; the host is
  never mutated -- the VM is the Heile-Welt simulation of the target machine).
  Note: the design's "generate/run loop" prose uses "run" for the deterministic
  realize step, which is now the `print` command; `run` is the activation verb.
  A `nix develop` shell for shell-shaped Solutions remains possible later.
  Host deployment stays a separate, explicit, privileged step.
  Run modes considered and DEFERRED (VM-only for now): two axes exist -- (a)
  activation backends over the same module (vm / systemd-nspawn container /
  host nixos-rebuild), a future `--mode` flag; (b) `nix-shell`, which is not a
  mode of running a system module but a different realization target (the
  engine emitting `mkShell`), meaningful only for a shell-shaped Solution, so
  it belongs with the artifacts / Solution-kinds milestone.
- **Direction file (done).** Optional owner taste for the mint: per-program
  `<program>.direction`, plain text, appended to the minting prompt when
  present. Sharp boundary: the program states what must be true; direction
  states what to prefer (mechanism taste: restic vs rsync, no docker, secrets
  via env files). Direction never carries obligations -- anything that must
  hold belongs in the program (a decision) or `.expect` (an assertion); the
  appended guard states this rule to the model ("PREFERENCE, not requirement;
  never override a value the program states"). Pinned for free: direction
  enters the system prompt, which the `.generation` record embeds verbatim, so
  it enters `genId`. `print`/`run`/`check` never see it. Also softens mechanism
  churn across regenerations (same taste, stable mechanisms). Pure composition
  in `Minting.promptWithDirection`; `generate` reads `<program>.direction` and
  passes the composed prompt to both `callPi` and `record`; `Record` unchanged.
  A repo-wide direction file was rejected (ambiguous search root, comes from
  nowhere); ambient `AGENTS.md` is deliberately excluded (the mint is hermetic
  via `pi -nc`), so this per-program file is the sole owner-taste channel.
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
  `2026-07-20-completeness-plan.md`.
  - Value completeness: DONE (8ffd70d). `Value` now covers the Nix value
    algebra minus computation -- string, list, bool, int, float, path, null --
    and a typed hole `<value:int|bool|float|path>` (and `<value.N:...>`) fills
    a non-string option from a program token, coerced and fail-loud, injection
    still closed. Deferred: `VAttr` literal (nested attrsets are expressible as
    deeper option paths). Unblocks the int-typed port.
  - Template completeness: DONE for the nginx case (d4c4468). The tokenizer is
    quote-aware: a `"..."` span is one token whose surface is its inner text
    (quotes dropped, spaces kept), so a normal hole captures a quoted value,
    and a template `"<body>"` reads as a capturing hole. Bullets need no block
    machinery: `-` is just a literal token, and each item stays a distinct
    decision by putting its own value (the path) in the subject. Deferred:
    unquoted multi-token holes (bind several words up to a literal) and true
    parent-child block aggregation (a decision that owns a list); neither is
    needed yet.
  - Glue: TODO. The one documented incompleteness (computation).
- **Language migration.** When `.lang` regenerates to a different shape, there
  is no diff or migration path for existing programs.
- **Multi-language composition.** The sketch composes three languages in one
  decision base; the prototype runs one engine. Composing several
  engines/languages in one Solution is unbuilt.
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

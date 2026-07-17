# lipsidea Design

Status: approved concept design. Evidence base: the four surveys in
`docs/superpowers/survey/` (cited below as Survey A/B/C/D).

## Terminology

- **Kernel**: the self-describing spec-language itself.
- **Vocabulary**: a problem-specific language minted in the kernel.
- **Solution**: an application spec written in one or more vocabularies. The
  human-authored artifact.
- **System**: kernel + vocabularies + compiler + Nix realization. The
  engineered substrate a Solution runs on.
- **Glue**: Solution content outside any vocabulary, written directly in the
  general substrate. Legal, marked, and second-tier by design.
- **Application kind**: a platform's notion of a runnable unit. Canonical
  kind: a NixOS module.

## 1. Thesis

AI produces code faster than humans can review it. Reviewing mechanism-level
diffs at AI speed is a lost race, so the human-reviewable artifact must move
up to intent: dense, precise, and small. That artifact must then execute
deterministically; a second model guessing at realization time would
reintroduce the unreviewable gap.

lipsidea is therefore a spec-language with one structural commitment: **zero
LLM inference between a Solution and its realized system**. AI participates
only at authoring time, and everything it produces (Solutions, vocabularies,
even compiler implementations) is a human-verifiable artifact checked against
a specification.

Survey D confirms this position is unoccupied: every surveyed spec-driven
tool of 2023-2026 (GitHub Spec Kit, AWS Kiro, Tessl, BMad, OpenAI's "spec is
the new code") places an LLM exactly where lipsidea places a compiler. Tessl,
the closest competitor, regenerates different code from an unchanged spec.
The field's own critics ("false sense of security", LLM-graded gates being
silently ignored) describe the failure without naming the fix.

The deliverable form of lipsidea is a rigorous language specification, not a
blessed runtime. Any conforming implementation must behave identically; a
conformance suite, not ownership of a VM, polices the ecosystem.

## 2. Architecture: The System/Solution Split

The System is the concentrated engineering artifact: built once, verified
hard, evolved slowly, by experts using AI labor under human verification.
The Solution is what a human writes for a problem: thin intent in the perfect
language for that problem, carrying decisions and nothing else.

The governing invariant: **a Solution may contain nothing that the System
could have known.** This is simultaneously

1. the review criterion for Solutions (anything mechanism-shaped in a
   Solution is a defect),
2. the promotion rule for the System (recurring glue across Solutions means a
   vocabulary is missing), and
3. the health metric of a codebase (the glue-to-intent ratio).

Vocabularies are minted freely, per problem. Comprehension transfers because
every vocabulary shares the kernel's uniform meta-structure: reading a new
vocabulary's definition is cheap, and its tooling is derived, not hand-built.
An application typically composes several vocabularies (a CRUD core, a
pipeline, a CLI) in one Solution; the intent level is fully general, so
nothing is ever inexpressible, and gaps are filled with marked glue inline.

The canonical application kind is a NixOS module. The compiler emits
target-language artifacts plus Nix expressions that build, wire, and deploy
them; Nix is the universal deterministic realizer, not the logic runtime.
The NixOS module system is also the architecture's production proof: twenty
years of typed, mergeable, per-domain vocabulary over one general lazy
substrate, zero LLM anywhere (Survey D, verified firsthand via nix eval).
terranix demonstrates the module machinery retargets beyond NixOS.

## 3. Kernel

One substrate, self-describing in the Racket `#lang` sense (Survey A's
closest structural precedent): the meta-language and the object language are
the same material, so minting a vocabulary is writing in the substrate, not
filling a foreign schema. Vocabulary definitions, and eventually the kernel's
own semantics, are written in the kernel.

Design commitments, each anchored to surveyed evidence:

- **One definition, many backends** (K Framework discipline, Survey A): a
  vocabulary's single definition derives its checker, its compiler, and its
  documentation. No hand-written second path.
- **Derived static checking with proven determinism** (Statix scope graphs,
  Survey A): name binding and typing rules come from a constraint formalism
  with a stability guarantee, not an ad hoc checker per vocabulary.
- **The MPS aspect checklist** (Survey A): a vocabulary definition must
  expose structure, constraints, type rules, editor bindings, and generator.
  These aspects make tooling derivable. Projectional editing is rejected:
  specs stay ordinary text, diffable by git and writable by AI.
- **Semantics-rigor and tooling-completeness are separate achievements**
  (Survey A's central cross-cutting finding: K has rigorous semantics and no
  generated editor tooling after ten years; Langium is the inverse). The
  kernel architects for both explicitly.
- **Tooling is a zero-cost export**: checker, completion, hover docs, errors,
  formatter, and option search derive from the same typed declarations the
  compiler checks (the search.nixos.org model, Survey D), from day one.

Four defects of the Nix substrate, fixed as kernel primitives (Survey D):

1. Options, types, merging, and priorities are **language primitives**, not a
   library convention. Nickel's postmortem pins Nix's bad error messages and
   poor discoverability on exactly this decision.
2. **Provenance is first-class data** surviving every compilation stage; the
   `<unknown-file>` degradation class of error is architecturally impossible.
3. **Escape hatches carry visible blast radius in the type system.** Nix's
   `freeformType` silently disables typo checking; lipsidea's glue marker
   visibly widens what the checker can promise.
4. Derived documentation and search are compiler outputs, not ecosystem
   afterthoughts.

## 4. Rigor Allocation

The reviewer's metric is comprehension per minute; proof burden must never
land on the Solution author. Survey C's evidence (seL4 at 50 proof lines per
code line, IronFleet at 3.7 person-years despite SMT automation, Amazon's
TLA+ at 2-3 weeks to learn) fixes where each rigor level is affordable:

| Layer | Rigor | Precedent |
|---|---|---|
| Vocabulary definition | SMT-automated proof or TLA+/Alloy model checking, paid once by the author | HACL* verified crypto consumed by Firefox without re-verification |
| Solution, vocabulary path | Decidable checks only: instant, total, no proof visible to the reviewer | Dhall, CUE, Elm |
| Solution, glue path | Syntactically marked; property and conformance testing, never silent trust | Agda TERMINATING, Koka div effect |
| Kernel compiler and runtime | Conformance suite; optionally full proof if resourced | WASM spec+testsuite, SQLite 590:1, CompCert |

The glue marker is one construct with two meanings: the expressiveness escape
hatch (nothing is inexpressible) and the rigor boundary (past this point,
guarantees downgrade from checked to tested). Solutions inherit their
vocabularies' once-paid guarantees.

## 5. Failure-Mode Defenses

Survey B's ranked taxonomy of how every prior "humans state intent, machine
does the rest" attempt died, each mapped to the design property that blocks
it here:

1. **Escape-hatch decay** (CASE, MDA, Helm, low-code: humans edited the
   generated artifact and the abstraction died) → glue lives inside the typed
   kernel; compilation is one-directional; generated output is disposable and
   never hand-edited.
2. **Economics before maturity** (STEPS, Eve, Dark) → the System must be
   useful to one owner at small scale immediately; no adoption threshold is
   load-bearing.
3. **Vendor and research lock-in** (Wolfram, Intentional, Dark) → the
   compile target is an open, independently inspectable artifact (a NixOS
   module), and the language itself is a public spec with a conformance
   suite, not a proprietary runtime.
4. **Loss of human legibility** (UML as wall decoration) → the Solution is
   the permanent source of truth with defined execution semantics; drift
   between model and system cannot open because only the model compiles.
5. **All-or-nothing adoption** (STEPS, Dark, early Eve) → one Solution
   compiles to one ordinary NixOS module, deployable beside hand-written
   modules on an existing machine.
6. **Platform death by owner neglect** (HyperCard) → the realization layer
   (Nix/NixOS) has independent governance; lipsidea does not own a runtime
   that can be orphaned.
7. **The natural-language trap** (4GLs' "English for managers"; Inform 7
   succeeds only by domain narrowness) → vocabularies are formal and dense,
   aimed at software-literate owners; no fake English.
8. **Interface research blocking a sound core** (Eve) → authoring is plain
   text for experts; no novel UI problem stands between the design and
   shipping.

## 6. Open Questions

Deliberately unresolved here, owned by the next phases:

- **Notation surface**: the concrete syntax family. Resolved by the language
  sketch, working backwards from what a reviewer should read.
- **Kernel base formalism, concretely**: how much of K's matching logic vs a
  smaller rewriting core; how Statix-style constraints embed. Resolved during
  prototype design.
- **Vocabulary promotion mechanics**: how project-local vocabularies migrate
  into the shared uber framework (curation, versioning, compatibility).
- **Naming**: "lipsidea" is the working title.

## 7. Phases

1. **Design doc** (this document).
2. **Language sketch**: one example application spanning three vocabularies
   (web CRUD core, ETL pipeline, CLI) written out in candidate notation,
   plus the definition sketch of one vocabulary. Feeds back into this doc.
3. **Prototype**: the three vocabularies and a reference compiler emitting
   target-language artifacts plus Nix wiring, realized as NixOS modules.
   The reference implementation is explicitly non-privileged; the spec and
   conformance tests remain the source of truth.

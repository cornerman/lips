# Erkenntnisse: Where lips Stands, and How Logic Gets In

Record of one working session (2026-08-02). It states what was settled, what was
rejected and why, what is still open, and the experiment that decides the rest.
Evidence lives in Surveys G through K; this file is the argument, not the
citations.

## 1. The Position Is Real and Now Has Numbers

Three schools answer the 2026 review bottleneck. Automate the review and keep
the pile of code. Prove the code correct against a formal statement somebody
still has to write. Shrink what a human reviews to intent and derive the rest.

lips is in the third and is its only deterministic member. The move that
separates it from every other spec-driven tool is that the model's output is a
**compiler**, not code: an engine is reviewed once and amortized over every
later compile, where the rest re-guess the artifact on each run.

That position does not decay as models improve, because the claim is
reproducibility rather than accuracy. A perfect model that emits a different
valid implementation on each run still leaves nothing to diff, bisect or audit.

## 2. Model-Driven Engineering Narrowed, It Did Not Die

The folk story ("MDD died, AI removes the reason") was too crude and is now
corrected in README and DESIGN. Surveying 450 practitioners, Hutchinson,
Whittle and Rouncefield found developers "rarely use it to generate whole
systems; rather, they apply it to develop key parts of a system often using
domain-specific modeling languages developed specifically for the purpose".

What died was one universal notation with a hand-editable middle layer and a
per-domain generator somebody had to maintain. What works is lips's own shape.
The mint removes the cost that kept that shape rare.

The ledger's honest half: three causes eliminated by AI, six mitigated, five
untouched, one worsened. The worsened one is non-determinism reintroduced at
the generation step, and it is not hypothetical here (see 5).

## 3. The Vocabulary Scaling Law

lips reaches exactly as far as some external, named, typed vocabulary of
mechanism reaches. Fourteen-line engines produce working systems because
nixpkgs defines, types and tests every name a rule emits; the engine only
selects and fills.

Two consequences. Breadth comes from new worlds rather than new physics, so
home-manager, kubenix and terranix cost zero kernel changes and any
schema-bearing world is a candidate on the same terms. Application code is
reachable only where a framework has already turned itself into configuration,
and where it has not, the entire correctness burden falls on claims.

## 4. Nix Is the Substrate, and It Is Complete Without Owning Computation

Three layers stay distinct: substrate (Nix, permanent), world (the option
vocabulary, open axis), surface (the target's own artifact, so a Kubernetes
user never learns Nix).

The substrate does not move because a NixOS configuration is an unordered set
of `path = value` assignments merged by path with priorities, which is the
decision calculus in different words. Realizing is close to a homomorphism.
Any substrate composing differently would need an adapter, and the only place
that adapter could live is the kernel.

The deeper lesson, which decided the whole logic question later: **Nix can
build anything and never understands a line of C++.** It owns the derivation
interface, a name, typed inputs, a builder reference, an output hash, and
treats bodies as opaque. Completeness comes from naming and wiring, not from
owning a compute grammar.

## 5. The Artifact Axis Is Empirically Broken

(Historical as of 2026-08-04: the `logscan` measured below was re-minted as
clauses and its Go is deleted. The numbers stand as the evidence that motivated
the axis; the file they describe is no longer in the repo.)

`examples/logscan` is five lines of intent and 76 lines of minted Go. Commit
885a900 added one sentence, a worked example pinning a string match, and
re-minted. The result differs from the previous mint in what the program DOES:
field matching gained numeric coercion, the bad-argument exit code moved from 1
to 2, the maximum line length moved from 10MB to 16MB.

An audit of that file traces roughly fifteen of its 76 lines to the five
sentences. The rest is invented policy, including a silent `continue` on
malformed JSON, which contradicts fail-loud doctrine while every gate stays
green.

So the objection "AI writes horror code that becomes unmaintainable" is exactly
right about the current design, and it is the strongest argument for changing
it. Under the direction below that same code is build output, regenerated,
gitignored, never read, and its quality stops being load-bearing. That holds
only while nobody hand-edits it, which is how CASE tools died and is already
invariant 4.

## 6. Clause Union Is the Discriminator

Surveying candidate target languages, the criterion that separates the field is
not typing, breadth or popularity. It is how two independently written pieces
combine.

Rego's documentation describes its merge in lips's own vocabulary: incremental
rules union ("the union of the documents produced by each individual rule"),
complete rules conflict when they disagree. That is `Append` and `Replace`
verbatim. DMN's hit policies are the same idea declared per table. Catala's
`exception` keyword goes further and makes priority a relation between two
named clauses rather than a global authored integer, which is the third option
beside structural strength and the priority integers that decayed in CSS,
Drools and XACML.

dbt is the instructive false positive: it nails external vocabulary, breadth
and independent growth, and fails because it composes by DAG. Ordered or
imperative composition drags target-specific knowledge into a domain-blind
kernel.

## 7. The Paradigm Was Forced, Not Chosen

Write down every constraint already committed to and exactly one shape remains:

**Pure, first-order definitions given by non-overlapping pattern clauses over
named external primitives, with general recursion, no effects and no
higher-order values.**

Each part is forced. Clauses keyed by a name because that is the decision base.
Non-overlapping because `Refine.hs` already makes it so ("at most one rule ever
fires per decision, rewriting is a function, hence confluent for free"), which
is static orthogonality replacing Prolog's clause order and cut. Pure and
first-order because that is what makes a clause testable alone and renderable
anywhere. Named primitives because the kernel must not define computation.
General recursion because completeness is non-negotiable and is inherited
(recursion equations) rather than built.

Constrained functional programming and deterministic Horn clauses are the same
object here, argued from two traditions. lips already owns the evaluator: a
96-line file whose own header calls it "the lips analogue of eval".

## 8. What Was Rejected Along the Way

**A kernel-owned computation grammar** (a term or lambda core, complete by
construction). Rejected because Nix refutes the premise by example: a kernel
that owns computation pays for a programming language the substrate proves
unnecessary.

**A total combinator grammar** (pipelines, guards, no recursion). Rejected on
completeness: it can say "cannot express this", which is forbidden.

**Name-only reachability** (only ever reference existing libraries). Same
reason.

**Per-host renderers written as kernel code.** Rejected on the project's own
test: a capability is complete when a language nobody foresaw works with no
kernel change. A renderer per host is a permanent marginal cost, so the design
that needs one is wrong.

**Rust as first host, and Go plus Rust as a checker pair.** Rejected because
`logscan` needs JSON, which Go has in its standard library on the proven
`vendorHash = null` path while Rust needs a crate and the untried vendoring
path, and because a second host is a recurring cost bought for a check the
kernel must implement anyway.

## 9. Two Layers, and the Nix Pattern Applies to Both

**Layer A, the description language**: per problem, minted, disposable. Built.

**Layer B, the inside language**: what behavior is written in. This is the new
choice.

Layer B gets Layer A's structure. One base notation, identical everywhere, plus
a **primitive vocabulary per runtime**: files and processes natively, DOM and
fetch in a browser, interop on a JVM. Exactly as `services.*`, `programs.*` and
`kubernetes.resources.*` differ over one Nix. A clause set runs where its
primitives exist, and adding a runtime is adding a vocabulary, which is data.

## 10. Still Open, and These Are the Expensive Ones

**Open predicates.** A predicate whose facts arrive at runtime rather than at
compile time, which is Datalog's EDB/IDB split read sideways in time. The
soundness condition inherited from incremental dataflow: a clause reading an
open predicate must otherwise be pure. This is the only genuinely new physics
the axis needs.

**The primitive signature vocabulary.** The artifact-axis analogue of choosing
nixpkgs. Candidates: a host's own standard library (simple, but silently picks
the runtime), WIT (names behavior without naming an implementation language).
R7RS-small has no JSON, so vocabulary fragments per runtime even when the base
notation does not; that is the concrete shape of this problem.

**Unmeasured, and it governs the economics**: the mint-decay curve, the ratio
of edits that merely compile to edits needing a fresh mint, over time, on one
real growing program.

**No answer at all**: brownfield adoption, and the organizational causes the
MDE literature found dominant, which lips scopes away rather than solves.

## 11. What Success Looks Like, Measurably

Every clause names the program line that caused it, so invented policy either
disappears or surfaces as a demand the author answers. A claim over one
rendered definition passes offline with no VM. Two mints of one program differ
only where the program differs.

The number to track from the first experiment onward: what fraction of a
program's stated behavior lands in clauses versus in an opaque named artifact.
If something as ordinary as `logscan` cannot stay in clauses, the direction is
wrong. If you ever want to hand-edit rendered output, the direction is wrong.

Honest gaps carried forward: no controlled study shows proof-tree explanations
help humans; debugging at the wrong level is the one documented MDD failure no
AI capability touches; the proof tree survives as review artifact only while
`.expect` stays the acceptance gate.

## 12. The Way Out Is Lisp, and It Is Not a Preference

Four constraints collide for every non-homoiconic host. Completeness, so
nothing is unbuildable. The kernel owns no computation. Nothing is emitted as
opaque text, or injection and unreviewability return. Adding a language costs
nothing marginal.

Keeping code as data means holding an AST. Turning an AST into Go or Rust means
a printer. A printer is per-host knowledge somebody owns forever. So you either
abandon code-as-data and emit strings, or you pay per host. There is no third
option.

**In Lisp the AST is the surface syntax.** The structure lips manipulates and
the program the machine runs are the same object, so emitting is serialization
rather than translation, and the renderer, the largest new component in every
earlier version of this design, does not exist.

The consequence is a correctness property, not an aesthetic one. With any
renderer, gates prove something about clauses and an unverified translator
produces what actually runs; the checked object and the run object differ, and
the gap is where drift hides. With s-expressions there is no gap: overlap,
exhaustiveness, signature checks and provenance all apply to the artifact
itself. **No trusted translator exists, because no translation happens.**

We do not own a language. We own a **subset we are willing to emit** into
somebody else's standard: clause forms, calls to named primitives, literals,
recursion. No macros, no mutation, no `eval`, no dynamic loading. Chez or Guile
implements Scheme; lips owns a gate, not semantics.

And the commitment is the *small* one, which inverts the fear that choosing a
host commits too much. Go commits you to one runtime. A tiny R7RS-small subset
commits you to a notation with many independent implementations: Hoot compiles
R7RS-small to WebAssembly and runs on Firefox 121+, Chrome 119+, Safari 26+ and
Node 22+, which works because Wasm 3.0 ships tail calls and garbage collection;
Kawa supports almost all of R7RS on the JVM; Chicken and Gambit compile through
C to small native binaries; Guix is the existence proof that Scheme carries
system work in production. Anything not clause-shaped stays reachable the way
everything else already is, as a named package in any language, built by Nix.

Recommendation, then: **emit a small R7RS-small subset as s-expressions, take
Guile as the first native runtime and Hoot as the browser leg, defer the JVM
and the C-compiled dialects until someone asks, and keep the kernel in
Haskell**, because the closed value grammar as a sum type with compile-time
exhaustiveness is worth more than homogeneity of implementation language.

The first experiment is `logscan` as clauses on two runtimes, native and
browser, checked against the same contract. One afternoon, no kernel changes,
and a failure kills the direction cheaply.

lips is Lisp rearranged, and DESIGN's founding line has always been that intent
is data and realize maps decisions to systems. Arriving back at code-as-data
was not taste. Four independent constraints forced it, which is the best kind
of evidence a design decision can have.

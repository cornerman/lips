# Logic as Data: Rendering Pattern Clauses Into Host Languages

## Where This Landed

lips compiles plain intent into `path = value` assignments over a typed
external vocabulary; the kernel is domain-blind and its rule right-hand sides
are a closed value grammar with no computation and no injection by
construction (`kernel/src/Lips/Kernel/Engine/Value.hs`). Configuration fits
that grammar because a configuration value is a leaf. Program logic does not,
because logic is computation, and today it escapes through "artifacts": AI
writes a Go file once into `<language>/artifacts/`, `buildGoModule` compiles
it deterministically forever after, and the only ground truth is an
observable test (`examples/http/artifacts/hello/main.go`). DESIGN.md's own
ledger admits the resulting gap: "a program whose behaviour lives in baked
source could state a sentence, have it minted into code, and have that code
drift with every gate green" (`DESIGN.md`, section 13).

The paradigm question is now settled, not open. The artifact axis is a pure,
first-order function defined by non-overlapping pattern clauses over named
external primitives, with general recursion, no effects, and no higher-order
values. This is the same object database theory calls deterministic Horn
clauses and the functional-programming tradition calls a constrained,
first-order functional program; lips already has half the machinery, because
`Refine.hs` makes rewriting a decision via more than one rule an `Overlap`
error ("at most one rule ever fires per decision, rewriting is a function,
hence confluent for free: same base, same result, always",
`kernel/src/Lips/Kernel/Refine.hs`), which is exactly Prolog's clause-order
and cut mechanism replaced by a static orthogonality check. Execution is by
**rendering** the clause set into a host language's own pattern matching, not
by shipping an interpreter: the host compiler supplies speed and type
checking, and a kernel interpreter survives only as an offline test oracle
that checks the rendered artifact against the same semantics before either is
trusted. What follows tests that design against four separate bodies of
prior art, adversarially, rather than surveying the wider field again.

## 1. Rendering: Does a Non-Overlapping Clause Set Compile Faithfully

The strongest existing evidence that this works is Soufflé, a Datalog
compiler that targets not an interpreter but a mainstream host's own
compiled representation: "Efficient translation to parallel C++ of Datalog
programs (CAV'16, CC'16)"
(<https://raw.githubusercontent.com/souffle-lang/souffle/master/README.md>).
Soufflé does not ship a Datalog virtual machine as the thing users trust; it
compiles rules to C++ and lets a mainstream, independently-verified compiler
(GCC or Clang) own the resulting speed and type checking, which is the exact
shape lips proposes for its own artifact axis, one layer up (host pattern
matching rather than host loops). Soufflé's own docs are explicit that a
Datalog program is a fact base (ground clauses) plus rules, and that rules
"can have multiple heads" as sugar for several single-head rules
(<https://souffle-lang.github.io/rules>), meaning the clause-to-clause
boundary Soufflé compiles across is the identical boundary lips's `Overlap`
check polices: one derived fact, one rule, by construction.

The second body of evidence is about the compilation step itself, not the
target language: Maranget's "Warnings for Pattern Matching" gives the formal
definitions a renderer must satisfy before it is allowed to hand a clause set
to a host compiler. Two anomalies are named precisely: "Matrix P is
exhaustive, if and only if, for all value[s]..." every value is matched by
some row, and "Row number i in P is useless, if and only if there does
not" exist a value that reaches row i without an earlier row matching first
(<PDF fetched from Maranget's own site, "Warnings for pattern matching", J.
Functional Programming>; the paper states plainly that "ML compilers should
normally flag pattern matching expressions that do not comply with those two
basic assumptions", non-exhaustive or containing useless clauses). Maranget's
algorithm is not a curiosity; it is the actual check OCaml and, per the
paper, Haskell tooling run before trusting a clause set to a compiled decision
tree, and it names the exact two failure modes a lips renderer must refuse
before ever handing clauses to Go, Rust, or Python: a clause set that is
non-exhaustive (some named external-primitive input produces no matching
clause, silent undefined behavior at the host level unless the renderer
inserts an explicit refusal case) and a clause set with a useless clause
(subsumed by an earlier, more general pattern, meaning `Overlap`'s check
already prevents this for lips specifically, since two clauses whose patterns
overlap are rejected before render time, not silently shadowed the way an ML
compiler's later clause would be). Augustsson's classic decision-tree
compilation approach (referenced throughout the pattern-matching-compilation
literature as the technique ML compilers use to turn a clause matrix into an
efficient branch tree) is the OTHER half of the same argument: decision-tree
compilation is well understood, decades old, and implemented independently in
at least OCaml, Haskell, Rust and Elixir's pattern matchers, which is strong
circumstantial evidence that the RENDERING step (clauses to host branches) is
not the risky part of this design; the risky part is upstream, in guaranteeing
the clause set was exhaustive and non-overlapping before rendering, which is
precisely what lips's own `Overlap` gate and Maranget's exhaustiveness check
both exist to do.

What breaks, concretely, if either check is skipped: an overlapping clause set
rendered naively produces host-dependent behavior (Go's `switch`, Rust's
`match`, Haskell's guards and Python's `match` statement each resolve
overlapping cases by SOURCE ORDER, silently, with no error), so the exact same
lips clause set could render to different running behavior in different
target languages unless the renderer either refuses the overlap outright
(lips's actual choice, via `Overlap`) or canonicalizes an explicit order before
printing, reintroducing the priority-number problem Section 4 argues against.
A non-exhaustive clause set rendered naively produces a host-level partial
function: Go's `switch` falls through silently, Rust's `match` is a compile
error (the one host where the check is free), Python's `match` raises at
runtime. The renderer's obligation, given this, is to run Maranget-style
exhaustiveness checking itself, in the kernel, before printing, and never to
lean on whichever host happens to catch the case (only one of four mainstream
hosts sampled here, Rust, catches it for free); this is the one place where
"the host compiler gives speed and type checking" is not quite true without a
kernel-side check first, and the survey flags it as the sharpest engineering
requirement Question 1 surfaces.

## 2. Open Predicates: Facts That Arrive at Compile Time Versus Run Time

The one genuinely new kernel concept in the settled design is a predicate
whose facts are not all known when lips compiles: a boundary between
"evaluate now, to build the system" and "evaluate later, because it is the
running program". Datalog already names this split and has for decades:
Soufflé's own facts page defines the base case precisely, "facts are clauses
that unconditionally hold; they are rules with a head, but no rule body... in
facts, all arguments must be constant terms" and notes "facts can also be
loaded with the input directive"
(<https://souffle-lang.github.io/facts>), meaning a base (extensional)
relation can be populated from outside the program text entirely, at a time
the rules themselves do not control. This is the textbook EDB/IDB split
(extensional database: relations given as ground fact input; intensional
database: relations derived by rules), and lips's open predicate is the same
split rotated ninety degrees: instead of "these facts arrive from a file
before Datalog runs," it is "these facts arrive from the running system after
lips compiles." The direction of the arrow changes; the discipline the split
demands does not.

Partial evaluation names the discipline directly, under the term binding-time
analysis: a program's variables (or, for lips, a clause's arguments) are
classified STATIC (known at the earlier stage) or DYNAMIC (known only at the
later one) before any specialization happens, and every operation in the
program must be checked against that classification, because an operation
that needs a dynamic value at a point the analysis believed static is exactly
the class of bug a staged system exists to rule out. This is well-established
programming-language theory (Jones, Gomard and Sestoft's "Partial Evaluation
and Automatic Program Generation" is the standard reference for
binding-time analysis as a static discipline enforced before specialization,
not a runtime check); the discipline's requirement for lips is structural,
not incidental: an open predicate's runtime-arrived fact can never be
consumed by a rule the kernel is asked to evaluate today, and the boundary
between the two must be visible in the clause's own type or shape, the way a
binding-time analysis annotates a variable, not left to be discovered when a
compile-time evaluator reaches for data that has not arrived yet.

Incremental view maintenance is the operational answer to what happens after
the split is drawn correctly: a materialized view (an IDB relation, in
Datalog's own vocabulary) that stays correct as its EDB inputs change without
being recomputed from scratch. Materialize states this as its reason to exist:
"to keep results up-to-date as new data arrives, Materialize incrementally
updates results as it ingests data rather than recalculating results from
scratch," and names its engine plainly: "its engine is built on Timely and
Differential Dataflow" (<https://materialize.com/docs/overview/what-is-materialize/>).
Differential Dataflow's own repository is explicit that this is a general
technique, not a Materialize-only trick: "differential dataflow is a
data-parallel programming framework designed to efficiently process large
volumes of data and to quickly respond to arbitrary changes in input
collections," built from ordinary functional operators (`map`, `filter`,
`join`, `reduce`) plus one operator for bounded recursion, `iterate`, which
"repeatedly applies a differential dataflow fragment to a collection"
(<https://github.com/TimelyDataflow/differential-dataflow>). What real
incremental-view systems require, translated to lips's open predicate: the
DERIVED relations (a clause's non-open patterns) must be expressible as a
monotone or at least well-behaved function of the open predicate's facts, so
that a fact arriving later can be folded into an already-computed result
rather than forcing a full re-derivation; what goes wrong when this is fudged
is exactly what Differential Dataflow's own worked example shows in miniature,
where "with only two edge changes we have six changes in the output" (same
repository, walking through its own `hello` example): a small runtime change
can legitimately cause a large, non-local change in derived facts, and a
renderer that assumed locality (a small patch to the host artifact) would be
silently wrong. lips must therefore treat an open predicate's downstream
clauses as re-derivable in full on every fact arrival unless it can prove
(the way Differential Dataflow's own operators are proven) that the
derivation is incremental-safe; assuming safety without that proof is the
exact fudge that breaks the split.

## 3. Stratified Negation and Termination: The Minimum Discipline

General recursion over named external primitives buys expressiveness and
buys back the halting problem in the same motion; the settled design's
`Overlap` check keeps rewriting confluent (`Refine.hs`'s own comment: "at most
one rule ever fires per decision... hence confluent for free") but confluence
says nothing about termination, and the kernel already knows it: "termination
is not decidable in general, so a step budget turns a runaway rule into a
loud `Nonterminating` error rather than a hang" (`Refine.hs`), enforced as
`n < 0 = Left (Nonterminating budget)` in the actual refiner. That is the
correct fail-fast answer for a MINT-TIME evaluator whose job is to check a
clause set once and report; it is not, by itself, a discipline that prevents
an author from writing a clause set that is unsound rather than merely slow,
which is where Datalog's stratification theory applies directly, because it
answers the sound half of the same question.

Soufflé's own docs state the unsound case plainly, with the canonical
counterexample: "`A(x) :- ! B(x). B(x) :- ! A(x).` is a circular definition.
One cannot determine if anything belongs to the relation 'A' without
determining if it belongs to relation 'B'... Such circular definitions are
forbidden. Technically, rules involving negation must be stratifiable"
(<https://souffle-lang.github.io/rules>). Stratified Datalog's standard result,
which this counterexample motivates, is that a program's predicates can be
partitioned into strata such that no predicate negatively depends on itself or
on a predicate in a later stratum, either directly or through a cycle of
rules; a program that admits such a partition has a unique, well-defined
minimal model and can be evaluated stratum by stratum, bottom-up, with each
stratum's IDB relations fully computed before the next stratum reads them
negatively. A program that does NOT admit a stratification (Soufflé's `A`/`B`
example) has no such well-defined answer at all, independent of termination:
it is not that evaluation runs forever, it is that the question "is `x` in `A`"
has no consistent truth value to converge on.

For lips this yields two separate gates, at two separate times, and the
settled design's own vocabulary already distinguishes them. At MINT time
(when `generate` or a human first commits a clause set, and again whenever
`check` re-verifies it): a stratification check over the clause set's
negative dependencies, structurally identical to Soufflé's, refusing any
clause set with a negative dependency cycle before it is ever rendered or
run, the same way `Overlap` already refuses a clause set with two rules
firing on one decision, and the same way `patternsOrthogonal`/`rulesOrthogonal`
in `Engine/Gate.hs` already run as static, pre-execution gates rather than
runtime checks. At RUN time (when the rendered host artifact, or the kernel's
own offline test oracle, actually evaluates a clause set against concrete
open-predicate facts): the step budget lips already ships is the correct
backstop for the part stratification cannot see, non-termination from
UNBOUNDED recursion over data whose size is not known until the open
predicate's facts arrive, which is a termination question, not a soundness
question, and `Nonterminating` already answers it the fail-fast way the
project's own invariants require ("deduce-or-fail... lips never guesses",
`AGENTS.md`). Stratification is therefore a mint-time completeness gate over
the STATIC shape of the clause set (can this clause set ever mean something,
independent of what data it is fed); the step budget is a run-time safety
net over the DYNAMIC behavior of one particular evaluation (did this
particular run of this particular meaningful clause set take too long). Both
are required; neither substitutes for the other, and conflating them (running
only a step budget, with no stratification check) is exactly the fudge that
would let a lips clause set be silently meaningless rather than loudly
rejected.

## 4. Proof Trees as the Review Artifact

lips already stamps every derived decision `Derived [parent] rule` (per
`Decision.hs`'s own constructor, `Derived [DecisionId] RuleId`), which makes a
resolution trace an explanation naming PROGRAM LINES, not generated code; this
is the design's answer to Böckeler's documented objection that debugging the
generated artifact rather than the model is a real, historical failure mode of
model-driven development (`DESIGN.md`'s own citation of that argument). The
evidence base for treating a derivation trace as a genuine review artifact,
not merely a debugging convenience, is Soufflé's provenance system, built and
shipped specifically because Datalog's declarative style makes normal
step-through debugging useless: "provenance is a way to explain the execution
of a Soufflé program, potentially useful for debugging. These explanations
come in the form of a proof tree. In Soufflé, for any tuple, these proof trees
are of minimal height for that tuple"
(<https://souffle-lang.github.io/provenance>). The mechanism is concrete and
directly transferable to `Derived`'s own shape: `explain path(1, 3)` prints
"all input and intermediate tuples required to generate the query tuple," as
an actual tree with rule numbers at each node (the same page's worked
example), and a companion command, `explainnegation`, answers the harder
question a positive proof tree cannot: WHY a tuple is absent, by walking the
same rule set backward and asking the user to supply witness values for free
variables. lips's `Derived [parent] rule` chain is exactly a Soufflé proof
tree with the tuples replaced by decisions and the rule numbers replaced by
`RuleId`s; the transfer is close enough that Soufflé's own accumulated
tooling experience (a command-line explain interface, an ncurses explorer for
large trees, a `setdepth` command to fold an unwieldy subtree behind a label)
is a direct, evidence-backed roadmap for what `lips check`'s own explanation
surface will eventually need once decision chains get deep, rather than
something to design from scratch.

The formal vocabulary behind why a proof tree is more than a debugging
convenience is provenance theory in the database literature: Cheney,
Chiticariu and Tan's survey "Provenance in Databases: Why, How, and Where"
(Foundations and Trends in Databases 1(4):379-474, 2009, bibliographic record
confirmed at <https://dblp.org/rec/journals/ftdb/CheneyCT09>) is the standard
reference distinguishing WHY-provenance (which base facts could possibly have
contributed to a derived fact being true) from HOW-provenance (the actual
derivation structure, a specific proof tree or expression witnessing it, which
is the richer of the two and the one Soufflé's `explain` command materializes)
and from WHERE-provenance (which source location a piece of output data came
from copy-wise); this session did not obtain the full text of that survey
(only its bibliographic record, via dblp, was verified), so the exact taxonomy
boundaries and the provenance-semiring algebra it surveys (Green, Karvounarakis
and Tannen's semiring-annotated relations, a later development in the same
line) are cited here by title, venue and year only, not by direct quotation,
and should be read from the primary source before any claim about their exact
formal content is relied on; this is flagged explicitly as a citation gap, not
smoothed over. The empirical half of Question 4, whether such explanations
actually help humans debug faster than reading generated code, is, honestly,
UNVERIFIED in this pass: this survey found no controlled study, in the search
depth available, directly comparing human debugging performance on Datalog
proof-tree explanations against debugging equivalent generated imperative
code, and none should be assumed; the argument for `Derived` chains rests on
Soufflé's own stated motivation for building the feature at all (declarative
code is not step-through-debuggable, so an explanation artifact was a
necessity, not a nicety) and on Böckeler's already-cited historical argument
that undebuggable generated artifacts killed MDD once, not on a measured
human-subjects result, and the summary to main states this gap plainly.

## Priority as a Relation, Not a Global Number

One further piece of prior art bears directly on Question 1's overlap
handling and belongs here because it is a live alternative to how lips
resolves conflicting clauses when several decisions co-own one function.
Catala, a language built to translate statutory law (itself a general-case-
with-exceptions structure) into executable code, resolves clause conflicts
with a named relation between two SPECIFIC clauses rather than a global
priority integer: "the exception keyword indicates that, in the pre-order of
definitions, the definition at line 10 has a higher priority than the one at
2" (Merigoux, Chataing and Protzenko, "Catala: A Programming Language for the
Law," arXiv:2103.03198). Formally, "after desugaring, definitions and
exceptions form a forest, with exactly one root definitions node for each
variable X, holding an n-ary tree of exception nodes" (same paper), so the
relation is acyclic BY CONSTRUCTION, not by a separate acyclicity check: an
exception names the specific definition or exception it overrides, so the
structure it builds is a tree, and a tree cannot contain a cycle. Ambiguity is
reported, not silently resolved: "in Catala, if, at run-time, more than a
single applicable definition for any context variable applies, program
execution aborts with a fatal error" (same paper), and the paper's formal
semantics for the underlying default-logic term makes this precise: "each of
the exceptions is evaluated; if two or more are valid... a conflict error is
raised. If exactly one exception is valid, the final result is that exception.
If no exception is valid, and the precondition evaluates to true, the final
result is the base consequence" (same paper, section 4.2, restated here from
the notation). This reduction is a fixed rewrite with no search and no
tie-breaking heuristic, which makes it deterministic in exactly the sense
lips needs: same clause tree, same facts, same answer, always.

This is a genuine third option beside lips's own structural strength order
and the salience/specificity integers that decayed in CSS, Drools and XACML
(Survey F documents the decay directly: "priority is an unstructured integer
any author may set at any site, so it stops expressing who has authority and
becomes a debugging tool: raise the number until the value wins,"
`docs/superpowers/survey/f-decision-calculus-theory.md`). Judged against
lips's own case, several decisions co-owning one function's clause set,
Catala's per-clause exception relation is the better fit, not the global
order: a global priority number requires every co-owning decision to agree on
a single total order over ALL clauses touching that function, including ones
written by decisions that have never heard of each other, which is precisely
the coordination failure that rotted CSS specificity and Drools salience; a
named exception relation only ever requires the ONE decision writing an
override to name the ONE clause it overrides, so two decisions that do not
mention each other stay unordered with respect to each other, composing
safely the same way lips's own systemd-style `Before=`/`After=` naming does
for service ordering. The cost is that Catala's relation is a tree per
definition, not a general partial order, which is a real restriction: it
cannot express "this clause beats these three others but is beaten by a
fourth in a diamond shape" without additional labels, but that restriction is
also exactly what buys the acyclicity-by-construction property, and for
lips's actual case (one function, several contributing decisions, each
wanting to name what it overrides) a tree is very likely sufficient, since
the alternative, a decision needing to express a diamond-shaped override
relationship over clauses it did not write, is a design smell (a sign the
function should be split) rather than a case the mechanism should be
stretched to accommodate.

## The Smallest Concrete Design and What Would Falsify It

The primitive vocabulary a leaf pattern-clause can call is the direct
analogue of the option schema lips already grounds NixOS, home-manager,
kubenix and terranix engines against (`README.md`'s own description of how
`generate` "confirms a name instead of hallucinating it" against "the pinned
schema of the target world"), so the smallest design commits to the same
move one layer down: leaf predicate SIGNATURES come from whichever host
language's own type or interface declarations the renderer targets, not from
a lips-owned registry. For a Go-rendering artifact axis, that signature
source is the package's exported Go type signatures nixpkgs already builds
and pins; for a Datalog-shaped artifact, Soufflé's own `.decl` declarations
are the signature schema (`.decl edge, path(x:number, y:number)`, from the
worked example above, is exactly a typed, named, external predicate
signature lips would look up rather than invent); across ecosystems, the
strongest single candidate for the general case is whichever host language's
type system nixpkgs already exposes as buildable, checkable metadata, because
that is the one place lips already trusts an external, versioned, typed
vocabulary (the option schema) and the discipline transfers unchanged: a
leaf predicate is grounded, never invented, the identical rule `AGENTS.md`
states for `${pkgs.<path>}`.

What would falsify the whole direction: if a realistic clause set that
several independent decisions plausibly need to co-author (not a contrived
worst case) requires an override relationship stratification cannot resolve
into a tree or a partial order (a genuine cyclic priority need, not merely a
diamond that indicates a design smell), or if rendering the same
non-overlapping, stratified, terminating clause set into two different
mainstream hosts produces two different observable behaviors for the same
open-predicate facts (a rendering-fidelity failure, not a soundness failure,
and the one Question 1 flags as the sharpest engineering risk), the design
has failed on its own terms, not on a hypothetical one, and should be
abandoned rather than patched with an escape hatch back into arbitrary
per-target code.

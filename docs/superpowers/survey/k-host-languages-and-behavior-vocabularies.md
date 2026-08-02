# Host Language and Vocabulary-of-Behavior: A Second Look

Prior-art scan, two questions neither of which survey F asks. Survey F formalizes
the kernel's four seams (rewriting, belief merging, diagnosis, deontic logic) inside
Haskell and inside the config-lattice family (CUE, Nickel); that ground is not
repeated here. This survey asks instead whether Haskell is the right vehicle for
that calculus, and whether the project's stated end target (a typed vocabulary for
behavior, "the Nix equivalent for artifacts") is reachable by naming library APIs
the way lips today names NixOS options.

A third question arrived after the first draft and supersedes both in weight: the
owner has converged on a design for the artifact axis (lips describing behavior,
not only configuration) and an earlier, richer proposal researched for this draft,
a kernel-owned computation grammar rendered into a host language, was rejected on
grounds this survey now adopts: Nix itself is complete without owning computation,
since it treats a derivation's build script as opaque and inherits universality
from the builder it names rather than from anything Nix's own module language
computes. The settled shape is narrower and is the centerpiece below: pure,
first-order definitions given by non-overlapping pattern clauses over named
external primitives, with general recursion, no effects, and no higher-order
values, executed by rendering into a host language's own pattern matching rather
than by a kernel interpreter. That section is written to be broken; four sharp
questions are asked of it before the two original halves resume as supporting
survey.

Terminology follows `AGENTS.md`: **program** (`.lips`), **engine** (`.lang`),
**kernel** (the domain-blind physics in `kernel/src/Lips/Kernel/`), **decision base**.

## Centerpiece: Pattern Clauses Over Named Primitives, Rendered Into a Host

The settled architecture, stated precisely so the four attacks below land on
something specific. An artifact-axis definition is a name (a function symbol) with
a set of clauses; each clause is a pattern on the left (literals, captures, and
constructor patterns over the closed value grammar `Engine/Value.hs` already
owns) and a body on the right built from three things only: literals, calls to
other defined names (general recursion, so a name may call itself), and calls to
named external primitives whose behavior the kernel never inspects. Clauses for
one name must not overlap, exactly the discipline `Refine.hs` already enforces
dynamically ("a decision matched by more than one rule is an `Overlap` error\...
rewriting is a function, hence confluent for free") and `Engine/Overlap.hs`
already enforces statically as a critical-pair check. No new merge semantics is
needed: clause union for one name is the existing merge, and a clause set with no
overlap is, by the argument survey F already made for rules in general (Rosen
1973, orthogonal rewrite systems are confluent), deterministic regardless of
write order. That is this design's answer to Prolog's cut and clause-order
dependency before either is asked for: order never matters, because overlap is a
mint-time error rather than a semantics.

No kernel interpreter ships this grammar to production. A definition is realized
by rendering its clauses into whatever the target host's own pattern matching
looks like (a Go type switch, a Rust `match`, a Haskell function with equations, a
JS discriminated-union dispatch), so execution speed and type checking are the
host compiler's, exactly as Nix's own `path = value` realization borrows an
evaluator that already promises bit-identical output (README, "Nix is the
substrate, not the subject"). A kernel-level interpreter survives only offline, as
a test oracle checking that the render is faithful to what the clause set means,
the same role `.expect` already plays for the value grammar.

### 1. Rendering: Does a Non-Overlapping Clause Set Survive the Trip Into a Mainstream Host?

The rendering step is not speculative; it is what every functional-language
compiler already does to its own surface syntax, and the literature is explicit
about what can go wrong. Maranget's decision-tree paper states the ground truth
mainstream pattern matching relies on: "matches are always attempted at the root
of the subject value... the matched rule is unique, thanks to the textual
priority scheme" (Maranget, "Compiling Pattern Matching to Good Decision Trees",
ML Workshop, fetched PDF,
http://moscova.inria.fr/~maranget/papers/ml05e-maranget.pdf). That sentence is the
first failure mode a renderer must refuse to reproduce: ML-family hosts (and by
extension Haskell, OCaml, Rust, Scala) disambiguate overlapping patterns *by
source order*, first match wins. lips's clause sets are guaranteed non-overlapping
before they reach the renderer (`Engine/Overlap.hs`), so order-dependent
disambiguation never fires for a lawful clause set, but if the overlap check is
ever bypassed or has a gap, the renderer's output silently acquires an ordering
semantics the kernel's own model does not have. This is not hypothetical: the same
paper's terminology for a pattern row that can never fire, "useless... redundant,
in the terminology of Milner et al. (1990)" (same source), names the exact defect
a renderer must be able to detect and refuse rather than silently drop.

The second failure mode is host asymmetry, and it is the sharpest adversarial
finding of this section: mainstream hosts do not agree on whether an incomplete
clause set is even an error. Rust makes it a hard compile error: "This error
indicates that the compiler cannot guarantee a matching pattern for one or more
possible inputs to a match expression" (Rust error index E0004, fetched,
https://doc.rust-lang.org/error_codes/E0004.html). GHC, targeting the same source
language family, makes the identical defect a warning that is *off by default*:
"The option -Wincomplete-patterns warns about places where a pattern-match might
fail at runtime... This option isn't enabled by default because it can be a bit
noisy" (GHC User's Guide, "Warnings and sanity-checking", fetched,
https://downloads.haskell.org/ghc/latest/docs/users_guide/using-warnings.html).
Go has no compiler-level concept of exhaustiveness for a type switch at all; the
third-party `exhaustive` linter exists precisely to fill that gap ("`exhaustive`
checks exhaustiveness of enum switch statements in Go source code", project
README, fetched,
https://raw.githubusercontent.com/nishanths/exhaustive/master/README.md), and it
is a lint, not a compiler gate, so nothing stops a Go build from succeeding on a
rendered clause set missing a case. The conclusion is specific and falls directly
out of these three sources: **a renderer cannot rely on "the host will catch it"
as the exhaustiveness gate, because whether the host catches it at all, and
whether it is an error or a warning, is a per-host fact that must be looked up,
not assumed.** The exhaustiveness and non-overlap checks belong in the kernel
(where `Engine/Overlap.hs` already lives), checked once, before any render;
host-side flags such as `-Wincomplete-patterns -Werror` or Rust's default E0004
are then a second, redundant confirmation, valuable exactly because two
independent checkers agreeing is stronger evidence than either alone, not because
either is sufficient by itself. Named failure modes a renderer must refuse to
produce, gathered from the above: an overlapping clause pair reaching the
renderer (host order-dependence would silently become semantics); a clause the
host's own checker calls unreachable (Milner et al.'s "redundant", meaning the
mint's clause set had dead logic the kernel's overlap check should have caught
first); and a non-exhaustive clause set reaching a host, such as Go, that will not
refuse it (a silent partial function, the exact defect Rust's E0004 exists to
forbid).

Souffle's own practice is the closest existing precedent for "pattern clauses
rendered into a mainstream host," and it is reassuring: Souffle "integrate[s] our
technique into Soufflé, a Datalog engine that synthesizes C++ code, and achieve[s]
high performance by using specialized parallel data structures" (Yang and
colleagues, "Debugging Large-scale Datalog", abstract, DOI 10.1145/3379446, fetched
via Crossref). A logic language with a checked, non-overlapping (stratified)
rule set compiling to a mainstream host's native code, at the scale of "tens of
millions of output tuples," is a working existence proof at a larger scale than
lips will need for years.

### 2. Open Predicates: The EDB/IDB Boundary Is Not New, and Its Failure Mode Is Well Documented

The one genuinely new kernel concept, a predicate whose facts arrive at runtime
rather than at mint time, is Datalog's oldest distinction wearing a different
name. "The set of facts is called the extensional database or EDB of the Datalog
program. The set of tuples computed by evaluating the Datalog program is called
the intensional database or IDB" (Wikipedia, "Datalog", fetched,
https://en.wikipedia.org/wiki/Datalog). lips's own boundary is EDB/IDB read
sideways in time rather than in derivation depth: a program's own decisions and a
model's minted rules are the EDB and IDB of *compiling the system*, fixed before
any artifact exists; an open predicate is a fact whose EDB membership is decided
when the *artifact* runs, not when lips compiles it. That is exactly the
distinction partial evaluation calls binding time, formalized since Futamura's
1971 projections: a computation is split into what is known now (static) and what
is known only later (dynamic), and "PyPy's RPython and GraalVM's Truffle framework
are examples of real-world JIT compilers that implement Futamura's first
projection" (Wikipedia, "Partial evaluation", fetched,
https://en.wikipedia.org/wiki/Partial_evaluation). The general term for the same
split, "binding time," is standardized outside partial evaluation too (ISO/IEC/IEEE
24765:2010, cited via Wikipedia, "Binding time", fetched,
https://en.wikipedia.org/wiki/Binding_time). What every one of these traditions
requires to keep the split sound is the same requirement stated three different
ways: the static half must never depend on a value only the dynamic half can
produce. Binding-time analysis exists specifically to catch a program that,
silently, breaks this rule (a use of a "static" value that is actually only
known dynamically), and a partial evaluator that skips this analysis produces
specialized code that is wrong, not merely slow.

Incremental Datalog is the sharpest concrete precedent for what an open
predicate must be checked against once it exists, because it is a system built
around exactly this boundary at production scale. DDlog states its EDB/IDB split
in operational terms: "DDlog is a programming language for incremental
computation... the programmer does not need to worry about writing incremental
algorithms. Instead they specify the desired input-output mapping in a
declarative manner, using a dialect of Datalog. The DDlog compiler then
synthesizes an efficient incremental implementation" (DDlog README, fetched,
https://raw.githubusercontent.com/vmware-archive/differential-datalog/master/README.md).
Differential Dataflow, the substrate DDlog compiles to, states the soundness
condition directly: a program is "written as functional transformations of
collections of data," and "once written, a differential dataflow responds to
arbitrary changes to its initially empty input collections, reporting the
corresponding changes to each of its output collections" (differential-dataflow
README, fetched,
https://raw.githubusercontent.com/TimelyDataflow/differential-dataflow/master/README.md).
The soundness condition both systems share, and the one lips's open predicates
must inherit, is that the IDB-side computation (the rules referring to an open
predicate) is a pure function of the EDB-side facts (whatever supplies the open
predicate at runtime): if that function is not pure, i.e. if a clause referring
to an open predicate has a side effect other than reading it, incremental
recompute (or, for lips, re-running the artifact with new runtime facts) stops
being sound, because the whole model assumes recomputation and re-derivation are
the same operation run at a different time. **What goes wrong when the split is
fudged, concretely: a clause that both reads an open predicate and calls a named
external primitive with a side effect (write a file, mutate a counter) can no
longer be re-evaluated safely when the open predicate's facts change, which is
exactly the invariant "no effects" in the settled architecture is already
protecting, independently arrived at from a different direction than Differential
Dataflow's soundness argument, and now doubly justified.** The kernel-level
check this buys, concretely: a definition using an open predicate must be pure in
every other argument, checkable statically over the clause grammar the same way
`Engine/Reach.hs` already checks that every captured value reaches some emit.

### 3. Stratification and Termination: What General Recursion Forfeits, and What It Does Not

Pure Datalog terminates by construction: "evaluating Datalog programs always
terminates; Datalog is not Turing-complete" (Wikipedia, "Datalog", §Complexity,
citing Dantsin, Eiter, Gottlob and Voronkov, ACM Computing Surveys 33(3), 2001).
The settled architecture explicitly wants general recursion over named external
primitives, which forfeits that guarantee outright: a language with unrestricted
recursion and no restriction on what a primitive returns is Turing-complete by
construction, and Turing famously proved in 1937 "that the halting problem is
undecidable, meaning that no general algorithm exists that can correctly solve
the problem for all possible program-input pairs" (Wikipedia, "Halting problem",
fetched, https://en.wikipedia.org/wiki/Halting_problem). This is not a gap to be
engineered around; it is a theorem, and it draws the mint-time/run-time line for
lips exactly. Systems that keep general recursion and still want a termination
guarantee do it by *restricting the shape of recursion itself*, not by analyzing
arbitrary recursive clauses after the fact: "Not all recursive functions are
permitted - Agda accepts only those recursive schemas that it can mechanically
prove terminating" (Agda documentation, "Termination Checking", fetched,
https://agda.readthedocs.io/en/latest/language/termination-checking.html), via
structural recursion on a strictly decreasing argument. Adopting that discipline
for lips would mean rejecting general recursion (an explicit non-goal of the
settled architecture, and the reason completeness must be inherited from the
host rather than proven inside the kernel), so Agda's answer is evidence the
question has a well-studied solution, and evidence that lips has deliberately
declined it in favor of a strictly weaker, cheaper guarantee: lips today gates
runaway rewriting with "a step budget [that] turns a runaway rule into a loud
`Nonterminating` error rather than a hang" (`Refine.hs`, module header). That
remains the correct choice given the halting theorem: no static check can replace
it without also replacing general recursion, and the settled architecture keeps
general recursion on purpose.

Negation is the one place a real static discipline is both available and free,
because it does not touch recursion's termination at all, only its meaning.
"Stratified negation can be added to Datalog while retaining its model-theoretic
and fixed-point semantics. Notable Datalog engines that implement stratified
negation include: LogicBlox, Soufflé" (Wikipedia, "Datalog", §Negation, fetched).
Stratification requires that a clause set can be layered so that any negated use
of a predicate refers only to a strictly lower layer, i.e. no predicate's
definition may negate itself, directly or through a cycle; survey F already
quotes LogicBlox's own statement of the rule ("negation is only allowed when the
platform can determine a way to stratify all rules"), not repeated here. lips has
no negation operator in its value grammar today (`Engine/Value.hs`), so this is
forward-looking, but it is the one item on this list that is a pure mint-time,
decidable check with zero runtime cost: computing whether a clause set stratifies
is a graph-cycle check over predicate dependencies, the same shape of static
analysis `Engine/Overlap.hs` already runs.

**The gate, stated once, cleanly.** Mint time (static, decidable, must reject a
bad engine before it is written): clause non-overlap (already built,
`Engine/Overlap.hs`), the open-predicate purity check described above, and, if
negation is ever added, stratification. Run time (the halting problem makes this
unavoidable given general recursion): the step budget and `Nonterminating` error
`Refine.hs` already has. Nothing above changes what lips does today; it explains,
with citations, why what lips does today is the correct split rather than a
placeholder waiting for a smarter static check.

### 4. Proof Trees as the Review Artifact: The Evidence Base, Honestly Weighed

lips already stamps `Derived [parent] rule` provenance on every rewritten
decision (`Refine.hs` module header: "the refiner stamps every derived decision
with `Derived [parent] rule`. A rule author cannot forge or omit the chain").
That is, in the vocabulary this question asks for, a how-provenance trace: it
names the rule and the parents, not merely that a fact is true. The formal
vocabulary splits this exactly: "why-provenance" (Buneman, Khanna and Tan, "Why
and Where: A Characterization of Data Provenance", ICDT 2001, DOI
10.1007/3-540-44503-x_20, confirmed via Crossref) asks which source facts a
derived fact depends on; "provenance semirings" (Green, Karvounarakis and Tannen,
"Provenance Semirings", PODS 2007, DOI 10.1145/1265530.1265535, confirmed via
Crossref, and already named by survey F as a seam not worked there) give the
algebra for combining that dependency information across derivation steps.
Souffle's `explain` tool is the production-grade version of exactly what lips's
provenance data could become: "Provenance is a way to explain the execution of a
Soufflé program... These explanations come in the form of a proof tree... `explain
path(1, 3)` prints the proof tree for the tuple `path(1, 3)`, showing all input
and intermediate tuples required to generate the query tuple" (Souffle docs,
"Provenance", fetched, https://souffle-lang.github.io/provenance), rendered as
literal ASCII proof trees with rule numbers at each step. The engineering behind
it, published separately, states its own motivation in almost lips's own words:
Datalog specifications for static analysis "process millions of tuples of data
and contain hundreds of highly recursive rules. As a result, they are notoriously
difficult to debug" ("Debugging Large-scale Datalog", abstract, DOI
10.1145/3379446, fetched via Crossref), which is the precise problem a
resolution trace naming program lines, rather than generated code, is meant to
solve one level earlier, before the analyst is staring at millions of tuples
instead of dozens of program lines.

The honest gap: this survey did not find a controlled, human-subjects study
measuring whether provenance-style explanations actually help people debug
faster or more accurately than reading generated output directly; the evidence
found is need-based ("notoriously difficult to debug" without it) and
engineering-based (Souffle's `explain`, and a follow-on paper specifically about
scaling proof-tree construction to production-size analyses), not a measured
before/after on human comprehension. That gap should be stated plainly rather
than papered over with a confident claim survey F's own house style would not
allow. What is not a gap, and is instead a documented failure this design
avoids by construction: this project's own survey B already names the MDD
failure mode this question is really asking about, that once "a developer
touched generated output directly, the model and the code diverged permanently,
and the tool could no longer regenerate without destroying the manual changes"
(`docs/superpowers/survey/b-graveyard.md`, on CASE tools' escape hatch). A
resolution trace naming program lines is lips's answer to that failure only if
the trace, and not the rendered host code, is the thing a human is ever asked to
read and edit; the moment a rendered Go or Rust file becomes something a reviewer
debugs and patches by hand, the proof tree is decoration and the graveyard's
failure mode is back. **The review artifact claim is therefore conditional, not
free: it holds only as long as `lips check`'s pinned `.expect` contract, not a
human reading rendered host code, remains the thing that decides whether a
regeneration is accepted (`AGENTS.md` invariant 5), because a proof tree that
explains code nobody is allowed to hand-edit is exactly the audit trail this
design needs, while a proof tree that explains code someone quietly patches
anyway is exactly the audit trail MDD tools also had and it did not save them.**

### The Smallest Concrete Design for the Primitive Vocabulary

A named external primitive needs a signature the kernel can ground the way
`Lips.Kernel.OptionType` already grounds a NixOS option path: a typed slot, owned
and versioned outside lips, that a mint-time lookup either confirms or refuses.
The candidate schemas surveyed, and why each does or does not fit:

- **A language's own standard library or package index** (Hackage/Hoogle for
  Haskell, crates.io for Rust, Go's standard library) is typed and externally
  maintained, but it is typed *for that host*, so grounding a primitive against
  it silently picks the render target at mint time, which breaks the design's own
  promise that switching hosts is a re-render, not a re-mint.
- **Protobuf/gRPC service definitions and GraphQL SDL** are host-agnostic and
  typed, but, as Half 2 already found, they type only the shape of a call
  (request in, response out), never its effect, so grounding a primitive against
  one confirms it exists and is well-typed without confirming what it does; useful
  as a shape-check, not sufficient alone.
- **The WebAssembly Component Model's WIT (Wasm Interface Type) language** is the
  best fit found: "WIT isn't a general-purpose programming language and doesn't
  define behaviour; it defines only contracts between components" (Bytecode
  Alliance, "An Overview of WIT", fetched,
  https://component-model.bytecodealliance.org/design/wit.html). WIT interfaces
  and worlds name typed functions with no implementation language attached at
  all, which is precisely the shape a named external primitive needs: a name,
  argument and return types, and nothing else, groundable once and renderable
  into any host that has, or can grow, a WIT binding generator. It is also,
  unlike a single language's package index, already built to be the target of
  exactly this kind of tool-generated, cross-language binding, which is what a
  render step is.

**Recommendation**: ground named external primitives against WIT-shaped
signatures (name, typed arguments, typed return, explicitly no behavior
specified beyond the type) rather than against any single host ecosystem's
package index, keeping the render step's freedom to target Go, Rust, Haskell, JS
or a WASM component itself genuinely open, the same way nixpkgs's option schema
names a package without constraining what builds it.

**What would falsify this whole direction.** If clause sets that pass the
mint-time overlap and purity checks turn out, in practice, to need host-specific
escape hatches to render correctly (a primitive whose type is identical across
hosts but whose *evaluation order*, *strictness*, or *exception behavior* differs
enough between, say, Haskell's laziness and Go's eager evaluation that the same
clause set produces different observable results on two hosts), then "switching
hosts is a re-render, not a re-mint" is false, and the render step is not the
thin, mechanical, host-blind translation this design assumes; it would instead
need its own per-host semantics layer, which is a second kernel by another name.
The concrete experiment: render one clause set with at least one primitive call
inside a recursive definition into two hosts with different evaluation
strategies (a strict host and a lazy one), run both against the same `.expect`
contract, and check whether they agree. If they do not, the direction is wrong
and the fix is either restricting primitives to ones whose result cannot depend
on evaluation order (a strong, checkable purity discipline, stronger than "no
side effects") or abandoning the single-clause-set-many-hosts promise entirely.

## Half 1: Does A Better Host Language Exist?

The kernel's actual job, read from `kernel/src/Lips/Kernel/`, is narrow: merge a
set of decisions by subject under a structural strength order (`Base.hs`), rewrite
the merged base to a fixpoint under a fixed, non-overlapping rule set
(`Refine.hs`), reject overlapping rules statically before that (`Engine/Overlap.hs`,
already a critical-pair check per its own header comment), and render the ground
result into a closed value grammar with no computation and no injection
(`Engine/Value.hs`). It merges to exactly one answer per subject; `Base.resolve`
picks a winner or reports a conflict, and there is never a second answer to search
among. That single fact rules out most of the logic-programming family before
their distinguishing feature (search) is even relevant.

### Prolog: A Search Engine For A Problem With No Search

Prolog resolves a query by unification and backtracking over Horn clauses: "Given
a query, the Prolog engine attempts to find a resolution refutation of the negated
query... an instantiation for all free variables is found that makes the union of
clauses and the singleton set consisting of the negated query false" (Wikipedia,
"Prolog", fetched, https://en.wikipedia.org/wiki/Prolog). Backtracking exists to
explore alternative clause choices when one path fails, and the cut (`!`) exists
to prune that search when the programmer knows a choice is final: "The cut... is a
goal, written as !, which always succeeds but cannot be backtracked. Cuts can
prevent unwanted backtracking, which could add unwanted solutions and/or
space/time overhead to a query" (Wikipedia, "Cut (logic programming)", fetched,
https://en.wikipedia.org/wiki/Cut_(logic_programming)). The same article's
taxonomy of green, red and harmful cuts is itself evidence against adopting
Prolog: a language whose community needs three named categories for "how much did
this efficiency hack change the meaning of your program" is optimizing a knob lips
does not have a socket for. lips's refiner already guarantees "at most one rule
ever fires per decision" (`Refine.hs`, module header), which is cut's job, done by
construction instead of by a control operator an author can misuse.

What Prolog would buy: nothing structural. Unification over subject patterns with
captures (`<name>`) is already how `Lang/Pattern.hs` and `Engine/Overlap.hs` match,
and Haskell's own pattern matching gets that for free without a resolution engine
underneath. What it would cost: reintroducing exactly the space of concerns
(choice points, cut placement, occurs-check, non-termination via infinite
backtracking) that the domain-blind, single-answer design is built to avoid.
**Verdict: not stealable, because there is nothing left to steal once search is
removed; the design already occupies the deterministic corner Prolog treats as a
special case.**

### Datalog: The Closest Formal Relative, and a Genuinely Useful Distinction

Datalog is the sharper comparison, because it already deliberately makes the
choice lips makes: no search, no backtracking, a decidable fragment. "Datalog
generally uses a bottom-up rather than top-down evaluation model. This difference
yields significantly different behavior and properties from Prolog"; bottom-up
evaluation "start[s] with the facts in the program and repeatedly appl[ies] the
rules until... the complete minimal model of the program is produced" (Wikipedia,
"Datalog", fetched, https://en.wikipedia.org/wiki/Datalog). That is refinement to
a fixpoint, described in the exact words `Refine.hs` uses for itself. Complexity is
also pinned down, not asserted: "the decision problem for Datalog is P-complete"
in data complexity and "evaluating Datalog programs always terminates; Datalog is
not Turing-complete" in program complexity (same source, §Complexity, citing
Dantsin, Eiter, Gottlob and Voronkov, "Complexity and Expressive Power of Logic
Programming", ACM Computing Surveys 33(3), 2001). lips's refiner instead bounds
termination operationally, with a step budget that turns a runaway rule into a
loud `Nonterminating` error (`Refine.hs` header); Datalog's decidability result
says that bound could, for the restricted grammar lips actually rewrites over
(flat subject patterns, no function symbols, no recursion through captured
values), be a theorem instead of a runtime guard, for this configuration-merge
rewriting layer specifically. (The centerpiece section below reaches the
opposite conclusion for the artifact-axis clause grammar, which deliberately
adds general recursion over named primitives and so gives up this guarantee on
purpose; the two layers are distinct and the two conclusions do not conflict.)
Whether `Refine.hs`'s own rule rewriting is already within safe Datalog, and so
could rule out non-termination statically rather than by budget, remains a
genuine, checkable claim worth a follow-up spike for that layer alone.

Stratified negation is the feature that would matter if lips ever needed "unless
a later, more specific line says otherwise": "Stratified negation can be added to
Datalog while retaining its model-theoretic and fixed-point semantics" (Wikipedia,
"Datalog", §Negation). lips has no negation operator today (`Engine/Value.hs`'s
grammar has none), and stratification is the textbook answer for adding one
without breaking the fixpoint story survey F already ties to Newman's lemma.

Two production Datalog features map onto open questions survey F names as
unresolved (obligation survival under override, lex specialis) with working code
instead of a citation. Soufflé implements **subsumption**: "Subsumption permits to
delete more specific tuples by more general tuples. A programmer can express this
by declaring a partial-order in the form of a subsumptive clause... A subsumptive
rule has a dominated and a dominating head separated by `<=`" (Soufflé docs,
"Subsumption", fetched, https://souffle-lang.github.io/subsumption). That is a
rule-level priority relation living beside the rules themselves, exactly the shape
survey F's "lex specialis" question asks for: a more specific derivation
dominating a more general one, decided at the rule level rather than folded into
the numeric strength lips resolves at merge time. DDlog (Differential Datalog)
answers the adjacent, unasked "what happens when one line of the program changes"
question directly: "DDlog processes input updates by performing the minimum
amount of work necessary to compute changes to output relations" (DDlog README,
fetched, https://github.com/vmware-archive/differential-datalog), built on Frank
McSherry's differential dataflow. lips recomputes the whole fixpoint on every
compile; that is fine at today's program sizes (a `.lips` file is "a few lines of
meaning", README) and would only matter if programs, or the corpora `generate`
crystallizes across, grow by orders of magnitude. Filed as a note, not a
recommendation: differential re-evaluation is a solved problem to reach for later,
not a reason to hold this survey open.

**What Datalog would buy**: a textbook decidability argument in place of a step
budget, a stratified-negation recipe if negation is ever added, and two concrete
techniques (subsumption, incremental evaluation) with working implementations.
**What it would cost**: Datalog's relations are untyped tuples; lips's decisions
carry a closed sum type per field (`Decision.hs`'s `Kind`, `Strength`) and a
closed value grammar (`Engine/Value.hs`) that a Haskell compiler checks
exhaustively at every pattern match over them. Reimplementing lips's calculus in
Souffle or DDlog would mean re-deriving that exhaustiveness as a runtime
convention (a `type` column checked by a rule, not a constructor a compiler
refuses to let you forget), which is precisely the property `AGENTS.md` calls
"illegal states unrepresentable" and lists as invariant 3. **This is the seam
where "gained or lost" has a real cost on the losing side, and it is decisive.**

### Answer Set Programming: Solved For The Wrong Problem

ASP asks a different question than Datalog: "Answer set programming (ASP) is a
form of declarative programming oriented towards difficult (primarily NP-hard)
search problems. It is based on the stable model (answer set) semantics of logic
programming. In ASP, search problems are reduced to computing stable models"
(Wikipedia, "Answer set programming", fetched,
https://en.wikipedia.org/wiki/Answer_set_programming). ASP's preference
extensions (weak constraints, `#minimize` in clingo/Potassco) exist to rank
*multiple* stable models against each other; lips has, by design, one merged base
per subject and no second model to rank. ASP's early and still-central
application, cited in the same article's history section, was product
configuration (Soininen and Niemelä, 1998); that is the honest reason ASP keeps
coming up in this space, and it is also the reason it does not fit here: a
configurator explores a combinatorial space of *valid* configurations and picks
one, while lips's merge is defined never to have more than one candidate to
choose among. **Verdict: not stealable; the preference machinery solves a search
problem lips's design deliberately does not have.**

### Racket: The Right Question, Answered By Someone Else's 20-Year Project

This is the most interesting negative result of the survey. `#lang` is exactly
the abstraction lips's own README describes an engine as: "a set of `#lang`
languages... For example, JavaScript programmers employ jQuery for interacting
with the DOM and React for dealing with events and concurrency. As developers
solve their problems in appropriate eDSLs, they compose these solutions into one
system" (paraphrased from Felleisen, Findler, Flatt, Krishnamurthi, Barzilay,
McCarthy and Tobin-Hochstadt, "A Programmable Programming Language", *Communications
of the ACM*, 2018 draft PDF, fetched,
https://www2.ccs.neu.edu/racket/pubs/fffkbmt-cacm18.pdf; quoted content
paraphrased rather than quoted verbatim because the PDF's custom ligature font
corrupts direct extraction of exact wording). Racket's own docs describe the
mechanism lips would need to borrow: "Racket offers additional facilities for
defining a starting point of the expander layer, for extending the reader layer,
for defining the starting point of the reader layer, and for packaging a reader
and expander starting point into a conveniently named language" (Racket Guide,
ch. 17, "Creating Languages", fetched,
https://docs.racket-lang.org/guide/languages.html). That "packaging... into a
conveniently named language" is `raco pkg`, i.e. `#lang` languages are installed,
versioned, shared software, not per-run artifacts.

That difference is the whole answer to "is `#lang` the right model for what lips
calls an engine". `#lang` languages in the Racket ecosystem are minted by
programmers, by hand, meant to be reused across an indefinite number of programs
by an indefinite number of authors, and to compose (the CACM paper's headline
example runs `typed/racket` and untyped `racket` modules in the same program,
crossing the boundary through a checked contract). A lips engine is minted once,
by a model, from one problem's own wording, disposable, and explicitly not meant
to be handed to a stranger; the README calls it "AI-minted, disposable,
regenerable" (`AGENTS.md`). Racket's 20 years of engineering (a hygienic macro
expander, a module system with phase separation, a language-server protocol
built on the same reader/expander split) solve the problem of *making a language
cheap to build and safe to compose with others*; lips's engine never needs to
compose with a stranger's language, because every engine lives beside the one
program (or small family of programs) it was minted for. Racket's own Datalog
`#lang` (`#lang datalog`, shipped in the Racket distribution) is itself evidence
for this reading: it is a hand-written, general-purpose Datalog implementation
packaged as a reusable language, the opposite of a disposable, per-problem
artifact.

**What Racket would buy**: a real answer to "how do you cheaply mint a new
little language", which is lips's own headline claim, executed by a human
compiler-writer over years instead of a model in one call; also hygienic macros,
which would matter if lips ever let an engine's rules reference each other
symbolically rather than as flat data. **What it would cost**: everything
Haskell's type system currently buys for free. `Engine/Value.hs`'s closed value
grammar is a sum type with no `Function` constructor; the invariant "no
computation, no injection" is enforced because the compiler will not let
`renderRealized` handle a case that does not exist. Racket is untyped by default
(Typed Racket exists, is opt-in, and the CACM paper's own example treats crossing
the typed/untyped boundary as the interesting, contract-checked case rather than
the default). Rebuilding lips's grammar in untyped Racket would move "illegal
states unrepresentable" from a compile error to a runtime contract, which is a
downgrade for a kernel whose entire selling point is that a bad mint costs
nothing because the compiler catches it before anything is written
(`AGENTS.md` invariant 3, README "The mint has two tools"). **Verdict: Racket
answers a question lips does not have (cheap language *distribution* to
strangers), at a cost lips cannot afford (losing compile-time exhaustiveness on
the value grammar). The idea worth stealing is not the language, it is the
insight that an engine and a `#lang` language are the same kind of object; that
insight is already lips's own thesis, arrived at independently.**

### Rosette: Solver-Aided, For A Problem That Has No Solving Left To Do

Rosette "extends Racket with language constructs for program synthesis,
verification, and more. To verify or synthesize code, Rosette compiles it to
logical constraints solved with off-the-shelf SMT solvers" (Rosette homepage,
fetched, https://emina.github.io/rosette/). This is squarely aimed at the
*mint* step, not the kernel: "you simply write an interpreter for your language
in Rosette, and you get the tools for free" (same source). lips already
delegates program synthesis to a general-purpose model rather than a symbolic
solver (`generate`, via `pi`), and the mint's own verification is not "does a
model exist that satisfies this specification" but "does this concrete engine,
run once, reproduce the pinned `.expect` contract" (`AGENTS.md` invariant 5).
Rosette's target problem, verifying or synthesizing *against a spec expressed as
constraints*, would matter if lips ever wanted to synthesize an engine from the
`.expect` file alone rather than from a model's read of the prose lines, or to
prove no input crashes a minted engine rather than testing that it does not.
Both are real future directions and neither is built today. **What it would
buy, if adopted for future work**: a route to a *proven*, not merely *tested*,
engine, since Rosette's approach turns "does this program meet its spec" into an
SMT query rather than a test suite. **What it would cost**: the model-writes-code
step Rosette needs (an interpreter for lips's rule language, written once in
Rosette) is itself a rewrite of `Refine.hs` and `Engine/Value.hs` into Racket,
which reopens the typed-grammar cost above. **Verdict: not for the kernel; a
plausible, narrow future tool for tightening the mint's own verification step,
worth a dedicated spike rather than a host-language change.**

### Clojure: EDN Answers a Real Open Question, Spec/Malli Do Not Change the Calculus

`DESIGN.md`'s open question (paraphrased from the survey brief) is a canonical
text form for decisions, where "text diff approximates set diff". EDN is a
direct, working answer to a narrower version of that question: it is "extensible
data notation... a subset of Clojure syntax... used for generic data
representation" (github.com/edn-format/edn README, fetched,
https://github.com/edn-format/edn), a plain textual encoding of maps, vectors,
sets and tagged literals with a documented, total round-trip. If lips ever wants
its `.decisions` cache or `.lang` file to be diffed as *data* rather than as
*lines*, EDN's tagged-literal mechanism (`#inst`, `#uuid`, and user-defined tags)
is a working precedent for "a value that carries its own type tag in plain
text", which is close to what `Engine/Value.hs`'s typed holes already do inside
lips's own closed grammar. clojure.spec's stated problem is adjacent but not the
same: "Clojure gets runtime checking of a richer set of types by the JVM itself.
However... important properties of Clojure systems are represented and conveyed
by the shape and other predicative properties of the data, not captured or
checked anywhere" (clojure.org, "spec Rationale and Overview", fetched,
https://clojure.org/about/spec). spec (and Malli after it) retrofit a schema onto
an otherwise untyped, dynamically-checked value; lips does not have this problem,
because `Engine/Value.hs` is a Haskell sum type checked at compile time, which is
strictly stronger than a runtime predicate checked at data-construction time.
Datomic's EDN-based schema and its own "everything is a set of facts, merged by
time" model (its docs describe schema, transactions and query all as data) is the
closest existing system to lips's own decision-base model, but its axis of
variation is time (an accumulate-only fact log with an "as of" query), not
strength; it is a relative of `Base.hs`, not a substitute for it.

**Steal, concretely**: EDN's tagged-literal notation as a possible future format
for `Engine/Value.hs`'s serialized form, if the canonical-text-form question is
ever revisited; nothing about spec or Datomic changes what the kernel needs to
do, because Haskell's type system already gives lips what spec retrofits onto
Clojure.

### miniKanren: A Relational Idea Already Present, Minus the Search

miniKanren is relational programming, "a family of embedded languages for logic
programming" built on unification and search over a stream of possible bindings.
Its defining property, again, is search over multiple answers; lips's captures
(`<name>` in `Lang/Pattern.hs`) already do the unification half without needing
the search half, for the same reason Prolog does not fit: one subject, one
decision, one answer. **Verdict: no gap to fill.**

### Summary Table, Half 1

| Language | lips already has this | lips would gain | lips would lose | Stealable without rewrite |
|---|---|---|---|---|
| Prolog | single-answer merge (no search) | nothing structural | nothing (already ahead) | no |
| Datalog | bottom-up fixpoint, decidable core | textbook termination proof, subsumption, incremental recompute | nothing directly, but reimplementing loses typed exhaustiveness | subsumption-as-lex-specialis, DDlog's incremental model (later) |
| ASP | — | preference-ranked search over models | — | no (wrong problem: no model space to rank) |
| Racket `#lang` | the engine-as-language idea, independently | cheap language *distribution* to strangers (unneeded) | compile-time exhaustiveness on the value grammar | the framing, already adopted; not the runtime |
| Rosette | mint-time verification against `.expect` | spec-to-SMT proof instead of test | a from-scratch interpreter rewrite | as a future, narrow mint-verification spike |
| Clojure (EDN/spec/Datomic) | compile-time schema (stronger than spec) | EDN as a candidate text notation | — | EDN's tagged literals, if canonical text form changes |
| miniKanren | unification via pattern capture | search over multiple answers (unneeded) | — | no |

## Half 2: Is A Typed Library API a Vocabulary of Behavior?

The hypothesis, restated precisely: nixpkgs grounds lips today because it is a
named, typed, externally maintained surface (`services.restic.backups.<name>.paths`
exists, has a type, and lips looks it up rather than inventing it). A typed
function signature in a library ecosystem, `restic :: BackupSpec -> IO ExitCode`
in a hypothetical Haskell binding, or `def backup(spec: BackupSpec) -> None` in a
typed Python one, is also named, typed and externally maintained. Could `generate`
mint calls into such an API, grounded the same way, and would that reach the
owner's stated target ("the Nix equivalent for artifacts", a vocabulary for
*behavior* rather than configuration)?

### What a Type Signature Actually Pins Down

A NixOS option's type is total for lips's purposes: `services.restic.backups.<name>.paths`
is a list of strings, full stop, and every legal value of that option is a legal
backup path list. A function signature is not total in that sense. Type-directed
synthesis research treats this gap as the central open problem, not a footnote.
FrAngel's abstract states the core difficulty directly: pure type-directed search
enumerates "well-typed but wrong" programs, so practical component-based synthesis
needs additional signal, in FrAngel's case "control structures" mined from example
programs, "Component-Based Synthesis with Control Structures" (arXiv 1811.05175,
fetched, https://arxiv.org/abs/1811.05175). "Specification-Guided Component-Based
Synthesis from Effectful Libraries" (arXiv 2209.02752, fetched,
https://arxiv.org/abs/2209.02752) goes further: for libraries with side effects
(exactly the kind lips would call, since a backup, a service, a build all have
effects), the type signature alone underdetermines behavior, and the paper's own
contribution is a way to specify the *effectful* part separately from the type.
"Type-Directed Program Synthesis for RESTful APIs" (arXiv 2203.16697, fetched,
https://arxiv.org/abs/2203.16697) is the closest existing system to the
hypothesis's own framing (an externally maintained, typed API surface, not a
language's whole standard library), and its existence is itself informative: if
type-directed synthesis against an API surface already worked outright, this
paper would not need to add anything beyond the OpenAPI type schema; it adds
value inference and dependency analysis across calls precisely because the types
do not pin down which sequence of calls, or which argument values, produce the
intended effect.

This is the same gap `DESIGN.md`'s own language names for options: a type answers
"is this a legal value", never "is this the value the program meant". lips's
current answer for NixOS is to let the model fill the value from the program's own
words, unverified beyond the type ("It grounds names, never values; what your
program does not state remains uninvented", README, "The mint has two tools").
That discipline transfers cleanly to a typed API: a rule could ground the *call
name and argument types* against the library's type checker exactly as it grounds
an option path against the NixOS schema today, while the *argument values* remain
the program's own words, exactly as they are now. What does not transfer is the
NixOS guarantee that a well-typed assignment is automatically a semantically
correct one; a well-typed call to a mutating, effectful function is not.

### DreamCoder, Babble, Stitch: What `generate` Already Is, and What Corpus Size Buys

Survey F names DreamCoder, babble and Plotkin's anti-unification without
developing them; the brief for this survey asks specifically what they say about
corpus size, since lips mints from as little as one program.

DreamCoder's own framing states the mechanism plainly: "It builds expertise by
creating programming languages for expressing domain concepts, together with
neural networks to guide the search for programs within these languages. A
'wake-sleep' learning algorithm alternately extends the language with new
symbolic abstractions and trains the neural network on imagined and replayed
problems" (Ellis et al., "DreamCoder: Growing generalizable, interpretable
knowledge with wake-sleep Bayesian program learning", arXiv:2006.08381, fetched,
https://arxiv.org/abs/2006.08381). Two words matter for the corpus-size question:
"replayed" and "imagined". DreamCoder's abstraction step only has real programs
to generalize over when it replays a growing library of previously solved tasks;
early in a run, with few or no solved tasks, it falls back on the neural network
*imagining* plausible programs to prime the search. That fallback is the
system's explicit answer to "what do you do with too little corpus": synthesize
plausible extra examples, because generalizing from too few real ones does not
produce a usable abstraction.

babble's abstract names the two failure modes of library learning at small or
noisy corpora directly: "it explores too many candidate library functions that
are not useful for compression" and "it is not robust to syntactic variation in
the input" (Cao, Kunkel, Nandi, Willsey, Tatlock and Polikarpova, "babble:
Learning Better Abstractions with E-Graphs and Anti-Unification", POPL 2023,
arXiv:2212.04596, fetched, https://arxiv.org/abs/2212.04596). The second failure
mode is the sharper one for lips: two programs that mean the same thing but are
worded differently ("back up X to Y daily" versus "daily, back up X into Y") look
like unrelated corpus items to naive syntactic anti-unification, and babble's
whole contribution, anti-unification performed inside an e-graph that has already
saturated an equational theory, is a way to make "the same up to known rewrites"
count as "the same" before generalizing. lips sidesteps this today by not
generalizing over wording variance at all: the model reads the words directly and
mints patterns for exactly the phrasings it saw (`Lang/Pattern.hs`,
`Lang/Crystallize.hs`), so there is no anti-unification step to get wrong. That is
the right call at n=1, and babble's result says precisely when it would stop
being the right call: once `generate` is asked to generalize a single engine
across programs with real wording variance (the README's own multi-program case,
"pass several programs... and it generalizes one grammar across them"), babble's
finding that naive anti-unification is "not robust to syntactic variation" is a
direct warning that the model doing that generalization today has no formal
backstop, and an equational e-graph is the shape of the backstop if one is ever
needed.

Stitch's finding is the most quantitative and the most useful for calibrating
corpus size against confidence: "Stitch is 3-4 orders of magnitude faster and
uses 2 orders of magnitude less memory while maintaining comparable or better
library quality (as measured by compressivity)... [and] is robust to terminating
the search procedure early" (Bowers, Olausson, Wong, Grand, Tenenbaum, Ellis and
Solar-Lezama, "Top-Down Synthesis for Library Learning", POPL 2023,
arXiv:2211.16605, fetched, https://arxiv.org/abs/2211.16605). "Compressivity" is
the load-bearing word: every library-learning system in this line, DreamCoder,
babble, stitch, treats **minimum description length of the corpus under the
induced vocabulary** as the objective a generalization is scored against, not any
notion of "the vocabulary the author actually meant". That objective is
well-defined and well-motivated for a corpus of dozens to hundreds of programs,
where compression differences are measurable and stable. At a corpus of size one
(lips's own default case), the compression objective degenerates: there is
nothing to compress against except the one program's own repeated substrings, so
description-length minimization cannot distinguish "the right domain vocabulary"
from "the shortest grammar that happens to parse this one file". **This is the
survey's sharpest inference (marked as such because no cited paper states it for
lips's exact case): corpus size is not a knob library-learning systems tune
gracefully down to one, it is the boundary condition where the entire family's
scoring function stops being informative, which is exactly why lips's own
`generate` uses a model's judgment (grounded by schema lookup and the draft-check
gate) rather than a compression objective, and exactly why the README frames
multi-program `generate` as a distinct, better-evidenced case ("pass several
programs... and it generalizes one grammar across them") rather than the default.**
Plotkin's anti-unification (1970, cited in survey F, not re-derived here) is the
shared primitive underneath all three systems' abstraction step; what this
survey adds is that its output quality is a function of corpus size in a way that
has a name (compressivity) and a documented failure floor (stitch and babble both
report degraded or unstable abstractions on small, noisy inputs), not merely a
vague "needs more data".

### Protobuf, gRPC, GraphQL: Vocabularies That Already Separate Shape From Behavior

These three are worth naming briefly because they already do, for RPC and query
surfaces, what NixOS options do for configuration: name a typed slot externally.
Protocol Buffers documentation calls itself exactly that, an interface definition
language: "gRPC can use protocol buffers as both its Interface Definition Language
(IDL) and as its underlying message interchange format" (grpc.io, "Introduction to
gRPC", fetched, https://grpc.io/docs/what-is-grpc/introduction/). Crucially, a
`.proto` service definition names a *method* (a behavior slot: `Backup(BackupSpec)
returns (BackupResult)`) with a typed request and response, but the method body
lives in generated stub code the type does not constrain at all; the IDL is
already, honestly, a vocabulary of shape-of-call, not of behavior, and it does
not pretend otherwise. GraphQL's SDL is the same shape one layer up (typed query
and mutation fields over a schema), and effect systems and capability grammars
(not independently fetched here; the claim is structural, marked inference) push
the same idea one step further by typing *what a function is allowed to do*
(read a file, open a socket) rather than only its input/output shape. That
step, typing permitted effects rather than only values, is the direction a
typed-API vocabulary for lips would need to grow in, because it is the only one
of the three that starts to close FrAngel's and the effectful-synthesis paper's
gap (a call's type says nothing about its side effect, but an effect-typed call's
type says something).

## Verdicts

**Host language.** No language surveyed fits lips's calculus better than Haskell,
and the reasons are specific rather than a default preference. Every candidate
whose defining feature is search (Prolog, ASP, miniKanren) solves a problem lips's
single-answer merge does not have; the search machinery would be pure overhead. The
one candidate that models the calculus itself well, Datalog, models it in an
untyped relational substrate, and adopting it wholesale would trade compile-time
exhaustiveness on the value grammar (`Engine/Value.hs`, `AGENTS.md` invariant 3)
for a handful of techniques (subsumption, incremental recompute) that are
independently portable into Haskell without the trade. Racket answers the deepest
question asked here, "is `#lang` the right model for an engine", with a qualified
no: the framing is right and lips already uses it, but Racket's engineering effort
went into making languages cheap to *distribute to strangers and compose*, a
problem lips's per-problem, disposable engines do not have, at the cost of the
static typing lips's kernel currently relies on for correctness by construction.
Rosette is the one live thread worth a dedicated follow-up, not for the kernel but
for the mint's own verification step, where "prove no input breaks this engine"
would strengthen invariant 5's `.expect` gate beyond testing. Haskell's actual
advantage is not idiomatic or aesthetic: it is that the kernel's core discipline
("illegal states unrepresentable", `AGENTS.md`) is a compile-time property in
Haskell and would be, at best, a runtime convention everywhere else surveyed.

**Steal Without Rewriting**

- Soufflé's subsumption (`<=` between rule heads) as the concrete mechanism for
  survey F's open "lex specialis" question: a more specific rule's derivation
  dominating a more general one. Touches `Refine.hs` (where rule application is
  decided) and possibly `Engine/Overlap.hs` (which already reasons about rule
  pattern overlap and could distinguish "overlap that must be an error" from
  "overlap resolved by specificity").
- DDlog/differential-dataflow's incremental fixpoint (`only work with the new
  tuples generated in the previous iteration`, Datalog semi-naive evaluation,
  and DDlog's "minimum amount of work necessary to compute changes") as a future
  optimization for `Refine.hs`'s fixpoint loop, once program or corpus size makes
  full recompute a measured cost rather than a hypothetical one.
- Stitch/babble's compressivity objective as the missing acceptance criterion for
  multi-program `generate`: today `Lang/Crystallize.hs` and the mint gate accept a
  generalized grammar if it parses every program and passes `.expect`; a
  compression check (does the induced pattern set actually shorten the total
  program corpus, or does it just barely parse it) would catch an overfit or
  needlessly narrow grammar the current gate cannot see. Touches
  `Lips/Generate/Minting.hs` and `Lips/Generate/Draft.hs` (the mint-time
  acceptance path) and would need a new check, not a rewrite of the refiner.

**Typed-API-as-vocabulary hypothesis.** Plausible as a *grounding* mechanism,
implausible as a *complete* one, and falsifiable directly: mint an engine
against a small, real, effectful typed library (a single function such as
`restic`'s hypothetical Haskell binding, or a well-typed HTTP client library, not
a pure data-shape library) instead of against NixOS options, using the same
two-tool discipline lips already has (ground the call's name and type, leave the
argument values to the program's words), and check whether the resulting engine's
calls are merely well-typed or actually behaviorally correct against the same
kind of pinned `.expect` test lips runs for NixOS engines today. The prediction,
based on FrAngel's and the effectful-synthesis paper's own stated gap ("well-typed
but wrong", the type not pinning down side effects or call sequencing), is that
grounding will succeed (every named call will type-check) while correctness will
not transfer automatically the way it does for NixOS options, because a NixOS
option's type is definitionally the full space of legal *configuration*, while a
function's type is never the full space of legal *behavior*. If that prediction
is wrong, i.e. if `.expect`-style behavioral tests pass at the same rate for a
typed-API engine as for a NixOS engine with no extra grounding beyond the type
checker, the hypothesis is stronger than this survey estimates and deserves a
dedicated design track; if it is right, the missing piece is an effect-typed or
specification-typed vocabulary (in the shape of the effectful-synthesis and
RESTful-API-synthesis papers cited above), not a bigger corpus of ordinary typed
signatures.

**Unverified, and named as such.** The exact wording of the CACM 2018 Racket
paper's prose is not quoted verbatim above; the fetched PDF's custom ligature
font corrupts direct text extraction (common OCR-adjacent ligature substitution),
so its content is paraphrased and the claims attributed to it are the paper's
documented abstract and section structure, confirmed independently via Racket's
own documentation for the mechanism ("`#lang`", "packaging a reader and expander
starting point"). The claim that effect systems and capability grammars are
"vocabularies of behavior" in the same sense as protobuf/GraphQL SDL is marked as
this survey's own inference (structural analogy), not sourced to a fetched
primary text; a follow-up should fetch a primary effect-systems source (e.g. Koka
or Eff documentation) before this claim is used in `DESIGN.md`.

The claim, made in the Half 1 Datalog discussion above, that lips's rule
language might already sit inside "safe Datalog" and so admit a decidable
termination proof, is superseded by the centerpiece section's own finding: the
settled artifact-axis design explicitly wants general recursion over named
external primitives, which is Turing-complete by construction (halting problem,
Turing 1937) and therefore forfeits Datalog's termination guarantee on purpose,
in exchange for completeness inherited from the host rather than proven inside
the kernel. The step budget in `Refine.hs` is not a placeholder for a future
static proof; given general recursion, no such proof can exist, so the step
budget is the permanent, correct answer, and the centerpiece section states the
mint-time/run-time gate this implies precisely.

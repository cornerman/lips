# The Guarantee Spectrum

This survey compares three levels of formal rigor that a language design can offer and asks where
lipsidea should spend its rigor budget. Terms used throughout: the **kernel** is the self-describing
spec-language itself; a **vocabulary** is a problem-specific language minted in the kernel; a
**Solution** is an application spec written in a vocabulary; the **System** is the kernel plus its
vocabularies plus the compiler plus the Nix-based realization. Solutions are meant to stay thin,
pure intent; mechanism lives in the System.

The reader is an expert developer reviewing a Solution at intent level. The metric is comprehension
per minute of review. Any rigor mechanism that forces the reviewer to read proof scripts, discharge
SMT obligations, or wait on a slow checker before understanding what a Solution does has already
failed the metric, no matter how sound it is.

## 1. Decidable Checks: Fast, Total, and Where They Break

A decidable check is one the compiler can always finish: it either accepts, rejects, or reports a
concrete counterexample, in bounded time, for every input. This tier buys speed and unconditional
termination at the cost of expressive power: anything that needs unbounded search or genuine
recursion over unstructured data has to be pushed out of the checked core.

**Dhall** is the purest example aimed at configuration. Its own README states the design goal
directly: "Dhall is not Turing-complete... Evaluation always terminates, no exceptions"
(https://github.com/dhall-lang/dhall-lang). Dhall achieves this by disallowing general recursion in
the language entirely; anything resembling a loop must be expressed as a fold over a fixed,
already-finite structure. The tradeoff is explicit and intentional: the project's slogan, quoting
the design rationale, is "Config files shouldn't be Turing complete." There is no escape hatch
inside the language; Turing-completeness, if needed, lives entirely in the host program that invokes
the Dhall interpreter.

**CUE** takes a different route to decidability: unification over a lattice rather than fold-only
recursion. CUE's own documentation frames it as "not a general-purpose programming language"
(https://cuelang.org/docs/introduction/) built around a merge operation that is associative,
commutative, and idempotent. That algebraic discipline is what makes CUE configurations composable
from independent sources without one importing another, and it is also what keeps validation
decidable: merging is a lattice meet, not arbitrary computation. CUE's escape hatch is external:
real computation (templating, code generation) happens in Go or in CUE's scripting extensions,
layered outside the checked core.

**Nickel** makes the boundary between decidable and general-purpose explicit inside one language
rather than by excluding a feature. Nickel is described by its own documentation as a full
programming language ("Nickel is a programming language... Don't use hacks, don't reinvent the
wheel," https://nickel-lang.org/), so it is Turing-complete and does not promise termination.
Instead Nickel offers a dial: "type annotations are checked statically, before the program even
starts, whereas contract annotations are checked lazily, at run-time"
(https://nickel-lang.org/user-manual/correctness/). The Nickel manual argues directly for this split
over pure static typing: for configuration code, "a configuration is a terminating program run once
on fixed inputs, so basic type errors will show up right away, even without static typing," while
properties like "this is a valid port number" are "trivial" to check at runtime but would require
"very advanced machinery" to check statically. This is gradual typing plus contracts
(refinement-style runtime predicates) used deliberately to keep the common case fast and push only
the hard properties to runtime.

**Elm** shows the same idea from the application-language side. Elm advertises "no runtime
exceptions in practice," achieved through the compiler's static type checking
(https://en.wikipedia.org/wiki/Elm_(programming_language)). Note the hedge: "in practice," not "by
construction." Elm's type checker is decidable and fast, but Elm permits ordinary recursion, so it
does not guarantee termination; it guarantees the absence of type errors and null-style crashes, not
the absence of infinite loops or stack overflows. This is a narrower, cheaper guarantee than
totality, and it is exactly calibrated to what a UI-rendering language needs: freedom from crashes,
not freedom from bugs.

**Agda's** totality checker sits at the strict end of this tier and shows how a decidable-checks
language handles a needed escape hatch honestly rather than silently. By default Agda accepts "only
these recursive schemas that it can mechanically prove terminating": primitive recursion (argument
shrinks by exactly one constructor per call) and the more general structural recursion, where the
recursive argument is a strict subexpression of the original, possibly decreasing lexicographically
(https://agda.readthedocs.io/en/latest/language/termination-checking.html). When a function
genuinely cannot be shown to terminate this way, Agda exposes two explicit, visible pragmas:
`TERMINATING`, which tells the checker to trust the function anyway, and `NON_TERMINATING`, a "safer
version" that additionally refuses to unfold the function during type checking. Both pragmas are
syntactically marked in the source, so a reviewer sees exactly where the decidable guarantee has
been switched off.

**Idris** generalizes this to an opt-in system rather than an all-or-nothing mode. "By default,
Idris allows all well-typed definitions, whether total or not." A function can be declared `total`,
which "will be a compile time error for the totality check to fail," and the checker can be queried
per-definition with `:total` (https://docs.idris-lang.org/en/latest/tutorial/theorems.html).
Totality in Idris requires covering all inputs, being well-founded, using only strictly positive
data types, and calling only other total functions; a proof that relies on a partial function is not
trusted. Crucially, Idris's own documentation admits the check "can, of course, never be certain due
to the undecidability of the halting problem," so it is conservative: it may reject terminating
functions it cannot prove terminating, but it never falsely certifies a non-terminating one as
total.

**Koka** takes a third approach: instead of banning or gating non-termination, it names it and
tracks it in the type system as an effect. A Koka function type carries an explicit effect row, and
the documentation gives the canonical example: `fun sqr : (int) -> total int`, `fun divide :
(int,int) -> exn int` ("may raise an exception, partial"), `fun turing : (tape) -> div int` ("may
not terminate, diverge") (https://koka-lang.github.io/koka/doc/book.html). A function without any
effect is `total` and "corresponds to mathematically total functions, a good place to be."
Non-termination is not forbidden; it is made visible, composable, and inferrable, so a reviewer or a
caller can see at the type level exactly which functions might diverge, without the language having
to reject them.

**What decidable checks buy, concretely:** an answer every time, in practice near-instant, with no
proof obligations for the reviewer to read. **What escapes them:** anything needing unbounded
search, general recursion over unstructured data, or properties that depend on run-time values
(Nickel's port-number example). **How each system handles the Turing-complete escape:** Dhall and
CUE push it entirely outside the language into a host process; Nickel and Elm accept full
Turing-completeness but keep the fast-checked subset (types) separate from the runtime-checked
subset (contracts); Agda and Idris keep totality as a checked, opt-in property with syntactically
visible escape pragmas; Koka tracks non-termination as an ordinary, inferred effect rather than an
exception to the type system.

## 2. Proof-Carrying: Real Numbers on Proof Burden

Proof-carrying systems (Dafny, F*, Idris in full theorem-proving mode, Liquid Haskell, and the
model-checking middle ground of TLA+ and Alloy) trade reviewer speed for a machine-checked guarantee
that a specific property holds for all inputs, not just the ones tested. The central empirical
question for lipsidea is: how much does that guarantee cost per line of code, and does the cost
scale with system size in a way that a Solution author could tolerate.

**seL4**, a formally verified microkernel, gives the highest-profile numbers in the field. As of
April 2025 the verified 64-bit RISC-V kernel is about 10,000 source lines of code, other verified
configurations run 12,100 to 16,000 SLOC depending on platform
(https://sel4.systems/About/FAQ.html). Against that code, the Wikipedia summary of the project
(sourced to the seL4 reference manual) reports "~10k LoC and ~500k LoP" (lines of proof), i.e. "the
proof overhead of 50 lines of proof per 1 line of C code," which it flags as drastically increasing
development cost and slowing velocity (https://en.wikipedia.org/wiki/Sel4). The same source reports
the project's own cost claim: about $400 per line of code for the verified kernel versus $1,000 per
line of code for comparable unverified high-assurance kernels, i.e. formal verification cost roughly
2x an unverified high-assurance process here, not an order of magnitude more, because the
verification work substitutes for other assurance activities rather than simply adding to them.

**CompCert**, a formally verified optimizing C compiler proved correct in the Rocq (Coq) proof
assistant, was put through six CPU-years of random differential testing by Csmith, a tool that
generates random C programs and compares the output of eleven compilers (Yang, Chen, Eide, Regehr,
"Finding and Understanding Bugs in C Compilers," PLDI 2011,
https://www.cs.utah.edu/~regehr/papers/pldi11-preprint.pdf). The result: "the under-development
version of CompCert is the only compiler we have tested for which Csmith cannot find wrong-code
errors... this is not for lack of trying." The bugs Csmith did find in CompCert were all in its
unverified front-end (integer promotions, implicit casts), and the paper reports that the
maintainers responded by expanding the verified portion of the compiler to cover exactly those
cases. This is direct evidence that a proof can eliminate an entire class of bug (miscompilation in
the verified middle-end) while leaving the unverified boundary exactly as fragile as any other
software.

**IronFleet**, a methodology for building verified distributed systems in Dafny, reports the
cleanest proof-to-code ratio in the literature because its authors measured it precisely. At the
implementation layer, "our ratio of proof annotation to executable code is 3.6 to 1," attributed to
specific proof-writing techniques and automation; across the whole project (two real systems,
IronRSL and IronKV) the total was about 1,400 lines of spec, 5,114 lines of implementation, and
39,253 lines of proof annotation, requiring "approximately 3.7 person-years" (Hawblitzel et al.,
"IronFleet: Proving Practical Distributed Systems Correct," SOSP 2015,
https://www.microsoft.com/en-us/research/wp-content/uploads/2015/10/ironfleet.pdf). The paper also
reports the iteration-speed cost directly: a full serial integration build "requires approximately
six hours," reduced in practice to "6 to 8 minutes" by parallelizing verification across a cloud
build farm, which the authors say is "comparable to any other large system integration build."
IronFleet's proof burden (3.6:1) is an order of magnitude lower than seL4's (50:1), plausibly
because Dafny's SMT-based auto-active verification discharges far more obligations automatically
than Isabelle/HOL's interactive proof style, at the cost of covering a narrower specification
(protocol refinement, not full C-level functional correctness to binary).

**HACL\*** shows the pattern working in a shipped product. Written and verified in F*, HACL*
primitives (starting with Curve25519) shipped in Firefox's NSS security library in 2017; Mozilla's
own announcement states the team believes Firefox was "the first major Web browser to have formally
verified cryptographic primitives," and that the verified implementation was "almost 20% faster"
than the code it replaced
(https://blog.mozilla.org/security/2017/09/13/verified-cryptography-firefox-57/). This is the
clearest real-world instance of "verified substrate, checked application": Firefox's own build and
release process does not re-verify HACL*; it consumes the library through an ordinary API and
inherits the proof.

**A cautionary data point outside software:** the Feit-Thompson odd-order theorem, a
pure-mathematics result with no adversarial or systems complexity at all, took a team led by Georges
Gonthier "a six-year collaborative effort" to formalize in Coq, producing "more than 150,000 lines
of proof scripts, including roughly 4,000 definitions and 13,000 theorems," for a proof whose
informal version runs about 250 pages, a ratio of "4-5 lines of SSReflect code per line of informal"
mathematics (Gonthier et al., "A Machine-Checked Proof of the Odd Order Theorem," ITP 2013,
https://hal.inria.fr/hal-00816699/document). This matters for lipsidea because it isolates the
proof-burden variable from systems-engineering variables (concurrency, hardware, adversaries): even
in the best case, mechanized proof of a single nontrivial result is a multi-year undertaking for
domain experts. Any guarantee level that requires a Solution author, who is not a proof engineer, to
produce artifacts in this vicinity is incompatible with reviewing at intent level.

**Model checking as the middle ground.** TLA+ and Alloy trade the unconditional "for all inputs"
guarantee of a proof for a much cheaper, still rigorous, "for all reachable states up to this bound"
guarantee, checked automatically rather than proved interactively. Amazon's own account of adopting
TLA+ across AWS services is unusually concrete about both the payoff and the cost (Newcombe, Rath,
Zhang, Munteanu, Brooker, Deardeuff, "Use of Formal Methods at Amazon Web Services," 2014/CACM 2015,
https://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf). Engineers "have been able to learn
TLA+ from scratch and get useful results in 2 to 3 weeks," far short of the years-long ramp implied
by interactive theorem proving. The model checker found bugs invisible to design review, code
review, and testing: one had "the shortest error trace exhibiting the bug contained 35 high level
steps," and the paper notes "the bug had passed unnoticed through extensive design reviews, code
reviews, and testing." The cost shows up in scale: one case required "the distributed version of the
TLC model checker, running on a cluster of ten cc1.4xlarge EC2 instances" to exhaustively explore
the state space, which is model checking's characteristic failure mode, state explosion, met with
raw compute rather than human proof effort.

Alloy takes explicit ownership of the same tradeoff as a design philosophy rather than a limitation
to work around. To keep model-finding decidable, "the Alloy Analyzer performs model-finding over
restricted scopes consisting of a user-defined finite number of objects," justified by the
small-scope hypothesis: "a high proportion of bugs can be found by testing a program for all test
inputs within some small scope" (https://en.wikipedia.org/wiki/Alloy_(specification_language),
hypothesis originally evaluated in Andoni, Daniliuc, Khurshid, Marinov, "Evaluating the Small Scope
Hypothesis," 2002). This is not a fallback position; it is Alloy's stated reason for bounding scope
at all, and it reframes "the checker didn't explore everything" as an acceptable, quantifiable risk
rather than a defect.

**Where proof burden kills iteration speed, summarized:** the ratio is not fixed; it depends on what
is being proved and with what automation. Full functional correctness to binary code (seL4,
interactive theorem proving in Isabelle/HOL) runs about 50 lines of proof per line of code.
Protocol-level refinement proofs with an SMT-automated tool (IronFleet, Dafny) run about 3.6 to 1.
Pure mathematics with a powerful automation library (Feit-Thompson, Coq/SSReflect) runs about 4 to 5
to 1 but still consumes years of expert time because the object being proved is itself enormous. In
every case, a change to the underlying code or protocol forces a partial re-proof; this coupling,
not the raw line count, is what damages iteration speed, because a small edit can invalidate a
large, non-obviously-related slice of the proof.

## 3. Conformance and Differential Testing: Policing Implementations, Not Specs

The third tier gives up the "for all inputs" guarantee entirely and replaces it with an extremely
large, automatically generated sample, checked continuously and cheaply. Its target is different in
kind from tiers 1 and 2: conformance suites police implementations (compilers, interpreters,
engines) against a shared specification, not individual programs against their own logic.

**WebAssembly** is the cleanest example of a specification, a reference implementation, and a
conformance suite shipped as one artifact. The WASM spec repository states it "holds the sources for
the WebAssembly specification, a reference implementation, and the official test suite"
(https://github.com/WebAssembly/spec). The reference interpreter, written in OCaml, is explicitly
built "for clarity and simplicity, not speed... a device for nailing down their exact semantics,"
and its own build target `make test` runs the test suite of `.wast` script files against it
(https://github.com/WebAssembly/spec/blob/main/interpreter/README.md). Every production WASM engine
(V8, SpiderMonkey, Wasmtime, and others) runs this same suite; none of them, nor the reference
interpreter itself, is proved correct against the formal semantics. Conformance is established by
agreement across independently developed implementations on a shared, large, versioned test corpus,
not by proof.

**SQLite's** testing regime is documented by the project itself in unusual quantitative detail
(https://www.sqlite.org/testing.html). As of version 3.42.0, the SQLite library is about 155.8 KSLOC
of C code; the project has "590 times as much test code and test scripts," 92,053.1 KSLOC. Four
independently maintained test harnesses attack the code from different angles: the original TCL test
suite (51,445 distinct test cases, "millions of separate tests" once parameterization is run); TH3,
a proprietary C harness providing "100% branch test coverage (and 100% MC/DC test coverage)" via
50,362 parameterized test cases that expand to about 2.4 million test instances for full-coverage
runs and up to 248.5 million tests in a pre-release soak test; SQL Logic Test (SLT), which runs 7.2
million queries against SQLite and against PostgreSQL, MySQL, Microsoft SQL Server, and Oracle and
checks that all five agree, a direct instance of differential testing; and a proprietary fuzz
engine, dbsqlfuzz, that mutates both SQL text and database file bytes simultaneously. Note that
SQLite's test-to-code ratio (590:1) is more than ten times seL4's proof-to-code ratio (50:1);
testing at this intensity is not cheaper than proof in raw volume, but it is cheaper in the currency
that matters for a general engineering team, since it is compute-bound and automatable rather than
bound by scarce proof-engineering expertise.

**C compiler test suites** show the same differential-testing pattern applied to a much older, less
centrally coordinated ecosystem. GCC's own build system documents explicit "support for torture
testing using multiple options" (https://gcc.gnu.org/onlinedocs/gccint/Testsuites.html), running the
same test programs under many optimization-flag combinations to catch bugs that only appear under
specific optimization passes. Csmith, discussed above for its CompCert result, found bugs by the
same random-differential method in the other ten compilers it targeted, five open source (GCC, LLVM,
CIL, TCC, Open64) and five commercial (https://www.cs.utah.edu/~regehr/papers/pldi11-preprint.pdf).
The paper's own conclusion is directly relevant to lipsidea's guarantee question: "verification does
not obviate testing, but rather complements it... verification, on the other hand, typically focuses
on a narrow slice of a stack of tools, and the parts outside the slice remain in the trusted
computing base." Even the most proof-heavy artifact in this survey (CompCert) still needed six
CPU-years of differential testing to find the bugs that lived outside its proof boundary.

**Why this tier is distinct from proof:** a conformance suite never certifies that no bug exists; it
certifies that a large, curated, growing sample of behaviors matches across independent
implementations or matches a reference. Its cost is dominated by compute and by the discipline of
maintaining the corpus, not by scarce human proof-engineering time, and unlike a decidable check it
does not need to run on every edit to be useful, only continuously in the background. That is
exactly why it is the right guarantee level for compilers and interpreters shared by many callers
rather than for the callers' own code.

## 4. Gradual Verification and the Verified-Substrate Pattern

The academic term for deliberately mixing tiers 1 and 2 inside one system is gradual verification:
"allows programmers to effectively verify partially specified code, checking statically where
possible and at run time where necessary," a direct analogy to gradual typing (Bader, Aldrich,
Tanter, "Gradual Program Verification," VMCAI 2018, DOI 10.1007/978-3-319-73721-8_2; framing quoted
from Jonathan Aldrich's research description, https://www.cs.cmu.edu/~aldrich/). The core move is to
let a static checker discharge whatever it can decide quickly and insert a runtime check, with an
explicit cost, for whatever it cannot.

Nickel's contract system (Section 1) is this pattern implemented directly in a configuration
language: static types for what the checker can decide ahead of time, runtime contracts for what
depends on values the checker cannot see in advance. Idris's per-function `total` annotation and
Koka's `div` effect are the same pattern implemented as a type-level label rather than a runtime
check: the guarantee is downgraded locally and explicitly, visible to a reader, rather than either
blocking the whole program or silently accepting an unchecked function.

HACL*, EverCrypt, and their deployment in Firefox NSS (Section 2) demonstrate the pattern at the
largest, highest-stakes scale found in this survey: "verified substrate, checked application." The
proof effort (F* verification of the crypto primitives) is paid once, by domain experts, inside the
library. Every consumer of that library, including Firefox's own release engineering, inherits the
guarantee by linking against the library's ordinary API and never re-derives or re-checks the proof.
The application layer around the verified core (parsing TLS handshakes, managing connections,
handling malformed input from the network) is not proved; it is tested and fuzzed by Mozilla's
ordinary browser QA process, i.e., it lives in tier 3, not tier 2.

**Refinement-type ergonomics, the friction point.** Liquid Haskell and Dafny both add
refinement-style predicates (preconditions, postconditions, invariants) to an otherwise ordinary
programming language, checked by handing proof obligations to an SMT solver (Z3) rather than
requiring an interactive proof (https://github.com/ucsd-progsys/liquidhaskell,
https://github.com/dafny-lang/dafny). This buys most of tier 2's precision without full
theorem-proving overhead, which is why IronFleet's 3.6:1 proof ratio is an order of magnitude better
than seL4's 50:1. The recurring practical complaint across both tools, visible in the IronFleet
paper's own discussion of "automation challenges," is SMT unpredictability: the solver can time out
or fail on a fact that is true but not visible to it without an explicit hint (a lemma invocation,
an unfolded definition, a narrower search scope), so refinement-typed code accumulates small proof
annotations that have nothing to do with the domain logic and everything to do with steering the
solver. This is the concrete mechanism by which "add a proof" quietly becomes "add proof-engineering
skill to the required skill set of every contributor," which is precisely the density-killing
failure mode lipsidea's guarantee level must avoid.

## 5. Guarantee Architecture for Lipsidea

**The hypothesis under test:** vocabularies are verified or model-checked once by their authors;
Solutions written in a vocabulary get only fast decidable checks but inherit the vocabulary's
guarantees; conformance suites police implementations (the kernel's compiler and runtime), not
individual Solutions.

**The evidence supports this hypothesis as the default shape**, for three converging reasons.

First, it matches where every real system in this survey actually put its expensive rigor: at a
shared substrate consumed many times, never at a leaf-level artifact written once. seL4, CompCert,
and IronFleet all pay a large, fixed proof cost for one thing (a kernel, a compiler, a protocol
library) that many callers reuse without re-verifying. HACL*/Firefox is the exact "verified
vocabulary, checked application" shape lipsidea proposes, just relabeled: HACL* is the
vocabulary-equivalent (a fixed, expert-verified building block), Firefox's use of it is the
Solution-equivalent (an ordinary consumer that inherits the guarantee through an API boundary and is
tested, not proved, at its own layer).

Second, it matches the density requirement directly. Feit-Thompson (six years, 150,000+ lines, for
one theorem, with no systems complexity at all) and seL4 (50 lines of proof per line of code) both
show that proof-carrying rigor at the point of authorship is incompatible with reviewing at intent
level. Pushing that cost to the vocabulary author, paid once, amortized over every Solution written
in that vocabulary, is the only placement in this survey where the cost is bounded and the benefit
compounds. A Solution author reading CUE- or Nickel-style decidable checks, or Dhall-style
guaranteed termination, is reading at the speed Elm and Dhall demonstrate: type errors and contract
violations surface immediately, with no proof script to read.

Third, it matches the layered-escape-hatch pattern every mature decidable-checks language already
uses rather than inventing a new one. Agda's `TERMINATING` pragma, Idris's opt-in `total`, and
Koka's `div` effect all show that a decidable-checks core can coexist with an explicit, visible,
locally-scoped downgrade, rather than forcing an all-or-nothing choice between "fully decidable" and
"fully general."

**The complication the plain hypothesis does not address:** lipsidea's kernel is fully general by
design, so a Solution is legally allowed to contain general recursion or arbitrary control flow,
"glue," not expressible as a fold over a vocabulary's fixed constructs. No decidable check can
certify termination or full correctness of that glue; Dhall's answer (forbid it) and CUE's answer
(push it outside the language) are both unavailable to lipsidea by design, since the substrate must
remain Turing-complete.

**Recommended modification, ranked against the plain hypothesis:**

1. Vocabulary layer: verified or model-checked once by the vocabulary's author, exactly as
hypothesized. Proof-carrying tools (Dafny-style SMT automation is the right cost point, not
Isabelle/HOL-style interactive proof, given IronFleet's 3.6:1 versus seL4's 50:1) or
TLA+/Alloy-style model checking for vocabularies whose main risk is concurrent or stateful protocol
logic. This is where lipsidea should be willing to spend person-years, because the cost is paid once
per vocabulary and inherited by every Solution.

2. Solution layer, default path: fast decidable checks only, in the Dhall/CUE/Nickel style, at every
point where a Solution uses a vocabulary's constructs as intended. This preserves
comprehension-per-minute and requires no proof literacy from the reviewer.

3. Solution layer, glue path (the case the plain hypothesis misses): when a Solution needs general
recursion or control flow the vocabulary does not provide, that code must be syntactically marked as
an escape, the way Agda marks `TERMINATING` and Koka marks `div`, not silently accepted as ordinary
vocabulary code. Marked glue drops out of tier 1 and into tier 3, conformance and property-based
testing against the glue's own stated intent, not tier 2 proof. This is the honest placement: glue
is rare, small, and exactly the part of a Solution that most resembles ordinary software, so testing
it (cheap, automatable, no proof expertise required) is proportionate, while requiring proof of it
(expensive, unbounded, blocks review) is not, and silently trusting it with no marker at all (Elm's
stance, acceptable for a UI language) would hide exactly the risk a reviewer most needs to see.

4. System layer: the kernel's own compiler and runtime are the highest-leverage target for a WASM-
or SQLite-style conformance suite (a growing corpus of test Solutions with known-correct compiled
output, run continuously against every change) regardless of whether the compiler itself is ever
proof-carrying. If resources allow, the compiler is also the best single candidate in the whole
System for CompCert-style proof, since, like CompCert and seL4, it is small, shared by every
vocabulary and every Solution, and changes far less often than Solutions do.

This ranks above the plain hypothesis because it keeps the plain hypothesis's core allocation
(expensive rigor at the substrate, cheap rigor at the leaf) while giving the glue case an honest,
visible home instead of either forbidding it (impossible, given the fully-general kernel) or
pretending decidable checks cover it (false, given the halting problem). It ranks below a
hypothetical "prove everything" architecture only in raw assurance ceiling, and this survey's own
numbers (50:1 at seL4, six years for one theorem at Feit-Thompson) are the evidence that a "prove
everything" ceiling is not reachable without destroying the comprehension-per-minute metric lipsidea
is optimizing for.


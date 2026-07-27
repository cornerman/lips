# The Theory Under the Decision Calculus

Prior-art scan (July 2026) with a different question from surveys A-E. Those asked
"has anyone *built* this?" (meta-formalisms, the graveyard, guarantee levels, the AI
wave, the compiled-AI paradigm). This one asks: **has anyone *formalized* the kernel?**

The finding: yes, four times over, in four fields that do not cite each other.
Merge-by-strength is belief merging; refinement-to-fixpoint is term rewriting;
conflict reporting is model-based diagnosis; oblige/forbid/allow is deontic logic.
Three of the four open questions in `DESIGN.md` §11 have textbook answers, and one
published result (priority rewrite systems, 1987) is the sharpest existing critique
of the kernel's shape: lips combines rewriting with priorities, and that combination
is known to be delicate.

Terminology follows `AGENTS.md`: **program** (`.lips`), **engine** (`.lang`),
**kernel** (domain-blind physics), **decision base**.

Scope note. Four seams are worked here (rewriting, merging, diagnosis, deontic
logic) plus the config-lattice competitors that implement seam 2 in production.
Three further seams are named but not worked, at the end.

## Quick-Reference Table

| lips mechanism | Field that formalized it | Key result to use | Payoff |
|---|---|---|---|
| Engine orthogonality (§11) | Term rewriting | Critical pairs; orthogonal ⇒ confluent (Rosen 1973) | Mechanical overlap check, replaces taste |
| Refinement confluence (§2.4) | Term rewriting | Newman's lemma; **priority rewrite systems are delicate** (Baeten/Bergstra/Klop 1987) | A named risk to answer |
| Merge by strength (§2.1) | Belief merging | IC postulates (Konieczny & Pino Pérez 1999/2002) | A checklist merge must satisfy or knowingly violate |
| Strength itself | Belief revision; CUE; Nickel | Epistemic entrenchment; the lattice argument against overrides | Strength derived from provenance, not a free integer |
| Conflict report (§2.2) | Model-based diagnosis | QuickXplain (Junker 2004), Reiter (1987) | Minimal conflict set instead of "two provenances" |
| Obligations (§3) | Deontic logic | Input/output logic (Makinson & van der Torre 2000) | A frame for pattern → mechanism; paradoxes named |
| Heile-Welt (§6) | Deontic logic | Contrary-to-duty (Chisholm 1963) | The coping-strategy structure, already studied |

## Seam 1: Engine Orthogonality Is Critical-Pair Analysis

`DESIGN.md` §11 lists "the concrete mechanism that flags overlapping engine
features" as open, and §4 asserts "overlap is flagged mechanically, not left to
taste". Term rewriting has flagged overlap mechanically since the 1970s.

An engine's rules are a rewrite system: each rule has a left-hand side (a pattern
over subjects, with capture holes) and a right-hand side (emits). The relevant
vocabulary transfers exactly:

- A system is **orthogonal** when it is left-linear (no repeated variable in a
  left-hand side) and non-overlapping (no two left-hand sides unify on a
  non-trivial subterm). Orthogonal systems are confluent: Rosen, "Tree-Manipulating
  Systems and Church-Rosser Theorems", JACM 20(1):160-187, 1973. lips already uses
  the word "orthogonality by construction" for exactly this property, apparently
  independently.
- **Critical pairs** are the computable witnesses of overlap: for each pair of
  left-hand sides that unify, the two divergent results form a critical pair, and
  local confluence follows if every critical pair joins. Knuth-Bendix completion is
  the algorithm; modern refinements (compositional confluence criteria, arXiv
  2303.03906) reduce the work for large systems.
- **Newman's lemma**: termination plus local confluence gives confluence. lips's
  refinement runs to a fixpoint, so termination must be argued anyway; once it is,
  critical pairs are the whole remaining obligation for §2.4's confluence claim.

**Steal.** Implement the orthogonality check as critical-pair computation over rule
left-hand sides, run at `generate` (the door minted engines enter), reported as a
named overlap between two rule ids. This is deterministic, domain-blind, and fits
the existing acceptance gate. It also makes "orthogonality is enforced" a theorem
rather than a promise.

**The warning, and it is serious.** Baeten, Bergstra and Klop, "Term Rewriting
Systems with Priorities" (RTA, Bordeaux, 1987; CWI report at ir.cwi.nl/pub/2047),
study exactly lips's combination: a rewrite system plus a partial order on rules
where a higher rule pre-empts a lower one. Their finding is that the semantics of
such a system is not automatically well defined; the naive definition is circular
(whether a low-priority rule applies depends on whether a high-priority rule
applies, which may depend on further reduction), and they must restrict the class of
systems to recover a sound semantics. lips has priorities in the *decision* layer
(strength) and rewriting in the *refinement* layer. The current design keeps them
apart: merge resolves strength first, refinement then rewrites a settled base. That
separation is very likely what saves lips, and it is currently implicit. It should
be stated as a kernel invariant, with this paper as the reason, because any future
convenience feature that lets rule priority depend on refinement results walks
straight into the 1987 problem.

## Seam 2: Merge by Strength Is Belief Merging

`DESIGN.md` §2.1 defines merge as: same subject, resolve by strength; §2.2: equal
strength and incompatible is an error. The AI literature calls a set of possibly
conflicting formulae a **belief base**, and combining several of them **belief
merging** (also fusion). Konieczny and Pino Pérez (1999, 2002) give rationality
postulates (IC0-IC8) for merging operators under integrity constraints; the survey
entry is the Stanford Encyclopedia article "Belief Merging and Judgment
Aggregation".

Three transfers are worth the reading time:

1. **Postulates as a checklist.** The IC postulates ask questions lips has not
   written down: is merge commutative and associative (order of sources
   irrelevant)? Is it idempotent? Does merging two consistent bases that agree
   yield their conjunction? Is a source ever silently outvoted? lips wants strict
   order-independence (a decision base is a *set*), which is a strong commitment;
   the postulates are how to check the implementation actually has it.
2. **Majority versus arbitration.** The literature separates operators that let
   repetition win (majority) from those that do not (arbitration). lips is
   implicitly arbitration: saying the same thing twice must not beat saying the
   opposite once. Worth stating, because list `Append` aggregation is the one place
   where multiplicity *does* count, and the distinction keeps that from leaking.
3. **Entrenchment instead of numbers.** AGM belief revision derives priority from
   *epistemic entrenchment*, a semantic order over sentences, rather than a dialed
   integer. This is the theory behind the design instinct below.

### The Production Face of This Seam: CUE and Nickel

Neither is in surveys A-E, and both implement §2.1 for real users. They also
disagree with each other, which is the useful part.

**CUE** makes values and types one lattice ordered by subsumption; combining
configurations is the meet (unification), which is commutative, associative and
idempotent *by construction*, so order cannot matter (cuelang.org, "The Logic of
CUE"; lineage: Carpenter, *The Logic of Typed Feature Structures*, 1992). CUE has
**no overrides at all**, and argues the case directly: with override-based systems
(GCL, Jsonnet, HCL, Kustomize, and by extension the NixOS module system) "finding a
declaration for a concrete field value does not guarantee a final answer", so a
reader must chase inheritance chains and file orders. CUE's invariant is the
opposite: *any concrete value you can see is the final value*.

That reads as a direct challenge to lips, and the answer has two parts.

First, the empirical one, which is the stronger: NixOS is the existence proof.
Prioritized merge is not a hypothesis but the substrate of an entire distribution,
running for twenty years at a scale no lattice-only configuration language has
reached. A design objection that predicts unworkability has to explain the working
system.

Second, the diagnostic one: what actually hurts in the systems CUE names is not
priority, it is missing provenance. GCL, Jsonnet, HCL and Kustomize can tell you the
winning value but not who lost, where, and why, so a reader must reconstruct the
chain by hand, and that reconstruction is the cost CUE is really pricing. Priorities
are affordable exactly when provenance is total. Nix's own worst override pain, the
`<unknown-file>` message (Survey D), is the case where its provenance goes missing,
which is the same claim arriving from the other side. lips carries provenance as
kernel data (§2.3), so for any subject the winner, every loser, and each source line
are a query, not an investigation. Strength is also structural rather than authored
(system default < engine default < program), so the order never has to be discovered.

Both parts belong in DESIGN.md §2.1, because the objection will be raised.

CUE's treatment of conflicting defaults is a steal, not a challenge: when two
defaults conflict, CUE does not pick, it drops to the non-default value and requires
an explicit answer, explicitly to avoid depending on "the mood of the
implementation". That is deduce-or-fail, arrived at independently from lattice
hygiene rather than from AI distrust. Two designs reaching the same rule from
different premises is decent evidence the rule is right.

**Nickel** (Tweag) takes the other branch and imports NixOS-style priorities into
the language: merge (`&`) is symmetric, every field has a priority (numeric, with
`default` lowest and `force` highest), a higher priority erases a lower one, and
equal priorities merge recursively or fail loud with both locations
(nickel-lang.org/user-manual/merging). Same-priority conflict is an error naming
both sides, which is exactly lips §2.2. Two observations:

- **Contracts survive override.** In Nickel a contract attached to a field
  constrains whatever later merges into it, including a value that erases it:
  `{foo | Number = 1} & {foo | force = "bar"}` fails. Metadata accumulates across
  the merge and applies to the winner. lips has no analogue: today a stronger
  decision simply wins, and any obligation or assumption riding on the weaker one
  is silently gone. Making obligations and demands attached to a subject survive an
  override, and apply to whatever wins, is a small kernel change with a real
  correctness payoff. This is the strongest single steal in this survey.
- **A wart to avoid.** Nickel's docs admit that merging two `doc` strings is
  unspecified and one is kept at random. Any metadata lips attaches to decisions
  (rationale, provenance notes) needs a defined merge, or it will grow the same
  wart.

### Shipped Strength Calculi and How They Decayed

Merge-by-strength has mass deployments outside configuration languages, and
their failure modes are the empirical case against a free-floating priority
number. CSS cascade specificity plus `!important`, Drools' `salience`, and
XACML's rule-combining algorithms (deny-overrides, first-applicable) are each a
shipped decision calculus; each has an infamous decay story, and the shape is
the same in all three. Priority is an unstructured integer any author may set
at any site, so it stops expressing *who has authority* and becomes a debugging
tool: raise the number until the value wins. The chain then encodes nothing.

Inversion (what would guarantee lips fails the same way): let engines or
programs author strength directly. lips's defense is that strength is
structural (system default < engine default < program) and not writable as a
number, which no shipped system in this list has. Worth keeping deliberate
rather than accidental.

OMG's **DMN** is the counter-example that standardized the problem instead of
suffering it: decision tables carry an explicit *hit policy* (UNIQUE, PRIORITY,
FIRST, COLLECT, ...) declaring per table what happens when several rules fire.
lips's equivalent is `MergeMode` (`Replace`/`Append`), derived from the option
schema rather than authored, which is the stronger version of the same idea.
Architecture Decision Records (Nygard, 2011) are the prose ancestor of the
decision-as-artifact move: subject, choice, rationale, provenance, reviewable
in isolation, but with no execution semantics.

### Other Neighbours, Briefly

**Pkl** (Apple) and **KCL** amend-and-override in the Jsonnet lineage, weaker
theory than CUE or Nickel but real deployment data on how override chains rot.
**System Initiative** (Adam Jacob) models infrastructure as a reactive
hypergraph with *qualifications*, continuously re-answered checks over each
asset; that is close in spirit to lips's assumption decisions with statuses,
and the only entry here that treats "is this still true?" as a live property
rather than a build-time one.

One same-architecture cousin turned up outside configuration entirely:
**Taprun** (taprun.dev) compiles a browser-automation flow once with a model
and replays it deterministically, advertising zero LLM calls at runtime. No DSL
ambition, no domain-blind kernel, but the identical bet, independently made,
and its FAQ already answers lips's regenerate door in miniature ("what happens
when the site changes?").

## Seam 3: Conflict Reporting Is Model-Based Diagnosis

lips reports a conflict as two decisions with both provenances. For two directly
contradictory lines that is perfect. For an over-constrained base where the
contradiction is *derived* several refinement steps down, it is not: the two ground
decisions that collide may both be innocent consequences of a third line the author
wrote.

The configurator community solved this. Reiter, "A Theory of Diagnosis from First
Principles" (Artificial Intelligence, 1987), defines diagnoses as minimal hitting
sets of conflict sets. Junker's **QuickXplain** (AAAI 2004,
cdn.aaai.org/AAAI/2004/AAAI04-027.pdf) computes a *preferred* minimal conflict, and
a preferred relaxation, in a logarithmic number of consistency checks, ordered by
user preference over constraints. Felfernig and colleagues built the product
configurator line on top of this.

**Steal.** With a provenance-linked derivation chain (which lips already has) and a
preference order over decisions (which strength already is), QuickXplain gives:
"these three of your forty lines cannot hold together, the smallest fix is to drop
or change this one." That is a large gain on the reviewer's comprehension-per-minute
metric (§7) for a small, deterministic, domain-blind algorithm. It is a good
candidate milestone: self-contained, testable, no AI, no new grammar.

## Seam 4: Obligations Are Deontic Logic, and Heile-Welt Is Contrary-to-Duty

`DESIGN.md` §3's oblige/forbid/allow are the operators of deontic logic
(obligatory / forbidden / permitted). Three results matter.

**Standard Deontic Logic has paradoxes lips can inherit by accident.** The
best-known is Chisholm's (1963) **contrary-to-duty** puzzle: what ought to happen
*given that* an obligation has been violated. Naively formalized, the set of norms
comes out inconsistent. This is not academic for lips: the Heile-Welt contract (§6)
*is* a contrary-to-duty structure. "Every bank row is recorded exactly once" is the
obligation; "the bank sent it twice" is the world violating the ideal; the coping
strategy (idempotence, reconciliation) is what ought to happen then. The engine is
where contrary-to-duty obligations live, and the literature says this is the corner
where norm formalisms break. Worth reading before the kernel fixes the semantics of
obligation.

**Input/output logic is the right frame, if lips adopts one.** Makinson and van der
Torre, "Input/Output Logics", *Journal of Philosophical Logic* 29:383-408, 2000
(icr.uni.lu/leonvandertorre/papers/jpl00.pdf). Norms are pairs (condition,
obligation) and the logic studies *detachment*: what a normative system produces
given an input, rather than what is true in a modal model. That is precisely lips's
"obligation pattern → mechanism mapping": the engine is an input/output operation,
the program is the input, the realized module is the output. The framework was built
specifically to keep norms out of the paradox-generating modal machinery, so it buys
the vocabulary without the puzzles.

**Prioritized norms have a conflict-resolution vocabulary already.** Defeasible
deontic logic (Governatori and colleagues) handles conflicting norms with the legal
principles: *lex specialis* (the more specific norm wins), *lex posterior* (the later
one wins), *lex superior* (the higher authority wins). lips's strength order is
*lex superior* only. The other two are candidate physics: a more specific subject
beating a general one is *lex specialis*, and it is arguably what an author expects
when a per-instance decision meets a language-wide default. If lips does *not* want
them, that is a decision worth recording, because users will expect specificity to
win.

## Naming Collision

"Decision calculus" is taken: John D. C. Little, "Models and Managers: The Concept
of a Decision Calculus", *Management Science* 16(8), 1970 (JSTOR 2628654) — a
manager-facing marketing/OR modelling method, still cited in that field. Different
domain, no practical clash, but a reader from operations research will arrive with
the wrong prior. One footnote in DESIGN.md disarms it.

## Seams Named but Not Worked Here

1. **Requirements engineering.** Zave and Jackson, "Four Dark Corners of
   Requirements Engineering" (1997), formalizes W, S ⊢ R: the machine specification
   S together with domain assumptions W entails the requirements R. That is the
   Heile-Welt contract stated precisely, decades early, and it gives assumption
   decisions (§3) their formal home: each names a W-clause the world may not honour.
   KAOS (van Lamsweerde) adds goal refinement with obstacle analysis, which is
   §12's "bank sends duplicate rows" walkthrough as a method. Parnas's four-variable
   model and Benveniste et al., "Contracts for System Design" (2018), supply the
   compositional algebra (refinement, composition, quotient) if engines ever compose.
2. **Provenance and incremental recompute.** Green, Karvounarakis and Tannen,
   "Provenance Semirings" (PODS 2007), is the algebra of how-provenance for derived
   facts; W3C PROV is the interchange form. Truth maintenance systems (Doyle's JTMS
   1979, de Kleer's ATMS 1986) maintain justification networks under retraction,
   which is what an editor needs when one line changes and the fixpoint must not be
   recomputed from scratch.
3. **Language crystallization as library learning.** Anti-unification (Plotkin's
   least general generalization, 1970) is the base operation `generate` performs
   across several programs. The modern line: DreamCoder (Ellis et al., 2020) learns
   a DSL from a corpus; babble (POPL 2023, dl.acm.org/doi/10.1145/3571207) does
   library learning with e-graphs and anti-unification modulo an equational theory;
   stitch does it top-down and fast. This is the theory of the **generalization
   radius**, including the ranking problem FlashFill/FlashMeta had to solve: many
   generalizations fit a corpus, and choosing needs an explicit objective. lips
   steers the radius with prose today; these give a computable objective (corpus
   compression, minimum description length) if prose stops being enough.

## Learnings for lips

Landed in DESIGN.md already:

1. **The merge/rewrite separation is now a stated kernel invariant** (§2), citing
   Baeten/Bergstra/Klop 1987: strength is resolved before refinement rewrites, and
   no rule's applicability may depend on a refinement result. One paragraph;
   prevents a class of future feature that would break confluence subtly.
2. **The lattice objection is answered** (§2): NixOS is the existence proof that
   prioritized merge works at scale, and total provenance is what makes the
   override chain a query instead of an investigation.
3. **Four open questions are recorded** (§11): critical-pair orthogonality,
   minimal conflict explanation, obligation survival under override, and lex
   specialis.

Still open, ranked by payoff over cost:

4. **Implement engine orthogonality as critical-pair analysis** at the `generate`
   gate. The refiner today enforces the cruder dynamic property that at most one
   rule fires per decision (`Overlap` in `Kernel/Refine.hs`), which is sound but
   only catches an overlap some concrete decision witnesses. Critical pairs decide
   it statically, before an engine is written to disk.
5. **Report conflicts as minimal conflict sets** (QuickXplain). Deterministic,
   domain-blind, and aimed straight at the comprehension-per-minute metric.
6. **Check merge against the IC postulates** and record which are intended, which
   are violated, and why (arbitration over majority, with `Append` as the stated
   exception).

Deliberately *not* built: **obligation survival under override** (Nickel's
contract-propagation rule). The gap is real in the code (`Base.resolve` groups by
subject and `Kind` never drives merge, so a stronger decision takes any obligation
on that subject with it), but no minted engine emits `Oblige`, `Forbid` or
`Invariant` today; every rule in every committed `.lang` emits `Fact`. Building for
an obligation nobody writes is speculative generality. Recorded in §11 so the first
engine that emits an obligation is recognized as the moment to decide.

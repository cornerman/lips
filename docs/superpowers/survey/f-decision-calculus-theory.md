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

That is a direct challenge to lips. `DESIGN.md` §2.1 promotes NixOS priorities to
kernel physics and calls that Nix's most credible fix; CUE's authors would answer
that priorities are the disease. The honest reconciliation, and it is defensible: in
lips the strength order is not authored, it is *structural* (system default < engine
default < program), and a program is small enough to read whole, so the chain a CUE
user must chase is one hop long and always points the same way. That answer belongs
in DESIGN.md, because the objection will be raised.

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

Ranked by payoff over cost.

1. **Obligations must survive an override** (Nickel's contract-propagation rule).
   Today a stronger decision erases a weaker one wholesale, taking any attached
   obligation with it. Small kernel change, real correctness gain.
2. **Implement engine orthogonality as critical-pair analysis** at the `generate`
   gate. Closes §11's open question with a fifty-year-old algorithm instead of a
   heuristic, and turns a promise into a theorem.
3. **Report conflicts as minimal conflict sets** (QuickXplain). Deterministic,
   domain-blind, and aimed straight at the comprehension-per-minute metric.
4. **State the merge/rewrite separation as a kernel invariant**, citing
   Baeten/Bergstra/Klop 1987: strength is resolved before refinement rewrites, and
   no rule's applicability may depend on refinement results. Costs one paragraph;
   prevents a class of future feature that would break confluence subtly.
5. **Answer CUE in DESIGN.md §2.1.** The lattice camp's objection to priorities is
   published and good; lips's answer (structural strength, one hop, small readable
   program) is also good, but it is currently unwritten.
6. **Check merge against the IC postulates** and record which are intended, which
   are violated, and why (arbitration over majority, with `Append` as the stated
   exception).
7. **Decide on lex specialis.** Either adopt specificity-beats-generality as
   physics, or record the refusal; do not leave it to be discovered.
8. **Footnote Little 1970** so the name collision is visibly known, not missed.

# The MDD Post-Mortem Ledger: Documented Causes Against 2026 AI Capability

Survey B (the graveyard) already told MDD's death story and synthesized eight recurring failure
modes across thirteen systems. This document does not repeat that synthesis. It goes one layer
deeper into the empirical literature that measured model-driven engineering (MDE) in industry
rather than arguing about it from principle, and tests one specific claim against that evidence:
that AI removes the cost that killed MDD (hand-built, hand-maintained code generators) while
keeping the determinism MDD had and the current AI-coding wave lost.

Terminology matches `AGENTS.md`: **kernel** is the domain-blind physics, **engine** is the
per-problem rulebook a model mints once, **program** is the human-written `.lips` file. Method
note: every row carries a source URL fetched and read directly for this document. Two items
(Selic 2003, Whittle et al. 2013) sit behind paywalls with no open preprint found; those rows are
marked unverified beyond bibliographic metadata, and no content is invented for them. My own
synthesis is marked "inference."

Verdict set (closed): ELIMINATED BY AI, MITIGATED BY AI, UNTOUCHED BY AI, WORSENED BY AI.

## The Empirical Base

Hutchinson, Whittle, Rouncefield, and Kristoffersen ran a twelve-month qualitative study
(questionnaires plus interviews), published as two ICSE 2011 papers. "Empirical assessment of MDE
in industry" (ACM, DOI 10.1145/1985793.1985858) states its method plainly: "we investigate and
document a range of technical, organizational and social factors that apparently influence
organizational responses to MDE." Its companion, "Model-driven engineering practices in
industry" (same venue), interviewed three commercial organizations in depth and concludes success
depends on "complex organizational, managerial and social factors, as opposed to simple technical
factors," requiring "a progressive and iterative approach; transparent organizational commitment
and motivation; integration with existing organizational processes and a clear business focus."

The team's 2014 follow-up, "The state of practice in model-driven engineering" (IEEE Software, 21
April 2014), surveyed 450 practitioners and interviewed 22 more. Its central finding cuts against
the folk story: "developers rarely use it to generate whole systems; rather, they apply it to
develop key parts of a system often using domain-specific modeling languages developed
specifically for the purpose," and "adoption largely depends on social and organizational
factors." MDE did not die from failing to generate whole systems; it survived by narrowing to
partial, domain-specific generation, closer to lips's own scope than the "generate everything
from UML" story the graveyard already dismantled.

Petre's "UML in practice" (ICSE 2013, DOI 10.1109/icse.2013.6606618) interviewed 50 engineers
across 50 companies over two years and sorted their UML use into five buckets: no UML (35),
selective notation (11), automated code generation (3), retrofit documentation (1), wholehearted
process use (0). Zero of fifty used UML the way its promoters described.

Mohagheghi and colleagues' companion industrial studies: "An empirical study of the state of the
practice and acceptance of model-driven engineering in four industrial cases" (Empirical Software
Engineering, 2013, DOI 10.1007/s10664-012-9196-x) names "perceived usefulness, ease of use and the
maturity of the tools" as adoption determinants. "Where does model-driven engineering help?"
(Software & Systems Modeling, 2013, DOI 10.1007/s10270-011-0219-7) names the recurring cost
directly: "merging different tools with one another in a seamless development environment
required several transformations, which increased the required implementation effort and
complexity," and reuse "sometimes had a negative impact on the performance of tools."

Whittle, Hutchinson, Rouncefield, Burden, and Heldal's "Industrial Adoption of Model-Driven
Engineering: Are the Tools Really the Problem?" (MODELS 2013, DOI
10.1007/978-3-642-41533-3_1) is cited by title, venue, and authorship only; the publisher elides
its abstract from every metadata source reached and no preprint surfaced. Selic's "The pragmatics
of model-driven development" (IEEE Software, September 2003, DOI 10.1109/ms.2003.1231146) is
confirmed at that DOI via Crossref but its text sits behind IEEE Xplore with no abstract found; it
is cited only as a bibliographic anchor for the era's own advocacy.

Böckeler's "Understanding Spec-Driven-Development" (martinfowler.com, 15 October 2025), fetched
directly: "MDD never took off for business applications, it sits at an awkward abstraction level
and just creates too much overhead and constraints. But LLMs take some of the overhead and
constraints of MDD away... The price for that is LLMs' non-determinism of course. And the
parseable structure also had upsides that we're losing now: We could provide the spec author with
a lot of tool support to write valid, complete and consistent specs. I wonder if spec-as-source...
might end up with the downsides of both MDD and LLMs: Inflexibility and non-determinism."

## The Ledger

**1. Generator build and maintenance cost.** Evidence: transformations "increased the required
implementation effort and complexity" (Mohagheghi 2013); Böckeler's "too much overhead and
constraints." Verdict: MITIGATED BY AI. A model mints the engine in one call instead of a team
maintaining generator code for years, but lips's own ledger concedes the cost reappears at scale:
"minting is whole-engine... invisible at a page; dominant at hundreds of rules" (DESIGN.md, Limits
of Scale). What lips does: `generate` gates on a compiling, passing draft before writing anything;
`--renew` makes regeneration explicit. Falsifier: a `.lang` past roughly a hundred rules where one
new sentence still costs a bounded mint rather than unpredictable full-engine churn.

**2. Round-trip engineering and the hand-edited-output escape hatch.** Evidence: graveyard's CASE
section: round-trip "never worked reliably," "protected regions" never solved the divergence once
code was hand-touched. Verdict: ELIMINATED BY AI. Round-trip existed because rerunning a 1990s
generator was slow or lossy enough that hand-editing was cheaper; cheap, reliable one-shot
regeneration removes that economics. lips hardens it into invariant 4: "Generated output is never
hand-edited." Falsifier: one real user forced to hand-edit compiled output to ship, ever.

**3. Model/code drift.** Evidence: graveyard's MDA section: the hand-tuned PSM "was where all the
messy platform detail lived," and the PIM became decorative. Verdict: MITIGATED BY AI. The classic
mechanism (silent hand-edit divergence) is eliminated with row 2; a narrower axis remains, since
regenerating an engine for an unrelated reason can silently change realized values, caught only by
`.expect`, and lips's own ledger records three of five baked-source examples "stating no
observable at all." An empty contract lets drift pass by construction. Falsifier: a program with a
non-trivial `.expect` where `--renew` changes behavior without the gate catching it.

**4. Expressiveness ceilings and escape hatches.** Evidence: the graveyard's single most lethal
recurring pattern (CASE, MDA, Helm, low-code, Dark); Petre found only 3 of 50 companies used
automated code generation. Verdict: MITIGATED BY AI. A model can mint a new grammar case cheaply
where a human generator author had to anticipate everything in advance, but the boundary does not
vanish: "lips reaches exactly as far as some external, named, typed vocabulary of mechanism
reaches" (survey G). Outside a schema-bearing world the ceiling reasserts itself where MDA's PSM
once sat. Falsifier: a program needing a genuinely free-form escape hatch, currently classified as
deferred glue, made to work without reopening an untyped hole.

**5. Tool lock-in and expensive proprietary toolchains.** Evidence: AD/Cycle tied to mainframe
DB2/OS2, Wolfram's single-implementation ceiling, Dark's founders naming "our-cloud-only runtime"
as fatal to trust. Verdict: ELIMINATED BY AI. A general-purpose model mints a generator for any
open target, so there is no proprietary IDE to buy into; lips's compile target is independently
governed (NixOS/home-manager/kubenix/terranix) and the model gateway is explicitly kept out of
lips's own closure and swappable. Caveat held honestly: contingent on that model-agnosticism
holding; if the mint's instructions ever assumed one provider's quirks, lock-in reappears one
layer up. Falsifier: a `.lang` only one specific model can regenerate correctly.

**6. Poor diff, merge, and version control of graphical models.** Evidence: sibling survey A on
MPS: projectional editing means "plain-git diffing, grepping, and copy-paste from outside sources
interoperate poorly" (Fowler, 2005), the closest parallel to UML/CASE model files that never
diffed cleanly either. Verdict: MITIGATED BY AI. A model can now describe semantically what
changed between two structured exports, something a textual diff cannot do for non-text formats;
it does not fix git's inability to three-way merge binary or XML models. This does not even arise
for lips, which sidesteps the cause by architecture: Solutions and engines are plain text.
Falsifier: none needed today; it would be a future lips feature introducing a binary model file.

**7. Debugging at the wrong level.** Evidence: the brief's own example, live in lips itself:
`hello.http.lips` mints a Go server whose source is "a committed, reviewable file beside the
program," not the `.lips` line. Verdict: UNTOUCHED BY AI. Whoever debugs a runtime failure reads
the artifact that actually ran; no AI capability changes which artifact a debugger stops in.
lips's own ledger names the boundary: the kernel "cannot guarantee the world cooperates," and
mismatches "surface at `nixos-rebuild`/runtime, not as a kernel property" (DESIGN.md). Falsifier: a
user who fixes a runtime failure in a baked artifact by editing only the `.lips` program, ever.

**8. Learning curve of the modeling notation.** Evidence: Petre found "overheads of understanding
the notation" among reasons 35 of 50 companies skipped UML; Mohagheghi found "ease of use... an
important determinant" for MDE adoption. Verdict: MITIGATED BY AI. The model, not the human, now
learns the target world's option vocabulary before minting; the human-facing notation is the
program's own plain lines. lips ships an LSP specifically for the residual cost: completion from
"the language's own patterns as snippets," live diagnostics, no per-language configuration. This
is exactly the "tool support to write valid, complete and consistent specs" Böckeler names as
MDD's lost advantage. Falsifier: an LSP that fails to catch an error a new author would have made.

**9. Who writes the model: the non-programmer promise.** Evidence: 4GLs "promoted English-adjacent
syntax as proof that non-programmers could write real applications," which "fell apart the moment
real business logic needed precise conditionals" (graveyard); Retool's own CEO conceded the
product is drag-and-drop "with code written on top of that, for the last 20% or 30% of the work."
Verdict: UNTOUCHED BY AI. A better model does not change who is capable of stating precise,
testable intent; lips names its audience as software-literate owners working in text and does not
attempt this, which sidesteps rather than answers the promise that broke 4GLs and low-code.
Falsifier: a genuinely non-technical domain expert, unassisted beyond the LSP, writing a working
`.lips` program on the first `generate`.

**10. Organizational and process factors (the Whittle line).** Evidence: the strongest-evidenced
row here: a twelve-month qualitative study, a 450-person survey, and 22 interviews all converge on
"adoption largely depends on social and organizational factors." Verdict: UNTOUCHED BY AI. None of
these factors are technical, so no model capability addresses them. lips's defense (DESIGN.md:
"the System must serve one owner at small scale immediately") is a scope reduction, not a
solution: it assumes away the multi-stakeholder organization the studies actually studied.
Falsifier: any team deployment where ownership of the program or the decision to re-bless a broken
`.expect` becomes a contested organizational question and stalls adoption.

**11. Platform churn and the platform-independent model as a moving target.** Evidence: MDA's
"platform-independence was a moving target (each new PSM technology needed new transformation
rules)" (graveyard). Verdict: MITIGATED BY AI. lips keeps no platform-independent intermediate;
each `--target` mints a fresh engine directly against that world's current schema, so churn is
absorbed by a cheap re-mint, not a patched transformation layer. The untested axis sits one level
down: nixpkgs's own schema evolves and deprecates names across releases, unexercised by any
committed example. Falsifier: an option rename or removal that compiles silently to something the
program no longer means, rather than failing loud.

**12. Performance of generated code and the verification burden on quality.** Evidence: Mohagheghi
found reuse "had a negative impact on the performance of tools"; Sonar's 2026 State of Code
Developer Survey (events.sonarsource.com, 1,100+ developers, fetched directly): "96% of developers
do not fully trust the functional accuracy of AI-generated code," and "the burden of work has
moved from creation to verification and debugging." Verdict: UNTOUCHED BY AI. Faster generation
does not make generated code faster to run, and industry-wide trust in mere functional correctness
sits at single digits before performance even enters. Where lips bakes source, it runs exactly as
fast as the model wrote it once. Falsifier: a baked artifact that regresses in performance across a
re-mint, undetected because no committed claim covers it.

**13. Standardization by committee (OMG) versus real semantics.** Evidence: UML standardized "14
diagram types by committee, optimized for diagram-vendor interoperability over runnable precision"
(graveyard). Verdict: ELIMINATED BY AI. No committee sits in lips's path; a model reads one target
world's own schema and mints against that single ground truth. This relocates rather than answers
the standardization question: the "standard" is nixpkgs's own release-governed schema, a real
engineering artifact with its own churn (row 11), not a notation congress. Falsifier: a second,
incompatible schema for the same world forcing lips to arbitrate between competing standards.

**14. Non-determinism reintroduced at the exact point classic generators were deterministic.** An
AI-era addition; 2011-2014 literature could not observe it, since those tools had no LLM in their
generation step. Evidence: Böckeler's own experiment, fetched directly: generating "multiple times
from the same spec" with Tessl and observing different output each time, hence her fear of "the
downsides of both MDD and LLMs: Inflexibility and non-determinism." Verdict: WORSENED BY AI. A
debugged 1990s generator run twice on the same model produced the same code; that determinism was
the one thing CASE/MDA/4GL tooling actually delivered. Wiring an LLM into generation itself removes
it. What lips does: confines the model to `generate`, producing a committed engine (data, not
code-writing-code), so every later `compile` is offline and bit-identical. Falsifier: survey G's
named, unmeasured mint-decay curve, "the ratio of edits that compile to edits that need a mint,
over time." If it does not trend toward zero as a language matures, the non-determinism is paid on
an ongoing basis, only hidden behind a `generate` command invoked often enough to reintroduce it.

**15. The review burden moves from writing to verifying, and does not vanish.** The general form
of row 12's evidence. Evidence: the same Sonar figures, verified at the primary source: trust in
AI-generated code sits at single digits, and the burden has moved to verification, not away.
Verdict: UNTOUCHED BY AI. Faster artifact production does not reduce the trust-critical material a
human must certify; it changes what that material is. lips narrows the reviewed surface (one
engine review per language, amortized over every later compile) rather than removing review, and
that review still needs a human able to read `.lang` rules and judge intent, a skill with no
evidence here of being cheaper to acquire than reviewing code. Falsifier: an engine review that
took longer, or caught a real defect less reliably, than reviewing the equivalent hand-written code
would have.

## Tally

Of fifteen rows: three ELIMINATED BY AI (round-trip escape hatch, tool lock-in, committee
standardization), six MITIGATED BY AI (generator cost, model/code drift, expressiveness ceilings,
graphical diff/merge, notation learning curve, platform churn), five UNTOUCHED BY AI (debugging at
the wrong level, the non-programmer promise, organizational factors, generated-code performance
and quality trust, the general review-burden shift), and one WORSENED BY AI (non-determinism
reintroduced at the generation step). A ledger with no UNTOUCHED or WORSENED rows would be
marketing, not evidence; this one is not that.

## What MDD Had That lips Must Not Lose

Böckeler names the one thing MDD had that the current wave lost: "the parseable structure also had
upsides... we could provide the spec author with a lot of tool support to write valid, complete
and consistent specs." lips already answers this, not aspirationally: `lips lsp` is a domain-blind,
offline process reading a language's own `.lang`, giving completion (the language's own patterns
as snippets) and live diagnostics, with editor glue for neovim, vim, VS Code, and Helix. It is
generated mechanically from the same grammar the compiler reads, not hand-maintained documentation
the way UML tooling eventually became.

The gap is chronological, not architectural. The LSP exists only after `generate` has minted a
language; an author writing the first program in a not-yet-existing language gets no completion
and no live diagnostics, because nothing yet exists to derive them from. This mirrors Eve's own
diagnosis that a platform "has to allow for the representation" before any interface can sit on top
of it (graveyard): lips's tool support is strong once a vocabulary exists and bare before one does,
exactly the moment a first-time author needs it most and has least of it.

## The Causes lips Has No Answer To

Debugging at the wrong level (row 7) is not a lips defect but a property of realizing anything at
all, demonstrated live in lips's own committed Go source. Organizational and process factors (row
10) carry the strongest empirical weight in this survey, and lips's answer is to scope the problem
away (one owner, one Solution) rather than solve it; a claim that lips "solves" MDE's adoption
problem is unsupported by the literature this ledger draws on, which studied teams. The
non-programmer promise (row 9) is a wall 4GLs and low-code already hit; lips does not attempt it,
correctly, but overselling it to a non-technical audience would walk straight back into that wall.
Generated-code performance and quality trust (row 12) and the general review-burden shift (row 15)
are not lips-specific failures; they are the current state of the whole field, measured across
1,100-plus developers, and no tool surveyed anywhere in these documents has an answer yet.

## The Five Questions To Ask Any lips Believer

1. Show the mint-decay curve on one real, growing program. Does the fraction of edits needing
   `generate`, rather than plain `compile`, trend toward zero as the language matures, or plateau?
   A plateau means row 14's non-determinism recurs every time the language must grow.
2. When the realized system misbehaves in production, which file gets opened first, and how long
   before it is generated code rather than the `.lips` line? If the answer is "quickly, and often,"
   row 7 is the normal debugging path, not an edge case.
3. Has a nixpkgs option an engine depends on ever been renamed or removed, and did `.expect` catch
   it loudly, or did the module silently stop meaning what the program says?
4. Put this to a second person, not the author: who owns re-blessing a broken `.expect`, and has
   that decision ever been contested rather than mechanical? If nobody has had to answer this, row
   10 has been assumed away, not tested.
5. Find one thing a program needs with no existing typed, named vocabulary behind it (application
   logic, not infrastructure). Does lips reach it, or does "lips reaches exactly as far as some
   external vocabulary of mechanism reaches" quietly become the ceiling the graveyard's
   escape-hatch failure mode always reasserted itself through?

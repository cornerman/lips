# The Verification Gap and the Three Schools (August 2026)

This survey updates Survey D with what the intervening year measured, and it
answers a question the earlier surveys did not ask: given that several
well-funded programs now attack the same problem lips attacks, which school
does lips belong to, and what does its choice of school cost and buy.
Terminology follows `AGENTS.md`: **program** is the human-written `.lips`
file, **engine** is the minted per-problem rulebook (`.lang`), **kernel** is
the fixed domain-blind physics.

Method note: claims below carry a source URL. The Böckeler article, the
SiliconANGLE report on Axiom, and the ByteIota summary of Sonar's survey were
fetched and read in full; figures attributed to Faros, ProjectDiscovery, and
Aikido come from secondary reporting only and are marked where they appear.
Anything labelled "inference" is this document's synthesis, not a source's
claim.

## 1. The Gap, Measured

lips opens with an assertion (DESIGN §1): AI produces software faster than
humans can review it. That assertion is no longer a forecast. Sonar's 2026
State of Code Developer Survey, of more than 1,100 developers, reports that 96
percent of developers do not fully trust the functional accuracy of
AI-generated code while only 48 percent always verify it before committing,
and that AI now writes about 42 percent of committed code, projected at 65
percent by 2027 (<https://events.sonarsource.com/2026-state-of-code-developer-survey/>,
summarized with the figures used here at
<https://byteiota.com/ai-code-verification-bottleneck-96-dont-trust-output-2/>).

Three findings from that survey matter more to lips than the headline gap.
Sixty-one percent of developers say AI code "looks correct but isn't
reliable", which is exactly the failure mode a diff review is worst at
catching. Thirty-eight percent say reviewing AI code costs *more* effort than
reviewing human code, against 27 percent who find it easier; AWS CTO Werner
Vogels named the difference "verification debt", the work of rebuilding
comprehension of code you did not write. Developers still spend 23 to 25
percent of their time on toil, unchanged from before the tools arrived, so the
work moved from writing to reviewing rather than disappearing.

Secondary reporting puts numbers on the downstream cost: pull requests 154
percent larger (Faros data, reported at
<https://www.linkedin.com/pulse/verification-bottleneck-why-your-ai-tools-making-team-rob-foster-56o2c>);
commits three to four times faster with roughly ten times the rate of security
findings (ProjectDiscovery's 2026 AI Coding Impact Report) and one in five
enterprise breaches attributed to AI-generated code (Aikido), both reported at
<https://www.anjin.digital/blog-posts/axiom-ai-safety-code-verification>.
Treat these three as directional, since this survey did not reach the primary
reports.

The consequence for lips is a sharpening, not a change: the bottleneck is not
generation and not even correctness in the abstract, but *review capacity per
unit of derived artifact*. Any design that leaves the derived artifact large
and human-reviewed inherits the bottleneck no matter how good the model is.

## 2. Three Schools

The field has sorted itself into three answers to that bottleneck. The
distinction is where each one puts its trust.

**Automate the review.** Keep generating code and let machines carry the
review load: Anthropic's Code Review for Claude Code (March 2026), SonarQube
AI Code Assurance and its Agentic Analysis beta, CodeQL and Semgrep as gates
in CI. The bet is that review is one more task a model can absorb, and the
reported practice is a two-pass workflow (a machine pass in CI, then a human
pass over a cleaner diff). This school accepts a large derived artifact and
tries to raise the throughput of looking at it.

**Prove the output.** Axiom Math raised a 200 million dollar Series A at a 1.6
billion valuation in March 2026, led by Menlo Ventures, to train models that
emit Lean proofs so that generated code is machine-checkably correct rather
than plausible
(<https://siliconangle.com/2026/03/12/verifiable-ai-startup-axiom-raises-200m-prove-ai-generated-code-safe-use/>).
Menlo's own framing of why is worth quoting, because it is also lips's
premise: "LLMs are statistical by nature, they produce plausible outputs, not
provably correct or safe ones ... This isn't a bug that will be fixed with the
next model generation. It's architectural"
(<https://menlovc.com/perspective/ai-will-write-all-the-code-mathematics-will-prove-it-works/>).
The open problem this school owns is the specification gap: a proof binds code
to a formal statement, and someone still has to write, read, and trust that
statement.

**Shrink the reviewed artifact.** Spec-driven development, in Böckeler's three
levels: spec-first (Kiro, GitHub spec-kit), spec-anchored, and spec-as-source
(Tessl)
(<https://martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html>).
The bet is that intent is small enough to review even when the mechanism is
not. Survey D established the flaw in every shipped instance: the spec is
executed by a model, so the artifact under the spec is not derived but
re-guessed, and Böckeler observed exactly that non-determinism when generating
twice from one Tessl spec.

A fourth group exists and is best understood as the mirror image of lips:
languages that make an inference call a first-class construct, such as Agentis
("the LLM as standard library") and mohiolang ("AI reasoning as a
compiler-enforced primitive"). They place the model inside the running
program, where lips forbids it even at build time. Nothing in that group
competes with lips; it inhabits the position lips defines itself against.

lips belongs to the third school and is, as far as these surveys have found,
its only deterministic member (Survey E reached the same conclusion from the
tool side). The distinguishing move is not that lips writes specs. It is that
the model's output is a *compiler*, not code: a minted engine, reviewed once,
amortized over every later compile of every program in that language.

## 3. Böckeler's Trap, and the Escape

The sharpest objection to lips's whole category was published before lips
existed, in the closing section of the same Böckeler article. She observes
that spec-as-source is model-driven development returning. MDD died in
business software because the custom code generators cost more to build and
maintain than the abstraction returned, and because the model languages were
rigid. LLMs remove the generator cost, but pay in non-determinism. Her fear,
in her words: spec-as-source "might end up with the downsides of both MDD and
LLMs: inflexibility *and* non-determinism", a Verschlimmbesserung.

She also names what MDD had and the current wave lost: "the parseable
structure also had upsides that we're losing now: we could provide the spec
author with a lot of tool support to write valid, complete and consistent
specs."

lips is a direct answer to that paragraph, and it is the clearest available
statement of what lips is (inference, though it follows closely from her own
two horns):

- Against non-determinism, lips keeps the parseable DSL and a real compiler.
  A program is read by a grammar, an unreadable line fails loud, `compile` is
  offline and bit-identical, and the author gets the tool support she names
  (an LSP with the language's own patterns as completions and live
  diagnostics, generated with no per-language configuration).
- Against inflexibility, lips makes the generator disposable. The engine is
  minted per problem, is pure data, and is a page long, so the cost that
  killed MDD (a hand-built, hand-maintained generator per domain) is paid by a
  model in one call and re-paid whenever the domain moves.

The escape works only if a mint stays cheap and a language converges, so the
economics of that loop, not the physics, are what the project must still
demonstrate; §5 states the measurement.

A corollary worth holding onto: lips's value does not decay as models improve.
The claim is about reproducibility, not accuracy. A perfect model that emits a
different valid implementation on each run still destroys diffs, bisection,
review, and audit. Determinism is a property no model quality supplies, which
is why the "just wait for a better model" objection does not reach lips.

## 4. What Actually Grounds an Engine: The Vocabulary Scaling Law

The surveys have credited lips's results to the kernel. The corpus suggests a
different and more useful explanation (inference, argued from the committed
examples and from lips's own doctrine).

lips works today because NixOS options are a large, typed, externally
maintained vocabulary of mechanism. When an engine emits
`services.restic.backups.<name>.paths`, the meaning of that name, its type,
and its behavior are defined and tested by nixpkgs, not by lips and not by the
mint. The mint confirms a name through the schema tool rather than inventing
one. lips's own doctrine already says this in the small (DESIGN §13, "A hole
is grounded from outside or by plurality"): a hole reaching a target option is
grounded externally, so one occurrence suffices.

State it in the large and it becomes a scaling law:

> **lips reaches exactly as far as some external, named, typed vocabulary of
> mechanism reaches.**

Everything the corpus does well sits inside such a vocabulary, and everything
it does poorly sits outside one. Fourteen-line engines produce working systems
because the engine only has to *select and fill* names that already exist.
Baked source has no vocabulary behind it, which is precisely where the corpus
is thin: single-file programs, three of five with no witness at all
(`TODO.md`, item 1).

Two consequences follow, and both are strategic rather than technical:

1. Breadth comes from new worlds, not new physics. home-manager, kubenix, and
   terranix landed with no kernel change, because each is another vocabulary
   the same grammar can name. Every schema-bearing world is a candidate on the
   same terms, and the kernel must not learn any of them (AGENTS.md, "The
   Kernel Knows Nothing").
2. Application code is reachable only where a framework has already turned
   itself into configuration. Where it has not, the correctness burden falls
   entirely on claims, which is a research bet and should be labelled one.

The law also supplies a cheap falsification test: take a schema-bearing world
that is not infrastructure and mint into it. If the axis is truly open, the
cost is zero kernel changes. Any kernel change the attempt demands is a
valuable negative result about how much of nixpkgs's shape the kernel silently
assumes.

## 5. What This Implies for lips (No Code)

- **Measure the mint-decay curve.** The economics of §3 rest on one unmeasured
  quantity: the ratio of edits that compile to edits that need a mint, over
  time, on one real growing program. If it decays toward zero, the thesis
  scales and the rest is engineering. If it plateaus, the language is not
  converging, and no kernel work fixes that. Nothing in the repo measures it,
  and it is cheap to collect.
- **Claim density before artifact size.** Growing baked source while nothing
  binds it to the program reproduces the untrusted-artifact problem lips
  exists to abolish, with extra steps (inversion: this is the fastest way to
  falsify the project's own premise).
- **Incremental minting.** Whole-engine minting makes engine size a multiplier
  on the cost and blast radius of every new sentence. At a page it is
  invisible; at hundreds of rules it is the dominant failure mode.
- **Brownfield is unaddressed.** Every tool in the graveyard (Survey B) died
  on adoption into existing systems, and lips currently has no story beyond
  coexistence (a hand-written module beside a lips one). The coexistence
  defense is real and may be enough, but it has never been exercised on a
  system of any size.
- **The audit trail is a market wedge, not only a discipline.** `.generation`
  records every byte the model saw and re-derives the id, which is the
  artifact a regulated buyer needs and which no tool in the other two schools
  produces.

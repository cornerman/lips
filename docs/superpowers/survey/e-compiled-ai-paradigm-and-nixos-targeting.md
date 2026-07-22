# The Compiled-AI Paradigm and How to Target NixOS

Prior-art scan (July 2026) answering one question and mining two seams of learning for lips:
does a tool like lips already exist; what can lips take from the wider "AI once, then
deterministic" paradigm; and what can lips take from the tools that already turn language into
NixOS. Terminology follows current project vocabulary (`AGENTS.md`): **program** is the
human-written `.loose` file, **engine** is the per-problem minted rulebook (`.lang`), **kernel**
is the fixed domain-blind physics. Where older surveys (`d-aiwave-and-nix.md`) say
"vocabulary", read "engine".

## The Finding: Does a Tool Like lips Already Exist?

No tool matches lips, but its paradigm is real and being staked out concurrently. Four
independent 2026 sources describe lips' compile-once/run-forever loop, and two of them share
its deepest framing ("the plan is data, not code"). The shipping tools that turn language into
NixOS all keep the model in the runtime loop and review generated Nix rather than prose, which
is architecturally the opposite of lips.

Two axes separate the whole field. First, **where the model sits**: one-time compile (Compiled
AI, lips) versus in the runtime loop (NixGen, nix-agent, Luminous Nix, AIKernel). Second, **what
the AI produces**: the output directly (NixGen, nix-agent, Luminous), a plan or instance in a
*fixed* DSL (AIKernel, the Endo essay, Compiled AI's function-in-template), or **the language
plus rules themselves** (lips alone). lips is the only point at both "one-time compile" and
"generate the language." The closest theoretical name for that move is a Futamura-projection
flavor: specialize a fixed interpreter (the kernel) with a program-specific engine (data) to
obtain a compiler. The cleanest antecedents are text-to-SQL (the model writes the query once,
the database runs it forever) and LLM+P (the model does intent understanding, a deterministic
solver does execution).

lips' five invariants map onto the field as follows; no source hits all five.

| | Model out of run loop | Generates the *language* | Input = plain prose | Domain-blind kernel | Test-gated regen |
|---|---|---|---|---|---|
| **lips** | yes | yes | yes | yes | yes |
| Compiled AI | yes | no (code in fixed template) | no (YAML) | no | yes |
| AIKernel | no (per task) | no (fixed IR schema) | partial | yes | partial (replay) |
| nix-agent | no | no | yes | no | no (human review) |
| NixGen | no | no | yes | no | no |
| Luminous Nix | no | no | yes | no | no |

Caveat (the map is not the territory): this covers indexed 2026 arXiv/journal/Zenodo work and
public GitHub tools. A stealth or unindexed project with lips' exact shape could exist; nothing
retrieved matches "mint the language, keep the kernel blind, gate on tests."

## The Papers

### Compiled AI (the paradigm, stated formally)

Trooskens et al., "Compiled AI: Deterministic Code Generation for LLM-Based Workflow
Automation," arXiv:2604.05150, April 2026 (XY.AI Labs / Stanford School of Medicine / Cornell /
Harvard). <https://arxiv.org/abs/2604.05150>

The closest formal statement of lips' loop. Its definition names three properties: one-time LLM
invocation (the model runs at generation, not per transaction), zero-token deterministic
execution (the deployed artifact is static code with no further model calls), and mandatory
multi-stage validation before deployment. These map almost verbatim onto lips invariants #1
("run never calls a model") and #5 (gated regeneration). Motivating asymmetry, quoted: "many
enterprise workflows require intelligence to *design* but not to *execute* repeatedly."

Architecture: a YAML workflow spec enters; an orchestrator selects pre-validated templates and
modules; the LLM generates a narrow business-logic function (20 to 50 lines) inside a fixed
template; a four-stage pipeline (security, syntax, execution, accuracy) validates it, with a
bounded regenerate-on-failure loop that feeds the specific error back; the result deploys as a
static Temporal activity. Reported results: a one-time 9,600-token generation cost then zero per
transaction, break-even against per-request inference at about 17 transactions, 57x fewer tokens
at 1,000 transactions, 450x lower latency on function-calling, 100% reproducibility versus 95%
for runtime inference at temperature 0.

Differences from lips. It generates *code* inside fixed human-written templates; the input
language is a fixed YAML schema the human authors. lips generates the grammar that reads the
prose plus the rules, and the human writes plain prose. It permits **bounded agentic
invocation** (the "Code Factory" variant): generated code may still call the LLM at runtime for
noisy subtasks such as invoice OCR. lips forbids this (invariant #1). Its stated Future Work
lists "natural language specification (moving beyond YAML)" and "automatic workflow
decomposition from high-level intent", which is lips' *starting point*; lips is ahead on the
input side and behind on production-scale evaluation.

### AIKernel Semantic DSL Compiler (the deepest philosophical match)

Sogawa, "AIKernel Semantic DSL Compiler and Deterministic Agent Execution Architecture,"
Zenodo, v0.1.0-rev1, June 2026. <https://doi.org/10.5281/zenodo.20534341>

Its central sentence is lips' core: "an AI-generated plan should be treated as **data, not
code**." Parallels: fail-closed governance where "undefined, ambiguous, malformed, unauthorized,
or indeterminate states do not proceed" and `Indeterminate` counts as deny (lips deduce-or-fail,
invariant #2); a non-Turing-complete IR "does not expose loops, eval, reflection" (lips invariant
#3); a capability table where "unknown providers produce compilation failure" (lips' kernel
reaching concrete things only by Nix name); a hash-linked ReplayLog where "any later modification
changes the replay hash" (lips' `@gen:<id>` provenance, invariant #6); and the boundary rule "the
compiler may interpret a node type, but it must not evaluate generated code."

Two concrete techniques worth lifting. Its acceptance is one explicit admissibility predicate,
`A(x) = schema_ok AND capability_ok AND policy_ok AND dataflow_ok AND loop_bounded AND
canonicalizable AND NOT indeterminate`, with a five-outcome taxonomy (Admit, Deny,
SuspendForApproval, Clarify, Indeterminate). Its reproducible hashing depends on canonicalization
("two equivalent plans produce the same normalized IR"), and it lists the byte-stability hazards
(field order, serialization, timestamps).

Difference from lips: the LLM stays in the runtime loop. It generates a fresh plan per task and
the kernel governs that plan's execution; its determinism is *replay* determinism (record provider
outputs, replay to the same hash), not lips' regeneration-free offline determinism. The IR is a
fixed pipeline JSON schema the kernel knows, not a per-problem minted grammar.

### The DSL-and-Compiler Manifesto

Takafumi Endo, "Domain-Specific Languages: The Deterministic Backbone of AI Agents," Medium,
March 2026.
<https://medium.com/@takafumi.endo/domain-specific-languages-the-deterministic-backbone-of-ai-agents-805da0ef2143>

The essay version of the thesis: "Human describes intent, AI authors the DSL, compiler validates
and generates outputs deterministically, humans review, approved patches return to the DSL." It
names lips' four selling properties (reproducibility, diffability, verifiability, composability)
and the "trace a single change" test. Difference: in its examples (`defineBehavior`,
`defineMolecule`) the AI writes *instances* in a pre-existing human-written DSL with a fixed
compiler; lips generates the grammar and rules.

### Lineage Cited Across the Above

DSPy (Khattab et al., arXiv:2310.03714) compiles declarative LLM calls into optimized pipelines.
LLM+P (Liu et al., arXiv:2304.11477) translates natural language to PDDL and hands execution to a
classical planner. Text-to-SQL is the recurring one-line analogy: generate the query once, execute
deterministically at scale. lips is best introduced as "text-to-NixOS-module" with the query (the
engine) committed and reviewed.

## The Tools That Target NixOS

### NixGen (defines the target; opposite architecture)

Ghogre, Hingawe, Thapa, "NixGen: A Framework for Natural Language-Driven NixOS Configuration,"
Advanced International Journal for Research, vol. 7 no. 2, April 2026.
<https://www.aijfr.com/papers/2026/2/4636.pdf> (student paper; no shipped code found.)

Target definition: NixOS configuration snippets (Nix expression fragments) at the
option-assignment level (`environment.systemPackages`, `networking.*`, `fonts.*`), merged into an
existing `configuration.nix` through a lossless rnix CST so comments and formatting survive.
Method: a fine-tuned Llama 3.2 3B (QLoRA), grounded on a curated corpus of real configs. Reported:
92.3% syntax validity, 88.1% semantic accuracy, 76.5% exact match.

Most transferable empirical finding: NixGen scored higher on Networking (CodeBLEU 0.72) than Fonts
(0.68) and diagnosed why. Networking is "nested attribute sets with clearly defined options"; fonts
are "flat, arbitrary lists of package names." **Structural regularity of the target sub-tree
predicts mint reliability.** Lesson for lips: targets shaped like typed option schemas mint
reliably; free-form package lists are the hard case and belong on the marked-glue path.

Architecturally it is the inverse of lips: the model runs on every request, generates the config
directly, guesses (accuracy below 100% by design, framed as a feature), and offers no
determinism or gating. It is exactly what invariant #1 forbids. Its one aligned posture is
local-first and offline (a small model on a laptop).

### nix-agent (the closest practical cousin)

ph0xphene, "nix-agent," GitHub (Rust, experimental alpha).
<https://github.com/ph0xphene/nix-agent>

Pipeline: `prompt -> isolated Nix module -> rnix AST gate (bounded repair, max 3 attempts) ->
nixos-rebuild -> human review -> explicit apply`. It retrieves from a **local NixOS options index**
built by `nix-build ... optionsJSON` so the model must use real options; it never emits shell
commands, only one small module; it stages a module, runs `nixos-rebuild test`, and removes it on
failure; risk tiers R0 to R4 (R0 read-only, R4 users/secrets/bootloader = refused). It shares lips'
ethos of least authority, untrusted model output, Nix as validator, isolated reviewable artifacts,
and VM-first testing. It keeps the model in the loop (each prompt regenerates, non-reproducible)
and reviews the generated Nix module rather than prose; its safety is human review plus Nix build,
not test-gated regeneration.

### Luminous Nix (least related)

Luminous-Dynamics, "luminous-nix," GitHub (Python).
<https://github.com/Luminous-Dynamics/luminous-nix>

A regex/heuristic intent mapper: "install firefox" becomes `nix-env -iA nixpkgs.firefox`, roughly
53 to 70% intent accuracy, LLM off by default. A convenience CLI over nix commands, not a config
compiler.

## Learnings for lips

### From the Paradigm

**Adopt: a bounded repair loop that feeds the exact failure back (Compiled AI; nix-agent).** On a
failed mint, regenerate with the precise compiler or `.expect` diagnostic as context, up to a
bound. This must slot in alongside the existing `Lips.Generate.Harness` resampling-unanimity
mechanism, not replace it: unanimity guards against a lucky single sample; the repair loop guards
against a fixable, diagnosable miss. A deterministic control loop around the one stochastic step is
the paradigm itself.

**Adopt: an explicit admissibility predicate (AIKernel).** State lips' mint acceptance as one named
boolean whose conjuncts are structural checks (engine compiles the program, every rule maps, every
demand met, module parses, `.expect` holds, and the options-schema checks below). This matches the
project doctrine "structural guards beat prompt pleas" and makes the gate auditable. The
five-outcome taxonomy (Admit, Deny, SuspendForApproval, Clarify, Indeterminate) is a checklist; lips
already has Admit (print), Deny (fail-loud to generate), and Clarify (unmet demand).

**Adopt: canonicalization before hashing (AIKernel).** Normalize the decision base to a canonical
form before computing the `@gen` fingerprint so a trivial reorder does not churn ids; this is the
Section 11 open question ("text diff approximates set diff"). Consider chaining per-line hashes into
one root (a Merkle over decisions), turning "was this engine hand-edited?" into a single-hash check.

**Adopt (positioning, not code): the break-even framing.** State lips as generate once, then every
print is free; break-even against asking the AI each time is one or two edits. Compiled AI's ~17
transactions is the same curve on a different axis.

**Validated (already correct, do not re-import):** engine-is-data, non-Turing-complete value
grammar, fail-closed deduce-or-fail, reach-by-name for concrete things, per-line provenance. The
convergence of four independent groups on these is evidence the core bet holds.

**Reject (learning by inversion): bounded agentic invocation.** When pure determinism failed on
noisy inputs, Compiled AI let generated code call the LLM at runtime. Treat this as the boundary
marker: the moment a mint "needs" a runtime model call, lips fixes the kernel or grammar, or fails
loud, and never smuggles the model back in. NixGen's "88% is fine, rerun each time" stance is the
same failure at the tool level.

### From Targeting NixOS

lips already targets NixOS at the option-assignment level: rules map decisions to option-path =
value pairs, and (verified in `Kernel/Engine/Value.hs`) the rule right-hand side is a **typed value
AST**, not string-templated Nix. `VStr/VList/VBool/VInt/VFloat/VPath/VNull/VHole`, no function
constructor (no computation), and `fillValue` escapes injection. So the quoting-and-injection safety
that nix-agent earns at runtime via rnix, lips already has by construction; the escaped strings in
`backup.loose.lang` are only the serialization of that AST. Do not adopt "parse the generated Nix to
check it is safe"; that unsafe form is already unrepresentable. This is a genuine lips advantage over
every shipping tool.

**Prioritized steal #1: ground in the NixOS options JSON and check against it offline (all three
tools; Survey D's search.nixos.org).** This is the single highest-leverage change. The options JSON
is a complete, machine-readable, typed schema of the target: for every option, its type,
description, default, and declaration site. Verified gap: `generate` today validates a mint by a full
run plus `nix-instantiate --parse` only, so it confirms the module *parses* but never that an option
path exists or that its value type matches. At generate time, fully offline, lips can reject any rule
whose left-hand side names a non-existent option (hallucinated option becomes a deterministic
mint-rejection, realizing invariant #2 at the NixOS layer) and, better, **derive the required
`HoleType` from the option's declared type** rather than letting the model guess it: the schema says
a port is an int and `enable` is a bool, and `Value.hs` already distinguishes `HInt/HBool/HFloat/HPath`.
This closes the loop between lips' existing typed holes and the target's own types, and keeps the
kernel domain-blind: it consumes *a typed option schema*, not knowledge of restic or nginx. terranix
proves the same schema-grounding retargets to Terraform providers, so this is the general mechanism,
not a NixOS special case.

**Prioritized steal #2: free tooling from the same schema (Section 8, confirmed by the tools).** The
options JSON that grounds generation is also the completion, hover, and search source;
search.nixos.org is literally built on it. Once lips ingests it for validation (steal #1), the
"perfect autocompletion, hover docs, option search" claim in Section 8 becomes a near-free export of
the same artifact: type plus description plus default plus declaration per option.

**Other useful ideas.** Validate by building or booting as part of the acceptance gate (nix-agent's
`nixos-rebuild test`, Compiled AI's execution stage): promote "the realized module evaluates against
real nixpkgs" into the generate predicate rather than leaving it to an optional `run`. Least
authority, one concern per module, isolated beside hand-written modules: lips' design already states
this (Section 9); nix-agent's R0 to R4 risk tiers are a good idea *if* a need appears, and would live
in engine or `.direction` data, never in the kernel (apply YAGNI). Retrieval-grounding (feed the
relevant slice of the options JSON into the generate prompt) is the AI-assist that pairs with the
deterministic post-check of steal #1; the check is the guard, retrieval is the help.

**Reject NixGen's core stance** (model every request, guessing accepted) while keeping its
offline/local-first privacy posture, which aligns with running `pi` locally.

### Open Design Questions (for a follow-up plan)

How is the options JSON obtained deterministically and offline given lips' reproducibility
constraints (it is large and nixpkgs-version-dependent; pin it via the flake's nixpkgs and cache the
evaluated `optionsJSON`). How does the derived `HoleType` interact with options whose type is a
submodule or a free-form attrset (the "flat package list" hard case NixGen flagged). Where does the
repair loop's diagnostic come from and what is the bound, alongside resampling unanimity in
`Harness`.

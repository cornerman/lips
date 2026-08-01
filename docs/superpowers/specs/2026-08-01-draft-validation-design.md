# Draft Validation: A Mint That Can Check Itself Before Answering

Status: approved design, 2026-08-01. Base: `main` at `598589c` (the
meaning-dimension work landed). Motivation: complex languages currently need
an expensive model (opus) to mint reliably; this shrinks how much a mint has
to get right blind.

## Diagnosis

`generate` calls the model exactly once. `callPi` (`Main.hs`) runs `pi -p`
with no session, and its single call site in `generate` never retries. The
model's one tool, `query_options`, grounds option NAMES only. Everything
else the mint must get right blind, in one forward pass, while holding the
whole grammar in context: pattern coverage and orthogonality, subject-to-rule
mapping, the closed value grammar, typed and package holes, artifact wiring,
fills, expects, and the self-review checklist at the end of `assets/mint/body.md`.
That prompt is now 854 lines, having grown 61 with the claim grammar.

Feedback arrives only after the model is finished, when the kernel runs
crystallize, realize, `nix-instantiate --parse`, the expect gate and the
artifact build. A failure refuses the mint and sends the HUMAN back to run
`generate` again. Nothing corrects the model inside its own turn.

A stronger model wins here for one reason: better one-shot adherence to a
large, precise, constrained-output grammar. That is the burden this design
removes, so capability matters less.

### What the evidence does and does not support

Two weak-model regressions are on record, and honesty requires saying that
NEITHER is fixed by this design:

- `examples/function` (DESIGN §13): a sonnet-5 mint emitted echo lines
  instead of a built binary and demoted a declaration to a `concept`. That
  passes every gate, since a `concept` needs no rule. It is a silent quality
  regression; no validation loop fires, because nothing failed.
- `examples/board` (DESIGN §13): a sonnet-5 mint hit a hard refusal on
  `${artifact.<self>-core}`, which was a KERNEL bug, fixed by kernel physics.
  Helping a model route around such a refusal would violate invariant 4.

So this design targets the third class, unrecorded but structurally certain:
a mint that fails a gate it could have discovered itself. Making silent
demotion loud is a separate, still-open lever (TODO 2a(ii), the per-hole
inert report), and it is complementary: once the cheap path is a refusal,
draft validation is what lets a weak model recover from that refusal in-turn.

## Design

Give the mint a second tool. It takes the draft engine, runs the deterministic
gates over it, and reports the first gate that rejects it. The model corrects
and re-validates within its single turn, then answers. The authoritative gate
still runs afterwards in Haskell, exactly as today.

### Rejected alternative: automatic retry of `generate`

Considered and rejected: on a failed mint, re-run the model automatically with
the failed draft plus the kernel's refusal appended, up to `--max-attempts`.

Rejected because it costs more and buys less:

- It is the MORE invasive change. The `generate` path is straight-line `die`
  calls from the model call through the artifact gate; retry requires
  refactoring every gate to return a failure and threading it to a loop.
- It needs a new multi-attempt `.generation` format, changing `record` and
  what `genId` hashes. The tool needs no record change at all: `prTranscript`
  is already recorded and hashed, so every validation lands in the audit
  trail for free and invariant 6 is untouched.
- Cost per round is far worse: a fresh process re-sending the 854-line prompt,
  the corpus and the prior draft, versus one tool call inside a live context.
- A model re-deriving a whole engine per attempt can fix one error and
  introduce another. Incremental correction against a draft already in
  context does not have that failure shape.

### Interface: a flag on `check`, not a new verb

The backing command is `lips check --draft -`. It reads a draft engine from
stdin in the model's REPLY format (`<confidence> <id> <keyword> ...` lines
plus `<<<lips` heredocs), materializes a throwaway language folder from it,
and checks the programs against that folder.

No new verb: `validate` would be a synonym of `check`, which the repository's
terminology rule forbids (one word per act). `check` already means "verify an
engine against a contract, offline, no AI"; a draft engine is the same act on
a different input, and a difference of INPUT belongs in a flag.

`--draft` and `--lang` are mutually exclusive and passing both fails loud:
`--lang` points at an engine that exists, `--draft` builds a temporary one.
(The existing flag is spelled `--lang DIR`, field `ceLangDir`.)

The throwaway folder must be NAMED after the language, because
`Identity.resolveLangDir` refuses a folder whose basename is not the
program's language. So the draft materializes to `<tmp>/<language>/`.

`check` takes exactly one program (`programArg`), and that arity stays. The
mint tool loops over the language's programs, feeding the same draft on stdin
each time, and stops at the first failure. The engine-level gates are
program-independent, so repeating them per program is redundant but harmless,
and a language has few programs.

The draft is supplied in reply format, not `.lang` format, deliberately.
Asking the model to write `.lang` for validation while answering in reply
format would be a divergence between what it checks and what it ships.
Materialization reuses `parseEngineCandidates`, `assemble`, `renderLang`,
`expectsOf` and `sourcesOf` from `Generate/Minting.hs`.

### What the tool receives, and what it must not receive

The tool parameter is the draft text ONLY. Everything else comes from the
environment `generate` already controls, following the `LIPS_MINT_TARGET`
precedent in `assets/mint-tools.ts`:

- the program file paths, so the model cannot validate against a doctored
  corpus;
- the GOVERNING contract (below);
- the schema path `generate` resolved before the model ran.

### The governing contract (a false-green hazard)

`generate` selects the contract that gates a mint:

```haskell
committed <- if renew then pure Nothing else tryRead (expectPath rep)
```

The committed `.expect` governs on a regeneration; the draft's own minted
expects govern only on a first generation or under `--renew` (invariant 5).

`checkLoose` reads `.expect` from the folder it is pointed at, so the
throwaway folder must carry the GOVERNING contract. Materializing the draft's
own expects on a regeneration would grade the model against promises it just
wrote itself: it always passes, then the real gate refuses. That is worse than
no tool, because a weak model trusts the green and answers.

`generate` therefore resolves the contract once, as it already does for
itself, and passes the chosen file to the tool; an empty value means "use the
draft's own minted expects". The rule stays in one place and cannot drift.

### Gates

`check` gains the five PURE engine gates, which today run only in `generate`
(`Main.hs:528-532`): `assertPatternsOrthogonal`, `assertRulesOrthogonal`,
`assertValuesReach`, `assertNoPathHoles`, `assertDemandsAnswerable`. They need
no nixpkgs, so TODO 5a's constraint holds.

This also closes a real hole: a committed `.lang` is never re-verified for
orthogonality today, so drift from a bad merge or a change in matching
semantics goes unnoticed. It is the same direction as TODO 4, which wants
`check` to verify `@gen` stamps: one authoritative verifier, three callers
(`generate` before accepting, the mint tool on a draft, CI on committed
engines).

`assertOptionsAdmissible` (`Main.hs:533`) stays OUT of `check`, because it
needs the option schema and only `generate` and `options` ever build one
(`Main.hs:478`, `Main.hs:695`); that absence is the nixpkgs-free boundary.
The draft path runs it itself, since it sits on the mint side where the
schema already exists. One extra call, not a duplicated sequence, and
`check`'s public interface stays as it is. Without it the tool would be blind
to a hallucinated option path or a wrong type, which is the error class most
likely to sink a small model, and blind in the false-green direction.

The two cheap claim gates run too: `claimlessBakedSource` and
`unplaceableClaims` (`Main.hs:578`, `Main.hs:584`).

### The claim gate is skipped, and says so

`checkLoose` now ends with `when contract (claimGate dir file rl)`
(`Main.hs:288`). That gate builds the `#claims` rung: a sandbox claim compiles
the artifact, and a machine claim boots a VM needing KVM, failing loud without
it. Running it per validation would cost minutes and, on a KVM-less machine,
hard-fail every call: a false RED that blocks the model from validating at
all.

So `--draft` skips the claim gate and the artifact build, and REPORTS which
gates it did not run. Observational verification stays at the final gate. The
doctrine that "not verified must never render as verified" is honored by
stating the omission, not by pretending coverage.

`--no-contract` cannot express this, since it also disables the expect gate.

### Reporting

One call reports the FIRST failing gate with all of its violations, in the
exact text the human refusal shows. `assets/mint-tools.ts` states the reason:
what the model is told is what lips itself would say, with no second
model-facing renderer that could drift. Collecting every gate at once would
require refactoring the gates away from die-on-first, and later gates are
often meaningless when an earlier one failed.

### No enforcement

`generate` does NOT refuse a mint whose transcript shows no validation call.
The final gate already runs every one of these checks and already refuses, so
a guard buys no correctness while risking the destruction of a valid engine
for a process reason. The feature is therefore strictly non-worse than today:
unused, it costs nothing and adds no failure path.

## Consequences

- A draft can pass the tool and still fail the final gate, via the claim
  gate or the artifact build. Intended, and reported.
- `.generation` grows, since drafts and diagnostics enter the transcript.
  That is the audit trail doing its job.
- Documentation must stop saying the mint has ONE tool: `assets/mint/body.md`
  ("YOUR ONE TOOL", "There is no tool that judges your engine"), `README.md`
  ("The mint has a single tool"), the `callPi` comment, and the header of
  `assets/mint-tools.ts`.
- `assets/mint-tools.ts` records a deliberate decision: "There is deliberately
  no tool that JUDGES an engine. Informing is safe to expose; deciding is not."
  The boundary moves, and the comment must be rewritten to state the new one:
  the tool REPORTS which gate rejects a draft; the Haskell gate still DECIDES.
  The model does not become the judge, exactly as `query_options` informs
  about names while `assertOptionsAdmissible` still decides.

## Risks

- Moving five gates into `check` must not break the committed engines. TODO 6
  documents `assertDemandsAnswerable` refusing engines that are CORRECT (the
  `<k:key>` subject bug), so it is the likely offender. Verify all committed
  engines pass before landing; if one trips, fix the gate or hold that single
  gate back, never weaken it.
- A small model may not call the tool. Mitigated by prompt instruction only,
  by choice (see "No enforcement"); worst case is today's behavior.
- The tool must not become a channel for guessing. It reports structural
  failures and never supplies a domain value, so deduce-or-fail is untouched.

## Verification

- Conformance cases for: reply-format materialization; `--draft` with
  `--lang` failing loud; governing-contract selection across first
  generation, regeneration, and `--renew`; the skipped-gate report.
- The five moved gates run under `check` for every committed engine.
- One live mint of a claim-bearing language with a small model, comparing
  outcome against the same mint without the tool. This is the only test of
  the actual goal; everything else tests the mechanism.

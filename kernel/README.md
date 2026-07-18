# lips kernel (reference implementation)

The decision calculus of lips, as pure Haskell. This is the deterministic
core the design doc names the source of truth (spec v2, section 12.4); it
contains no LLM and no I/O. Only `generate` (not built here) needs a model.

## What Is Here

| Module | Spec | Role |
|---|---|---|
| `Lips.Kernel.Decision` | section 2 | the atom: `Decision`, `Subject`, `Strength`, `Provenance`, `Kind` |
| `Lips.Kernel.Base` | section 2.1-2.2 | decision base, merge by strength, conflict with both provenances |
| `Lips.Kernel.Refine` | section 2.4, 4 | refinement to fixpoint, orthogonality (`Overlap`), stamped provenance |
| `Lips.Kernel.Demand` | section 2.5 | demands and open questions, completeness |
| `Lips.Kernel.Reader` | section 2 | canonical stored form: `readBase`/`renderBase`, round-tripping diffable text |
| `Lips.Kernel.Realize` | section 10 | projects a ground base to a NixOS module (`realize`), refusing conflicts |
| `Lips.Kernel.Run` | section 5 | the deterministic pipeline; `RunError` is the spec's four run outcomes |
| `Lips.Generate.Harness` | section 5 | the deterministic core of `generate`: deduce-or-fail admission and resampling unanimity |
| `Lips.Generate.Reading` | section 5 | the reading half of `generate`: system prompt + candidate parser (pure) |

## The Loop

    lips generate [model] examples/feed.loose   # AI step: loose text -> feed.loose.decisions (+ open questions)
    lips run examples/feed.loose.decisions       # deterministic: decisions -> NixOS module

`generate` is the one step where a model runs (spec section 5). It routes the
model call through `pi` in print mode (`pi -p -nt --no-session --model ...`),
so pi is the model gateway and handles provider auth; the default model is
`anthropic/claude-opus-4-8`, overridable as the first argument. Each run writes
a `<file>.generation` audit record (model, prompt, input, raw reply).

## The AI Boundary

Only the model call inside `generate` is non-deterministic; everything else is
pure. The boundary is kept explicit in the code:

- `Lips.Generate.Reading` holds the *pure* reading logic: the system prompt (a
  versioned artifact, spec section 5 layer 3) and the parser that turns the
  model's confidence-prefixed lines into candidates.
- `Lips.Generate.Harness` disposes of candidates deterministically: `admit`
  accepts only those at or above the confidence threshold (0.7) and demotes the
  rest to open questions carrying their candidate answer; `unanimous` forces
  only deductions that recur identically across resamples.
- The model call itself lives in the CLI shell (`app/Main.hs`, `callPi`).

This milestone implements the *reading* half of `generate` (loose text ->
decision base). Engine synthesis (proposing new obligation-to-mechanism
mappings) stays hand-written; engines like `Lips.Engine.Feed` are written by
hand for now.

The canonical form is one decision per line,
`id kind subject strength "assertion" [@file:line | <-ids via rule] [-- rationale]`,
with `#` comments and blank lines ignored. It is the on-disk, diffable
representation (text diff approximates set diff); it is not the loose
authoring text, which only `generate` turns into decisions.

`test/Spec.hs` is the seed conformance suite: every block cites the spec
invariant it pins.

`Lips.Engine.Feed` is one hand-written example engine (a real engine is what
`generate` produces); `app/Main.hs` is the reference `lips` CLI. Together they
run a canonical-form program to a NixOS module with no AI:

    nix run . -- run examples/ledger.decisions   # prints a valid NixOS module

An unmet demand instead prints the verbatim open question and exits non-zero.

## Design Choices (answering spec section 11)

- **Subject** is an attribute path and serves as the merge key: decisions
  compete only when they share a subject.
- **Strength** is the total order `Default < Stated < Law` (the NixOS priority
  mechanism promoted to kernel physics). Cross-language strength is deferred.
- **Orthogonality by construction**: a decision matched by more than one rule
  is an `Overlap` error, so rewriting is a function and refinement is confluent
  for free.
- **Provenance by construction**: the refiner, not the rule author, stamps each
  derived decision with `Derived [parent] rule`.
- **Termination** is guarded by a step budget; a runaway rule fails loud as
  `Nonterminating`.

## Running the Suite

    nix flake check          # compiles with -Wall and runs the suite
    nix develop              # then: ghc -Wall -isrc -itest test/Spec.hs -o /tmp/spec && /tmp/spec

Offline (network-restricted) note: the flake pulls nixpkgs from GitHub. Where
that is blocked but a nixpkgs checkout is already in the store, build the same
compiler with
`nix-build -E 'with import <path-to-nixpkgs> {}; haskellPackages.ghcWithPackages (p:[p.hspec p.QuickCheck])'`
and invoke its `ghc` directly.

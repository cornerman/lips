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
| `Lips.Lang.Pattern` | section 5 | a crystallization pattern: token template with holes -> one decision |
| `Lips.Lang.Crystallize` | section 5 | loose text x language -> decision base, deterministically (three outcomes) |
| `Lips.Lang.Lang` | section 5 | the `.lang` stored form: patterns as `meta` decisions, round-tripping |
| `Lips.Generate.Harness` | section 5 | the deterministic core of `generate`: deduce-or-fail admission and resampling unanimity |
| `Lips.Generate.Minting` | section 5 | the model-facing half of `generate`: system prompt + pattern-candidate parser (pure) |

## The Loop

    lips generate [model] examples/feed.loose   # AI step: mints feed.loose.lang, validates by a full run
    lips run examples/feed.loose                 # deterministic: crystallize -> refine -> realize (no AI)

`generate` is the one step where a model runs (spec section 5). The model mints
a *language* (a set of patterns in `<file>.lang`); it never states the meaning
of the program. The kernel then crystallizes the program with that language,
validates it by a full run, and only then writes `<file>.lang`, the crystal
witness `<file>.decisions`, and a `<file>.generation` audit record. It routes
the model call through `pi` in print mode (`pi -p -nt --no-session --model
...`); the default model is `anthropic/claude-opus-4-8`, overridable as the
first argument.

`run` takes the loose program directly and crystallizes it with `<file>.lang`,
with no model. Edits that stay within the language (changing a value or
instance a hole binds) flow through unchanged; an edit that escapes the
language fails loud and names `generate` as the remedy.

## The AI Boundary (the inversion)

Only the model call inside `generate` is non-deterministic; everything else is
pure. The model delivers *grammar*, never *meaning*: it mints patterns, and the
kernel derives the program's decisions from them by deterministic template
matching. AI may invent grammar; only the kernel assigns meaning to the program
text. The boundary is explicit in the code:

- `Lips.Generate.Minting` holds the *pure* minting logic: the system prompt (a
  versioned artifact, spec section 5 layer 3) and the parser that turns the
  model's confidence-prefixed pattern lines into candidates.
- `generate` refuses to write a language it is unsure of: any pattern below the
  confidence threshold (0.7) aborts the write (deduce-or-fail). The minted
  language is then validated by crystallizing the actual program and running it
  end to end; nothing is written unless the whole loop succeeds.
- The model call itself lives in the CLI shell (`app/Main.hs`, `callPi`).

This milestone crystallizes the *front half* of the engine (the language). The
*back half* (obligation-to-mechanism rules, demands) stays hand-written;
engines like `Lips.Engine.Feed` are written by hand for now. Making rules data
too is the engine-synthesis milestone.

`.decisions` is no longer a source artifact: it is the cached crystal, derived
from the loose text plus `.lang`, safe to delete. The only irrecoverable
artifact is the loose program itself.

The canonical form is one decision per line,
`id kind subject strength "assertion" [@file:line | <-ids via rule] [-- rationale]`,
with `#` comments and blank lines ignored. It is the on-disk, diffable
representation (text diff approximates set diff); it is not the loose
authoring text, which only `generate` turns into decisions.

`test/Spec.hs` is the seed conformance suite: every block cites the spec
invariant it pins.

`Lips.Engine.Feed` is one hand-written example engine (a real engine is what
`generate` produces); `app/Main.hs` is the reference `lips` CLI. Together they
crystallize a loose program to a NixOS module with no AI:

    nix run . -- run examples/feed.loose         # crystallize + realize, no AI

This reads `examples/feed.loose` and `examples/feed.loose.lang`. An unmet
demand, an escaping line, or a missing language instead fails loud and names
`generate` as the remedy.

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

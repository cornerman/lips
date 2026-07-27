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
| `Lips.Kernel.Expect` | ledger 13 | the `.expect` behavioral contract: relational option-value assertions, parsed/rendered/judged (pure) |
| `Lips.Kernel.Lang.Pattern` | section 5 | a crystallization pattern: token template with holes -> one decision |
| `Lips.Kernel.Lang.Crystallize` | section 5 | loose text x language -> decision base, deterministically (three outcomes) |
| `Lips.Kernel.Lang.Store` | section 5 | the `.lang` stored form: the whole engine as `meta` decisions, round-tripping |
| `Lips.Kernel.Engine.Data` | section 5 | the engine's back half as data: minted rules (`match ... => options`) and demands, interpreted generically |
| `Lips.Kernel.Engine.Value` | section 5 | the closed rhs value grammar (string/list/bool/int; holes and `${pkgs...}` refs only) -- computation and injection unrepresentable |
| `Lips.Generate.Harness` | section 5 | the deterministic core of `generate`: deduce-or-fail admission and resampling unanimity |
| `Lips.Generate.Record` | section 5 | the pinned generation record and its content id; every minted `.lang` line is stamped `@gen:<id>` |
| `Lips.Generate.Minting` | section 5 | the model-facing half of `generate`: system prompt + whole-engine candidate parser (pure) |
| `Lips.Generate.Readme` | section 5 | the mint's `report` and `gap` blocks rendered as `<language>/README.md`, the human's review artifact |

## The Loop

    lips generate examples/ingest.feed.lips   # AI step: mints feed/feed.lang + feed/feed.expect, validates by a full run
    lips compile examples/ingest.feed.lips    # deterministic: crystallize -> refine -> realize -> module dir (no AI)
    lips check   examples/ingest.feed.lips    # deterministic: the committed .expect contract must hold (no AI)
    lips lsp                                  # the domain-blind language server (stdio)
    # (paths are relative to the repo root, where examples/ lives)

Every path is derived from the program name by `Lips.Identity`: a program
`<instance>.<language>.lips` keeps everything the machine writes in a
`<language>/` folder beside it (`feed/feed.lang`, `feed/feed.expect`,
`feed/feed.generation`, `feed/artifacts/`), with derived output under
`feed/out/` (`out/ingest.decisions`, the compiled dir `out/ingest/`). Running is
not a lips verb: `compile` prints the stock `nix` commands over the compiled
directory.

`generate` is the one step where a model runs (spec section 5). The model mints
a whole *engine* into `<language>/<language>.lang` -- patterns (the language), rules (the
mechanisms, as `match <kind> <subject> => <option.path> "<rhs>" ; ...`, where
`<rhs>` is a value in a closed grammar, never a Nix expression), and
demands -- and it never states the meaning of the program. The kernel then
crystallizes the program with that engine, validates it by a full run, a
Nix parse (`nix-instantiate --parse`), and an option-schema check (every minted
rule must fill a NixOS option that exists in the pinned nixpkgs, with a
compatible value type, or the engine is rejected -- deduce-or-fail), and only
then writes the language's `.lang`, the
per-instance crystal witness `out/<instance>.decisions`, and a `.generation`
audit record. It
routes the model call through `pi` in json print mode (`pi -p -nt -nc
--no-session --mode json`); lips bakes in no model, so by default `--model` is
omitted and pi's own configured default applies. A model may be given as the
optional first argument. Either way lips reads the model pi actually used back
out of the json stream and records it in `.generation`, so provenance stays
concrete without a vendor model in the deliverable. No domain vocabulary is compiled in: the model invents
the subjects, and closure is checked (unmapped decision, unmet demand,
uncovered line, invalid Nix, or an unknown/mistyped NixOS option each rejects
the engine), not trusted. The option schema is domain-blind in the kernel
(`Lips.Kernel.OptionType`, a typed `OptionSchema`); the NixOS `optionsJSON`
shape and its type-string wording live in `Lips.Nix.Options`. `generate` builds
the schema lazily from the pinned nixpkgs baked into the packaged binary
(`LIPS_NIXPKGS_FLAKE`), announcing the one-time build; `compile`/`check`
never touch it. A caller may override with `LIPS_OPTIONS_JSON` (a prebuilt
`options.json`), which the suite uses for an offline fixture.

`compile` takes the loose program directly and crystallizes it with the
language's `.lang`, with no model. Edits that stay within the language (changing a value or
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
  confidence threshold (default 0.7, overridable with `--confidence <0..1>` and
  pinned into the generation record) aborts the write (deduce-or-fail). The minted
  language is then validated by crystallizing the actual program and running it
  end to end; nothing is written unless the whole loop succeeds.
- The model call itself lives in the CLI shell (`app/Main.hs`, `callPi`).

The whole engine is data: patterns (front half) and rules + demands (back
half) all live in the one `.lang` file and are interpreted by generic kernel
executors (`Lips.Kernel.Engine.Data`). Nothing problem-specific is compiled into the
kernel; there is no hand-written engine anymore. Minted rules emit only ground
(`Meta`) decisions, so a minted engine terminates in one refinement pass by
construction (cascades stay a hand-written-`Rule` capability until a real
program needs them minted). An emit's `<value>` hole takes the matched
decision's assertion verbatim; `<value.N>` takes its Nth whitespace token --
kernel physics absorbed from the first live run, where the model otherwise
unpacked packed values with Nix `splitString` gymnastics.

`.decisions` is no longer a source artifact: it is the cached crystal, derived
from the loose text plus `.lang`, safe to delete -- which is why it lives under
the language folder's self-ignoring `out/`. The only irrecoverable
artifact is the loose program itself.

The canonical form is one decision per line,
`id kind subject strength "assertion" [@file:line | <-ids via rule] [-- rationale]`,
with `#` comments and blank lines ignored. It is the on-disk, diffable
representation (text diff approximates set diff); it is not the loose
authoring text, which only `generate` turns into decisions.

`test/Spec.hs` is the seed conformance suite: every block cites the spec
invariant it pins.

`app/Main.hs` is the reference `lips` CLI. With a minted engine beside the
program, it crystallizes a loose program to a NixOS module with no AI (run from
the repo root, where the flake and `examples/` live):

    nix run . -- compile examples/ingest.feed.lips    # crystallize + realize -> module dir, no AI
    nix run . -- compile examples/ledger.backup.lips  # a second, non-feed domain

This reads the program and its language's `.lang`. An unmet demand, an escaping
line, or a missing language instead fails loud and names `generate` as the
remedy.

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

From the repo root (the flake lives there, not in `kernel/`):

    nix flake check          # compiles with -Wall and runs the suite (+ VM smoke)
    nix develop              # then: cd kernel && ghc -Wall -isrc -itest test/Spec.hs -o /tmp/spec && /tmp/spec

Offline (network-restricted) note: the flake pulls nixpkgs from GitHub. Where
that is blocked but a nixpkgs checkout is already in the store, build the same
compiler with
`nix-build -E 'with import <path-to-nixpkgs> {}; haskellPackages.ghcWithPackages (p:[p.hspec p.QuickCheck])'`
and invoke its `ghc` directly.

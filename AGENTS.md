# lips — Agent Notes

Read `README.md` first (the loop, the files). Design truth lives in
`DESIGN.md` (repo root); its section 13 is the milestone ledger (done /
partial / missing) and must be updated when a milestone lands. Dated plans
live in `docs/superpowers/plans/`, surveys in `docs/superpowers/survey/`.

## The Kernel Knows Nothing (read this first)

The kernel is domain-blind, and this is the point of the whole project, not a
style preference. The kernel knows nothing about any actual program: not the
domain, not the words, not the language a program is written in, not the tools
it builds with. It never mentions banks, backups, nginx, Rust, systemd, or any
concrete thing.

So you may never put a concrete, per-problem ("kleinkariert") case into the
kernel. No `if language == rust`, no builtin list of builders, no hard-coded
option names, no domain keyword, no special-casing of a program's shape. The
moment you feel the urge to teach the kernel about a specific program, stop:
that knowledge belongs in the minted engine (data), and the kernel must reach
the concrete thing only by *name*, inherited from Nix/nixpkgs (a package ref, a
builder ref), exactly as `${pkgs.<path>}` names a package without the kernel
knowing what it is.

The test: a capability is complete when a program, or a language, that nobody
foresaw works without any kernel change. If a new case would need a new kernel
branch, the design is wrong. Grow a closed, complete grammar the engine fills
in; never an open list the kernel enumerates. A missing grammar case is a
kernel bug; a missing domain fact is the engine's job.

## Terminology (use these words exactly)

- **Program**: the human-written `.loose` file. The only unrecoverable
  artifact; everything else is derived or regenerable.
- **Decision**: the atom. `id kind subject strength "assertion" @provenance`.
  Programs, engines, and all intermediate stages are decision bases.
- **Kernel**: the fixed, domain-blind physics (merge, refine, realize,
  template matching, value grammar). Code in `kernel/src/Lips/Kernel/`.
  Evolves slowly; per-problem knowledge never lives here (see "The Kernel
  Knows Nothing"). It reaches concrete things only by name, inherited from
  Nix.
- **Engine**: the per-problem rulebook, pure data in `<program>.lang`
  (patterns + rules + demands). AI-minted, disposable, regenerable. There is
  no per-problem engine *code*.
- **generate / run / check**: generate is the only AI door (via `pi` print
  mode). run and check are deterministic and offline, always.

## Invariants (do not break)

1. `run` never calls a model. No AI after generate, ever.
2. Deduce-or-fail: unreadable input fails loud naming the remedy; lips never
   guesses. Structural guards beat prompt pleas.
3. Illegal states unrepresentable: rule rhs is the closed value grammar
   (`Kernel/Engine/Value.hs`); computation and injection have no constructor.
   Completeness by construction: closed grammars the engine fills, never open
   lists the kernel enumerates; the kernel names concrete things (packages,
   builders) via Nix, and knows nothing about them.
4. Workarounds become kernel physics: if a mint needs gymnastics (or a human
   would hand-edit output), fix the kernel/format, not the prompt or output.
   Generated output is never hand-edited.
5. Regeneration is gated: the committed `.expect` contract must hold against
   the new engine's realized module; a break is a human decision (re-bless by
   deleting `.expect`), never silent.
6. Every minted line is stamped `@gen:<id>`; the id must re-hash from the
   committed `.generation` record.

## Working Here

- Feature work in a worktree under `.worktrees/`, TDD against the conformance
  suite, small single-line commits, rebase + ff-merge to main (no merge
  commits), then update ledger section 13.
- Test fast: `just test` (or in `kernel/`:
  `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`).
  Full: `just check` (needs KVM), `just check-expect`.
- The suite and app must stay `-Wall` clean.
- Nix flakes see only git-tracked files: `git add` before `nix build`/`nix run`.
- `*.decisions` is gitignored (derived cache); `.lang`, `.expect`,
  `.generation` are committed.
- Model gateway: `pi -p -nt --no-session --model <provider/id>` reading the
  prompt from stdin; `pi` is deliberately not in the dev shell (it is the
  user's harness and carries auth).

# lips — Agent Notes

Read `README.md` first (the loop, the files). Design truth lives in
`docs/superpowers/specs/2026-07-18-lipsidea-design.md`; its section 13 is the
milestone ledger (done / partial / missing) and must be updated when a
milestone lands. Plans and surveys sit beside it.

## Terminology (use these words exactly)

- **Program**: the human-written `.loose` file. The only unrecoverable
  artifact; everything else is derived or regenerable.
- **Decision**: the atom. `id kind subject strength "assertion" @provenance`.
  Programs, engines, and all intermediate stages are decision bases.
- **Kernel**: the fixed, domain-blind physics (merge, refine, realize,
  template matching, value grammar). Code in `kernel/src/Lips/Kernel/`.
  Evolves slowly; per-problem knowledge never lives here.
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

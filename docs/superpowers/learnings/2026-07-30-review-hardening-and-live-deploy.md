# Learnings: review, hardening, and the first live deployment

Session scope: a thorough code+docs review of `lips`, then closing several
TODO items (gap-report file writer, a reserved-hole-name bug, the mint
prompt rewrite, and the first live host deployment). Recorded here because
each finding teaches something more general than the one-line fix it
produced.

## On the project's own self-audit

`DESIGN.md` §13 ("Verified Breakages") and `TODO.md` already track most
known gaps in forensic detail: each entry names the exact reproduction, the
root cause, the fix commit, and the regression test that pins it. A fresh
review pass mostly could not out-find that process — the cheap, obvious
bugs were already caught by it. The two things a fresh pass *did* add were
outside that process's own scope by construction:

1. **Doc staleness** — claims that were true when written and never
   revisited after the code that made them true landed elsewhere (README
   said `just ci` was red for a reason that TODO.md itself, further down the
   same file, already recorded as fixed). A ledger that logs "done" events
   does not automatically update every *other* place that referenced the
   "not done" state. Lesson: when closing an item, grep the whole repo for
   places that assert the *old* state, not just the ledger entry for the
   *new* one.
2. **A bug the existing tests structurally could not see**, because the test
   exercised a narrower claim than the one that mattered. `lipsModules-eval`
   asserted `test -f ${p}/default.nix` — true, and irrelevant to whether
   `imports = [ p ]` actually works, which is the only claim anyone
   downstream relies on. A file existing on disk and a value being a valid
   NixOS module are different properties; a check that only proves the
   easier one gives false confidence in the harder one. Lesson: when writing
   a check for "X works", ask what the *actual consumer* does with X, and
   make the check do that, not something merely correlated with it.

## Two bugs, one shape: an internal workaround that never reached the public contract

Both real bugs found this session have the identical shape, worth naming
because it will recur:

- **The reserved-`<value>`-capture bug**: the unbound-capture check (which
  *does* exist, and *does* work) covers "a hole the subject never bound" but
  not "a hole the subject bound to something the reserved-word logic then
  silently shadows". The general case (unbound names) was solved; the
  specific, sharper case (a bound name colliding with a keyword) was not,
  because it required asking a different question ("does this bound name
  collide with a reserved one?") than the one the existing check asked.
- **The `modulesFromDir` importability bug**: `vm-smoke` and `artifact-vm`
  *already knew* a bare derivation is misread by NixOS's module loader
  (their own code comments say so explicitly) and *already worked around
  it* locally (`imports = [ "${realized}" ]`). That knowledge never
  propagated to the public `lib.modulesFromDir` helper the README
  documents, so every external consumer hit the bug fresh, on a real
  machine, before any check here could.

**The shared lesson**: a workaround applied at one call site is knowledge
that has not yet become a fix. If two call sites need the same workaround,
the workaround belongs in the thing they both call, not copy-pasted (or
worse, applied once and forgotten to apply the second time). This is the
same principle the project's own AGENTS.md states for the kernel
("workarounds become kernel physics") — it turns out to apply exactly as
much to Nix glue code as to the Haskell kernel.

## On verifying Nix/flake changes correctly

`nix develop <path>` and `nix build <path>#...` read the **git-tracked
state of the flake at `<path>`'s current branch**, not the literal
filesystem contents of whatever directory you happen to be sitting in.
Running `nix develop /repo -c ...` from inside `/repo/.worktrees/branch/`
silently tests the *wrong* branch's flake.nix — it will build and often
even look like it passed, because the old code usually still compiles; it
just isn't testing the change you think it's testing. Point `nix develop`/
`nix build` explicitly at the worktree whose changes you're verifying,
every time. This cost one wasted verification pass this session before it
was caught (a `Data.FileEmbed` "module not found" error was the tell — the
devshell had the *old* flake.nix, which didn't yet depend on `file-embed`).

## On confirming a root cause before believing a diagnosis

The `modulesFromDir` bug was confirmed, not assumed: reading the exact
pinned nixpkgs source (`lib/modules.nix`'s `loadModule`) rather than
recalling how NixOS's module loader "probably" works. The recalled model
was wrong in a specific way (guessed that `isStringLike`/derivation
coercion was special-cased; it is not — `isAttrs` is checked before any
such coercion, and a derivation is always `isAttrs`). The fix that came out
of reading the real source (expose a string, not a derivation) is also
simpler than the fix the wrong mental model would have produced (which
would have involved restructuring the returned value's shape into
`{ imports = [...]; }`, a bigger and riskier change for no added benefit).
**Reading the real implementation, once, was cheaper than the extra
complexity a plausible-but-wrong guess would have cost.**

## On delegating large, well-specified work

The mint-prompt rewrite (a ~700-line prose rewrite plus infra change) went
to a subagent as one shot, not the full per-task subagent-driven-development
machinery the project's own plan file recommended. Reasoning: the work was
already fully specified section-by-section in an existing plan doc, prose
content benefits from one consistent voice more than from independently
reviewed fragments, and the per-task review-loop overhead would have cost
more turns than the work itself. The subagent's own report flagged its one
deviation from the plan's literal commit granularity (2 commits instead of
9) with a clear reason, which made it easy to accept on review rather than
push back. **Lesson**: delegate the whole well-specified unit, require the
delegate to flag its own deviations with reasoning, and always independently
re-verify the deliverable (rebuild, re-run the suite, spot-check technical
claims against source) rather than merging a subagent's self-report at face
value — which is exactly how the `nix develop`-wrong-worktree mistake above
got caught before it became a false "all green".

## On live deployment as a test category VM tests cannot substitute for

This was the project's own stated thesis (DESIGN §13's "Shortest Summary"
named live deployment as the one missing proof) and it held up empirically:
the first real attempt, on a real machine, nested inside a real
`useGlobalPkgs`-style host, found a bug that eleven committed example
programs, two VM-boot flake checks, and a full conformance suite had all
missed — not because those tests were poorly written, but because none of
them exercised the *specific* path (the public helper's return value,
consumed exactly as an external, unrelated repo's flake would consume it)
that a real downstream user actually exercises. A test suite that only ever
tests a project against itself cannot find the class of bug that only shows
up at the boundary with something else. This is now a permanent regression
guard (`lipsModules-eval` instantiates a real `nixosSystem`/
`homeManagerConfiguration` per example), which is the right kind of fix:
not "add a test for the specific bug" but "make the check exercise the real
contract, so this whole *class* of future regression is caught here
instead of on someone's machine."

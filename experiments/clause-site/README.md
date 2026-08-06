# A Clause Site, End to End

The smallest program whose behaviour is clauses, used to prove plan Task 7:
`compile` writes a runnable site and stock `nix` runs it.

    lips compile experiments/clause-site/echo.lips
    printf 'a\nb\nc\n' | nix run 'path:experiments/clause-site/echo/out/echo#site'
    lips check experiments/clause-site/echo.lips     # judges the claim over its clauses

The engine is HAND-WRITTEN, which is the only thing here that a real program
would not have: no mint emits clauses yet (plan Task 9). Its `@gen:` stamps are
zeros for the same reason. Everything downstream of the engine is the real path.

What `compile` writes into `out/echo/site/`:

- `core.scm` -- the three clauses, each naming the program line that caused it.
- `adapter-pure.scm`, `adapter-effects.scm` -- copied from the runtime lips chose
  by covering the contracts the core reaches (`read-a-line`, `end-of-input?`,
  `emit`) against what each catalogued runtime provides.
- `main.scm` -- adapters, then core, then the entry the runtime declares.
- `build.nix` -- the runtime's own builder, copied verbatim.
- `claims.scm` -- the second sentence, as a judgment: the same core with the
  runtime's list-backed adapters and verdict harness linked instead of the real
  effects, so `nix build ...#site-claims` runs the program in memory. A failed
  claim exits nonzero and fails the build, which is what makes an unheld claim
  impossible to mistake for a held one.

Verified by breaking it on purpose: with `(emit line)` removed from the engine's
scan clause, `lips check` reports `FAIL both got=() want=("a" "b")` and refuses.

One wart worth knowing, and it will bite the mint too. Inside a CLAUSE the hole
marker is `#<name>`, not `<name>`, because `<` and `>` are ordinary Scheme
identifier characters and a clause must be able to write `(< n 3)`. Inside a Nix
value it stays `<name>`. This engine gets both right on purpose: its `feed` is a
Nix list of strings with `<in1>`, and its `equals` is an s-expression with
`#<in1>`.

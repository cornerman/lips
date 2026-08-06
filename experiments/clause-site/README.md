# A Clause Site, End to End

The smallest program whose behaviour is clauses, used to prove plan Task 7:
`compile` writes a runnable site and stock `nix` runs it.

    lips compile experiments/clause-site/echo.lips
    printf 'a\nb\nc\n' | nix run 'path:experiments/clause-site/echo/out/echo#site'

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

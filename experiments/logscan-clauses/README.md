# logscan as Clauses

The logic-axis falsifier (`TODO.md` item 8), run by hand with no kernel changes.
Result and numbers: `docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`.

- `logscan.lips` -- the five original sentences plus two that answer demands.
- `clauses.scm` -- the minted part, one definition per thing the program says.
- `runtime.scm` -- the guile primitive vocabulary, written once, never minted.
- `claims.scm` -- claims over single definitions, offline, no VM.
- `logscan.scm`, `run.sh` -- assembly and how to run it.

    printf '{"a":"1"}\n{"a":"2"}\n' | ./run.sh a=1     # prints {"a":"1"}
    ./check.sh                                          # the claims

# logscan as Clauses

The logic-axis falsifier (`TODO.md` item 8), run by hand with no kernel changes,
then extended to prove the contract boundary. Result and numbers:
`docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`.

Human-written intent:

- `logscan.lips` -- SEVEN lines: the five of `examples/logscan.lips`, plus two
  answering the demands honest minting produced (a bad argument, a non-JSON
  line). Every `@from logscan.lips:N` in `clauses.scm` counts into this file, not
  into the five-line committed example.

The minted core (this is the whole reviewed artifact):

- `clauses.scm` -- 8 definitions, each naming the program line that caused it.

Everything the core reaches the world through, never minted per program:

- `contracts.scm` -- the declared contract set. Four effect contracts are this
  program's entire reach into the world.
- `adapter-pure.scm` -- guile's pure contracts (guile-json, one hand-written gap).
- `adapter-effects-guile.scm` -- stdin, stdout, exit: the real run.
- `adapter-effects-memory.scm` -- the same four names backed by lists: the claims.

Checks and assembly:

    ./gate.sh                                           # nothing runs: the core read as data
    ./check.sh                                          # claims, offline, ~120 ms
    printf '{"a":"1"}\n{"a":"2"}\n' | ./run.sh a=1      # prints {"a":"1"}

`logscan.scm` is the assembly realize would emit: adapters, then core, then entry.

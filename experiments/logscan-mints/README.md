# Two Mints of One Program

Falsifier check (c), run for real (2026-08-04): mint the same five-line
`examples/logscan.lips` twice, with the same model, target and thinking level,
and see whether the results differ only where the program differs.

**They differ in the representation itself, so check (c) fails.** Both engines
are fifteen lines and both pass every gate. What they contain is not comparable:

| | mint a | mint b |
|---|---|---|
| behaviour lives in | 6 clauses | 94 lines of Go plus a shell wrapper |
| clause subjects | `scan`, `parse-spec`, `keep?`, `show`, `main`, `tool-name` | none |
| staged source | none | `artifacts/logscan-core/{main.go,go.mod}` |
| gaps reported | `clause-program-not-installable`, `no-argv-contract` | `no-argv-contract` |

Both engines are kept here as evidence, with their `.expect` and the README each
mint wrote about itself. `b/artifacts/` is its baked Go.

## Why b Chose Go, and Why That Is Not a Prompt Problem

Mint a took the clause path and hit two capability gaps, which it reported rather
than worked around. Mint b took the Go path, which has neither gap, and produced
a working engine.

Both were right. The prompt PREFERS clauses; it cannot make them adequate. The
clause path today cannot satisfy `install the tool as the command logscan`,
because a clause site has no reference form: there is no `${site}` in the value
grammar, no artifact builds it, so no NixOS option can put it on PATH. Nor can a
clause read its own arguments, since no contract yields them and `main` depends
on the runtime entry handing them over. A model optimizing for an engine that
actually works will keep choosing source until those two holes are closed.

This is the project's own doctrine arriving from the other side. "A hole is
grounded from outside or by plurality, never by wishing" has a sibling: a
capability gap cannot be closed by preferring the thing that lacks the
capability. Prompt wording loses to missing physics, every time.

## What Mint a Proves Anyway

The clause path is real end to end, not a hand experiment: an unmodified `pi`
call produced six clauses over declared contracts, `check_draft` accepted them,
every gate passed, and the engine writes a `.lang` a human can read in fifteen
lines. Its own README says it in the mint's words: "It is minted as clauses
(small definitions in lips' Scheme subset), not as a source file, so every
definition is traceable to the sentence that asked for it."

## The Two Holes, Precisely

**No reference to the site.** `${pkgs.<path>}` and `${artifact.<name>}` are the
value grammar's only derivation references. A clause site is built by
`site/build.nix` and exposed as `packages.site`, but nothing in a module can name
it, so a program cannot install its own behaviour.

**No arguments contract.** The runtime entry is `(main (cdr (command-line)))`, so
argv reaches a clause only as a parameter the entry passes. A clause cannot ask
for it, and a claim cannot vary it.

## Also Observed, About Mint Cost

Mint a took 13m 35s. Mint b needed three attempts: two returned "no usable
reply" after 47s and 12m 26s before the third succeeded. The clause doctrine
lengthens the mint, and the failure mode is a model that spends its budget on
tool calls and never emits a final answer. Worth watching, since a mint that
fails two out of three times is expensive even when it eventually works.

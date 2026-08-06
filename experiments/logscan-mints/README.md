# Two Mints of One Program

(`examples/logscan` was re-minted as clauses on 2026-08-04 and its Go deleted, so
the committed corpus now demonstrates the axis rather than the defect. The four
engines here are kept as the evidence that got it there.)

Falsifier check (c): mint the same five-line `examples/logscan.lips` twice, same
model, target and thinking level, and see whether the results differ only where
the program differs. Run twice, before and after the capability gaps the first
run exposed were closed.

## Second Run (e and f): It Passes, Behaviourally

Both mints chose CLAUSES. Neither wrote a line of source. Both engines are twelve
lines, both cores are seven definitions, and every definition names the program
line that caused it.

The two cores are NOT textually identical: `e` factors the loop into `scan` plus
`print-kept` and `filter-lines`, `f` into `scan` plus `emit-all` and `matches?`.
So at the level of text, two mints still differ where the program does not.

What matters is that they do not differ in what the program DOES. Both were
compiled, built and run against thirteen inputs, including every case where the
two Go mints disagreed:

| input | e | f |
|---|---|---|
| `a=1` over `{"a":"1"}`, `{"a":"2"}` | `{"a":"1"}` | same |
| `a=1` over `{"a":1}` | dropped (exact comparison) | same |
| `a=1` over a non-JSON line | dropped, exit 0 | same |
| a bad argument `a` | `argument is not field=value: a`, exit 1 | same, exit 1 |
| `a=1 a=2` over `{"a":"1"}` | dropped ("every" holds) | same |
| `a=1 b=y` over `{"a":"1","b":"x"}` | dropped | same |
| empty input, empty args, blank line, missing field, empty value, empty key | | all same |

Thirteen probes, byte-identical output and byte-identical exit codes. The Go axis
diverged on two of these same probes.

Two honest qualifications. Thirteen probes are evidence, not proof. And both
mints invented the same policy for a non-JSON line (drop it silently), which the
five sentences do not state; the invention is now visible in a traceable clause
rather than buried in seventy lines of Go, but it is still invention.

Gaps reported: none by `e`; one by `f` (`witness-line-count`, that a witness
pattern fixes the number of example lines, so a three-line example needs a fresh
mint). Neither reported a missing capability.

## First Run (a and b): It Failed, and Why

**They differed in the representation itself.** Both engines were fifteen lines
and both passed every gate. What they contained was not comparable:

| | mint a | mint b |
|---|---|---|
| behaviour lives in | 6 clauses | 94 lines of Go plus a shell wrapper |
| clause subjects | `scan`, `parse-spec`, `keep?`, `show`, `main`, `tool-name` | none |
| staged source | none | `artifacts/logscan-core/{main.go,go.mod}` |
| gaps reported | `clause-program-not-installable`, `no-argv-contract` | `no-argv-contract` |

All four engines are kept here as evidence, with their `.expect`, the README each
mint wrote about itself, and (for `e` and `f`) the core they realize to.
`b/artifacts/` is its baked Go.

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

## What the Second Run Cost, and What It Caught

Mints `e` and `f` each succeeded on the first attempt, against the first run's
two-of-three failure rate. The difference is that the closed gaps stopped the
model from spending its budget looking for a way around them.

The run also caught a defect no gate had: both mints defined `(define (main) ...)`
reading argv through the `arguments` contract, while the runtime entry called
`(main (arguments))`. Every gate passed and both binaries died on first run with
"wrong number of arguments". Fixed by deriving what the core must define from the
entry expression itself, so one declaration states the requirement and lips
refuses a core that does not meet it.

## Also Observed, About Mint Cost

Mint a took 13m 35s. Mint b needed three attempts: two returned "no usable
reply" after 47s and 12m 26s before the third succeeded. The clause doctrine
lengthens the mint, and the failure mode is a model that spends its budget on
tool calls and never emits a final answer.

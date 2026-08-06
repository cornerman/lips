# Validating the Clause Axis

Six programs, minted live, compiled, built and run. 36 cases, all green:

    ./validate.sh            # every scenario
    ./validate.sh threshold  # one of them

Nothing here is stubbed. Each scenario is `lips compile`, then `nix build` of
its site, then a real process fed on stdin, compared against a table of cases.
A scenario's engine is committed beside its program, so the table is a
regression test over an engine a model actually wrote.

## What Each Scenario Is For

Each one was chosen to stress something the others do not.

| scenario | what it stresses | clauses |
|---|---|---|
| `logscan` | JSON, conjunctive filtering, two fail-loud paths | 7 |
| `tally` | accumulation, arithmetic, output only at end of input | 4 |
| `threshold` | **a number the program states reaching a clause as a hole** | 4 |
| `watch` | **clauses and a systemd timer from one program** | 2 |
| `dedupe` | state (a seen-list and a counter) threaded through recursion | 4 |
| `report` | ranking without a sort primitive; an escape to glue | 7 |

## The Result That Matters Most

`threshold` says "print the name of every line whose number is above 100", and
its engine holds:

    (define (above? text) (> (string->number text) #<value:int>))

Editing the program to say `above 200` and running `lips compile` again, with no
model anywhere, changes the clause to `(> ... 200)`, and the rebuilt binary drops
`web 150` while keeping `db 250`. That is the whole thesis in one diff: the
program's own word governs the behaviour, and the compiler is deterministic and
offline.

## What Held Up

**Clauses stay small as logic gets harder.** Seven definitions is the largest
core in the corpus, for a program that ranks lines by frequency. `report` wrote a
selection sort (`best`, `top-n`, `without`) out of plain recursion, so the fear
that ranking needs a sort primitive was unfounded at this size.

**Recursion carries state.** `dedupe` threads a seen-list and a drop count
through its loop and prints `dropped 3` correctly; no mutation, no sequencing.

**The two axes compose.** `watch` produces 9 option assignments (a systemd
service, a timer, a package on PATH) and 2 clauses from one five-sentence
program, and its whole system builds as a VM.

**Every core is fully traceable.** Across all six, every definition carries the
program line that caused it. No exceptions and no gaps in provenance.

## What Broke, and What It Taught

Every scenario in this directory found something. None of it was found by the
suite, because each needed a model to write the shape that triggers it.

**`tally` reported `emitted-output-not-observable`.** For a program whose whole
job is to print, no claim could observe the printed lines. The capability existed
(`(emitted)` in the in-memory adapter) and the prompt never mentioned it, so no
model could reach it. Fixed by documenting the claim-time observation vocabulary.

**`report` exposed a hole in the grounding counter.** Its behaviour includes a
mint-invented shell pipeline, `"<value> | mail -s nightly-report $RECIPIENT"`,
sitting in `systemd.services.<self>.script`. The counter called that a vouched
option assignment, which is true of the option and false of the pipeline: a schema
vouches for a name and a type, never for the text inside a string. Fixed by
counting the literal words a mint writes into option strings, which now reports
`10 mint-written words` for that program and names the script.

**`logscan` (mints `e` and `f`) exposed the entry mismatch.** Both defined
`(define (main) ...)` against a runtime entry calling `(main (arguments))`, so
both binaries died on first run with every gate green. Fixed by deriving what the
core must define from the entry expression itself.

## The Limits This Corpus Found

Two are precise and worth keeping in view.

**A number word is not a number.** `report` was asked for "the ten most common"
and reported `counted-word-is-not-a-number`: a hole capturing "ten" binds the
word, and neither grammar converts it to 10. The count stayed a literal, so
changing it needs a fresh mint. Writing `10` in the program instead is the
author's fix; teaching lips English number words would be domain knowledge the
kernel must not hold.

**A witness fixes its own shape.** Several mints reported that an example pinning
two input lines cannot be reused for three, because a claim's feed is a list value
and no hole repeats. The general answer is a repeating hole in the template
grammar, which nothing else needs yet.

## What This Does Not Prove

Six programs of two to five sentences, four to seven clauses each. That measures
physics, not size. Nothing here has two languages composing, nothing has a second
site, and the largest core is 20 lines. `DESIGN.md`'s "Limits of Scale" still
applies in full: every statement about large systems remains extrapolation.

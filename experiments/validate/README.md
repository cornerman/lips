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

## One Limit, and One Thing I Wrongly Called a Limit

**A number word is not a number, and that is correct.** `report` was asked for
"the ten most common" and reported `counted-word-is-not-a-number`: a hole
capturing "ten" binds the word, and neither grammar converts it to 10. This is
not a hole in the concepts. A count is already expressible: the author writes
`10`, a pattern captures it, `#<value:int>` carries it into a clause, and
`threshold` proves that path end to end. Teaching lips English numerals would put
a table of one language's words in the kernel, which is exactly what "the kernel
knows nothing" forbids.

**A witness fixing its own arity was NOT a grammar gap.** Four mints -- `logscan`,
`watch`, `dedupe` and the older `board` -- wrote witness patterns with one hole
per example line (`<l1>`, `<l2>`, `<l3>`), so a three-line example refuses a
four-line program and adding one costs a fresh mint. I recorded that as a missing
repeating hole in the template grammar. It is not.

`Lang/Nest.hs` already carries the case, and its header says why the kernel must
not carry it any other way: "The kernel would otherwise be dictating a collection
syntax". A block is a header pattern plus a child nested under it, each item keyed
by `<n:index>`, and `Append` assembles one list from the N contributors.

Demonstrated with a hand-written engine, one engine and no model:

    given these lines:        given these lines:
      "a"                       "a"
      "b"                       "b"
      "c"                       "c"
                                "d"
                                "e"

    feed-lines ("a" "b" "c")  feed-lines ("a" "b" "c" "d" "e")

Same pattern, no arity anywhere, and the five-item run correctly failed the claim
whose expected value still said three. So the concept had no limit; the prompt
had a gap, the same class as `emitted-output-not-observable` above. Fixed by
telling the mint never to fix a count in a template, with the block shape spelled
out.

## The Boundary, Found Precisely

`rotate` is the most useful program in this directory and it has no scenario,
because the mint did not write clauses for it at all. Asked to delete files older
than 14 days under three directories, it produced 97 lines of Go and never
mentioned the clause path.

That is correct behaviour, and the counter says so plainly:

    grounding: 11 option assignments (schema), 0 clauses (contracts), 0 claims,
               4 unvouched assertions (nothing), 101 lines vouched by nothing

The reason is the contract set. There are nine contracts and all nine serve one
shape: standard input, standard output, arguments, stopping, JSON, and three
string and field helpers. **The clause axis today reaches text tools that read
stdin and write stdout, and nothing else.** A program that touches a file, a
clock, a process or a socket has no contract to name and falls back to baked
source, where lips has no gate worth the name.

The tempting fix is to invent `list-directory`, `file-age`, `delete-file`. That
would break the vocabulary scaling law, which is the reason the configuration
axis works at all: lips reaches as far as some EXTERNAL, named, typed vocabulary
reaches, and nixpkgs is that authority for options. Inventing an effect interface
would make lips the authority for one it never designed and must maintain forever.

So the principled growth path is to adopt an external vocabulary rather than mint
one, and the 2026-08-02 decision already named the candidate: WIT, which "names
behaviour without naming an implementation language", with WASI's own filesystem
and clock interfaces as the typed authority. That is the open question §10 called
the expensive one, and this round is the first evidence of exactly what it costs
to leave it open.

## What This Does Not Prove

Six programs of two to five sentences, four to seven clauses each. That measures
physics, not size. Nothing here has two languages composing, nothing has a second
site, and the largest core is 20 lines. `DESIGN.md`'s "Limits of Scale" still
applies in full: every statement about large systems remains extrapolation.

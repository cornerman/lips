# The logscan Clause Falsifier: Result

Run of `TODO.md` item 8, the cheapest possible refutation of the logic axis.
Hand-mint, no kernel changes. Files under `experiments/logscan-clauses/`.

**Verdict: the direction survives.** Twenty-four lines of minted clauses replace
seventy lines of minted Go, every one of them names the program line that caused
it, and the claim that today needs a Go build and a witness run now passes in
58 milliseconds with no build at all. The two checks the experiment could
answer, pass. The third could not be answered by a hand-mint and is restated
below as what to measure next.

## What Was Built

`logscan.lips` keeps its five sentences and gains two, which are the answers to
demands honest minting produces (see "The Demands"). Three files:

- `clauses.scm`, the minted part: 8 definitions, 24 code lines, each carrying
  `;; @from logscan.lips:N`.
- `runtime.scm`, the guile primitive vocabulary: 9 definitions, 21 code lines,
  written once and shared by every program on this runtime. The analogue of
  nixpkgs on the configuration axis.
- `claims.scm`, five claims over single definitions.

`./run.sh a=1` on the witness input prints `{"a":"1"}` and nothing else.

## Check (a): Does Every Clause Name Its Program Line? Yes

All 8 definitions carry provenance, and the mapping is one line of intent to one
or two definitions. Nothing in `clauses.scm` exists without a sentence behind
it, which is a property the Go file never had: an audit traced roughly 15 of its
76 lines to the five sentences.

More telling is what happened to the invented policy. Three of the Go file's
inventions became demands the author must answer, one disappeared because the
primitive has no such knob, and one reversed to the faithful reading.

| Go invention | Fate under clauses |
|---|---|
| silent `continue` on malformed JSON | demand, answered by `logscan.lips:7` (fail, naming the line) |
| `os.Exit(2)` and a message on a bad argument | demand, answered by `logscan.lips:6` (fail, naming the argument) |
| `asString` numeric coercion (18 lines) | demand; left unanswered, so comparison stays exact, and the witness still holds |
| 16 MB maximum line length | gone: `read-line` has no such knob, so no line of the mint can carry a number nobody asked for |
| `map[string]string` makes `a=1 a=2` mean "last wins" | reversed: a list makes it mean "both must hold", which is what "every field named on the command line" says |

The last row is the strongest single result. The Go mint silently contradicted
the program's own word "every"; the clause form could not, because the clause is
a recursion over the pairs the author gave.

## Check (b): Does a Claim Over One Definition Pass Offline? Yes, Decisively

`claims.scm` calls `keep?` directly on a parsed record and a parsed spec. Five
claims, 58 ms, no VM, no `nix build`, no binary. Today the same witness costs a
`buildGoModule` derivation and a process run against `${artifact.logscan}/bin/logscan`.

The claims also reach cases the current `.expect` cannot express at all, because
`.expect` observes a whole binary through stdin and stdout while a claim observes
one definition: an absent field, two fields that must both hold, one field named
twice.

## Check (c): Do Two Mints Differ Only Where the Program Differs? Not Answerable Here

A hand-mint is one mint. What the run did establish is the size of the surface
where drift can hide, and it measured the drift on the axis lips has today.

Both mints of `logscan` are still in the store, so the divergence is measured
rather than read:

| input | mint 1 (53 lines) | mint 2 (76 lines) |
|---|---|---|
| `logscan a` (bad argument) | `invalid argument: a`, exit 1 | `expected field=value, got "a"`, exit 2 |
| `{"a":1e-7}` under `a=0.0000001` | dropped | kept |

Neither behavior is mentioned by any of the five sentences, and one sentence was
added between the mints. The float case is the sharper one: `fmt.Sprint` renders
`1e-07` while `strconv.FormatFloat(_, 'f', -1, 64)` renders `0.0000001`, so a
coercion nobody asked for changed which lines a user's filter keeps.

Under clauses that surface is 24 traceable lines instead of 70 mostly untraceable
ones, so drift has less room by construction. Whether two real mints agree is
the measurement that still has to be made.

## The Demands

Honest minting of the original five lines produces three questions, all of which
the Go mint answered silently:

1. What should happen when an argument is not `field=value`?
2. What should happen when an input line is not JSON?
3. Does a value given as text equal a JSON number, so that `a=1` matches
   `{"a":1}`?

Three demands for five sentences is a real cost and worth watching. Two of them
were answered by adding one sentence each, which is the loop working as designed.
The third was left unanswered on purpose: exact equality is the reading the words
carry, the witness confirms it, and answering it would have cost the 18-line
`asString` block that caused the measured drift above.

## What the Run Says About the Open Questions

**The primitive signature vocabulary is the real problem, and it bit immediately.**
R7RS-small has no JSON and no `string-index`, so `runtime.scm` reaches for
guile-json and hand-writes `string-cut`. That is the concrete shape of the
question §10 raised: the base notation is portable while the vocabulary fragments
per runtime. Good news on the same point: JSON came from an external package, so
lips owns no JSON code, exactly as it owns no restic code.

**The effect boundary needs a decision the design has not yet made.** §7 says "no
effects"; §12's emitted subset ("clause forms, calls to named primitives,
literals, recursion") does not exclude them. The experiment put `scan`,
`scan-line`, `emit` and `die` in the minted set, so four of the eight definitions
are effectful, and only the pure four are claim-testable in isolation. Two ways
out, and picking one is the next design decision:

- Mint the effectful shell too, as here, and mark those definitions as unclaimable.
- Keep the loop in the runtime as an archetype ("a line filter": read lines,
  call `keep?`, print the kept ones) so the mint emits only the pure core, at the
  cost of a library of archetypes that lips would own forever.

**No renderer was needed, and none was missed.** The clause file is Scheme, the
run object and the checked object are the same text, and nothing translated. On
this program §12's claim holds as written.

## What Would Have Killed the Direction, and Did Not

The stated failure conditions were a clause set larger or harder to read than the
Go file, or a mint that still invents behavior no line asks for. Twenty-four lines
against seventy, and the inventions became demands.

## Next

1. Two real mints of `logscan` as clauses, through `pi`, to answer check (c).
2. Decide the effect boundary (mint the shell, or own an archetype vocabulary).
3. Reconcile `DESIGN.md`'s "Logic Axis" section, which still describes the
   per-host renderer that the 2026-08-02 decision rejected.

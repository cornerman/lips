# The logscan Clause Falsifier: Result

Run of `TODO.md` item 8, the cheapest possible refutation of the logic axis.
Hand-mint, no kernel changes. Files under `experiments/logscan-clauses/`.

**Superseded in one respect, 2026-08-04: `examples/logscan` now IS clauses.** The
76-line Go file this document audits was deleted when the example was re-minted;
every measurement of it below is history, and the two engines that produced the
comparison are committed under `experiments/logscan-mints/`.

**Verdict: the direction survives.** Twenty-four lines of minted clauses replace
seventy lines of minted Go, every one of them names the program line that caused
it, and the claim that today needs a Go build and a witness run now passes in
121 milliseconds with no build at all. The two checks the experiment could
answer, pass. The third could not be answered by a hand-mint and is restated
below as what to measure next.

A second run then split the runtime into a declared contract set and adapters
bound by name at link time, which settles the effect boundary the first run left
open: every clause is claim-testable, and a mechanical gate proves the core can
reach the world no other way ("The Contract Boundary").

## What Was Built

`logscan.lips` keeps its five sentences and gains two, which are the answers to
demands honest minting produces (see "The Demands"). The files split by author:

- `clauses.scm`, the minted part and the whole reviewed artifact: 8 definitions,
  24 code lines, each carrying `;; @from logscan.lips:N`.
- `contracts.scm` and three adapters, written once and shared by every program on
  this runtime. The analogue of nixpkgs on the configuration axis.
- `claims.scm` and `gate.scm`, the checks.

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

`claims.scm` calls `keep?` directly on a parsed record and a parsed spec, and
runs the whole program on a list of lines. Eight claims, 121 ms, no VM, no
`nix build`, no binary. Today the same witness costs a `buildGoModule`
derivation and a process run against `${artifact.logscan}/bin/logscan`.

The claims also reach cases the current `.expect` cannot express at all, because
`.expect` observes a whole binary through stdin and stdout while a claim observes
one definition: an absent field, two fields that must both hold, one field named
twice.

## Check (c): Do Two Mints Differ Only Where the Program Differs? RUN, AND IT FAILS

Answered for real once the mint could emit clauses (evidence and both engines:
`experiments/logscan-mints/`). Same program, same model, same thinking level, and
the two mints differ in the REPRESENTATION: mint a put the behaviour in six
clauses and no source file, mint b put it in 94 lines of Go behind a shell
wrapper. Both engines are fifteen lines and both pass every gate.

The cause is specific, and it is not the prompt. Mint a took the clause path and
hit two capability gaps, which it reported rather than worked around:
`clause-program-not-installable` (a clause site has no reference form, so no
NixOS option can put it on PATH) and `no-argv-contract` (no contract yields the
command line). Mint b took the Go path, which has neither gap. Both were right.
A prompt can prefer clauses; it cannot make them adequate, so until those two
holes are closed the mint will keep choosing source.

Two smaller observations from the same runs. Realize was emitting clauses INTO the
module (`clause."keep?" = (define ...)`), which no gate caught and which made the
module unparseable; fixed by treating a clause as kernel vocabulary like a claim
and an artifact. And mint b needed three attempts, two of them returning "no
usable reply" after 47s and 12m 26s, so the clause doctrine lengthens the mint
enough that budget exhaustion is a real failure mode.

## What Two Mints Looked Like on the Go Axis

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
R7RS-small has no JSON and no `string-index`, so `adapter-pure.scm` reaches for
guile-json and hand-writes `string-cut`. That is the concrete shape of the
question §10 raised: the base notation is portable while the vocabulary fragments
per runtime. Good news on the same point: JSON came from an external package, so
lips owns no JSON code, exactly as it owns no restic code.

**The effect boundary is settled, and the archetype alternative is dead.** §7 says
"no effects"; §12's emitted subset ("clause forms, calls to named primitives,
literals, recursion") does not exclude them. The first run put `scan`,
`scan-line`, `emit` and `die` in the minted set and called those four
unclaimable, offering a library of runtime archetypes ("a line filter") as the
way out. The second run shows no archetype is needed. See "The Contract
Boundary" below.

**No renderer was needed, and none was missed.** The clause file is Scheme, the
run object and the checked object are the same text, and nothing translated. On
this program §12's claim holds as written.

## What Would Have Killed the Direction, and Did Not

The stated failure conditions were a clause set larger or harder to read than the
Go file, or a mint that still invents behavior no line asks for. Twenty-four lines
against seventy, and the inventions became demands.

## The Contract Boundary, and the Subset Gate

Second run, same core, no change to `clauses.scm`. The old `runtime.scm` was
split into a declaration and three adapters, which turns the vague "named
primitives" of §7 into something mechanical.

**Capabilities bind by name at link time, not as passed values.** The core names
`read-a-line`; which definition that name carries is decided by which adapter
realize links, exactly as `${pkgs.<path>}` names a package realize binds. So
nothing higher-order is needed and the clause language stays first-order, while
the usual capability-passing discipline still holds.

**Every clause is claim-testable, effectful ones included.** `claims.scm` links
`adapter-effects-memory.scm` instead of the guile one and runs the whole program
on a list of lines: the witness, byte-for-byte output, and both failure paths.
Eight claims, 121 ms, no process, no stdin, no VM, no build. All 8 definitions
are exercised.

**A program's reach is a list, not an audit.** `contracts.scm` declares four
effect contracts (`read-a-line`, `end-of-input?`, `emit`, `die`). That is
`logscan`'s entire reach into the world, and a reviewer reads the list instead of
reading the implementation. The Go file offers no such statement at any price.

**The gate is mechanical, and it bites.** `gate.scm` reads `clauses.scm` as data
(no parser: homoiconicity paying off directly) and checks that every free
identifier is a base form, a base procedure, a declared contract, or a clause the
core defines, plus that every clause carries `@from`. Against the real core it
reports 8 clauses, 4 effect contracts, 0 ungrounded names, 0 missing provenance.
Seeded with a clause calling `system` and a clause without `@from`, it names all
three offenders and exits 3.

This is the shape the prior art already uses: a safe subset of somebody else's
language, enforced by a verifier, with authority arriving only through declared
contracts. Joe-E does it to Java, SES to JavaScript, Starlark to Python, SPARK
to Ada. lips owns the gate and the contract vocabulary; it owns no semantics and
ships no runtime.

## The Corpus, Measured

The run earned a counter, `Lips.Kernel.Grounding`, printed on every `lips check`:
every assertion is vouched by the target schema, by the contract set, by the
author who stated an observable, or by nothing. It classifies nothing by shape,
because guessing which strings are really programs is the invention lips refuses.
The caller that stages measures file sizes, since the kernel is pure and a path
would otherwise read as one harmless word.

What the corpus says, before any migration:

| program | unvouched |
|---|---|
| `logscan` | staged tree, 80 lines in 2 files |
| `hello.http` | staged tree, 66 lines in 2 files |
| `board` | staged tree, 41 lines in 1 file |
| `function` | staged tree, 25 lines in 2 files |
| `habit` | staged tree |
| `greet` | 4 words of mint-chosen bash (`echo "hello from lips"`) |
| the other 14 | nothing: every assertion is an option the schema defines |

So the defect is exactly localized. Configuration-only programs are clean, and
every unvouched line in the corpus belongs to an artifact. `greet` is the
interesting borderline: four words in one assertion attached to one program line,
which is the escape worth keeping, bounded by its own shape.

## Next

1. Two real mints of `logscan` as clauses, through `pi`, to answer check (c).
2. Decide where the contract declaration lives in a real mint: `contracts.scm`
   is hand-written here, and in the loop it would be minted from the program
   (a demand when a needed capability has no adapter on the chosen runtime).
3. Reconcile `DESIGN.md`'s "Logic Axis" section, which still describes the
   per-host renderer that the 2026-08-02 decision rejected.

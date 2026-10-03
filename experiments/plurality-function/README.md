# One Call Instead of Three: Does a Singleton Demote a Hole?

The experiment that TODO "Plurality is not a gate" left untried, run 2026-10-02.
The claim it tested: with ONE instance a hole and a constant are
indistinguishable, so cutting `examples/function.lips` from three calls to one
should make a mint fold the call's text into a constant. The result decides
whether a static "hole never contrasted" diagnostic beside `diagInert` is worth
building.

## Result

The prediction did not hold. The one-call mint kept the call's text a hole, and
editing it moves the output (`hallo` to `bye` prints `bye`). What a singleton DID
cost showed up in two other places, neither of them a constant:

1. In the CONTROL (three contrasted calls, one declaration), the never-contrasted
   type word became a hole that governs nothing. `function println_to_stdout(x:
   Int)` compiles and prints `hallo`. The program now says the parameter is an
   Int and passes it a string, and the engine accepts that sentence without
   honouring it. This is the defect the TODO item describes, observed on the
   singleton DECLARATION of the program whose calls were contrasted.
2. In the VARIANT, the mint's contract holds at one call only. Adding a second
   call is refused by the contract gate (`should be [ "du" ], but is [ "hallo" ]`),
   although the built program prints both lines correctly (run with
   `--no-contract`). So the singleton froze the language's arity through its
   CONTRACT rather than through its pattern. The refusal is loud, but it names the
   wrong remedy (re-mint).

A counting diagnostic separates neither case from the honest singletons around
it (corpus scan below). That is evidence against building it.

n = 1 per arm. Everything here is observed, not measured as a rate.

## Setup

| arm | program | engine |
|---|---|---|
| baseline | `examples/function.lips` (declaration + 3 calls) | committed, opus-5, minted 2026-08-09 |
| control | `control/function.lips` (identical to the baseline) | fresh mint, this run |
| variant | `single/function.lips` (declaration + `println_to_stdout("hallo")`) | fresh mint, this run |

Both mints: `lips generate -t nixos -m claude-opus-5 --thinking medium`, from
the binary at commit 02f28f4. Each scratch folder is fresh by construction (no
committed engine beside it), so neither mint is a patch.

| arm | verdict | wall | turns | submit_draft | output tokens | cost |
|---|---|---|---|---|---|---|
| control | accepted, first verdict | 229.8s | 8 | 6 | 16,392 | $0.81 |
| variant | accepted, first verdict | 313.9s | 13 | 11 | 22,790 | $1.12 |

Total: $1.93. The figures come from each folder's `function.timing`.

## What Each Engine Made of Each Program Word

| word | baseline (3 calls) | control (3 calls) | variant (1 call) |
|---|---|---|---|
| `println_to_stdout` | hole `<fname>` | LITERAL pattern word | hole `<fname>` |
| `x` | literal | hole `<param>` | hole `<param>` |
| `String` | literal | hole `<ptype>` | literal |
| call text | hole `<text>` | hole `<text>` | hole `<arg>` |

The call text is a hole in all three engines. Every word that is a singleton in
EVERY arm (the name, `x`, `String`) flips between hole and literal from one mint
to the next, and the flips show no direction. The control turned the function
name into a literal and filed the gap `function-body-and-name`: its reasoning
was that the name is the only thing saying what the function does. The variant
kept the name a hole, carried it into `function-print` as data, and filed
`function-body-unstated` plus `one-declaration-per-program`. On this evidence, the
hole-or-literal choice for an uncontrasted word is the mint's judgement call, and
the instance count does not force it.

## Offline Edit Probes

`probe.sh` copies an engine beside an edited program, compiles it (crystallize,
contract, claims), builds the result and runs it. No model is involved. The raw
output is in `probes.txt`.

| edit | baseline | control | variant |
|---|---|---|---|
| `"hallo"` -> `"bye"` | prints `bye` | prints `bye` | prints `bye` |
| add a 2nd call `"du"` | prints both | prints both | REFUSED by contract (prints both without it) |
| rename the function to `shout` everywhere | prints `hallo` | refused, no match | prints `hallo` |
| parameter `x` -> `y` | refused, no match | prints `hallo` | prints `hallo` |
| type `String` -> `Int` | refused, no match | **prints `hallo`** | refused, no match |
| call a function never declared | refused | refused, no match | refused, claim fails |

Every cell is honest except two:

- **control, `Int`.** `<ptype>` lands in one place: the message of a `die`
  branch, `(if (string? arg) (emit arg) (die "parameter #<value.1> is not a
  #<value.2>:" arg))`. Every call this grammar can read passes a quoted string,
  so `string?` always holds, the branch is dead, and the word changes nothing a
  program can observe. The reach gate (`droppedValues`) passes it, because the
  word does reach a clause. A word that lands only in dead code reads to that
  gate exactly like one that lands in live code.
- **variant, a second call.** The contract says `a1 expect
  claim.main.equals-lines from call.<n> is "[ \"<value.2>\" ]"`, and
  `expandExpects` expands it to one check per call. With three calls, BOTH
  extra checks report `but is [ "hallo" ]` (probe `S-three`): every expanded
  check is compared with the FIRST call's contribution. This fits
  `checkArtifactValues` (`Lips.Kernel.Expect`), which judges a ground slot
  against the first decision carrying its subject (`(a : _)`). On a slot fed by
  several program lines (a list-append clause or claim section), that is one
  contributor of many. The control dodged the problem by pinning `call.1` only,
  which holds at any call count (probe `C-swap`) but pins only the first call.
  This is a likely kernel defect, inferred from probes rather than from a test.
  With one call the gate cannot tell the two readings apart either: the mint's
  own check, which runs on its one program, cannot exercise a slot that has
  several contributors.

## Corpus Scan: What a "Never Contrasted" Diagnostic Would Flag

`scan/Scan.hs` (a throwaway tool, built from the kernel's own `matchTemplate`
and `wordLandings`) lists, per language, every (pattern, hole) pair together with
its distinct values across all committed programs of that language. It also
lists the emits that carry each word, using the reach gate's two tests per emit.
Output: `scan/corpus.txt` (committed corpus), `scan/mints.txt` (the two arms).

Committed corpus: 92 (pattern, hole) pairs, of which **59 are singletons**.
Restricted to the diagnostic's proposed scope (a hole landing in clause or
artifact source), **9 singletons remain, and every one is honest**: the value is
substituted into the clause, and an edit moves the behaviour.

| language | hole | value | why the singleton is honest |
|---|---|---|---|
| board | p3 `<col>` | `## name` | column marker the parser matches; pinned by the witness |
| board | p3 `<card>` | `- text` | card marker the parser matches; pinned by the witness |
| board | p4 `<names>` | `todo, doing, done` | the column list, split by the clause; the witness prints all three |
| board | p5 `<sep>` | `, ` | join separator; the witness output `milk, eggs` holds it |
| habit | p6 `<mark>` | `#` | logged-day mark; the witness `#..#` holds it |
| habit | p7 `<mark>` | `.` | missing-day mark; same witness |
| hello | p1 `<text>` | `hallo` | the greeting printed; a claim equals it |
| hello | p3 `<text>` | `goodbye` | the farewell printed; a claim equals it |
| hello | p2 `<var>` | `namen` | only in the message of a `die` on end of input: decorative, harmless |

The other 50 singletons land in options (ports, hosts, images, schedules,
command names), which is what any value of a one-instance configuration program
looks like. Landing site is a structural criterion, so a scope rule can exclude
these without naming any of them.

The two arms add these clause-landing singletons. Control: `<param>` (`x`, dead
`die` message, harmless) and `<ptype>` (`String`, dead `die` message, **the
defect**). Variant: `<fname>` (live, the undeclared-function check uses it),
`<param>` (dead `die` message, harmless) and `<arg>` (the call text, live).

Across corpus and arms, then: 14 clause-landing singletons (the variant's `<fname>`, bound by p1 and p2, counted once), 1 defect. The
exemption the diagnostic would need cannot be stated in the kernel's terms.
Three of the singletons sit in the same syntactic position, a string inside a
`die` message: `hello`'s `<var>` and the two arms' `<param>` are harmless there,
while the control's `<ptype>` is the defect. Telling them apart needs to know
that a TYPE word should govern behaviour and a variable name need not. That is
a fact about the domain, so a kernel rule would have to enumerate it, and the
kernel may not.

## What It Means for the Diagnostic

- Counting distinct values flags 14 holes to find 1 defect, and no domain-blind
  exemption narrows that. A per-line LSP warning at this precision is noise that
  authors learn to ignore.
- The defect that did occur is a word whose only landing is dead code. A sharper
  static question exists: does the word reach a clause position that some
  program can execute? But a dead branch is decided by Scheme semantics plus
  the grammar's reach, which is a reachability analysis rather than a count.
  That is recorded here as a direction, not a proposal.
- What would have caught the defect is plurality itself. A program declaring two
  functions of different types forces the type to select behaviour, and a claim
  observes it. The variant's own gap `one-declaration-per-program` says the
  grammar cannot hold two declarations today (the kernel gap
  `identifier-from-program`, TODO 7c), so that richer program is not yet
  expressible.

## Files

- `control/`, `single/`: the two programs and their minted language folders
  (`out/` derived, ignored).
- `probe.sh`, `probes.txt`: the offline edit probes and their output.
- `scan/Scan.hs`, `scan/corpus.txt`, `scan/mints.txt`: the singleton scan.
  Build: `ghc -Wall -ikernel/src experiments/plurality-function/scan/Scan.hs
  -outputdir /tmp/<dir> -o /tmp/<dir>/scan`, then run it over `examples/*.lips`.

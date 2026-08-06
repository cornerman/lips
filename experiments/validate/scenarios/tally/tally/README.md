<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `tally` language

This language describes a small line-oriented adding tool. A program states
what it reads, what it prints, what it ignores, what the command is called,
and one worked example. All five lines are required, and each is demanded by
name, so a program that drops one is refused with a question instead of
building a tool with a missing piece.

## The line shapes it accepts

- `read numbers, one per line, from standard input.` — fixes the input: a
  reader loop that pulls lines until input ends. No editable value here; the
  wording is fixed vocabulary, not a hole.
- `ignore a line that is not a number.` — fixes what a line has to be to
  count: a line that does not read as a number contributes nothing.
- `print their total when the input ends.` — fixes the result: sum the
  numbers collected, print it once, at end of input.
- `install the tool as the command <name>.` — the only editable word in the
  setup. Change `tally` here and the installed command name changes.
- `given the lines <a> and <b>, print <sum>.` — the worked example. All three
  numbers are holes; edit them and the checked observation changes with them.

## The mechanism

The behaviour is expressed as clauses, not as a baked source file, so every
definition is traceable to the line that asked for it:

- `numbers` (from the input line) reads with `read-a-line` until
  `end-of-input?`, keeping a line only when `number-of` gives a number.
- `number-of` (from the ignore line) is the "is this a number" decision; a
  non-number yields `#f` and the reader drops that line.
- `total` and `main` (from the print line) sum the collected list and print
  the result once with `emit`. `main` is the entry point.

The clauses are built into one executable; the install line names it via
`site.<self>.command` and puts that executable on the system PATH through
`environment.systemPackages`. No artifact and no wrapper script is minted —
the site is installed directly. The instance name (`tally.lips` → `tally`) is
used only as the site's key, never as the command name: the command name is
the program's word.

## What is pinned

The worked example becomes a claim, judged offline: the example's two input
lines are fed to the reader and the total is compared with the example's
stated result. The expect pins the third word of the example line (`5`) to
that claim's expected value, so a later re-mint cannot quietly drop or narrow
the author's example. Nothing else in the module holds a program value, so
there are no other expects: the command name lives in the site emit, which
is not an assertable module option.

## What I could not express

There is no way to observe the bytes a clause writes with `emit` from an
expression claim, so the example is checked as the total that `main` prints
rather than as the printed line itself. This is filed as a gap
(`emitted-output-not-observable`).

## Known Gaps

### emitted-output-not-observable

blocked line: print their total when the input ends.
an expression claim observes a returned value (call/equals); there is no way
to observe what a clause wrote with emit, short of a command claim on a built
binary. the witness is therefore stated as claim.sum.call "(total (numbers))"
with feed, which observes the total that main prints, not the printed bytes.
repro: feed [ "2" "3" ], call (main), and nothing can be compared.


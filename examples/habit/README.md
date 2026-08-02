<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language describes one small terminal tool that renders a habit log as a
row of characters, and builds it. A program of this language is compiled into a
Go program plus a home-manager module that puts the built command on your PATH
(`home.packages`); there is nothing to boot and no service, because the thing
described is a command you run yourself.

## The line shapes it reads

Four shapes carry values, and editing them changes the built tool:

- `mark a day the named habit was logged with "#".` -- the character printed for
  a day the named habit appears in the log. The quoted character is the value.
- `mark a day it was not logged with ".".` -- the character printed for a day it
  does not appear.
- `install the tool as the command habit.` -- the word after "the command" names
  the command. It becomes the Go module name (so the produced binary carries
  that name) and the derivation's pname, so renaming it here renames the command
  you type.
- `given the log of "2026-01-01" for "run", "2026-01-02" for "read" and
  "2026-01-04" for "run", the habit "run" prints "#..#".` -- the worked example.
  This is the only line that holds the tool to its words: it is compiled into a
  claim that actually runs the built binary in the build sandbox, feeding those
  three date/habit pairs on standard input as tab-separated lines and comparing
  what is printed byte for byte with the quoted output. This line must come
  *after* the install line: it reads the command name from it (it is an item of
  the block that line opens).

Five shapes are decorative -- they are the design of the generated source, not
values it can vary, so editing their wording changes no output at all:

- `track daily habits from the terminal.`
- `the first argument names the habit to print.`
- `read the habit log from the file named as the second argument, or from
  standard input when no file is named.`
- `each log line holds an ISO date and a habit name separated by a tab.`
- `print one character per day from the log's earliest date to its latest date.`

They are honest documentation of what the baked Go program does, and I kept them
readable rather than dropping them; but the argument order, the tab separator,
the ISO date format and the one-character-per-day span live in `main.go`. To
change any of them you must regenerate the language, not edit the program.

## What the built tool does

`main.go` reads the log from the named file or from standard input, splits each
line on the first tab into an ISO date and a habit name, takes the earliest and
latest date over *all* log lines as the span, and prints one character per day
in that span: the "logged" character when the queried habit was logged that day,
the "not logged" character otherwise, followed by a newline. Unparsable and
blank lines are skipped; an empty log prints an empty line. The two characters
reach the source as fills (`@mark_logged@`, `@mark_missing@`), and the command
name as the fill `@name@` in `go.mod` and in the usage message, so all three are
substituted offline at compile time.

## Choices I made, and what is pinned

The builder is `buildGoModule` with `vendorHash = null`: the source uses only
the Go standard library, so there is nothing to vendor. The version `0.1.0` is
mine -- the program says nothing about versions, and no sensible question could
ask for one. The derivation is keyed by the program's instance name (the file
name, `habit`), because the two mark lines must reach the same build and they
sit above the line that names the command, so they cannot borrow that word;
the command's *name*, though, is entirely governed by the program.

The contract checked on every future compile: the two marks and the command name
land in the fills that carry them into the source, and the example's expected
output is the claim's expected stdout. No expect names `home.packages`: it holds
a build reference, not a checkable value.

One limitation is filed as a gap: the witness line is fixed at three log
entries, because a claim's standard input is a single value and nothing in the
grammar repeats a chunk per entry. A two- or four-entry example will fail to
compile with "no pattern matched"; regenerating with such an example in hand is
the way to add it.

## Known Gaps

### fixed-arity-witness

blocked line: given the log of "2026-01-01" for "run", "2026-01-02" for "read" and "2026-01-04" for "run", the habit "run" prints "#..#".
the example log holds three entries, and a claim's stdin is one value with no
way to repeat a per-entry chunk: the pattern has to spell out exactly three
date/habit pairs. a witness with two or four entries would need its own
pattern, which is duplication a repeating-value construct would remove.


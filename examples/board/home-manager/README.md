<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

## What this language says

A board program is a handful of plain sentences describing a terminal kanban
printer. Eight line shapes are accepted:

1. `show a kanban board in the terminal.` -- a decorative heading; it realizes
   nothing.
2. `read the board from the file named on the command line, or from standard
   input when no file is named.` -- declares where the board text comes from.
3. `the board is markdown: a "## name" line opens a column and a "- text" line
   under it is one of its cards.` -- both quoted markers are holes. The first
   word of each marker (`##`, `-`) is what the built program tests each input
   line against, and the rest of the line is the column name or card text. Write
   different markers and the parser changes with them.
4. `the board has the columns "todo, doing, done".` -- a hole: the comma-separated
   column names, in print order. Columns are printed in exactly this order,
   whether or not the input mentions them.
5. `print one line per column: its name, a colon, a space, then its cards joined
   with ", ".` -- the join text is a hole; the `name: ` prefix is fixed wording.
6. `a column with no cards prints its name and the colon only.` -- fixes the
   empty-column form; it has no editable value.
7. `install the tool as the command board.` -- a hole: the command name that
   lands on the user's PATH.
8. `given the lines "...", ... and "...", print the lines "...", "..." and "...".`
   -- the worked example, turned into a claim that runs the whole program
   offline: the input lines are fed to it and its printed lines are compared
   exactly.

## Mechanism

The behaviour is minted as CLAUSES, not as a source file: `main` reads every
input line, splits the declared column list, collects each column's cards from
the parsed lines, and emits one rendered line per column. Nothing else is
invented -- each clause traces back to the sentence that asked for it.

The whole thing is installed by naming a site: `site.<self>.command` takes the
command name from sentence 7, and `home.packages` gets `${site}` itself, so the
tool appears on the user's PATH with that name. No systemd unit is created:
this is a command a person runs, not a service.

## What I could not do (two gaps filed)

* There is no contract that opens a FILE, so sentence 2 is honoured only for
  standard input (`board < file.md` works; `board file.md` ignores the name).
  That rule carries reduced confidence for exactly this reason.
* The worked example states five input and three output lines inside one
  sentence, so its pattern fixes those counts. Editing the example to a
  different number of lines will need a fresh mint. Freeing it would need an
  aggregating form for a claim's expected value, which the grammar has not.

## Contract

The expects pin the example: the input lines reach the claim's feed and the
expected lines reach the claim's comparison, both verbatim, so a later mint that
quietly narrows or drops the author's example is refused.

## Known Gaps

### no-file-contract

blocked line: read the board from the file named on the command line, or from standard input when no file is named.
no contract opens a file: read-a-line reads standard input only, and arguments
merely hands back the words. minimal repro: a program stating "read from the
file named on the command line" can only be realized as a standard-input
reader, so the file half of the sentence governs nothing.

### fixed-witness-count

blocked line: given the lines "## todo", "- milk", "- eggs", "## doing" and "- taxes", print the lines "todo: milk, eggs", "doing: taxes" and "done:".
the example states its input and output lines inside ONE sentence, so the
pattern needs one hole per item and thereby fixes the counts at five input and
three output lines. a block would free the input side (one one-element list per
line, aggregated into claim.feed), but claim.equals is a single expression and
has no aggregating form, so the output side cannot be freed at all. repro: add
a sixth input line to the sentence and no pattern matches it.


<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

This language describes a small terminal kanban board printer, and every
sentence of `board.lips` is read by the engine you already have; this mint
changes no pattern and no rule. It adds the report (which the committed
engine was missing) and files one capability gap that the corpus makes
visible.

**The line shapes it accepts**, in the order the program states them:

- `show a kanban board in the terminal.` — a heading, decorative only: it
  names what the program is and realizes nothing.
- `read the board from the file named on the command line, or from standard
  input when no file is named.` — fixes the input mechanism; it realizes the
  line-reading clause (`board-read-lines`, built on the `read-a-line` and
  `end-of-input?` contracts).
- `the board is markdown: a "## name" line opens a column and a "- text"
  line under it is one of its cards.` — the two markers are holes, so
  changing `##` to `###` or `-` to `*` changes the parser. They become the
  clauses that classify a line and cut a card's or a column's text off its
  marker.
- `the board has the columns "todo, doing, done".` — the column list, and
  its ORDER, is one value; a clause splits it on commas and trims spaces, so
  reordering or adding a column is a one-word edit.
- `print one line per column: its name, a colon, a space, then its cards
  joined with ", ".` — the joiner is a hole; the rest of the format (name,
  colon, space) is fixed wording of this language.
- `a column with no cards prints its name and the colon only.` — selects the
  empty-column rendering.
- `install the tool as the command board.` — the command name is a hole; it
  becomes `site.<self>.command` and the built program is put on the user's
  PATH through `home.packages`.
- `given the lines ..., print the lines ...` — the worked example. It is the
  only observable: it becomes a claim that feeds those input lines to the
  program and compares, byte for byte, what it prints.

**Mechanism.** The behaviour is expressed as clauses (a small Scheme
subset), not as a source file, so every definition is traceable to the
sentence that asked for it, and the whole program is checked offline by the
claim. Nothing is written to disk, no service and no timer is created: the
result of a program in this language is one executable, named by the
`install the tool as the command ...` line, installed into the user's
profile. There is no NixOS-level option anywhere; `home.packages` and the
site are the whole footprint.

**What it cannot yet do** (see the gap below): the example sentence has a
fixed shape of five input lines and three printed lines. Editing the example
to a board of a different size needs a fresh mint. Everything else in the
program — markers, columns, joiner, command name — is a hole and flows
through the engine you already have.

## Known Gaps

### fixed-example-arity

blocked line:
  given the lines "## todo", "- milk", "- eggs", "## doing" and "- taxes",
  print the lines "todo: milk, eggs", "doing: taxes" and "done:".

The input side of this example could be read with a list hole plus an item
pattern, so that claim.board.feed aggregates one element per line at any
count. The OUTPUT side cannot: claim.<id>.equals takes a single expression,
not a list-typed option, so a per-item rule cannot contribute one expected
line each and there is no way to assemble (list "a" "b" ... ) from a variable
number of decisions. Making only the feed general and leaving the expected
output pinned at three would be worse than the present symmetry, so pattern
p8 still fixes 5 input lines and 3 output lines and an author who wants a
bigger example must regenerate.

minimal repro: a program identical to board.lips but whose example feeds six
lines fails to crystallize under p8.

what would fix it: a list-accepting claim section for the expected output
(e.g. claim.<id>.equals-lines, aggregating one element per contributing
decision exactly as claim.<id>.feed already does).


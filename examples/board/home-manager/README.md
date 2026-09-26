<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

This mint changes only how the EXAMPLE sentence of a board program is read --
the last line, which states an input board and the lines it must print.
Everything else about the language is exactly as it was: the same seven line
shapes, the same subjects, the same clauses, the same site installation.

## What was wrong

The example line used to be read by a pattern with one hole per item: five
input lines and three printed lines, no more and no fewer. Adding a card or a
column to the example matched no pattern at all, so extending an example --
the cheapest and most useful edit an author can make -- cost a whole new
engine. The printed side was frozen twice over, because the rule wrote all
three expected lines into a single `equals` expression.

## What it reads now

The sentence is read with two LIST holes, cut on commas and on the word
"and":

    given the lines A, B and C, print the lines X and Y

Any number of input lines and any number of printed lines is read by the same
sentence. Items may be quoted, which is what lets a line contain a comma
(`"todo: milk, eggs"` stays one item); the quotes are not part of the value.

Each input item becomes its own fact `witness.feed.<position>` and each
printed item its own `witness.out.<position>`, so the order of the sentence is
the order of the claim. The rules contribute one element each:
`claim.board.feed` gets one fed line per input item, and the expected output
now uses `claim.board.equals-lines` -- one expected line per printed item --
instead of one frozen `equals` expression. Repeats are kept: two identical
cards in the example are two fed lines.

## Ids that changed, and why

- `p8`: rewritten from fixed holes to two list holes; it now also emits a
  constant `witness.example` fact, which is simply "there is an example here".
- `r8`: contributes one fed line per input item instead of all five at once.
- `r9`: now `claim.board.equals-lines`, one expected line per printed item,
  instead of `claim.board.equals` with a fixed three-element list.
- `r10` (new): states the claim's call, `(begin (board-main) (emitted))`, once
  for the example as a whole. It is its own rule precisely because the call
  must be stated once, not once per line.
- `q5`, `q6`: same questions, re-stated so their subjects match the new
  per-item subjects.

Patterns `p9`/`p10` from an intermediate attempt are gone: this engine was
re-submitted whole rather than patched, since a patch cannot remove a line.

## What I could not do

I first read each quoted item with its own item pattern, one per list. lips
refused that: the two item patterns have the same shape (a single item), and
orthogonality is judged across all patterns rather than within the list each
one reads. See the gap below. The working form reads the items directly from
the list holes, which is fine here because every item of both lists is a plain
quoted line.

Nothing was invented: every fed line and every expected line still comes
verbatim from the author's own sentence. As before there are no `expect`
lines -- every program value lands in a clause or in a claim section, which
the claim gate checks by running the program, and an expect over a claim slot
would only restate the rule that fills it.

## Known Gaps

### item-pattern-orthogonality

blocked line: given the lines "## todo", "- milk" and "- taxes", print the lines "todo: milk", "doing:" and "done:"

wanted, to read each item of each list with quotes dropped:
  p8 pattern given the lines <l.list:,|and> print the lines <o.list:,|and> => concept w "an example"
  p9.each.p8.l pattern "<line>" => fact witness.feed.<n:index> "<line>"
  p10.each.p8.o pattern "<printed>" => fact witness.out.<n:index> "<printed>"

refused with: "patterns p9 and p10 both read the line <line>". Two item
patterns that read items of DIFFERENT list holes of the same parent can never
both read one item, yet they are judged against each other as if they read
whole lines. Item patterns should be orthogonal only within the hole they are
declared for.

second, smaller issue met on the way: writing the comma the sentence actually
contains directly after a list hole, as the documentation's own example does --
  given the lines <l.list:,|and>, print the lines <o.list:,|and>
-- makes the hole stop being a list hole ("pattern p9 reads an item of <l> in
p8, which binds no list hole of that name"). The comma had to be dropped from
the template and absorbed as a separator instead.


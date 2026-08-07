<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `chunk` language

This language describes a small line-chunking filter: it reads lines, prints
them in fixed-size groups joined by one mark, prints whatever is left over when
the input ends, and installs itself on the machine under a command name.

## The lines it accepts

- `read lines from standard input.` -- the input side. "standard input" picks
  the reading mechanism (the `read-a-line` contract), so it stays a fixed word
  of the pattern rather than a hole; it is the only input this language can
  wire today. Drop the line and compilation asks for it.
- `print them in groups of three, joined by commas.` -- two editable values in
  one sentence: the group size and the joiner, both written as English words.
- `print a short last group when the input runs out.` -- says a partial final
  group is printed rather than dropped. It carries no value of its own, but it
  is what puts the flush clause into the program, so it is a real line and not
  decoration: leave it out and compilation asks what should happen to the tail.
- `install the tool as the command chunk.` -- the command name is a hole, so
  renaming the command is a one-word edit.
- `given the lines a, b, c and d, print a,b,c then d.` -- the worked example.
  This is the line that is actually executed: the four words on the left are
  fed to the program as four input lines, the program runs end to end, and
  everything it printed must equal exactly the two groups on the right of
  "print".

## What it builds

The behaviour is clauses, not a baked source file. `main` loops over the input
with a pending group and a counter (`chunk-loop`), appending each line with
`add-last`; when the group is full it prints it with `emit-group`/`join-with`,
and at end of input `finish` prints whatever is pending, or nothing when the
input divided evenly. Each of those definitions traces back to one sentence:
the loop to the input line, the joining and the size to the "groups of three"
line, the flush to the "short last group" line.

The size and joiner words reach the clauses through two lookup definitions,
`count-named` ("three" -> 3) and `mark-named` ("commas" -> ","). Those tables
are the one thing I had to invent, and I would rather you knew than found out:
lips values cannot convert a word to a number or to a character, so the words
are carried into the program as text and translated there. The tables cover
one through ten and the common punctuation names (commas, semicolons, spaces,
pipes, dashes, singular or plural). A word outside them stops the tool with a
named error the first time it runs, instead of failing at compile time. That is
filed as the gap `word-valued-number`. If you would rather have compile-time
failure, write the size and joiner as literals in a future language instead.

The clauses are built into one executable. Its name comes from your own word in
the "install the tool as the command" line (`site.<self>.command`), and the
executable is put on the system PATH through `environment.systemPackages`.

## The example, and its limit

The example sentence is read with one hole per input line, so it reads exactly
four example lines and exactly two printed groups. This is a real limitation,
filed as the gap `inline-list-in-sentence`: a list of examples would normally be
written one per line under a heading, where any number works, but this program
states them inline in a single sentence and no rule can split a captured phrase
into a list. Changing the number of example lines means minting the language
again; changing the example *words* does not.

## What is pinned

Every word of the example is pinned individually: the four input lines to the
claim's input, and the two expected groups to what the claim compares against.
So the contract cannot be quietly narrowed by a later mint. Two things are not
pinned by an expect and are governed by their rules alone: the package list
(it holds a build reference, which the behavioural check cannot read) and the
command name on the site (not a module option, so there is nothing to assert
against in the realized configuration).

## Known Gaps

### inline-list-in-sentence

blocked line: given the lines a, b, c and d, print a,b,c then d.
the sentence states its example input as an inline list, but a rule's rhs
cannot split a captured phrase into a list of strings, and a block needs the
items on their own lines. so the template must bind one hole per item and is
frozen at four example lines; a program giving three or five of them no longer
crystallizes.

### word-valued-number

blocked line: print them in groups of three, joined by commas.
"three" must reach a claim as the number 3 and "commas" as the character ",".
the value grammar has no word-to-number or word-to-character conversion, so the
engine ships lookup clauses; a word outside those tables fails when the tool
runs instead of when the program is compiled.


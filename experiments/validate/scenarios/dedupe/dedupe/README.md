<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `dedupe` language

This language describes a small line-filtering tool: it reads standard input,
prints each distinct line once, and finishes with a summary line counting what
it dropped.

## The four sentences it accepts

1. `read lines from standard input and print each line the first time it
   appears.` -- the core behaviour. It is fixed wording with no editable value
   in it; it is what turns on the dedupe loop.
2. `count how many lines were dropped and print that count last, as a line
   reading "dropped N".` -- the quoted text is a hole: it is the summary line,
   with the capital letter **N** standing for where the number goes. Write
   `"skipped N duplicates"` and that is what the tool prints.
3. `install the tool as the command roster.` -- the last word is a hole: it is
   the name the command gets on the machine.
4. `given the lines "a", "b" and "a", print a, b and dropped 1.` -- the worked
   example. The three quoted values are the input lines, the three values after
   `print` are the exact output lines, in order.

## What is built

The behaviour is minted as clauses, not as a source file, so every definition
is traceable to a sentence above:

- `seen?` and `dedupe-loop` (from sentence 1) read a line at a time, print it
  the first time it is seen, and count the repeats.
- `summary-line` (from sentence 2) builds the final line by cutting your quoted
  text at the first `N` and putting the number in that spot; if the text has no
  `N`, it is printed unchanged.
- `main` runs the loop and prints the summary last.

Sentence 3 installs that program: `site.<self>.command` names the executable
after the word you wrote, and the site derivation goes into
`environment.systemPackages`, so the command is on every user's PATH machine-
wide. The site is keyed by `<self>`, the program's own file name, so two such
programs can live in one configuration.

Sentence 4 becomes a claim, checked offline on every compile: the three lines
are fed to the program, `main` runs, and everything it printed must equal the
three lines you named, exactly. That claim is the only thing holding the minted
code to your sentences, which is why the example is demanded rather than
invented -- a program without it is sent back rather than guessed at.

## What I chose, and what I could not pin

- **N as the placeholder.** The program says the line reads `dropped N` but
  never says how the number is marked. I read the first capital `N` in your
  quoted text as the number's slot. Confidence on that rule is lowered for
  exactly that reason.
- **No expect on the command name.** The behavioural contract can only assert
  values that land in checkable slots; the command name reaches a site and a
  package list, which are derivations and carry no readable value. The two
  expects pin the claim instead -- the input the example feeds and the output
  it must produce.
- **The example is fixed at three lines in and three lines out.** That is a
  limit of the pattern grammar, filed as the gap `fixed-arity-witness`. An
  example of a different size, or a second example in one program, needs a
  fresh mint.

## Known Gaps

### fixed-arity-witness

blocked line: given the lines "a", "b" and "a", print a, b and dropped 1.
the example is read by a pattern with exactly three input holes and three
output holes. a program whose example feeds two lines, or four, matches no
pattern and needs a fresh mint. a repeating item inside ONE line has no hole
form: a multi-token hole binds a phrase, but nothing splits it into a list,
and a rule may not compute one. the same limit would bite a program that
wanted several worked examples, since a second such line would collide on the
subjects example.input / example.output.


<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `threshold` language

This language describes a small tool that filters lines of standard input. The
behaviour is minted as clauses (small named definitions), not as a source file,
so every definition is traceable to the sentence that asked for it, and the
example the program states is checked offline on every future compile.

## The sentences it reads

- `read lines of a name and a number, separated by a space, from standard input.`
  fixes the input shape. It mints the clause that cuts each line at its first
  space. Nothing in this sentence is a hole: a different input shape is a
  different tool, and the line would stop matching and ask for a fresh language
  rather than quietly govern nothing.
- `print the name of every line whose number is above <limit>.` The number is a
  hole -- edit it and the built tool changes. This sentence mints the read loop:
  read a line, parse it, print the name when the number is above the limit,
  repeat to end of input.
- `fail, naming the line, when a line has no number.` mints the parsing clause.
  A line with no space, or whose second field is not a number, stops the program
  with `die`, naming the offending line.
- `install the tool as the command <name>.` The command name is a hole. It names
  the site's command and puts the built program on the machine's PATH through
  `environment.systemPackages`. The site is installed as itself, never wrapped.
- `given the lines "<a>" and "<b>", print only <out>.` is the author's example.
  It becomes a claim: those two lines are fed to the program, `main` runs, and
  what the program printed must equal exactly the stated output -- so the
  threshold sentence is held to the behaviour the author described, not merely
  to the text of a clause.

Every one of the five sentences is demanded: a program missing one is refused
with a question instead of compiled into a tool that cannot run, since the
clauses depend on one another (the loop calls the parser, the parser calls the
splitter).

## What I had to supply

- The failure message text (`line has no number:` followed by the line). The
  program says to fail naming the line but not what to say.
- The test for "has no number": the standard `string->number`, since no contract
  offers a numeric test. A field that does not read as a number fails the line.

## What the contract pins

`alert.threshold.expect` pins the example: the input lines reach the claim's
feed and the expected output reaches the claim's comparison. The threshold and
the command name land inside a clause and inside the site's name respectively,
neither of which is a module option holding a checkable value, so no expect
names them -- the claim is what holds the threshold, and the install rule is
the whole contract for the command name.

## Known gap

The failure sentence is minted but unobserved: the program states no example of
a bad line, and an example may not be invented. See the filed gap
`failure-witness-missing`.

## Known Gaps

### failure-witness-missing

blocked line: fail, naming the line, when a line has no number.
the program gives an example only for the printing path ("db 250" / "web 40" -> db),
so the failure path is minted but never observed. an example may not be invented,
and this language has no line shape in which the author could state one, e.g.
  given the line "db", fail naming it.


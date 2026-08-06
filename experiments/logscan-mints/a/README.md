<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes one line filter: a program that reads JSON lines,
keeps the ones matching field=value arguments, and prints them. It is minted
as clauses (small definitions in lips' Scheme subset), not as a source file,
so every definition is traceable to the sentence that asked for it.

## The lines it reads

* `filter JSON lines read from standard input.` -- defines `scan`: read a
  line, stop at end of input, parse it as JSON, ask `keep?` about it, and
  hand a kept line to `show`. `scan` returns the list of lines it kept, which
  is what the example below is checked against.
* `keep a line only when every field named on the command line equals the
  value given with it.` -- defines `parse-spec` (cut each argument at its
  first `=` into a field name and a required value; an argument without `=`
  stops the tool with an error naming the tool) and `keep?` (every pair must
  match, so no arguments keeps every JSON line, and a line that is not JSON
  is never kept).
* `print each kept line unchanged.` -- defines `show`, which emits the line
  text exactly as it was read.
* `install the tool as the command <name>.` -- the name is a hole: it becomes
  the tool's own name in its error message, and this line also defines the
  entry point `main`, which turns the command-line arguments into a spec and
  runs `scan`.
* `given the lines <l1> and <l2> with <args>, print only <out>.` -- the
  example. It becomes three observations, run offline: the first line is
  kept, the second is not, and running the whole tool over both lines with
  those arguments returns exactly the stated output line.

Only the command name and the example's values are holes. The other three
sentences select mechanism rather than carry a value -- there is exactly one
contract that reads input, one that parses JSON, one that writes output -- so
they must be written in these words, and each is demanded: a program missing
one gets a question instead of a broken build.

## What I had to decide

* Values are compared as text: `a=1` matches `{"a":"1"}` but not `{"a":1}`,
  because the argument side is always text.
* A line that does not parse as JSON is dropped rather than reported; the
  program says which lines to keep, not what to do with malformed input.
* No expect names the example's JSON: the contract checker compares the raw
  words of the program against the realized text, where the quotes inside
  the JSON are escaped, so such an expect could never hold. The claims cover
  those values instead -- they run the clauses on them. The expects pin the
  argument text into all three claims, so dropping the example is refused.
* Two things this world cannot express are filed as gaps below: nothing
  installs the program under the stated command name, and no contract hands
  the entry point the command line it is meant to read.

## Known Gaps

### clause-program-not-installable

blocked line: install the tool as the command logscan.
a program built from clauses has no reference form: ${clause.logscan} is
refused by the value grammar and no artifact builds it, so no NixOS option
(environment.systemPackages or otherwise) can put it on PATH under that name.
the command name reaches only the tool's own error text.

### no-argv-contract

blocked line: keep a line only when every field named on the command line equals the value given with it.
no contract yields the command-line arguments. main takes them as a parameter
and depends on the adapter calling it with them; a clause cannot ask for argv
itself, so nothing here can be observed about the real command line.


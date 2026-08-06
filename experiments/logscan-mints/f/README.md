<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes one small command-line filter, in five sentences, and
turns them into behaviour clauses that are built into a single executable and
put on the machine's PATH. No systemd unit, no source file: the whole result is
a program you run, so the mechanism chosen is the clause site plus
`environment.systemPackages = [ site ]`.

## The line shapes it accepts

- `filter JSON lines read from standard input.` -- the input side. Defines the
  entry point `main` and the reading loop `scan`, which reads one line at a
  time until end of input and collects the ones that are kept. "JSON" and
  "standard input" pick the mechanism (the `json-parse` and `read-a-line`
  contracts), so they are fixed words, not holes.
- `keep a line only when every field named on the command line equals the value
  given with it.` -- the criterion. Defines `parse-spec` and `parse-pair`
  (each command-line word is cut at the first `=` into a field name and a
  value), `matches?` (every named field of the record equals its given value;
  an empty command line keeps everything) and `keep?` (parse the line as JSON,
  then match).
- `print each kept line unchanged.` -- the output side. Defines `emit-all`,
  which writes each kept line, verbatim, on its own line, and returns them.
- `install the tool as the command <name>.` -- the only ordinary value in the
  program. The word after "command" is a hole: it names the installed command
  and the executable that carries it. Rename it in the sentence and the
  installed command is renamed.
- `given the lines <a> and <b> with <fields>, print only <c>.` -- a worked
  example. This is not documentation: it becomes a claim that is actually run,
  offline, at every compile. The two lines are fed to the program's input, the
  field spec becomes its command line, `(main)` is called, and the lines it
  printed must be exactly the one the sentence names.

Both the command name and the example are demanded: a program that leaves
either out is sent back with the question rather than compiled with a guess.

## What I had to choose

- **Lines that are not JSON are dropped.** The program says it filters JSON
  lines but never says what an unparseable line should do. `keep?` treats it as
  not kept. This is the one policy no sentence asked for, so the rule carrying
  it is minted at low confidence; one more sentence (drop them, or stop with an
  error) would pin it.
- **A command-line word with no `=` stops the program**, naming the offending
  word, rather than being silently ignored -- the sentence says every field is
  named "with the value given with it", so a word carrying no value is not a
  filter the program can honour.
- **Input is read to the end, then printed.** The clause split follows the
  sentences (reading is one line's clause, printing another's), so the tool is
  not streaming. For a log filter fed a file this is invisible; for an endless
  pipe it would matter, and a sentence about printing as it goes would be a
  reason to re-mint.

## What is pinned

The claim is the real contract here: it runs the whole program on the author's
own example and compares the printed lines byte for byte. Beside it, one expect
pins the example's field spec (`a=1`) into the claim's command line. The other
captured values (the JSON lines) are pinned by the claim itself rather than by
an expect: lips' contract check compares plain text, and those values contain
quotes that are escaped in the realized module, so an expect on them would
report a false mismatch. The installed command name is carried by the site
rule, which is its own contract -- there is no checkable option value behind it.

## Known Gaps

### witness-line-count

blocked line: given the lines {"a":"1"} and {"a":"2"} with a=1, print only {"a":"1"}.
the witness pattern has to fix the number of input lines (two) and of printed
lines (one): a claim's feed is a list value, and no hole repeats to build a list
from a variable-length phrase ("the lines A, B and C"). a program that wants a
three-line example needs a fresh mint.


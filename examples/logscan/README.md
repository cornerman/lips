<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes one small filtering tool: it reads lines on standard
input, keeps the ones matching `field=value` pairs given on its command line,
prints the survivors, and installs itself as a named command on the machine.

## The five line shapes

1. `filter JSON lines read from standard input.` — the input side. It has no
   holes: reading a line at a time and parsing it as JSON is exactly what the
   available contracts (`read-a-line`, `end-of-input?`, `json-parse`) do, so
   the sentence selects a mechanism rather than carrying a value. It realizes
   the two driver clauses, `main` and `run` (the read loop).
2. `keep a line only when every field named on the command line equals the
   value given with it.` — the decision. It realizes `keep?` (all pairs must
   match) and `matches?` (split one argument at the first `=`, look the field
   up in the parsed record, compare the values).
3. `print each kept line unchanged.` — the output side. It realizes
   `consider`, which parses a line, asks `keep?`, and on a yes emits the
   ORIGINAL text, never a re-serialized record — that is what "unchanged"
   buys you.
4. `install the tool as the command <name>.` — the only configuration value in
   the language. The name is a hole: it becomes the site's command name and the
   built program goes onto `environment.systemPackages`, so the machine has
   `logscan` on PATH. Rename it in the sentence and the installed command
   renames with it.
5. `given the lines <a> and <b> with <args>, print only <c>.` — the author's
   worked example. All four words are holes: the two input lines are fed to the
   program, `<args>` becomes its command line, and `<c>` is the single line it
   must print. This compiles to a claim that runs the whole program offline and
   compares what it printed, so the sentences above are held to the behaviour
   they describe rather than merely to some text in a module.

## What I chose, and what I had to invent

Behaviour is minted as clauses, not as a source file, so every definition is
traceable to the line that asked for it: five clauses, five short definitions,
no policy beyond them. The program is installed through a `site` (no wrapper
script), which is what puts one executable named by line 4 into the system
profile.

Two things the program is silent about, decided rather than demanded:

- a line that is not JSON is simply not kept (it has no fields to match), and
  filtering continues with the next line;
- an argument with no `=` in it stops the program with `die`, naming the bad
  argument, instead of being silently ignored.

## Contract

The claim is the real contract here: it feeds the two example lines, passes the
example arguments, and requires the emitted output to be exactly the one line
the program names. Beside it, one expect pins the example's argument list into
`claim.filter.args`. The JSON-bearing parts (the fed lines, the expected output)
carry no expect of their own: they are re-quoted as Scheme string literals when
realized, so a literal-containment expect on them can never hold — the claim
already observes them byte for byte, which is stronger.

The `site.<self>.command` value cannot be asserted by an expect either (it is
not a module option that evaluation can read back); rule `r4` is its whole
contract.

Every line shape is demanded, so a program missing any of the five fails with a
plain question instead of a dangling clause name. One example line per program:
a second `given ...` line would set the same claim twice and lips refuses it
loudly.

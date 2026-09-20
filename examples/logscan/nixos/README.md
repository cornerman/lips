<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This is the `logscan` language: a handful of plain sentences describing a
JSON line filter, realized as behaviour clauses (no source file) plus one
installed command.

The line shapes it accepts, and what each means:

- `filter JSON lines read from standard input.` -- fixes where input comes
  from. It mints the entry point `logscan-main` and the read loop
  `logscan-run`, which reads a line at a time until end of input.
- `keep a line only when every field named on the command line equals the
  value given with it.` -- the keep policy, `logscan-keep?` together with
  `logscan-matches?`. Each command-line argument is cut at `=` into a field
  name and a value; a line is kept only when every one of them matches the
  parsed record. An argument that is not `field=value` stops the program
  loudly, naming the offending argument.
- `print each kept line unchanged.` -- `logscan-consider`: parse the line,
  test it, and on a match emit the ORIGINAL text, not a re-serialization.
  A line that is not JSON is silently skipped.
- `install the tool as the command <name>.` -- the command name. The built
  site is named after that word and put on the system PATH via
  `environment.systemPackages`; no wrapper is built around it.
- `given the lines A and B with ARGS, print only OUT.` -- the author's
  worked example. It becomes an offline claim: the two lines are fed to the
  program, ARGS becomes its command line, `logscan-main` runs, and
  everything it printed is compared with OUT exactly.

Mechanism: behaviour lives in clauses rather than in a baked source file, so
every definition traces back to one sentence and the example is checked
without building a binary or booting a machine. Nothing runs as a service,
so no unit and no boot-observed claim are involved -- the whole behaviour is
the command, and the claim observes it end to end.

What this re-mint changed: nothing in the engine itself. No pattern, rule or
demand was touched, so every program that compiled before compiles the same
way. What is new is this report, one expect (`a2`, pinning the example's
command-line arguments into the claim that runs the program), and two filed
gaps.

The two gaps are the checks I wanted and could not write:

- the installed command name reaches `site.<self>.command`, and an expect
  over that slot is refused ("nothing realizes this slot"), so that word is
  pinned by no contract;
- the example's expected OUTPUT cannot be asserted either, because the
  value's own quotes are escaped in the realized claim text but not in an
  expect's is-text, so a JSON example can never compare equal.

The claim itself still runs the example on every compile, which is the real
guard here; the gaps are about the contract that would survive a future
re-mint.

One known limitation, left in place deliberately: the example pattern `p5`
reads exactly TWO input lines (`the lines A and B`). An example with one or
three lines does not crystallize. The grammar can express the general form
(a list hole, one fed line per item, keyed by position), but doing so
renames the `witness.filter` subject the committed contract is written
against, and a mint may not break a standing contract on its own authority.
If you want examples of any length, edit the example line and run
`lips generate examples/logscan.lips`; that re-mint can move the subject and
rewrite the contract with your consent.

## Known Gaps

### unassertable-site-command

blocked line: install the tool as the command logscan.
The command name is the one program value in this language that reaches a
module-side slot (site.<self>.command), but an expect over it is refused:
"site.<self>.command: nothing realizes this slot". So the word that names
the installed command is pinned by no check at all, and a later mint could
key the site off the filename with every gate still green.
minimal repro:
  0.95 a1 expect site.<self>.command from tool.command

### expect-quoting-mismatch

blocked line: given the lines {"a":"1"} and {"a":"2"} with a=1, print only {"a":"1"}.
The rule emits claim.filter.equals "(list \"#<value.4>\")", and the realized
value is (list "{\"a\":\"1\"}") -- the substituted value's own quotes are
escaped for the surrounding Nix string. An expect's is-text substitutes the
raw value instead, so the two can never be equal for any value containing a
quote, and the expected output of a JSON example cannot be asserted.
minimal repro:
  0.9 a3 expect claim.filter.equals from witness.filter is "(list \"<value.4>\")"
  -> should be (list "{"a":"1"}"), but is (list "{\"a\":\"1\"}")


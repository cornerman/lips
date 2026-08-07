<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `tally` language

This language describes a small stdin-summing command-line tool built
entirely from Scheme clauses (no source files).

Line shapes it reads:
- "read numbers, one per line, from standard input." names the read loop.
- "print their total when the input ends." names when the total is printed.
- "ignore a line that is not a number." names the non-numeric-line policy.
- "install the tool as the command X." names the executable; X is the one
  value these three fixed sentences leave for the human to state, so a
  program omitting it is asked for a name.
- "given the lines A and B, print C." is the program's own worked example.

The three fixed behaviour sentences carry no varying word of their own --
every program in this language states the same algorithm -- so each compiles
to one Scheme clause: parse-line (a line becomes a number or #f),
sum-loop (reads lines through the read-a-line/end-of-input? contracts,
adding numbers and skipping non-numbers), and main (prints the total
through emit). Because their text never varies, two programs of this
language agree on these clauses word for word, so nothing collides when
more than one is compiled together.

The command name is installed as a site: the clauses are built into one
executable named by "install the tool as the command X", and that
executable is put on PATH. The example line becomes a claim: it feeds A
and B to the tool as input lines and checks that what main() prints
equals C, so the baked Scheme stays honest to the sentence that specifies
it.

One thing I could not pin with an expect: the command's own name
(site.<self>.command) only parametrizes the built derivation -- like a
package name -- and the module contract has no evaluable slot to check it
against, the same reason a package or build option gets no expect. Its
value is still real and rule-driven; it is simply not independently
observable the way the claim's feed and equals values are.

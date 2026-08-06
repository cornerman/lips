<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes a small command-line filter over JSON lines, and it
is written as behaviour: the sentences become clauses (named definitions),
not a source file, and the clauses are built into one executable that the
machine installs system-wide.

## The lines it reads

1. `filter JSON lines read from standard input.` — sets up the reading loop:
   read a line, parse it as JSON, decide, repeat until input ends
   (clauses `main` and `scan`).
2. `keep a line only when every field named on the command line equals the
   value given with it.` — the decision itself (clauses `keep?`,
   `parse-spec`, `parse-pair`). The command line is read as `field=value`
   words; a line is kept when every one of them matches the field of that
   name in the parsed record.
3. `print each kept line unchanged.` — what happens to a kept line (clause
   `print-kept`: the original text, byte for byte, not a re-serialization).
4. `install the tool as the command <name>.` — the only editable word in the
   first four lines. It names the built executable and puts it on the
   machine's PATH through `environment.systemPackages`.
5. `given the lines <one> and <other> with <args>, print only <kept>.` — a
   worked example, which becomes two observations that are re-checked on
   every compile: filtering those two lines with those arguments yields
   exactly the stated line, and the stated line is one `keep?` says yes to.

Sentences 1–3 carry no editable word: "JSON", "standard input" and
"unchanged" select the mechanism (which parser, which input contract, what
gets printed), so they are fixed words of the pattern. Changing them stops
the line matching, which is the honest outcome — a different decision needs
a different language, not a silently ignored word. The command name and the
four words of the example are holes, so those you may edit freely.

## What I had to choose

The program does not say what happens to a line that is not JSON, nor to an
argument with no `=` in it. I dropped the non-JSON line silently (it is not
a line the filter can judge) and made a malformed argument stop the tool
loudly with `argument is not field=value:`. Say either of these in the
program if you want them different, and regenerate.

Comparison is textual: `a=1` matches the field `a` whose value is the string
`"1"`, not the number `1`. This follows the example given.

`filter-lines` exists to make the example observable as a whole run over a
list of lines; the installed tool streams through `scan` instead, using the
same `keep?` and `print-kept`.

## Limits worth knowing

One example line per program: a second `given ...` line would state the same
subject twice and be refused as a conflict. Both the command name and the
example are demanded, so a program that omits either is sent back with a
question rather than compiled against a guess. The contract file pins the
example's argument text where it reaches the observations; the command name
is carried by the site emit that names the executable.

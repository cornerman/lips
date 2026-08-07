<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes one small stream filter: what it reads, what it keeps,
what it prints, what the command is called, and one worked example. Five line
shapes, in the order the program writes them.

**`filter JSON lines read from standard input.`** -- the input side. The tool
reads standard input one line at a time until input ends.

**`keep a line only when every field named on the command line equals the value
given with it.`** -- the decision. Each command-line argument is `field=value`;
a line is kept when every one of those fields, looked up in the parsed record,
equals the value written beside it.

**`print each kept line unchanged.`** -- the output side. A kept line is written
back out verbatim, as it arrived, not re-serialized from the parsed record.

**`install the tool as the command <name>.`** -- the only varying word here is
the command name, so it is a hole: renaming the command is a one-word edit and
needs no new language.

**`given the lines <a> and <b> with <args>, print only <out>.`** -- the worked
example. It is the observable: the two lines are fed to the program, its
arguments are set to what the sentence says, the program runs, and what it
printed must equal exactly the one line the sentence names.

## What it builds

The behaviour is minted as clauses, not as a source file, so every definition
is traceable to the sentence that asked for it:

- from the input sentence: `main` and `scan` -- read a line, consider it, go on
  until end of input (contracts `arguments`, `read-a-line`, `end-of-input?`);
- from the keep sentence: `parse-specs` and `parse-pair` (split each argument at
  the first `=` with `string-cut`), `keep?` (parse the line with `json-parse`)
  and `matches?` (compare each named field with `field-of`);
- from the print sentence: `consider` -- when the line is kept, `emit` it
  unchanged.

Those clauses are built into one executable. `site.<self>.command` gives it the
name the program states, and `environment.systemPackages` puts that executable
on the machine, so the command is on every user's PATH. Nothing else in the
NixOS configuration is touched: this is a command-line filter, not a service, so
there is no unit and no timer.

## Things worth knowing

Two questions the program does not answer, decided here: a line that is not
valid JSON has no fields at all, so it can never satisfy the keep condition and
is dropped silently; an argument with no `=` in it is a usage error and stops
the program, naming the offending argument. If either should be different, that
is a new sentence and a fresh mint.

Every program in this language must state all five sentences: without the input,
keep and print sentences there are no clauses to build, without the install
sentence the command has no name, and without the example nothing observes what
the tool actually does. Each missing one is asked for by name.

Three gaps are filed alongside. The example writes its input lines inline joined
by "and", so the pattern reads exactly two of them -- an example with one or
three lines will not compile. And two checks I wanted could not be written: an
`expect` cannot pin a value containing a double quote (it compares against the
escaped rendering), and an `expect` on `site.<self>.command` reads null, so the
command name is pinned by its rule alone. The example itself is still checked
for real, by running the program offline and comparing what it printed.

## Known Gaps

### inline-list-hole

blocked line: given the lines {"a":"1"} and {"a":"2"} with a=1, print only {"a":"1"}.
the example states its input lines inline, joined by "and", on one line. a hole
binds one token and a multi-token hole binds one blob, so the only way to read
this line is one hole per item, which fixes the count at two: an author adding a
third example line needs a fresh mint. a block reads any number of items, but
only when the items sit on their own lines. missing: a repeating hole that reads
an inline list into one decision per item.

### expect-quoted-value

blocked line: given the lines {"a":"1"} and {"a":"2"} with a=1, print only {"a":"1"}.
wanted: 0.9 a2 expect claim.filter.feed from witness.line.1
lips renders the value escaped ([ "{\"a\":\"1\"}" ]) and then looks for the raw
captured text {"a":"1"} inside it, so the check fails on the escaping alone:
  claim.filter.feed: should contain {"a":"1"}, but is [ "{\"a\":\"1\"}" ]
the same happens for claim.filter.equals. so no expect can pin a program value
that contains a double quote, and the example's lines are pinned only by the
claim that runs them.

### expect-site-command

blocked line: install the tool as the command logscan.
wanted: 0.9 a2 expect site.<self>.command from tool.command
the rule emits site.<self>.command, but the expect reads it as null:
  site.logscan.command: should contain logscan, but is null
site emits seem not to be visible to the expect checker the way artifact args
are, so the installed command name cannot be pinned by a behavioural check.


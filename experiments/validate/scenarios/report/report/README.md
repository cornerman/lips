<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `report` language

This language describes a little line-counting reporter: what it reads, how
many of the commonest lines it reports, who gets them, what the command is
called, and one worked example that is checked on every compile.

## The lines it accepts

1. `read lines from standard input and mail the <count> most common ones to
   <address> every night.` -- `<count>` is a number word (one .. ten) and
   `<address>` is the mail recipient. The rest of the sentence is fixed
   vocabulary: "standard input" and "every night" pick the mechanism, they are
   not values.
2. `install the tool as the command <name>.` -- the name the tool gets on the
   system.
3. `given the lines <a>, <b>, <c>, <d> and <e>, print <x> then <y>.` -- the
   worked example: five input lines and the two lines that must come out. It
   is compiled into a claim and re-run on every compile.

## What it builds

The behaviour is written as clauses, not as a source file: `all-lines` reads
standard input to end of input, `tally` counts each distinct line keeping
first-appearance order, `top-lines` repeatedly takes the most frequent
remaining line, and `main` prints them. Ties go to the line seen first, which
is what makes the program's own example ("a then b", both seen twice) come
out in that order. The count word from sentence 1 reaches the behaviour
through `count-of`, a small table from number words to numbers; a word outside
one..ten stops the program loudly rather than guessing.

Those clauses are built into one executable and installed system-wide under
the name sentence 2 gives, so `nightly` is on every user's PATH.

The nightly mail is cron, because cron is the mechanism that already mails a
job's output: `services.cron.mailto` is the address from sentence 1, and
`services.cron.systemCronJobs` gets one entry, at 03:00 daily, running the
command. Whatever the command prints that night is what arrives in the
recipient's mailbox.

Two choices are mine, not the program's: the hour (03:00 -- the program says
only "every night"), and the fact that the nightly run gets cron's own
standard input, which is empty. The program says the tool reads standard
input but never says where the night's lines come from, so nothing is wired
in front of it and nothing was invented; if the lines should come from a file
or a command, that has to be said in the program and the language rebuilt.

## What is checked

Every compile re-checks that the address reaches `services.cron.mailto`, that
the command name reaches the cron entry, and that the worked example still
holds: the five given lines are fed to the program and its output must equal
the two printed lines, exactly.

## The rough edge

Sentence 3 states its list inline, and a line's items can only be counted out
one hole at a time, so that sentence is locked to five inputs and two outputs.
Changing the example's size needs a fresh `generate`; this is filed as a gap.

## Known Gaps

### inline-list-witness

blocked line: given the lines a, b, a, c and b, print a then b.

repro: an example sentence that carries its items inline. A block fans one
decision out per item and <n:index> keys them, but a block needs the items on
separate lines; a multi-token hole reads the whole phrase as one string and
nothing can split it into the per-line strings claim.<id>.feed takes.
So the sentence has to be read with one hole per item, which fixes the example
at five input lines and two printed lines: "given the lines a, b and c, print
a" no longer crystallizes.

wanted: a way to read an inline, comma-separated list in one line as one
decision per item.


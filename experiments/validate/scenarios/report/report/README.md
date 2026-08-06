<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `report` language

This language describes a nightly line-frequency report.

It reads exactly two sentence shapes:

- `read lines from standard input and mail the ten most common ones to <address> every night.`
  The address is the only editable word; it becomes the recipient of the mail.
- `install the tool as the command <name>.`
  The name is what the tool is called on the machine's PATH.

**The counting is behaviour, not a script.** The ranking is minted as clauses:
`collect` reads standard input line by line, `bump` keeps a tally of how often each
line was seen, `best`/`without`/`top-n` pull out the ten most frequent in
descending order, and `emit-all` prints them, most common first, one per line, with
no counts (there is no way to render a number as text with the contracts
available). `main` ties them together. These clauses are built into one executable,
installed system-wide, and named by the second sentence, so `nightly` on this
machine is exactly this filter.

**Mailing and scheduling are the machine's job**, because a clause can only read
lines and print lines -- there is no mail contract. So the module also defines a
oneshot service and a timer, both keyed by the program's instance name: the timer
fires `daily` (with `Persistent`, so a machine that was off catches up), and the
service's script runs the tool and pipes its output into `mail -s nightly-report`
at the recipient address, which is passed to the unit as the environment variable
`REPORT_RECIPIENT`. The service's PATH carries the built tool and `mailutils`.

**Two things you should know before you rely on it.**
First, the machine needs a working mail transport; the program says to mail a
report, not how mail leaves this host, so nothing here configures one.
Second, the program says the tool reads *standard input*, and a timer-started unit
has no standard input of its own. Nothing in the program says what should feed the
nightly run, and I did not invent a source (a log file, the journal): as it stands
the scheduled run mails an empty report until you connect its input, e.g. by
adding `StandardInput` to the unit or by stating the source in the program and
regenerating. Running `nightly` by hand in a pipeline works today.

Two limits are filed as gaps: the word "ten" cannot be a hole (a number word
cannot become an integer anywhere in this grammar), so the count is fixed by the
sentence's wording; and the program states no example input/output, so nothing
observes the ranking -- add one ("given the lines A A B, print A") and a
regeneration can claim it.

## Known Gaps

### counted-word-is-not-a-number

blocked line: read lines from standard input and mail the ten most common ones to ops@example.com every night.
"ten" is a value a human would edit, but a hole capturing it binds the word "ten",
and neither the value grammar nor the clause subset can turn a number word into
the integer 10 (no conversion, no computation). So the count had to stay a literal
template token and is fixed at ten; changing it needs a fresh mint.

### no-witness-for-baked-behaviour

blocked line: read lines from standard input and mail the ten most common ones to ops@example.com every night.
The program bakes behaviour (counting and ranking lines) but states no example
input and no example output, so there is nothing to claim. A witness may not be
invented, so the ranking is realized unobserved.


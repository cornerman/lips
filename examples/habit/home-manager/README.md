<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language describes a small terminal habit tracker, and it is realized as
behaviour clauses (a real little program), not as configuration.

Line shapes it accepts, one per sentence of the program:

- `track <what> from the terminal.` -- a decorative title. The words are read
  but nothing is realized from them.
- `the first argument names the habit to print.` -- fixes where the habit name
  comes from: the first command-line argument.
- `read the habit log from the file named as the second argument, or from
  standard input when no file is named.` -- fixes the input. See the caveat
  below.
- `each log line holds an ISO date and a habit name separated by a tab.` --
  fixes the line format: this is what the parser is written from.
- `print one character per day from the log's earliest date to its latest
  date.` -- fixes the rendering: the whole day-by-day walk, including the
  calendar arithmetic (month lengths, leap years), comes from this sentence.
- `mark a day the named habit was logged with "#".` and
  `mark a day it was not logged with ".".` -- the two marks. Both characters
  are holes: change them in the program and the built tool changes.
- `install the tool as the command habit.` -- the command name is a hole; it
  becomes the name of the installed program (`site.<self>.command`) and the
  program is added to `home.packages`.
- `given the log of "<date>" for "<habit>", ... , the habit "<name>" prints
  "<out>".` -- the worked example. It becomes a claim: the three log lines are
  fed to the program, the habit name is its argument, and what it prints is
  compared byte for byte. This is the only thing that holds the minted code to
  the program's words, so every program must state one.

Mechanism: the behaviour is clauses (habit-name, read-log, parse-entry,
parse-date, render, marks, earliest, latest, logged-days, logged?, next-day,
days-in-month, leap-year?, multiple-of?, date-same?, date-before?,
present-mark, absent-mark, main). Dates are parsed with the string-cut
contract, compared as (year month day) lists, and the range is walked one day
at a time. Because home-manager is unprivileged and there is nothing to boot,
the tool is simply installed into the user's profile: `home.packages` gets the
built site, named by the command sentence.

Two things I could not derive and one I had to choose:

- No contract opens a named file, so the clauses read standard input only; the
  "file named as the second argument" half of that sentence is not honoured.
  Filed as a gap (no-file-contract), and the rule that reads the log carries
  lowered confidence for it.
- The worked-example sentence lists its log entries inside one line, so the
  pattern fixes three entries. Filed as a gap (one-line-item-list); an example
  with a different number of entries needs a regeneration.
- The program says nothing about an empty log; the tool prints an empty line in
  that case.

The behavioural contract pinned on every future compile is the example itself:
the claim feeds the stated log to the program, passes the stated habit as its
argument, and requires exactly the stated output.

## Known Gaps

### no-file-contract

blocked line: read the habit log from the file named as the second argument, or from standard input when no file is named.
no contract opens a named file: the clause layer offers read-a-line (standard
input) and nothing else, so only the standard-input half of that sentence is
realized. A file-reading contract (open a path, read its lines) would close this.

### one-line-item-list

blocked line: given the log of "2026-01-01" for "run", "2026-01-02" for "read" and "2026-01-04" for "run", the habit "run" prints "#..#".
the example log is a list of items written inside ONE sentence, and a template
cannot repeat a hole, so the witness pattern fixes three entries. A four-entry
example needs a fresh mint, or the author must be able to write the entries as
lines of a block. A repeating hole (or a list hole binding a comma-separated
run of items) would close this.


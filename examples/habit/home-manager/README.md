<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language describes a small terminal habit tracker, and lips builds it as
clauses (a real program), not as configuration.

Line shapes it accepts:

- `track daily habits from the terminal.` -- a heading; decoration only.
- `the first argument names the habit to print.` -- the command line: the
  first word after the command is the habit; with no argument the tool stops
  loudly ("no habit named").
- `read the habit log from the file named as the second argument, or from
  standard input when no file is named.` -- where the log comes from.
- `each log line holds an ISO date and a habit name separated by a tab.` --
  the line format; a line without a tab is skipped.
- `print one character per day from the log's earliest date to its latest
  date.` -- the output: one line, one character per calendar day between the
  earliest and latest dates seen in the log (real date arithmetic, leap years
  included).
- `mark a day the named habit was logged with "#".` and
  `mark a day it was not logged with ".".` -- the two marks. Both characters
  are holes: change the quoted character and the output changes.
- `install the tool as the command habit.` -- the command name is a hole; it
  becomes the site's command name and the built program is added to
  `home.packages`.
- `given the log of "DATE" for "HABIT", ... and "DATE" for "HABIT", the habit
  "NAME" prints "OUT".` -- the worked example. Any number of log entries is
  read (a list hole plus a per-entry pattern), and it becomes a claim: the
  entries are fed as tab-separated lines, NAME is the argument, and the
  printed line must equal OUT exactly. This is what holds the minted code to
  your sentence.

Mechanism choices: behaviour lives in `habit-*` clauses, installed through
the site (`site.<self>.command`) and put on PATH with `home.packages`. No
systemd unit, no artifact source file: nothing here runs on a schedule.

What I could not honour: there is no contract that opens a named file, so the
"file named as the second argument" half of the input sentence is not
realized -- the tool reads standard input. That is filed as the gap
`file-input`, and the rule carries the matching low confidence.

What I had to decide, since the program is silent: a log line with no tab is
skipped rather than fatal, and running with no argument stops with an error
instead of printing nothing. The tab separator and the date layout are fixed
words of the sentences, not holes, because a different separator would need a
character the grammar cannot derive from the word "tab".

## Known Gaps

### file-input

blocked line: read the habit log from the file named as the second argument, or from standard input when no file is named.
no contract opens a named file: read-a-line reads standard input only, and arguments returns the words but nothing can turn a word into a readable file. the clauses therefore read standard input and silently ignore a second argument. a "read-file (1)" contract would close this.

### site-command-unassertable

blocked line: install the tool as the command habit.
the command name reaches site.<self>.command, but no expect can assert that slot
("nothing realizes this slot"), so the only pin left for the installed name is
the rule itself. an assertable site.<self>.command (as artifact args are
assertable) would close this.


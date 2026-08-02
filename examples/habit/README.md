<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `habit` language

This language describes a small daily-habit tracker CLI, built from source.

**Line shapes it reads**
- The opening sentence and the four sentences describing the argument
  convention, the log source, the log line format and the print-range rule
  are read as `concept` lines: they state the fixed behaviour every program
  of this kind shares (first argument = habit name, second argument or
  stdin = the log, tab-separated `date<TAB>habit` lines, one character per
  day from the log's earliest to its latest date). They carry no
  per-program value, so they realize nothing and only document intent.
- `mark a day the named habit was logged with "X".` and
  `mark a day it was not logged with "Y".` capture the two marker
  characters used in the printed chart as program values.
- `install the tool as the command NAME.` captures the shell command name
  the built tool is installed as.
- `given the log of "d" for "h", "d" for "h" and "d" for "h", the habit "H"
  prints "OUT".` is the program's own worked example. It becomes the
  behavioural claim: the three dated entries are turned into real
  tab-separated input, the built binary is run against it with the named
  habit as its argument, and its printed line is checked byte-for-byte
  against the stated output.

**Mechanism**
The tracker is built with `stdenv.mkDerivation` from a bundled bash script
(`habit.sh`) that reads `date<TAB>habit` lines from a file argument or
stdin, and uses GNU `date` to walk every day between the log's earliest and
latest date, printing one marker character per day. `date` is put on the
script's PATH with `makeWrapper` against `coreutils`, so the result behaves
the same regardless of the host's own `date` tool. The two marker
characters reach the script through fills (`@present@`/`@absent@` markers
inside `habit.sh`), so editing either quoted character changes the built
binary without touching the engine itself.

The artifact is keyed by `<self>` (the program's own instance/file name)
rather than by the captured command name. The marker facts and the worked
example appear on lines that say nothing about the command name, so they
have no way to reach an artifact keyed by that captured word; `<self>` is
the one key every rule can reach regardless of which line produced its
decision. The captured command name is still honoured: it becomes the
derivation's `pname`, and the built script is *also* installed as a second
`$out/bin/<name>` entry, so editing "install the tool as the command X"
still renames the real, user-facing command. The claim always calls the
`<self>`-named binary, so it stays stable no matter what the command is
named.

**What I had to choose**
- The build system (`stdenv.mkDerivation` + `makeWrapper`) and the fixed
  version "0.1.0" are mechanism choices: nothing in the program names a
  build system or a version, and none is a value a program would state.

**Limit I could not lift (filed as a gap)**
The witness pattern is fixed to exactly three dated log entries, matching
the one example given. The grammar has no way to repeat a sub-match inside
one line (no list-splitting, no computation), so a program whose example
states a different number of entries cannot be read by this pattern; see
the filed gap for how a repeating block would fix this.

## Known Gaps

### witness-entry-count

blocked line: given the log of "2026-01-01" for "run", "2026-01-02" for "read" and "2026-01-04" for "run", the habit "run" prints "#..#".
The witness pattern is fixed to exactly three dated log entries because the
grammar has no way to repeat a sub-match within one line (no list-splitting,
no computation): a program stating two or four entries in its example
sentence cannot be read by the same pattern. A repeating bulleted block
("- date for habit", closed by a "the habit ... prints ..." line) would let
the count vary, but that is not the shape this program uses, so I did not
invent one.


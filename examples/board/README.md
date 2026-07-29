<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

This language describes a single-user terminal "kanban board" tool that reads
a markdown file with column sections and prints them to the terminal.

Line shapes recognized:
- `show a kanban board in the terminal.` — a decorative heading that fixes
  the mechanism (a terminal CLI tool, built from source) but carries no
  program value of its own, so it is a `concept` and needs no rule.
- `the board is stored in <path>.` — states where the board's markdown file
  lives; captured as fact `board.storage`.
- `the board has the columns "<cols>".` — the quoted, comma-separated list
  of column headings the board file uses; captured as fact `board.columns`.
- `install the tool as the command <name>.` — names the command the built
  tool should be installed as; captured as fact `command.name`.

Mechanism chosen: since no existing package can read this program's own
markdown convention, the tool is built from source with `stdenv.mkDerivation`
(the plainest builder that takes a `src` directory and an `installPhase`,
matching a shell script with no external dependencies). The artifact is
keyed by `<self>` (per source-file instance), and the program's own command
name is threaded through as the built binary's name via `<value>` in
`installPhase` and `args.pname`, so renaming the command in the program
renames the installed command. The board's file path and column list are
values that don't change at runtime, so they are threaded into the script at
build time via `fill` markers (`@BOARD_PATH@`, `@COLUMNS@`) rather than
through a runtime environment variable. The built package is added to
`home.packages` so it is installed into the user's profile.

The script itself (source `board/run.sh`) parses `## <column>` sections out
of the markdown file and prints each column's bullet items in turn; that
parsing algorithm is a fixed mechanism, not a program value.

Invented at full confidence (mechanism constants, not values the program
states): the builder `stdenv.mkDerivation`, the version string `0.1.0`, the
source file name `run.sh`, and the markdown convention of `##` section
headers per column.

Every program in this language must state where the board file lives, what
its columns are named, and what command to install the tool as; missing any
of these produces a demand for that line.

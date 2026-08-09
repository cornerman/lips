<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `board` language

This language describes a single command-line "kanban board" tool that
reads a small markdown dialect (## headers open columns, - bullets are
cards) and prints one summary line per column.

Line shapes:
- Descriptive sentences that only explain the tool's fixed behaviour
  (what it does, how it reads input, the markdown grammar, the print
  format, the empty-column rule) are decorative and become `concept`
  lines; they select the mechanism (a small bash script) but hold no
  program value of their own.
- `the board has the columns "a, b, c".` states the ordered column list.
  This is the one piece of data the script needs at runtime; it is
  spliced into the script through a fill (`@columns@`) and the script
  itself splits it on commas at runtime.
- `install the tool as the command <name>.` names the actual executable
  that ends up on the user's PATH (via `home.packages`); the name governs
  both the derivation's pname and the installed binary's filename.
- `given "..." ..., print "..." ...` is the worked example from the
  program. It becomes the behavioural claim: the fixed number of quoted
  input lines (this program states five) are joined with newlines and
  fed to the built binary's stdin, and the quoted output lines (this
  program states three) are joined with newlines and compared byte for
  byte against its stdout.

Mechanism: the tool is built as a plain `stdenv.mkDerivation` around one
committed shell script (`board.sh`), installed straight to
`$out/bin/<command>`, so no compiler/vendoring questions arise. The
script reads its argument (or stdin when none is given) and reproduces
exactly the grouping/formatting rules stated in the program.

Every program in this language must state its column list and its
install command name (both are demanded when absent), and must give at
least one given/print example, since that example is the only thing
that pins the baked script's behaviour going forward.

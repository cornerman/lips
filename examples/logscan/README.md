<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This program describes a single self-written filter tool, so the language
has one value-bearing line shape and three fixed descriptive lines that
only document the tool's fixed behaviour (they carry no per-program value,
so they crystallize as `concept`s and mint no rule):

- "filter JSON lines read from standard input." — describes the input
  channel (concept `io.stdin`).
- "keep a line only when every field named on the command line equals the
  value given with it." — describes the filter algorithm (concept
  `io.filter`).
- "print each kept line unchanged." — describes the output behaviour
  (concept `io.output`).

The one value-bearing line is:

  install the tool as the command <name>.

which captures the command's name (here `logscan`) as `cmd.<name>.name`.
This is the only word in the program that varies across instances of this
language, and everything else follows mechanically from it.

Mechanism chosen: since the program must filter arbitrary JSON lines by
equality on arbitrary command-line-specified fields — a small algorithm,
not configuration of an existing package — it is written from source and
built with `buildGoModule` (Go's standard `encoding/json` makes this a
robust, dependency-free implementation, so `vendorHash` is `null`). The
built derivation is exposed as an ordinary user package via
`home.packages`, since the program only asks that the tool be *installed
as a command*, not run as a background service.

The captured command name reaches the build in two places: as the
derivation's `pname` (so nix knows the package's name), and as a `fill`
substituted into `go.mod`'s `module @name@` line, so the compiled binary
is actually named `logscan` (buildGoModule names the binary after the
module/package path) — this keeps `${artifact.logscan}/bin/logscan`
truthful. `version` is an invented build constant ("0.1.0"), never asked
of the program, since it has no observable effect on behaviour.

The Go source itself implements the fixed algorithm literally stated by
the three descriptive lines: read newline-delimited JSON from stdin,
parse each line, keep it only if every `field=value` pair given as a
command-line argument matches (comparing strings directly, and JSON
round-tripping non-string field values for comparison), and print kept
lines unchanged to stdout.

Nothing was left as a demand: the program fully names everything a
build needs (the tool's own name); there was no silent gap to ask the
human to fill in.

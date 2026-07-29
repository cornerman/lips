<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

## What this language recognizes

`logscan.lips` is read as five line shapes:

1. **`filter JSON lines read from standard input.`** — a fixed, structural
   sentence describing the tool's input channel. It carries no program
   value (stdin is not a configurable option here), so it is captured as a
   `concept` (decorative vocabulary) with no rule.
2. **`keep a line only when every field named on the command line equals
   the value given with it.`** — describes the filtering algorithm itself.
   The actual field names/values are supplied at *invocation* time (argv),
   not written into the program, so there is nothing to extract as a
   config value; this is algorithm, so it lives in the artifact's source,
   not in an option. Captured as a `concept`.
3. **`print each kept line unchanged.`** — describes the output channel
   (stdout, verbatim). Also a `concept`.
4. **`write the tool in go, using only the standard library with no
   external dependencies.`** — this sentence *selects the mechanism*: Go,
   built via nixpkgs' `buildGoModule`, with no vendored/external Go
   modules. Since "go" here is a mechanism-selecting word rather than a
   value, it stays as literal template text and is realized as a `concept`
   too; the actual mechanism choice (buildGoModule, `vendorHash = null`
   because there are no external deps to vendor) is made once, at full
   confidence, in the rule for the next line.
5. **`install the tool as the command <name>.`** — the one line that
   states an actual program VALUE: the command's name (`logscan`). This is
   captured as `fact tool.<name>` and is what names the built artifact, so
   editing this word renames the binary, the build directory, and the
   installed package everywhere consistently.

## Mechanism chosen

The tool is a short-lived CLI filter invoked by the user (stdin -> stdout,
argv-driven), not a long-running daemon, so no `systemd.user.service` is
needed — it is simply built and put on `PATH` via `home.packages`. It is
built from source with `buildGoModule` because the program says "in go...
standard library... no external dependencies," which needs nothing beyond
`pname`/`version`/`src`/`vendorHash`. `vendorHash` is set to `null` because
the program explicitly states there are no external dependencies to
vendor/hash. `version` ("0.1.0") and the go.mod module path ("logscan")
are build-recipe constants with no observable effect on program behavior,
so they are chosen once at full confidence rather than demanded.

## What was invented

- The Go module name/version placeholder (pure build plumbing, no
  behavioral effect).
- The actual filtering/JSON-parsing/printing logic, since the program only
  states the algorithm in prose ("keep a line only when every field named
  on the command line equals the value given with it") — this is
  structure, not a value, so it is written once into `main.go` and reads
  its filters from `os.Args` at runtime rather than freezing anything the
  program could later change; there is nothing in the program text for a
  future edit to redirect here.

## What is NOT expected

No `expect` lines are emitted: the only program-stated value (the command
name) flows exclusively into package/build definitions (`artifact.*.args`,
`home.packages`), which build a derivation rather than set a checkable
config value, and such options are explicitly exempt from behavioral
expects.

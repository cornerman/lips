<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

## What this language describes

A `.lips` program here describes one small command-line filter for
JSON-lines input, in five plain sentences. The program shown reads:

```
filter JSON lines read from standard input.
keep a line only when every field named on the command line equals the value given with it.
print each kept line unchanged.
install the tool as the command logscan.
given the lines {"a":"1"} and {"a":"2"} with a=1, print only {"a":"1"}.
```

## The line shapes it accepts

1. `filter JSON lines read from standard input.` — states the input
   interface. No value in it varies, so it carries no hole: it is read as
   vocabulary (a *concept*) and realizes nothing.
2. `keep a line only when every field named on the command line equals the
   value given with it.` — states the matching rule. Also a concept, for the
   reason in the gap note below.
3. `print each kept line unchanged.` — states the output interface. Concept.
4. `install the tool as the command <name>.` — the one word that governs
   configuration. `<name>` is a hole: it names the derivation, becomes the
   Go module name (so the built binary is called that), and the package is
   put on every user's PATH via `environment.systemPackages`.
5. `given the lines <in1> and <in2> with <args>, print only <out>.` — the
   worked example. It is read as an *item of line 4*: lips nests this
   pattern under the install line (`p5.under.p4`), which is how the example
   learns which command it is exercising. **Order matters: the install line
   must come before the example line.** All four words are holes, so editing
   the example changes what is actually run and compared.

Sentences 1–3 must be written exactly as above; a reworded variant will not
crystallize and will send you back to `generate`. That is deliberate: those
sentences describe code, and code cannot be holed (see the gap).

## The mechanism I chose

The program asks for a tool that does not exist in nixpkgs, so this is a
*build*, not a configuration of an existing package:

- `buildGoModule` with a two-file Go source tree staged at
  `artifacts/<name>/` (`go.mod`, `main.go`), `vendorHash = null` since the
  program has no dependencies outside the standard library.
- The command name reaches the source through a **fill**: `go.mod` says
  `module @name@`, and `@name@` is substituted at compile time. Go names the
  binary after the module path, so `install the tool as the command foo`
  really produces `bin/foo` — renaming the command in the sentence rebuilds
  and reinstalls it under the new name.
- Installation is `environment.systemPackages`, i.e. system-wide on this
  machine, since a NixOS module is evaluated as root.
- Version `0.1.0` is a constant I chose: `buildGoModule` needs `pname` *and*
  `version` to derive a name, and the program states no version. It is not a
  value you need to maintain.

## What holds the code to the sentences

The module text says nothing about what the Go program *does*, so the worked
example is realized as a **claim**: the built binary is run with the stated
filter arguments, fed the two stated input lines on standard input, and its
output must equal the stated line exactly (one trailing newline is stripped).
The command names only the build, so it runs in the build sandbox — no
machine boot. Field comparison is done on the JSON value rendered as text,
so `a=1` matches both `{"a":"1"}` and `{"a":1}`; blank lines and lines that
are not valid JSON are skipped rather than printed.

Exactly one example line per program is supported: a second one would try to
set the same claim twice and lips would refuse the compile, loudly.

## Contract checked on every compile

- the command name reaches `artifact.<name>.args.pname` and the `@name@`
  fill in `go.mod`;
- the expected output of the example reaches the claim's `stdout`.

No expect names `environment.systemPackages` or the build reference itself:
those hold a derivation, which the behavioral check cannot read.

## If a program stays silent

Two demands are minted. A program with no `install the tool as the command
...` line is asked which command name to install; a program with no `given
... print only ...` line is asked for a worked example. The second is not
politeness: source is baked here, and without an example nothing at all
would hold that source to the three sentences describing it.

## Known Gaps

### source-semantics-not-parametric

blocked line: keep a line only when every field named on the command line equals the value given with it.
This sentence states the filter's ALGORITHM, and an algorithm has no hole
form: a fill substitutes a marker in the baked Go source, it cannot swap
"every field matches" for "any field matches". So the line is read as a
concept (vocabulary only) and the algorithm lives in main.go, held to the
sentence solely by the worked-example claim. A program that reworded it
("...when any field...") would not crystallize at all, which is loud but
means a fresh mint.


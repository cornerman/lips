<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `function` language

## What a program in this language says

Two line shapes, and the second only ever appears under the first:

```
function println_to_stdout(x: String)

println_to_stdout("hallo")
println_to_stdout("du")
println_to_stdout("!")
```

1. **A declaration** — `function <name>(<param>: <type>)`. It names the function
   and opens a block; the call lines that follow belong to it. The function's
   *name* is a real value: it names the binary that gets built and the systemd
   unit that runs it, so renaming the function renames both. The parameter's
   name and type are read but govern nothing on the machine — the printer takes
   one string — so this line is recorded as a decorative heading (`concept
   func.<name>`) and nothing is realized from `x` or `String`. If you later want
   the type to *mean* something (an integer argument, a different printer), that
   is a new mint, not an edit.
2. **A call** — `<name>("<text>")`. The quoted text is the value; each call line
   becomes one item of the block, numbered by its position (1, 2, 3, ...), so
   two identical calls stay two calls and the order of the file is the order of
   the output. The subject vocabulary is `call.<name>.<n>.text`.

Anything else — an unquoted argument, a call before any declaration, a second
statement kind — will not crystallize, and `compile` says so loudly.

## What is built, and why

"Print to stdout" on a whole machine means: a program that runs and whose output
lands in the journal. So each declared function becomes:

* **A Go binary**, built with `buildGoModule` from the source staged beside the
  engine (`artifacts/println_to_stdout/`). The source holds only the *structure*:
  a function that prints one string, and a loop that walks its arguments in
  order. The function's name reaches the source through a fill (`@fname@` in
  `main.go` and `go.mod`), which is also why the module name, the produced
  `/bin/<name>` and the unit's `ExecStart` all agree.
* **A oneshot systemd service of the same name**, wanted by
  `multi-user.target`, so the program runs once as the machine comes up and its
  stdout is the journal (`journalctl -u println_to_stdout`).
* **One environment variable per call** on that unit: `CALL_1`, `CALL_2`, ... The
  call texts deliberately do *not* go into the Go source: a fill replaces a
  marker, it cannot repeat a statement per call, so the calls travel as unit
  environment and the binary reads them at start. That is what keeps adding a
  fourth call a one-line edit instead of a regeneration. (Practical limit: 1024
  calls per function.)

I chose the arguments the builder needs myself, as mechanism, not from the
program: `version = "0.1.0"` and `vendorHash = null` (the source fetches
nothing). The function name must be a legal Go identifier and a legal unit name,
which `println_to_stdout` is.

## The contract

`function.expect` pins the one thing the program actually states: every call's
text appears as `CALL_<n>` on the unit named after the function. The build
reference in `ExecStart` holds no checkable value, so nothing is asserted about
it — the rule is its own contract there.

## If a program is silent

A declaration with no calls is refused with a question: which strings should the
function be called with? A function that prints nothing is almost certainly a
half-written program, so it fails at compile time rather than shipping a silent
service.

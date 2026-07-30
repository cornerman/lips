<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `function` language

This language reads a tiny imperative program: one function declaration
followed by calls to it.

**The two line shapes**

- `function println_to_stdout(x: String)` -- declares the program's one
  primitive: a function that writes its argument, followed by a newline, to
  stdout. The parameter *name* is a hole (`x` here), so renaming it flows
  through; the function name `println_to_stdout` and the type `String` are
  fixed words of the language, because they select the mechanism (what the
  function does, and that the argument is a string) rather than carrying a
  value. Everything below this line belongs to its block.
- `println_to_stdout("hallo")` -- one call, with the string argument in a
  hole. Calls carry no identifier of their own (two calls may pass the same
  text), so each is keyed by its position in the block: `call.1.text`,
  `call.2.text`, `call.3.text`. Order is therefore preserved and repeats stay
  repeats.

**The mechanism I chose**

The declaration is realized as a real program built from source
(`buildGoModule`, sources staged under `artifacts/println_to_stdout`): a Go
file defining `println_to_stdout(<param> string)` -- the parameter name
reaches the source through a fill -- and a `main` that replays the calls.

The calls are *not* baked into the source: a fill replaces a marker and
cannot repeat a block, so per-call source is not expressible. Instead each
call becomes one environment variable on the unit that runs the program,
`CALL_1`, `CALL_2`, ..., and the source loops from index 1 until a variable
is missing. This keeps the source purely structural (the algorithm and the
function body) and puts every word the program states into a plain, readable
NixOS option value.

The program is run by a `oneshot` systemd service named after the program
file (its instance name), wanted by `multi-user.target`, so the machine runs
the program once at boot and the printed lines land in that unit's journal.
The built binary is also installed into `environment.systemPackages`, so a
human can run `println_to_stdout` by hand.

**What the contract pins**

Every call's text is asserted to appear at
`systemd.services.<self>.environment.CALL_<n>`, and the parameter name at the
artifact's fill. The `ExecStart` line holds a build reference, so nothing is
asserted about it -- the rule that emits it is the contract there.

**What I had to invent, and what a program must state**

The package version `0.1.0` and `vendorHash = null` are mechanism constants;
`null` is correct because the source I wrote has no external dependencies. A
program must state both a declaration line and at least one call: a program
missing either is asked for it rather than given a default. Only the
`String` parameter type is readable -- see the filed gap
`declared-type-mapping`.

## Known Gaps

### declared-type-mapping

blocked line: function println_to_stdout(x: Int)
The declaration's type token is fixed as `String` in the pattern. Turning a
declared type word into the corresponding type of the generated source
(String -> Go `string`, Int -> `int`) needs a lookup from one token to
another, and the value grammar has no mapping or conditional: a fill
substitutes a marker verbatim, so filling `@type@` with `String` would emit
invalid Go. Only String-typed declarations are readable today.


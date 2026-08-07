<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `function` language

This language is a tiny print program: one function declaration, then the
calls to it, and it compiles to a real executable installed on the machine.

Line shapes it accepts:

- `function <name>(x: String)` -- declares the printing function. The NAME is
  a hole: it is what the installed command is called (`site.<self>.command`),
  so renaming it in the program renames the binary. The parameter `x` and the
  type `String` are fixed words of the shape, not holes: the parameter name
  cannot reach the generated code (see the filed gap `identifier-from-program`),
  and `String` selects the mechanism -- printing a string line as-is.
  This line also opens the block that the call lines below it belong to.
- `<name>("<text>")` -- a call, one statement, written under the declaration.
  The TEXT is a hole; the function name is a hole too and keys the program's
  decisions and its claim.

Mechanism: the behaviour is clauses, not a source file. The declaration
realizes one clause, `(define (print-line line) (emit line))`, which is the
`emit` contract -- the only door to standard output. Each call line
contributes one statement to `main`, in program order, so the three calls
become `(define (main) (print-line "hallo") (print-line "du")
(print-line "!"))`. The clauses are built into one executable (`${site}`),
named after the declared function and put on the system PATH via
`environment.systemPackages`.

What is observed: one claim runs the whole program end to end -- it calls
`main` and compares everything the program printed, in order, with the stated
lines. The stated lines are handed to the claim through `claim.args`, because
that is the only claim section that can be assembled line by line; the check
itself is exact and byte-for-byte. Editing, adding or removing a call line
therefore changes both what the program prints and what the claim demands, and
the two must agree. Two claims cannot be used here (the claim adapters share
their output list), which is why there is one whole-program claim rather than
one claim per line -- see the gap `per-line-expected-output`.

No `expect` lines: the behavioural contract file can only assert values that
land in ordinary NixOS options, and everything this program says lands in
clauses, in the site's command name, or in a package reference -- none of them
assertable there. The claim is the contract instead.

Nothing was invented: the only choices I made are mechanism choices (the emit
contract for printing, one `main` in program order, installing the binary
under the declared function's name).

## Known Gaps

### identifier-from-program

blocked line: function println_to_stdout(x: String)
a clause name and a clause's parameter name cannot come from the program: a
hole outside a Scheme string must be typed (int/float/bool), and a capture is
substituted into an emit PATH but not into the s-expression. So the declared
function is realized as a fixed clause (print-line line), and the parameter
name has to be a literal token of the template ("x"), which means renaming the
parameter costs a fresh mint.

### per-line-expected-output

blocked line: println_to_stdout("hallo")
one claim per statement is unusable, because the claim adapters share state:
the second claim's (emitted) still holds the first claim's lines. One claim for
the whole program would need its expected output assembled from every statement
line, and claim.<id>.equals takes a single s-expression, not a per-line
aggregate -- only feed/args aggregate as lists. The engine therefore carries
the stated lines in claim.args and asserts (equal? (emitted) (arguments)).
An aggregating expected-output section would remove the detour.


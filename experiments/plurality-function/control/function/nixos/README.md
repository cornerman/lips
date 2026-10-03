<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `function` language

This language reads a tiny script: the declaration of the printing function
`println_to_stdout`, and a list of calls to it.

Two line shapes are accepted:

- `function println_to_stdout(<param>: <Type>)` declares the function. The
  parameter's name and its type are holes: both are carried into the clause
  `function-println_to_stdout`, which checks its argument is a string, prints
  it, and otherwise stops with a message naming the declared parameter and
  type ("parameter x is not a String: ...").
- `println_to_stdout("<text>")` is a call statement. Each such line adds one
  statement to the clause `function-main`, in the order written, so three
  call lines print three lines. The quoted text is a hole, so editing it
  changes what the program prints.

The behaviour is minted as clauses (not as a baked source file) and built
into one command installed system-wide through `environment.systemPackages`,
named after the program's own instance. Nothing here is a unit or a timer, so
no claim needs a booted machine: the behaviour is observed offline.

Why the function NAME is not a hole: the declaration states no body. Nothing
in the program says what the function does -- only its name does. Rather than
invent a body for an arbitrary name, the name is a literal word of this
language: it selects the mechanism (print the argument to stdout). A program
declaring some other function therefore does not crystallize, and asks for a
fresh language instead of silently printing. The same limit is filed as the
gap `function-body-and-name`.

What the contract pins: the declared parameter and type, exactly as they are
spelled into the clause; the shape of the claim's entry expression; and the
first call's text in the claim's expected output. The rest of the call texts
are held by the claim ITSELF, which runs `(function-main)` and compares every
printed line, in order, with the texts the call lines state -- an expect
cannot be written per call, because all the call lines contribute to one
aggregated list and a family expect would compare each of them against the
whole. So adding, removing or editing a call line changes the program and the
observed output together.

## Known Gaps

### function-body-and-name

blocked line: function println_to_stdout(x: String)
the declaration carries no body, so what the function DOES cannot be read
from the program at all; only its name suggests it. The name therefore had
to become a literal token of the language (a mechanism word) rather than a
hole, and a program declaring any other function fails to crystallize. What
is missing is a way for a program to state a function's BODY (a sequence of
contract calls over its parameter) so that the name could be a hole and the
type could select the check instead of only wording the failure message.


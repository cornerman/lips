<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `function` language

This language reads a very small imperative program: one function declaration
and the calls to it.

Two line shapes are accepted.

1. `function <name>(<param>: String)` declares a function. Both the function
   name and the parameter name are values -- edit either and the generated
   program changes. The type word `String` is a fixed token of the template: it
   selects the check the generated code performs (`string?`), and a hole cannot
   select a procedure, so a declaration of any other type does not match (gap
   `parameter-types-other-than-string`).
2. `<name>("<text>")` calls the declared function with a quoted string. Each
   call line is a statement, numbered by its position on the page, and the
   statements fold in order into the program's entry point.

Mechanism. The behaviour is minted as CLAUSES -- no source file, no systemd
unit, so nothing here needs a booted machine to be observed. The declaration
becomes `function-print`, which takes the called name and the argument: it
stops the program if the name is not the declared one, stops it if the argument
is not a string (that is the `String` in the signature), and otherwise writes
the argument to standard output. Each call line contributes one statement to
`function-main`, the entry point. The clauses are built into one executable,
named after the program's own instance name (`site.<self>.command`) and put on
the system PATH via `environment.systemPackages`.

Why the declared name is data rather than the clause's name: a clause's
definition name must be literal text, so the program's word is carried INTO
`function-print` as a string it compares against, instead of naming a clause per
function. The visible cost is that one program may declare one function; a
second declaration is refused at build time (gap `one-declaration-per-program`).

What had to be invented. The program never says what the declared function
DOES; only its name says it prints to standard output. That reading is the one
low-confidence item of the engine (see the because note on the declaration rule)
and is filed as the gap `function-body-unstated`.

What is pinned. The call line is also the program's only example, so it is
claimed directly: running the entry point must print exactly what the call
passes (`println_to_stdout("hallo")` prints `hallo`), and expects hold the
generated statement, the expected printed line and the declaration's own clause
to the words the program wrote. A later mint that drops the parameter name, the
type check or the printed line is refused by that contract.

## Known Gaps

### parameter-types-other-than-string

blocked line: function println_to_stdout(x: Int)
The parameter type is read as a literal token of the template (String), because
the type word selects a check (string?) and no hole can select a procedure.
A program declaring any other parameter type does not crystallize at all.

### function-body-unstated

blocked line: function println_to_stdout(x: String)
The declaration states a signature and no body. The language has no line shape
for saying what a function DOES, so the body had to be read out of the name.

### one-declaration-per-program

blocked program:
  function println_to_stdout(x: String)
  function warn(y: String)
A clause's definition NAME must be literal: a hole outside a Scheme string is
refused ("a hole outside a string must carry a type"), so the declared function
name cannot become the clause's own name, and all declarations must share one
clause (function-print) that carries the declared name as data. A second
declaration therefore emits the same clause twice and the build refuses it.


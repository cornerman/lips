<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `redact` language

## What this language says

Five sentences describe a one-line-in, one-line-out JSON filter. Each has its
own shape, and a program must state all five (each is demanded by name if it
is missing):

- `read JSON lines from standard input.` -- fixes where the work comes from:
  one JSON object per line, read until end of input.
- `replace the value of the field named on the command line with ***.` -- the
  replacement is a hole, so writing `with [redacted]` instead changes what is
  printed. The field itself is *not* fixed here: it is the first word after
  the command name at run time.
- `print each line, changed or not, as JSON.` -- every input line produces one
  output line, whether or not it carried the named field.
- `install the tool as the command redact.` -- the command name is a hole;
  rename it in the sentence and the installed command is renamed.
- `given the line {"user":"ada","pw":"s3cret"} with pw, print
  {"user":"ada","pw":"***"}.` -- a worked example. The line, the field and the
  expected output are all holes, so this sentence is the program's own test.

## What it is turned into

The behaviour is written as clauses, not as a source file: `main` reads a line,
checks it really is JSON (`json-parse`), rewrites it, and prints it, looping
until input ends. The rewrite is a character-level scan of the *raw* line
(`string-cut`): every quoted span followed by `:` is a field name, and the
value after it is either a quoted string or a bare scalar ending at the next
`,` or `}`. Only the matching field's value is replaced -- everything else,
including field order and number formatting, is copied through byte for byte,
which is what "changed or not" asks for.

Why the raw text rather than the parsed record: a record loses the line's
field order and there is no contract that renders one back to JSON, so
rendering from it would reorder every line. That limitation is filed as a gap
(`no-json-render`), and it bounds this tool: flat JSON objects whose values
are strings, numbers, booleans or null. A nested object or array value, or a
`\"` escaped inside a string value, is beyond the scan.

The clauses are built into one executable and installed as the named command
on the system PATH (`environment.systemPackages`), so the whole machine gets
`redact`.

## Choices I had to make, that the program does not state

- A line that is not JSON stops the tool loudly, naming the line, instead of
  being passed through silently.
- Running the command with no argument stops it loudly as well.
- The replacement is always written as a JSON *string*, even when it replaced
  a number or a boolean.

## What holds it

The example sentence becomes a claim: the tool is fed exactly that line with
exactly that argument, and its printed output must equal the stated line, byte
for byte. That claim is the contract here -- there are no `expect` lines,
because nothing in this program lands in an ordinary NixOS option holding a
readable value (the command name lands in the built executable, the packages
list holds a derivation). Edit the example sentence and the check moves with
it; delete it and the next compile asks for it back.

## Known Gaps

### no-json-render

blocked line: print each line, changed or not, as JSON.
json-parse turns text into a record, but no contract turns a record back into
JSON text, and the record's field order is not the line's field order (a record
parsed from {"user":"ada","pw":"s3cret"} renders as {"pw":...,"user":...}).
So the printing had to be hand-written as a character-level scan of the raw
line with string-cut, which handles a flat object only: a nested object or
array value is not understood, and a quote escaped inside a string value ends
the span early. A json-render contract (record -> text, order preserved) would
make the whole rendering half of this language disappear.


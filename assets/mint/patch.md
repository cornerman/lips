THE ENGINE YOU INHERIT (this language is already minted; you are EXTENDING it).

Below is the committed engine, written in the same line format you answer in:
its patterns and rules, its expect contract, and its report. It already passes
every gate and already serves every program of the corpus.

Answer with a PATCH, not with a whole engine:
  - a line whose id is NEW adds that line,
  - a line whose id ALREADY EXISTS below replaces that line entirely,
  - an id you do not mention stays exactly as it is.

Do not restate a line you are not changing. Restating costs the human money and
risks changing what already holds. There is no way to delete a line: if the
language can only be read by dropping something, say so in the report and leave
it, so the human decides.

Change an existing line only where a program cannot be read otherwise.
Everything else in this prompt applies unchanged: the same value grammar, the
same confidence rule, the same demands and expects.

The report is the account of the language as it stands, not a log of this
patch. It is inherited like any other line, so leave it unmentioned when your
patch changes nothing it describes. When your patch changes or adds a pattern,
rule, demand, merge, ignore or expect, restate the report whole under its own
id, describing the language as it now is: lips refuses a changed engine whose
report is left as it was, and a second report beside the first.

{{ENGINE}}

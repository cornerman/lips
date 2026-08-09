<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `greet` language

This language describes a single kind of program statement: `install a command NAME that prints "MESSAGE".` Each such line names a shell command to build and install into the user's profile.

- Pattern `p1` captures the command's instance name (`<name>`) and the literal message it should print (`<msg>`), producing the fact `cmd.<name>.msg`.
- Rule `r1` realizes this as an artifact: a `writeShellApplication` build whose `name` is the captured command name and whose `text` is a one-line `echo` of the captured message. The built derivation is then added to `home.packages` so it lands on the user's PATH as `greet` (or whatever name is given).

I chose `writeShellApplication` as the plainest nixpkgs builder for "a command that prints a fixed string" — it needs no external dependencies and stays self-contained, matching the artifact mechanism's "keep source self-contained" guidance. I did not use a `source` heredoc because the printed message is a program VALUE, not fixed structure: baking it into a frozen source blob would mean an edit to the message could no longer flow through. Instead the message rides the rule's `<value>` hole directly into the builder's `text` argument, so future edits to the quoted message re-realize correctly.

No `expect` is emitted: the only observable option here (`home.packages`) holds a package/build reference, which the grammar explicitly forbids checking (no derivation-reading in an empty-pkgs evaluation). The artifact's `args.text` is not a real target-world option path either, so it is likewise exempt.

A demand (`q1`) is filed defensively for the message, in case some future line omits it — though every program seen so far states it inline.

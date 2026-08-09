<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `packages` language

This language reads one kind of program: a heading line `install packages:`
followed by one package name per line.

- `install packages:` is a heading. It carries no value of its own, so it
  realizes nothing; it only opens the block that the package lines sit in.
- each following line is a single package name (`wget`, `curl`, `neovim`).
  Each name becomes its own fact, `pkg.<name>`.

Mechanism: a NixOS configuration governs a whole machine, evaluated as root,
so there is no per-user profile to install into here. Every listed name is
lowered to `environment.systemPackages`, one element per line, aggregated
into a single list -- the system-wide profile, on the PATH of every user of
the machine. A name is looked up as `pkgs.<name>`, so a token that is not a
package attribute fails loudly at compile time rather than building
something wrong.

No expect is written: `environment.systemPackages` holds derivations, and a
derivation carries no checkable value, so the rule itself is the whole
contract. The demand asks a program that lists no packages at all which
packages it means, rather than silently realizing an empty machine.

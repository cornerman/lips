<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `packages` language

This language installs packages.

A program opens with the heading line `install packages:` and then lists one
package name per line under it. Each name is read as its own fact
(`pkg.<name>`), so the list may be any length and editing, adding or removing
a line changes exactly one package.

Mechanism per world:

- **NixOS**: each name becomes an element of `environment.systemPackages`, so
  the packages are installed machine-wide.
- **home-manager**: each name becomes an element of `home.packages`, so the
  packages are installed into the user's profile.

Both options are lists of packages, and lips aggregates the one-element list
each line contributes into a single list; a name repeated twice is installed
once (the default set merge), which is the right behaviour for a package list.

A package name is validated as an identifier and resolved as `pkgs.<name>`, so
a typo fails loudly at compile time rather than silently installing nothing.

No expects are written: both target options hold package derivations, which
carry no checkable value; the rules themselves are the whole contract. No
demands either -- a program that lists no packages simply installs none.

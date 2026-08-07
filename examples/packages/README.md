<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `packages` language

This language installs packages into the user's home profile.

A program is one heading line, `install packages:`, followed by one package
name per line:

```
install packages:
wget
curl
neovim
```

The heading is decoration: it only opens the block and realizes nothing. Each
line under it is a bare nixpkgs attribute name, and every such line
contributes one element to `home.packages`. Because the item pattern nests
under the heading, a stray word elsewhere in the file is not silently read as
a package -- it fails at compile time instead.

Each package name is its own decision (`pkg.<name>`), so two lines naming the
same package collapse to a single entry rather than duplicating it; that is
lips' default set merge for a list option, and it is what you want for a
profile.

No expect is written: `home.packages` holds derivations, which the behavioral
check cannot read. The rule itself is the contract -- the name you write
becomes `pkgs.<name>`, and a name that is not a valid attribute name fails
loudly at compile time rather than building something wrong.

A program that opens the heading and lists nothing is refused with a question
asking which packages to install, since an empty package language states
nothing.

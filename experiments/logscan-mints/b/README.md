<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->

# The `logscan` language

This language describes one small command-line filter for JSON log lines, and
turns it into a package installed on the machine.

## The five sentences it reads

1. `filter JSON lines read from standard input.`
   The sentence that says a tool exists at all. It carries the build: a Go
   program compiled with `buildGoModule` from the source tree staged beside
   the program (`artifacts/<instance>-core`). Nothing in it varies; "JSON" and
   "standard input" pick the mechanism (the parser, the input side), they are
   not values, so a program that words this line differently fails at compile
   time instead of quietly building something else.

2. `keep a line only when <every|any> field named on the command line equals
   the value given with it.`
   The one word that varies is the quantifier. It is carried into the source
   as the `@match@` fill, and the built tool implements both: with `every`, a
   line survives only if all `field=value` arguments match; with `any`, one
   match is enough. A word that is neither makes the tool refuse to start with
   a message, rather than guessing.

3. `print each kept line unchanged.`
   Decoration. The output side is fixed by the mechanism (the kept input line
   is written back byte for byte), so this line realizes nothing and lips
   reports it as decorative. It is still worth writing: it is what the claim
   below actually checks, and rewording it fails the compile, which is where
   you want to find out that the language cannot yet do what you asked.

4. `install the tool as the command <name>.`
   The word after "command" is the installed command name. It becomes a tiny
   `writeShellApplication` wrapper of that name which execs the compiled core
   and forwards its arguments, and the wrapper goes into
   `environment.systemPackages`, so the machine gets `logscan` on PATH.

5. `given the lines <a> and <b> with <field=value>, print only <c>.`
   The example. It becomes a claim: the compiled core is run with the stated
   arguments, fed the two lines on standard input, and must print exactly the
   line you said it would keep, and exit 0. This runs in the build sandbox --
   no machine is booted -- because the command names only the artifact.

## Why a wrapper instead of one build

A Go binary is named by its module, and the module name lives in the source,
not in an option. If the compiled binary were named from the program's word,
nothing outside the rule that reads line 4 could name its path -- and the
claim comes from line 5, a different rule. So the core is built under the
program's own instance name (`<self>-core`, binary `bin/<self>-core`, a stable
path the claim can use), and the program's word names the wrapper that is
actually installed. Rename the command in line 4 and the installed command
renames; the core keeps its internal name.

## What every program in this language must say

All four demands must be answerable by some line: what is read (1), how fields
must match (2), what command name to install (4), and a worked example (5).
A program missing any of them is refused with the question, not with a default.

## What I had to choose

The tool's version string (`0.1.0`) and the JSON-value comparison rule
(numbers, booleans and null compare by their plain text; objects and arrays
never match) are mine -- the program does not state them. Everything the
program does state is a hole or a literal template word, nothing was invented
in between. I also filed a gap: the clause notation, which would otherwise be
the right home for this behaviour, has no contract for command-line arguments
and no way to install a clause program as a command, which is why source is
baked here.

## Known Gaps

### no-argv-contract

blocked line: keep a line only when every field named on the command line equals the value given with it.
the clause notation has no contract for a process's own arguments. read-a-line reaches
standard input, but nothing reaches argv, and no emit binds a clause program to an
installed command name, so a filter whose spec is given on the command line cannot be
written as clauses at all. this mint therefore bakes a Go source tree instead.
minimal repro: a program saying "keep a line only when every field named on the command
line equals the value given with it" needs a contract like argv (0) -> list of strings,
plus a way to install the clause program under a command name.


# Cross-Program Composition

Date: 2026-08-12. Status: design settled by discussion, no code yet.
Driven by a falsifier rather than by speculation: `libero`, a football manager
written in lips, whose second language could not reach the first one's
vocabulary.

## The Defect, Measured

DESIGN's "Limits of Scale" already names this: "Cross-language composition is
accidental. Two languages meet today only by realizing into the same option
namespace. No decision refers across a language boundary." The falsifier shows
what that costs in practice, and it is worse than a missing feature.

A program in language `training` stated a reference to language `match`:

    contribution(p) := as defined by match.

The mint read it as "reads the raw `contribution` field of the player record".
No refusal, no warning, every gate green, and one concept quietly became two:
in `match`, contribution is rating times fitness per mille; in `training`, it
is a JSON field no fixture will ever carry. The kernel could not object,
because nothing in lips represents a reference across a language boundary, so
there was no name to fail to resolve. **Deduce-or-fail did not hold, and its
failure was silent.**

Two further limitations surfaced in the same mint, filed by it under its own
names, and both inform the design:

- `symbol-splice`: a clause hole may land only inside a quoted string or a
  typed literal, never as a bare identifier, so a definition's own name and its
  call targets cannot be holes.
- `two-shape-redefinition`: two differently-shaped lines defining one clause
  are refused, because the fold combines only lines matching the same pattern.

## What Composition Is

Composition is a **union of decision bases**, not an import system. The algebra
is already in place and needs no new concept:

- a base is an unordered set merged by subject;
- `clause.<name>` is a flat subject space;
- the covering gate already refuses a call to a name nothing defines.

So two languages compose when their decisions are unioned and the existing gate
judges the result. What is missing is not physics for composing; it is a way for
a program to SAY that it composes, and a way for the mint to know the imported
names before it invents its own.

## Names Are Namespaced by Construction

A flat `clause.<name>` space makes `report` in one language collide with `report`
in another, and a collision can only be refused, so a project of five languages
would have to keep a global name registry in its authors' heads.

The answer is to qualify a clause by its language, and the only question is
WHERE. Qualifying at realization was considered and rejected: it makes the
kernel rewrite names inside clause bodies, deciding which symbols are call
targets, which is a translation, and the logic axis is built on the opposite
principle that emitting is serialization, "so the structure lips checks and the
text a runtime runs are the same object", pinned by `parse . render = id`.

So the qualification happens at MINT time, where it costs nothing. The mint
knows which language it is writing, and emits the qualified name in the rule
itself:

    clause.player-contribution "(define (player-contribution p) ...)"

Nothing is ever rewritten, the round trip is untouched, and the sentence stays
clean, because the author writes `contribution(p)` and the RULE carries the
qualified name -- data, which is where per-problem knowledge belongs.

The kernel gains a check rather than a transformation: a clause subject declared
by language `L` must be `clause.L-<something>`, refused otherwise. That one
predicate makes collision-freedom a theorem, since two languages cannot share a
prefix and duplicates within one language are already refused. It also sharpens
provenance, because a name in the emitted core says where it came from.

Imports inherit the property: generate hands the importing mint the exported
names ALREADY qualified, so it calls `player-contribution` and cannot
accidentally define it, that name being outside its own namespace.

`main` is the one reserved exception, because the runtime's entry is fixed data
(`entry (main)`). It stays unqualified, and exactly one language in a composed
site may define it: the program being compiled. Also a check, not glue.

## The Bootstrap, Which Forces the Shape

When `training` is minted, the mint must already know which names `match`
defines. Otherwise it invents local definitions, which is precisely the observed
failure. Therefore the dependency must be readable **before any grammar exists
for that program**, which rules out carrying it in a minted pattern, and rules
out reading it after crystallization.

That leaves it in the fixed lexical frame, where lips already keeps the four
rules a program author must know (a line is the unit, a blank line carries
nothing, `#` is a comment, indentation is weightless except under a self-nesting
pattern) plus the filename convention `<instance>.<language>.lips`. The
dependency joins them as a fifth, and it stays domain-blind exactly as `#` is:

    uses match.

One keyword, one language name, terminated like any other line. The kernel reads
it before crystallizing and never asks what `match` means.

### Alternatives Rejected

A **sidecar file** (`training.uses`, beside `.direction`) keeps the program free
of new syntax and was rejected because a dependency is intent, not taste:
`.direction` is advisory and may be ignored, while an unresolved dependency must
stop the build. Splitting the two across files would put the load-bearing one in
the weaker channel.

**Co-location** (every program in a directory composes automatically) needs no
syntax at all and was rejected for being implicit: it couples programs that
merely share a folder, gives no way to state which vocabulary was meant, and
makes moving a file a semantic change.

A **CLI flag** (`generate --uses match`) was rejected outright: it puts the
dependency outside the only artifact a human owns, so the program would no
longer say what it needs.

## The Mechanism

**Generate.** Reading `uses match`, generate loads that language's committed
engine, extracts every `clause.<name>` it defines together with its arity, and
hands them to the mint as grounded external names, the same way the option
schema tool grounds an option path. The mint may call them and may not redefine
them. The imported engine is pinned by content hash in `.generation`, so the
mint's inputs stay complete and auditable.

**Compile.** The site is assembled from the union: the imported language's
clauses, then the program's own. Nothing is copied into the engine; the union
happens at realization, so `player` remains the single definition of its own
rules.

**The gate.** Imported names ground calls exactly as local clauses do. Two
definitions of one name across the union remain a conflict refused by name, as
the kernel's merge semantics already do one level down -- though with namespacing
by construction it can now only fire for `main` or for a bug in the prefix check.

**Claims.** A claim in `training` may call an imported clause, because the site
it runs against is the union.

**Drift.** If `match` is re-minted, `training`'s pinned hash no longer matches
and lips says so, naming the remedy. That is the contract between two languages,
and it is the same shape as the world pin and the schema pin.

**Cycles** are refused when the `uses` graph is not acyclic, before anything is
minted.

## Deliberately Out of Scope

**Identifier holes** stay impossible (`symbol-splice`). A joint between two
languages holds precisely because the name is literal on both sides; making a
name a hole would reintroduce the fuzzy joint this design exists to remove. The
cost is real and accepted: renaming a definition needs a re-mint, not an edit.

**Clause-level override** (`two-shape-redefinition`) stays refused. Composition
needs calling, not overriding, and the corpus has no case for the latter.
Refinement across languages should be reopened only when a program cannot be
written without it, and it would then be designed against the strength lattice
the kernel already has, not bolted onto the fold.

**Cross-language contracts beyond names.** A caller sees a name and an arity,
nothing else: no types, no pre- or postconditions. That is the same trade the
clause language already makes with its own contracts, and widening it is a
separate axis.

## Layering, Not Peer Imports

The falsifier had `training` depend on `match`, which is the wrong shape and was
an artifact of how the experiment was written. `contribution`, `rating` and
`fitness` describe a PLAYER, not a match engine, so a dependency on `match`
would drag ninety minutes of simulation into a language that only wants an
attribute, and `match` would become the god language every other one imports.

The vocabulary therefore gets its own small language, and the others are peers
that use it:

    player  <- match, training, transfer, season

The dependency graph stays a shallow tree, each layer is separately reviewable,
and `player` is exactly the artifact a modder reads first.

## A Dependency Belongs to the Language

A language's RULES do the calling, and one grammar is shared by every program
written in it, so a dependency is a property of the language rather than of an
instance. `classic.match.lips` and `arcade.match.lips` cannot coherently
disagree about what `match` uses.

The `uses` line still sits in the program, because that is the artifact a human
owns and a dependency is intent. Agreement is then a mint-time check: every
program of one language is read in the same call, so a disagreement is refused
there, naming both files.

## Consequences for the Kernel

- `Lips.Identity` gains the resolution of a language name to its engine
  directory, since it is the only module that knows those paths.
- `Lips.Language` gains reading another language's engine for its clause
  signatures, next to `mintedWorlds`.
- The reader of the lexical frame gains `uses`, beside `commentOrBlank`.
- `Generate` gains the imported signatures as a mint input and as a recorded,
  hashed one.
- `Realize`/`Stage` assemble the union into one site.
- The gate needs no change beyond receiving a larger ground set, which is the
  measure of whether this design is right: **if composition needs new gate
  physics, the shape is wrong.**

## The Test That Settles It

The falsifier repeats, corrected for layering. `player.lips` defines
`contribution(p)`, `training.lips` states `uses player.` and calls it, and
exactly one of two things happens: the call resolves to `player-contribution`,
or lips refuses by name. Silently becoming a JSON field must be unreachable.

A second test settles the namespacing: two languages that both define `report`
compose into one site without a word of renaming by either author.

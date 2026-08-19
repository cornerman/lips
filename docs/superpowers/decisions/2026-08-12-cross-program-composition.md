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

A program in language `training` stated a reference to another language:

    contribution(p) := as defined by match.

The mint read it as "reads the raw `contribution` field of the player record".
No refusal, no warning, every gate green, and one concept quietly became two: in
`match`, contribution is rating times fitness per mille; in `training`, a JSON
field no fixture will ever carry. The kernel could not object, because nothing in
lips represented a reference across a language boundary, so there was no name to
fail to resolve. **Deduce-or-fail did not hold, and its failure was silent.**

Two further limitations surfaced in the same mint, filed by it under its own
names, and both shape the design:

- `symbol-splice`: a clause hole may land only inside a quoted string or a typed
  literal, never as a bare identifier, so a definition's own name and its call
  targets cannot be holes.
- `two-shape-redefinition`: two differently-shaped lines defining one clause are
  refused, because the fold combines only lines matching the same pattern.

## What Composition Is

Composition is a **union of decision bases**, not an import system. The algebra
is already in place and needs no new concept:

- a base is an unordered set merged by subject;
- `clause.<name>` is a flat subject space;
- the covering gate already refuses a call to a name nothing defines.

Two languages compose when their decisions are unioned and the existing gate
judges the result. What was missing is not physics for composing; it is a way to
SAY that you compose, and a way for the mint to learn the imported names.

## A Dependency Is an Atom

A dependency is stated in the program, in the author's own words, and
crystallizes into a decision of its own kind:

    players come from standard.player.        <- the program line

    d4 uses player stated "standard" @match.lips:3

The kind is the twelfth member of a closed enum (`Concept, Fact, Oblige, Forbid,
Allow, Invariant, View, Assume, Steer, Glue, Meta`), the subject is the language,
the assertion is the instance, and the provenance is the line that said it.

It is a KIND rather than a fact with a reserved subject (`fact uses.player`)
because the kernel may not special-case a word. A kind is a structural category,
and structure is the only thing the kernel is allowed to know. Everything else
falls out of physics already present: two `uses` decisions on one subject with
different instances are an equal-strength disagreement, so merge reports a
conflict carrying both provenances and refuses, with no new rule anywhere.
Realization ignores the kind; the site assembler consumes it.

## Discovery Is a Tool, Not a Frame

The apparent obstacle was the bootstrap: when `match` is minted, the mint must
know which names `player` exports, or it invents local ones, which is the
observed failure. That seemed to force the dependency out of the program and
into something the kernel reads without a grammar.

It does not, because lips already solved the same problem for option names. The
mint does not know `services.restic.backups.<name>.paths` in advance either; it
asks `query_options` and grounds the answer, and every answer is recorded in
`.generation` and enters the hash. A dependency is the same question, so it takes
the same answer: a second tool, `query_language <name>`, returning that
language's exported clause names and arities.

So the mint reads a line in whatever wording the author chose, asks, grounds, and
writes a pattern producing the `uses` decision. Nothing needs to exist before the
call, the lexical frame stays at four rules, and no new human-written file type
appears.

### Alternatives Rejected

**A language-level sidecar** (`match.uses`, beside `match.direction`) was the
design's previous shape and was rejected on two counts. It cannot express the
instance choice without a resolution convention, and every such convention is a
hack the moment two worlds share one vocabulary instance while a third has its
own. And it puts a load-bearing statement in the slot occupied by the advisory
channel, where `.direction` may be ignored and this may not.

**A fifth lexical rule** (`uses player.` read by the kernel before
crystallization) was rejected once the tool made it unnecessary. The frame is
four rules and every addition to it is paid by every program forever.

**The call is the declaration** (no statement at all: generate offers every
sibling language, the engine records what it calls) was rejected for loudness. A
missing or misspelled dependency can always be answered by an invented local
definition, since defining something locally is legal, so the silent failure that
opened this design would stay reachable.

**Co-location** (every program in a directory composes) was rejected for being
implicit: it couples programs that merely share a folder, and moving a file
becomes a semantic change.

**A CLI flag** was rejected outright: a binding dependency outside every artifact
means the repository no longer says what it needs.

## Names Are Namespaced by Construction

A flat `clause.<name>` space makes `report` in one language collide with `report`
in another, and a collision can only be refused, so a project of five languages
would need a global name registry in its authors' heads.

The answer is to qualify a clause by its language, and the only question is
WHERE. Qualifying at realization was considered and rejected: it makes the kernel
rewrite names inside clause bodies, deciding which symbols are call targets,
which is a translation, and the logic axis is built on the opposite principle
that emitting is serialization, "so the structure lips checks and the text a
runtime runs are the same object", pinned by `parse . render = id`.

So qualification happens at MINT time, where it costs nothing. The mint knows
which language it is writing and emits the qualified name in the rule:

    clause.player-contribution "(define (player-contribution p) ...)"

Nothing is rewritten, the round trip is untouched, and the sentence stays clean,
because the author writes `contribution(p)` and the RULE carries the qualified
name, which is data.

The kernel gains a check rather than a transformation: a clause subject declared
by language `L` must be `clause.L-<something>`, refused otherwise. That one
predicate makes collision-freedom a theorem, since two languages cannot share a
prefix and duplicates within a language are already refused. It also sharpens
provenance, because a name in the emitted core says where it came from.

The entry point needs no exception. A runtime states how it starts a program as
data (`entry (main)` in `assets/runtime/guile/runtime`), and lips derives from
that line which symbol the core must define. Namespacing would leave that symbol
undefinable, so the entry line gains a hole like every other value in lips:

    entry (<entry>)

`compile` knows which language it is compiling and fills `match-main`. Nothing is
reserved, no glue appears, and a runtime that starts a program differently still
owns its own spelling.

## The Mechanism

**Generate.** Reading a line the mint takes for a dependency, it calls
`query_language`, receives that language's exported clause names and arities,
grounds its calls against them, and writes the pattern that produces the `uses`
decision. The exported signatures and the engine they came from are recorded and
hashed like every other mint input.

**Compile.** Crystallizing yields the `uses` decisions, so compile never reads
the program's syntax to learn a dependency. It resolves each named instance,
crystallizes and realizes it with its own engine, and assembles one site from the
union: imported clauses first, then the program's own.

**The gate.** Imported names ground calls exactly as local clauses do. Two
definitions of one name across the union remain a conflict refused by name.

**Claims.** A claim may call an imported clause, because the site it runs against
is the union.

**Drift.** If `player` is re-minted, the pinned signature hash in `match`'s
`.generation` no longer matches and lips says so, naming the remedy. That is the
contract between two languages, the same shape as the world pin and the schema
pin.

**Cycles** are refused before anything is minted.

**Pruning.** A dependency is an upper bound on what a language may reach, while
what a given instance actually reaches is derived: realization runs over one
instance's decisions, so a site holds only the imported clauses that instance
reaches. Declared at the program, computed at the site.

## Layering, Not Peer Imports

The falsifier had `training` depend on `match`, an artifact of how the experiment
was written. `contribution`, `rating` and `fitness` describe a PLAYER, not a match
engine, so depending on `match` would drag ninety minutes of simulation into a
language that wants an attribute, and `match` would become the god language every
other one imports.

The vocabulary gets its own small language and the others are peers that use it:

    player  <- match, training, transfer, season

The graph stays a shallow tree, each layer is separately reviewable, and `player`
is the artifact a modder reads first.

## Deliberately Out of Scope

**Identifier holes** stay impossible (`symbol-splice`). A joint holds precisely
because the name is literal on both sides; a name that is a hole reintroduces the
fuzzy joint this design removes. Renaming a definition needs a re-mint.

**Clause-level override** (`two-shape-redefinition`) stays refused. Composition
needs calling, not overriding, and the corpus has no case for the latter. It
should be reopened only against the strength lattice the kernel already has,
never bolted onto the fold.

**Cross-language contracts beyond names.** A caller sees a name and an arity: no
types, no pre- or postconditions. That is the trade the clause language already
makes with its own contracts.

## Related Finding, Not In This Design

The rationale field is one hop from working. The atom carries it
(`Decision.dRationale`), the line format carries it (`Reader.hs:12`,
`… "<assertion>" [<provenance>] [-- <rationale>]`), it is parsed and rendered,
and crystallizing a program sets it unconditionally to `Nothing`
(`Crystallize.hs:196`). So a reason has a home everywhere except where a human
could state one. Recorded here because it came up while asking what comments are
for, and it is a separate design.

## Consequences for the Kernel

- `Decision.Kind` gains `Uses`; reader and renderer follow.
- `Crystallize` produces it from the pattern the mint writes.
- `Lips.Identity` resolves a language name and an instance to their paths.
- `Lips.Language` reads another language's engine for exported signatures.
- `Generate` gains the `query_language` tool and records its answers.
- `Realize`/`Stage` assemble the union into one site.
- The gate needs no change beyond a larger ground set, which is the measure of
  whether this design is right: **if composition needs new gate physics, the
  shape is wrong.**

## The Test That Settles It

The falsifier repeats, corrected for layering. `player.lips` defines
`contribution(p)`, `training.lips` says where its players come from and calls it,
and exactly one of two things happens: the call resolves to
`player-contribution`, or lips refuses by name. Silently becoming a JSON field
must be unreachable.

A second test settles the namespacing: two languages that both define `report`
compose into one site with no renaming by either author.

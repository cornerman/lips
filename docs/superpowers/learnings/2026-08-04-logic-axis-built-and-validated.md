# Building and Validating the Logic Axis

Record of one long session (2026-08-04), branch `logscan-clauses`, 59 commits.
It starts from a question ("could lips generate compilers for Rust or
JavaScript?") and ends with behaviour minted as clauses, gated, running, and
measured. Companion documents: the falsifier result
(`2026-08-04-logscan-clause-falsifier.md`), the four live engines
(`experiments/logscan-mints/`), the scenario corpus (`experiments/validate/`),
and the plan (`docs/superpowers/plans/2026-08-04-logic-axis-plan.md`).

## The Argument, Settled

**A general-purpose language cannot be the target, and the reason is not
capability.** The decision calculus is an unordered set of `path = value`
decisions merged by path. A statement sequence composes by order and mutation,
so `x = 1; x = 2` has no image in it. Teaching the kernel that one particular
target composes by last-write-wins is the one thing the kernel must never learn.

**Printing is not the objection; translating is.** lips already owns two
printers (`renderValue` for Nix, `renderSexp` for clauses). The distinction that
matters is serializer versus translator. A serializer maps a structure onto a
syntax that already IS that structure, so `parse . render = id` is a test you can
run. A translator into Go or Rust must choose a `match` or an if-chain, what is
owned, which name each temporary gets; those choices are semantics appearing in
no clause the gate checked, and no round trip can recover them.

**The hidden cost of a printer is a type system.** Printing into a typed host
means knowing that `field-of` returns an optional JSON value. Contracts would
stop carrying an arity and a sentence and start carrying real signatures, which
is a new axis, not a printer.

**What a printer would buy is already reachable.** A host's libraries arrive as a
contract whose adapter is a package that host built, named and never read. Host
performance matters for nothing measured. Host familiarity is the one honest item
on the list. Falsifiable trigger to reopen, recorded in `DESIGN.md`: a program
whose LOGIC must run where no Lisp can live and nothing can be called by name,
which leaves eBPF, a GPU shader, an EVM contract, a spreadsheet cell.

**The shape that works is a safe subset of somebody else's language.** Prior art
is uniform: Joe-E verifies a capability-safe subset of Java, SES one of
JavaScript, SPARK one of Ada, Starlark a deterministic Python. Keep the runtime
and the libraries; forbid the forms that reach the world unannounced. lips owns a
gate and a contract vocabulary, owns no semantics, ships no runtime.

**Capabilities bind by NAME at link time, not as passed values.** That one choice
keeps the clause language first-order (no closures to pass), lets one core serve
several runtimes, and makes every clause claim-testable by linking a different
adapter. It is the same move as `${pkgs.<path>}`: a name realize resolves.

**Runtime choice is arithmetic, never a model's decision.** Contracts come from
the clauses (derived), properties come from the author (stated), the catalogue
says who offers what, and `coveringRuntime` intersects. It fails rather than
guesses in both directions: nothing covering names the gap, several covering
lists the candidates. The choice happens at compile, after the mint is gone, so
switching runtimes relinks adapters instead of re-minting.

## What Was Built

Kernel (domain-blind, `-Wall` clean, 716 suite examples):

- `Kernel/Sexp.hs` — the closed clause grammar. Parse, render, fill. Never
  evaluated. A symbol is the only way a clause names anything; no constructor
  turns a program word into code. Hole marker is `#<value:int>`, because `<` and
  `>` are ordinary Scheme identifier characters and a clause must write `(< n 3)`.
- `Kernel/Hole.hs` — `HoleType`, shared by both value grammars so `<value:int>`
  cannot come to mean two things.
- `Kernel/Clause/Vocabulary.hs` — definers, binders, forms, base procedures,
  contracts, as data.
- `Kernel/Clause/Gate.hs` — the subset gate. Every free identifier grounded,
  every clause provenanced, every call's argument count checked against the
  declared arity. `reachedContracts` reports the program's whole reach.
- `Kernel/Clause/Catalogue.hs` — runtimes as data, `coveringRuntime`,
  `entryDemand` (what the core must define, derived from the entry expression),
  `siteFile`, `clauseClaimsFile`.
- `Kernel/Grounding.hs` — what vouches for each assertion, counted: schema,
  contracts, author, or nothing; plus the words a mint wrote into option strings,
  which no schema vouches for.
- `Realize.realizeClauses` — clause decisions assembled in program-line order,
  provenance walked back through `Derived` parents to the sentence, gated.
- `Value.VSexp` — a clause is a rule's right-hand side.
- `Lips/Site.hs` — the site plan, pure: which runtime, which files, total
  content. `app/Main.hs` only writes what it returns.
- `Lips/Runtime.hs` — loads the shipped assets, keeping the kernel a reader.

Data (reviewable assets, not code):

- `assets/runtime/scheme/{vocabulary,contracts}` — the notation and its nine
  contracts.
- `assets/runtime/guile/` — `runtime` declaration, pure adapter, effect adapter,
  in-memory adapter, claim harness, `site.nix` builder.
- `assets/mint/body.md` — the clause doctrine, with the contract list rendered
  from the shipped vocabulary so prompt and gate cannot drift.

Reserved subject heads now: `artifact.*`, `claim.*`, `clause.*`, `site.*`.

## Bugs Found, and What Found Them

Every one of these passed the suite. Each is now pinned by a regression test
naming what found it.

| defect | found by |
|---|---|
| `generate` never ran the clause claims, so a clause engine's only contract was unverified | review pass 1 |
| `site.*` unreserved, so the prompt taught an emit the option grounder refuses | review pass 1 |
| `${site}` with no clauses realized a module importing a directory compile never writes | review pass 1 |
| claims file loaded the real effect adapter and shadowed it (worked by last-write-wins) | review pass 1 |
| clauses rendered INTO the module as `clause."keep?" = (define ...)`, unparseable Nix | first live mint |
| the site binding was decided from option values only, missing a reference from an artifact argument | live mint |
| `claims.nix` needed the same binding | live mint |
| every gate's temp directory needed the site staged beside the module | live mint |
| entry called `(main (arguments))` while both cores defined `(define (main) ...)`; both binaries died on first run | two live mints |
| `#tomato` parsed as `#t` (first letter taken, rest dropped) | review pass 2 |
| a `die` inside a claim aborted the whole claims file, and a fail-loud sentence could not be claimed at all | review pass 2 |
| contract arity declared and never read: `(emit)` with no argument accepted | review pass 3, on being challenged |
| `(emitted)` existed in the memory adapter and the prompt never said so, so no model could observe printed output | `tally` scenario |
| grounding called a mint-invented shell pipeline in `systemd.services.x.script` a vouched option assignment | `report` scenario |

The pattern worth carrying forward: **the last two review passes found the same
shape, a fact declared in one place and consumed in another with nothing checking
they agree.** Entry versus core, arity versus call. One instance remains open by
choice: a runtime's `provides` list is not checked against what its adapters
actually define.

## What Was Measured

Falsifier (`TODO.md` item 8, `logscan`): 24 lines of clauses against 70 of Go,
8 of 8 traceable against roughly 15 of 76. Three of five invented policies became
demands, one vanished for want of a knob to invent (a 16 MB line limit), one
reversed to the faithful reading of the author's own word "every".

Check (c), two live mints of one program: both chose clauses, neither wrote
source, and the two binaries agree byte-for-byte on thirteen probes including the
two where the Go mints diverged (exit code 1 versus 2; `{"a":1e-7}` kept by one
and dropped by the other). They do NOT agree textually: the cores factor the loop
differently. So two mints differ where the program does not in TEXT and not at all
in BEHAVIOUR, on this program.

Scenario corpus (`experiments/validate/`, 36 cases, all green): `logscan` (JSON,
conjunction, fail-loud), `tally` (accumulation, output at end), `threshold` (a
stated number reaching a clause), `watch` (clauses and a systemd timer from one
program), `dedupe` (state threaded through recursion), `report` (ranking with no
sort primitive, wrote its own selection sort).

**The thesis, demonstrated once explicitly.** `threshold` holds
`(define (above? text) (> (string->number text) #<value:int>))`. Editing the
program from `above 100` to `above 200` and running `compile` with no model
changed the clause to `(> ... 200)`; the rebuilt binary dropped `web 150` and kept
`db 250`.

**Language reuse costs nothing.** `nginx.watch.lips` shares `heartbeat`'s engine
with no model: same two clauses, one word different, two commands installed.

## The Boundary, and Why Not to Invent Past It

`rotate` (delete files older than 14 days under three directories) produced 97
lines of Go and never considered clauses. There are nine contracts and all nine
serve one shape: stdin, stdout, arguments, stopping, JSON, three helpers. **The
clause axis reaches text tools that read stdin and write stdout, and nothing
else.** Files, clocks, processes, sockets have no contract to name.

Do not invent `list-directory`. That breaks the vocabulary scaling law, which is
the only reason the configuration axis works: lips reaches as far as some
EXTERNAL named typed vocabulary reaches, and nixpkgs is that authority for
options. Inventing an effect interface makes lips the authority for one it must
maintain forever. The named candidate is in the 2026-08-02 decision: WIT, which
names behaviour without naming an implementation language, with WASI's filesystem
and clock interfaces as the typed authority. **This is the open decision that
settles whether the axis is a text-tool niche or a general capability.**

## One Limit Claimed and Withdrawn

I recorded "a witness fixes its own arity" as a missing repeating hole in the
template grammar. It is not a grammar gap. `Lang/Nest.hs` already carries the
case and its header says why the kernel must not carry it any other way: "the
kernel would otherwise be dictating a collection syntax". A block is a header
pattern plus a child keyed by `<n:index>`, and `Append` assembles one list from
the N contributors. Demonstrated with one hand-written engine over three and five
items, no model, and the five-item run correctly failed the claim whose expected
value still said three.

Fixed in the prompt, not the kernel. Narrower than first stated: the rule bites
when an author writes a list as a block, and cannot change how a mint reads an
inline sentence, which is why the re-minted `logscan` still has
`given the lines <in1> and <in2>`.

The other claimed limit stays outside on purpose. Converting `ten` to `10` needs
a table of one language's number words, and a count is already expressible by
writing `10`, which `threshold` proves end to end.

## Doctrine Landed

**No per-program source written by a model.** A blob is admissible only where it
is not per program and reviewed once (an adapter under `assets/runtime/`), or
where it is somebody else's package reached by name. Where no contract covers the
capability, baked source stays admissible, because refusing it refuses the
program rather than the mechanism.

**Behaviour nothing observes is refused.** `generate` refuses an engine that bakes
source with no claim, and one that mints clauses with no claim over them. This was
a warning for months while `logscan` demonstrated the cost.

**The escape for a one-off is a value, never a file.** `greet`'s four words of
bash are bounded by sitting in one assertion attached to one program line; a
staged tree has no such bound and grew to 76 lines. Author glue (foreign text in
the program) is legitimate; mint glue is counted and must be pinned by a claim.

## Where It Stands

`examples/logscan` is clauses: 5 clauses where 76 lines of Go were, grounding line
reads `0 unvouched assertions`. All ten plan tasks landed, Task 10 (several sites
per program) deliberately as shape only, with two sites refused rather than
guessed. 716 suite examples, 36 validation cases, 21 corpus programs, package
builds, `nix flake check` green including VM boots.

Open, in priority order:

1. **The effect vocabulary decision** (WIT/WASI or not). Everything about the
   axis's reach depends on it, and no further validation inside the current
   boundary is informative.
2. `app/Main.hs` is 2000 lines; the gates deserve their own modules.
3. A runtime's `provides` is not checked against what its adapters define: the
   last known instance of the declared-but-unverified pattern.
4. `examples/function.lips` bakes source with no claim, so a future re-mint of it
   is now refused until its program states an example.

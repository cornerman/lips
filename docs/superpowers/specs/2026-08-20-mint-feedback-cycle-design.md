# The Growth Mint: a Feedback Cycle an Author Can Stay Inside

**Status:** decided, unmeasured, ready to build in three errands. Errand 1
(measurement) is the gate on the other two: every speed claim below is a
hypothesis until its stats file exists.

## The Defect

An author with a working language writes a line the language cannot read.
`compile` refuses loud and names `generate` (correct, deduce-or-fail), and
`generate` then re-mints the language FROM ZERO: the model re-emits the whole
engine, 4 to 6 minutes, opus wherever artifacts are involved. Committed sizes
say what that output is: `examples/habit` 1569 bytes of grammar plus 5682 of
rules, `examples/board` 1400 plus 4551, `examples/website` 945 plus 2997.

The wait breaks the edit loop, and the loop is the promise: edits within the
current language cost zero AI (DESIGN §"the loop"), so the one act that leaves
the loop is the one an author hits every time the language must grow. Growth is
not rare. It is how a language reaches its second sentence.

What makes the whole re-mint look necessary and is not: the belief that
soundness comes from the model rewriting everything. It does not. Soundness
comes from the gates, which run over the whole corpus regardless of how the
engine was produced (`generate`'s `progs`, `Lips.Kernel.Engine.Gate`, the
committed `.expect` under `--compat`, the claim gate, the artifact build).

Cost profile, as far as it is measured today (DESIGN §13, the `--thinking`
entry): lips' own work is under 1% of a mint (one `check_draft` ~0.95s inside a
six-minute mint), the same program minted in 6m22s at `high` against 4m17s at
`medium`, and TURN COUNT dominates (one program took 23 drafts before its
prompt was corrected, 3 after). So the minutes are model turns and the tokens
they carry. Nothing beyond that is measured, which errand 1 exists to fix.

## Errand 1: Measure the Mint

**What.** Every mint writes an unsealed stats file beside the sealed record,
`<language>/<world>/<lang>.timing`, holding the LAST event, exactly as
`.generation` holds the last record (history is git's job, not a growing log).
It is COMMITTED, like every other machine-written file in a world folder: the
cost of a mint is a fact about the committed engine, and a reviewer comparing
two mints wants the diff. Its path lives in `Lips.Identity` with the others, so
nothing else in the tree knows how a language folder is spelled.

Contents, each item chosen because a design decision waits on it:

- total wall time, and per phase (schema, mint, gates, artifacts). `Lips.Cli.Output`
  already computes these durations for the live display and discards them.
- model turn count, and tool calls by name with counts. The `check_draft` count
  is the interesting one: it says whether turns are spent drafting or thinking.
- token usage, if pi's `--mode json` stream carries it. pi's assistant messages
  carry `usage { input, output, cacheRead, cacheWrite }` (pi docs,
  `docs/custom-provider.md`); whether the `agent_end` event lips already parses
  (`Lips.Generate.PiJson`) exposes it must be verified at implementation. If it
  does not, the file records turns and wall time and says nothing about tokens
  rather than guessing them.
- the verdict (accepted, or which gate refused), and the basis (errand 2).

**Where it may NOT go: `.generation`.** That record's bytes hash to the id every
minted line is stamped with (invariant 6), so a duration inside it would make
`genId` differ between two identical mints, and every stamp unreproducible. The
stats file is therefore a separate concept on purpose: sealed inputs in the
record, observed costs beside it.

**Why first.** Errand 2's justification is "output tokens and turns dominate,
so a small patch is a short mint". That is plausible and unmeasured. The stats
file is also what would decide the model question (below) and what would tell us
where the lips-developer's own re-mint loop spends its minutes.

**Consequence worth having:** DESIGN §13 records per-mint datapoints by hand
today. After this they are machine-recorded.

## Errand 2: The Growth Mint Is a Patch Keyed by Id

**What.** `generate` against a language that already has a committed engine
sends that engine for the target world (grammar, rules, demands, expects) into
the prompt, and asks for a PATCH rather than an engine:

- a line with a NEW id adds it,
- a line whose id EXISTS replaces it,
- an id not mentioned is inherited verbatim.

Deletion has no form. Dropping a pattern is what `--fresh` is for, so the patch
grammar stays the reply grammar that exists, with nothing new for a model to
learn and nothing new for lips to parse.

**Reuse, not invention.** The mechanism is already here for the multi-world
case: `inheritedGrammar` (kernel/app/Main.hs) reads the committed grammar when
`grammarIsFrozen` says a run does not cover every world, `assets/mint/grammar.md`
carries it into the prompt, and `appendOnlyViolations`
(`Lips.Generate.Minting`) refuses any change to an inherited pattern. Two
extensions: inheritance covers RULES as well as the grammar, and it applies to
the same-world case (today `grammarIsFrozen ["nixos"] ["nixos"] = False`, so a
one-world language inherits nothing).

**Edit is allowed, and needs no new guard.** A patch that REPLACES a committed
line is exactly as guarded as today's full re-mint, because the gates are
identical and they already see everything: every program of the corpus must
still crystallize, the engine gate still refuses a non-orthogonal engine, the
committed `.expect` must still hold under `--compat`, claims still run, the
artifact still builds. A patch that breaks the contract fails loud and names
`--compat`, which is the existing re-blessing door (invariant 5: a break is a
human decision, never silent).

**Append-only stays exactly where it is.** It is required for a world ABSENT
from the run, whose rules are not re-minted and must not have the shared grammar
moved under them. It is not required for the world being minted.

**Default: inherit; `--fresh` rewrites.** Growth is the common act, so the cheap
path is the default one. The basis is a sealed INPUT of the event and enters
`.generation` and thus `genId`: `basis: inherited <genid-of-basis>` or
`basis: fresh`. So invariant 6 keeps pinning every input, and a chain of patches
is traceable back to the mint it grew from.

**Accepted cost, stated rather than hidden.** Prompt improvements and kernel
physics changes stop reaching committed languages until somebody runs `--fresh`.
That is the price of not re-paying for a rewrite on every growth, and the record
now says which basis produced each engine, so the ossification is visible rather
than assumed.

**The claim to measure, not to assert.** Output shrinks from a whole engine to a
few lines; turns should shrink with it, since there is less to get right per
draft; and a pure append may become sonnet-able. The model DEFAULT does not move
on that hope: DESIGN §13 records sonnet-5 regressing artifact mints twice
(dropping the built artifact in `function`, installing `habit`'s script under two
names so its claim would pass), so the cheaper model is a measurement errand
against the stats file, not an assumption.

**Implementation notes (not decisions).** `check_draft` keeps working once the
draft folder is materialized as "committed engine patched by this reply", which
is a change inside `Lips.Generate.Draft`. The write phase should print which ids
were added and which replaced, since that is the diff a human wants to see
before the engine changes under them.

## Errand 3: `compile --watch`, One Key to Mint

**What.** Poll the program and its engine files (~250 ms mtime poll; the dev
shell has no fsnotify, and polling a handful of paths costs no dependency),
re-run the pure pipeline on change, and print the diagnosis or the realized
summary. Crystallize and realize are pure and need no nix, so the loop is
instant.

When a line does not crystallize, the remedy line becomes an offer: `g` runs the
growth mint, `q` quits.

**Invariant 1 is intact, and the code must say so.** `compile` never calls a
model. The watch loop is a DRIVER around it, and the mint is a deliberate
keypress that runs the ordinary `generate` path with all its gates. A reader who
finds a model call reachable from a `compile` flag will read it as a violation
unless the comment states the separation, which is exactly the kind of
surprising line the review rules say must be documented or flagged.

## Rejected

- **`generate --watch`.** Mints on save, so it burns a model call on every
  half-written program, and mints programs whose author is mid-sentence.
- **`compile --generate-if-it-does-not-compile`.** Puts a model call inside the
  deterministic verb, which is the one line invariant 1 draws. The watch-loop
  keypress buys the same ergonomics with the boundary intact.
- **Shortening the mint prompt to save time.** Input is the cheap side (and the
  cacheable one), a second shorter prompt is a second thing to keep true, and
  the 1026-line body is what makes a mint correct. Revisit only if errand 1
  shows input latency mattering.
- **Auto-escalating a failed patch to a full re-mint.** One command that
  silently pays either 20 seconds or 6 minutes teaches nobody which cost they
  are in. Refuse and name `--fresh`.

## Sequencing

Errand 1, then 2, then 3, each in its own worktree as a small commit series,
`just test` throughout and `just ci` before merge. Errand 1 gates the others:
after it lands, one growth mint of a committed example measures the before, and
the same mint under errand 2 measures the after, so DESIGN §13 records a number
rather than an expectation.

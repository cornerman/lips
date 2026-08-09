# One Mint, Many Worlds

**Status:** decided, measured, ready to build. Supersedes the sequential
per-world mint decided in `2026-08-07-multi-world-builds-design.md` §3 and built
on 2026-08-09 (DESIGN §13, "One program, several worlds").

## The Defect

Multi-world builds ship a shared grammar and per-world rules, minted by one
model call per world, left to right. The grammar is written by the FIRST call,
which sees one world. So the language's cross-world contract is authored by a
party that cannot see the contract's other side.

Measured, three live mints of `examples/nightly.timer.lips` for `nixos,kubenix`:
every one wrote `fact job.schedule "<time>"`, spelling the time as one atom.
NixOS accepts that (its `OnCalendar` contains `03:00` verbatim); a Kubernetes
CronJob does not (`spec.schedule` wants `0 3 * * *`). Nothing below the mint can
convert one to the other, by construction: the value grammar has no computation.
So the kubenix mint refused, correctly, naming the conversion it could not make.

The refusal names a remedy: "re-mint every world together: `lips generate
--target nixos,kubenix <program>`". Under sequential mints that command runs the
nixos call first, with the same information it had before, and writes the same
coarse grammar. **The remedy lips prints does not converge.** That is the defect,
and by invariant 4 it is fixed in the physics, not the wording.

Stated structurally: the call that DISCOVERS the defect must be the call with
the AUTHORITY to fix it. The kubenix mint diagnosed it precisely and was the one
call forbidden to touch the pattern.

## The Decision

One model call per LANGUAGE. It receives the corpus, the optional direction, and
every requested world's preamble, each scoped to its own section. It answers with
one engine: patterns and source blocks, which are shared, and rules, demands,
merges and expects, each tagged `@<world>`. Gates run per world over that world's
engine (grammar plus its rules); worlds that pass are written, a world that fails
is refused alone, and the run exits nonzero.

Rejected alternatives, with the reason each fails:

- **Computation in the value grammar** (a Nix call, or a closed set of
  transforms). `<value.N>` exists precisely because a mint otherwise unpacked
  packed values with Nix `splitString` gymnastics (kernel/README). It also makes
  a rule code you must execute rather than data you read, and hides program
  words from the grounding count. A closed set is an OPEN list in disguise:
  split, join, pad, reorder, ISO-8601, base64. The kernel may not enumerate.
- **Two phases** (a grammar call, then per-world rules calls). Loses the
  co-design that produces neutral grammars in the first place: the pattern is
  shaped by the rule the same answer must write. Leaves the shared `artifacts/`
  tree with no single author.
- **Prompt-only** (tell world one to be neutral). Tried, three mints, failed
  every time. A general rule with a hypothetical example does not create the
  local pressure that a rule the same answer must write does.
- **Gap feedback** (feed the refusing world's `.gap` into the joint re-mint).
  Converges only after a wasted round-trip, and leaves discovery and authority
  in different calls. Kept on record as the fallback if the measurement below
  ever inverts.

## The Measurement

One hand-composed call, 2026-08-09: the real body prompt, both preambles scoped,
the tag rule, the `examples/cron` worked example, `query_options` prototyped with
a world argument, `check_draft` withheld (it cannot read tags yet),
opus-5, thinking medium, `examples/nightly.timer.lips` as the corpus.

What it answered, first try:

    p1 pattern run <cmd> every day at <hh>:<mm> => fact job.command "<cmd>" ; fact job.schedule "<hh> <mm>"
    r2 @nixos   ... systemd.timers.<self>.timerConfig.OnCalendar  "\"*-*-* <value.1>:<value.2>:00\""
    r5 @kubenix ... kubernetes.resources.cronJobs.<self>.spec.schedule "\"<value.2> <value.1> * * *\""

Every question the measurement was for:

1. **Decomposition: yes**, first try, the exact form three sequential mints
   missed.
2. **Preamble scoping: held.** No nixos option under a `@kubenix` tag, none the
   other way. This was the one risk that fails silently rather than loudly.
3. **Tagging: correct.** Every rule, demand and expect tagged; patterns and the
   report untagged.
4. **Per-world lookup: correct.** Ten `query_options` calls, each naming the
   world whose schema it wanted.
5. **The report** came back as one account covering both worlds, which is why a
   joint mint files it at the language level.

Two findings the measurement produced that the design must absorb:

- **Invention where a demand was owed.** kubenix needs a container image; the
  program states none. The mint invented `busybox:latest` at confidence 0.8,
  above the 0.7 threshold, so it would have shipped, with an honest
  because-note and a paragraph in the report. The right answer is a kubenix
  `demand`, which is what `examples/cron`'s `q1` writes. The prompt must say:
  where a world needs a fact the program does not state, write that world's
  demand, never a value.
- **An unanswered demand is a WORLD's fact.** Demands live in `<world>/*.rules`,
  so a program that satisfies nixos and leaves kubenix's demand open must fail
  kubenix alone. `checkWorld` currently treats `OpenQuestions` as fatal for the
  whole run, on the reasoning that a demand is a fact about the program. That
  reasoning predates per-world demands and is now wrong. A CONFLICT stays fatal:
  it is refinement over the shared grammar, true in every world.

## Consequences

- **Shared artifacts have one author.** `<language>.grammar`, `artifacts/`, the
  record and the joint README are written only by a call that saw every world.
  When some committed world is not being re-minted in this run
  (`Lips.Language.grammarIsFrozen`), all of them are read-only and the mint may
  write only its world's folder. This closes a live clobber: today every world's
  mint replaces `artifacts/` wholesale (`app/Main.hs:1010`), so a second world's
  mint silently deletes the source the first world's rules reference.
- **One event, one record.** The joint record sits at the language level and
  pins every world it covers by name and content hash, plus each world's schema.
  A world minted alone keeps writing its own record in its folder, and
  `readRecordedWorld` prefers the world's own record, falling back to the
  language-level one.
- **The account is filed at the scope of the event.** A joint mint writes
  `<language>/README.md`; a single-world mint keeps writing `<world>/README.md`,
  so no committed example moves.
- **Ids are unique across the reply**, except a `because` note, which shares the
  id of the item it explains.
- **Single-world replies stay byte-compatible.** With one world in the run the
  tag is optional and defaults to that world, so every committed example's reply
  format is unchanged and the draft path keeps working.

## Known Costs, Accepted

- **Demand duplication.** Three facts demanded by two worlds produced six demand
  lines and prints each open question twice. The multi-world spec already
  deferred this ("left as duplication until it hurts"); it now visibly hurts a
  little, and the fix (a shared demand) would break the clean rule that the
  subject prefix decides which file a line lives in. Left alone.
- **Reply size.** Grammar plus N rule sets plus N contracts plus one report in
  one answer scales badly past two or three worlds. The escape already exists:
  mint two now and add the third later against a frozen grammar.
- **Correctness of foreign notation is still unvouched.** Nothing in lips knows
  that `0 3 * * *` means 3am to Kubernetes. A well-formed but wrong spelling
  passes every gate, exactly as an nginx snippet does, which is why the
  `nginx-vm` check boots and curls. Unchanged by this work.

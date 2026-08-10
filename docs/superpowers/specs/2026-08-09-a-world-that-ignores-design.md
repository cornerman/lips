# A World That Ignores A Fact

**Status:** decided, ready to build. Opened by the first live joint mint
(2026-08-09), after "One mint, many worlds" landed.

## The Defect

A program states what it means, once, and every world it is minted for lowers
the same facts. Some facts belong to only some worlds. Measured: `examples/
nightly.timer.lips` states a command and a time; the kubenix mint demanded a
container image, correctly, because a pod cannot run without one. A NixOS unit
runs the script directly and has nothing to do with an image.

Once the program states that image, NixOS places nothing for it, and
`Lips.Kernel.Run.runGround` refuses a ground decision no rule places (`Unmapped`)
-- so the nixos world reports the program unportable. A program therefore cannot
state a fact that only one of its worlds needs, which is exactly what genuinely
different worlds ask for. The alternative (invent a value) was measured and
rejected: told nothing, the mint wrote `busybox:latest` at confidence 0.8, above
the threshold, so it would have shipped something nobody wrote down.

## The Decision

The world's own rules DECLARE what they cannot place, as data, with a reason:

    0.9 i1 @nixos ignore fact job.image "a machine runs the script directly, so there is no image"

The kernel rule keeps its shape: every ground decision is placed by a rule, is a
concept, or is explicitly ignored. Nothing is silent, the reason sits in the file
that drops the fact, and the knowledge stays in the engine rather than the
kernel (the kernel gains one closed grammar arm and still knows nothing about
images, containers or machines).

**The guard, which is what makes this safe:** a world may ignore a fact only if
some OTHER world of the language PLACES it. A fact no world places stays the
refusal it is today ("it reads words from the program and then discards them").
So `ignore` cannot become an escape hatch for a mint that does not feel like
lowering something: to ignore a fact anywhere, the mint must spend it somewhere,
in an option grounded against that world's schema. The check is possible only
because one call now writes every world, and it runs offline in `check` too, so
it is a permanent property of a committed language rather than a mint-time
courtesy.

Rejected, with reasons:

- **`concept` instead.** Verified: a rule may already match a concept and
  realize it, and a world with no such rule is not refused, so this needs no
  kernel change at all. Rejected anyway on three counts. The drop is expressed
  by SILENCE -- a reviewer of `nixos/timer.rules` sees no trace of the fact and
  must diff against the grammar to notice. No guard is possible, because a
  concept nobody realizes is legitimate (`install packages:` is one), so the
  mint could mark anything a concept. And the diagnosis prints "decorative,
  realizing nothing" in the world that DOES realize it (measured), because
  `wordDecorates` reads patterns and never consults rules; fixing that would
  make `concept` mean "not necessarily realized", giving one word two jobs.
- **Tolerating an unmapped decision when another world places it.** Silent, and
  it removes the guarantee that every stated word reaches an output.
- **Letting the program name the world a line is for.** The program states
  intent; deployment detail belongs to the engine.
- **Refusing the asymmetry entirely** (a program may not state a fact one of its
  worlds cannot place). Keeps the strongest invariant, and makes any
  container-world plus machine-world pair unservable for the facts that differ,
  which is the pair the design most wants to serve.

## Consequences

- `concept` keeps meaning "realizes nothing", and a rule matching a concept is
  refused: with `ignore` in the grammar there would otherwise be two ways to
  express one asymmetry, one guarded and one not, and the model finds the
  unguarded one. No committed engine matches a concept today, so nothing breaks.
- Every run SAYS what a world ignores, beside the grounding line, so overuse is
  visible on every `check` rather than only at review time.
- An ignore may name a family (`pkg.<name>`), matched by `matchSubject` exactly
  as a rule or a demand is.
- A hole whose word lands only in an ignored fact is already handled:
  `Lips.Kernel.Engine.Reach.dropOf` reports nothing when no rule of this world
  matches the family, so no gate has to change.

# TODO

## Next up (priority order)

1. **Mint tooling** — plan
   `docs/superpowers/plans/2026-07-26-mint-tooling-plan.md`. The mint stops
   guessing: extract the gate into `Lips.Generate.Gate`, add `lips options`
   (schema lookup) and `lips dry-run` (rehearse a draft engine against that
   exact gate), ship a pi extension exposing those two tools and nothing else,
   bound the loop with `--rounds N` (default 8, stated to the model and
   enforced by the tool), and record the whole transcript in `.generation`.

2. **Mint expression channels** — plan
   `docs/superpowers/plans/2026-07-26-mint-expression-channels-plan.md`. Two
   new block kinds: `report` (required, exactly one) written to
   `<language>/README.md`, so a human reviews prose instead of `.lang`; and
   `gap`, a kernel capability the mint found missing, surfaced on both the
   success and the refusal path. Regeneration also sees the previous engine,
   report and contract, so vocabulary stays stable across mints.

3. **Mint prompt rewrite** — plan
   `docs/superpowers/plans/2026-07-26-mint-prompt-rewrite-plan.md`. Move the
   prompt out of escaped Haskell literals into `assets/mint/*.md` embedded with
   `file-embed` (byte-identical first), then rewrite it for the agent doing the
   job: where it sits, the machine its engine drives stage by stage, the
   verify-and-iterate loop, the output contract, one reference subsection per
   construct with each prohibition stated once, design guidance, two worked
   examples, a self-review checklist. A suite guard parses every fenced
   `lips-engine` example block, so an example cannot outlive its grammar.

4. **Gap report (`<program>.gap`)** — §13 Missing, tagged "cheap; do soon".
   When `generate` refuses because physics is missing, write a machine-readable
   artifact (refused lines, missing capability / extension point, minimal repro,
   model+prompt fingerprint) instead of on-screen-only text. Operationalizes the
   cross-repo escalation workflow (DESIGN Doctrine). Item 3 supplies the
   producer (the `gap` block); this item is only the file writer.

5. **Live host deployment** — the headline missing proof (§13 Shortest Summary).
   Wire one realized module into `~/nixos` on `wolf`. Reduced to "import one
   file"; proves survival on a real system, not just a VM boot.

6. **Template grammar completeness** (completeness plan Target 2). The value
   grammar is complete-by-construction over the Nix value algebra minus
   computation; the template grammar is only "complete over observed line
   shapes" — a weaker, honest claim. Missing capture forms: unquoted multi-token
   holes (bind several words up to a literal), and true parent-child block
   aggregation (a decision owning a list). Close these to make the template
   claim match the value claim.

## Backlog (larger / deferred by design)

- **Glue** — the one deliberate incompleteness (computation inside the decision
  layer). `Glue` is a `Kind` with no rigor-downgrade mechanism. Blocks a
  *computed value*, not building a program (that is artifacts, done).
- **Artifacts: templated source** — source is a fixed blob baked at generate; a
  value that must appear inside the compiled program needs regeneration, not a
  `compile`-time flow. Also: dependency-fetching builders (cargo/vendor hashes)
  untried. Concrete repro (2026, `server.lips` httpserver example): a route's
  status/mimetype/body must land inside the compiled Go source per route
  (keyed by `<path>`), but `source` heredocs are verbatim text with no holes
  and no per-item (capture-keyed) binding into source text; `generate` rightly
  refuses these three (confidence 0.35) rather than fake it. Needs a hole
  syntax usable inside a `source` block, reusing the `<capture>` mechanism
  already used for option paths, plus a decision on whether substitution is
  generate-time (model renders the per-item structure) or a new realize-time
  step.

- **Language migration** — no diff/migration path when a `.lang` regenerates to
  a different shape.
- **Multi-language composition** — the prototype runs one engine; composing
  several languages in one Solution is unbuilt (dual of instance reuse).
- **Kernel modules** — loadable, test-gated units extending the closed grammars
  at declared extension points (successor of the vocabulary milestone).
- **Guarantee lifecycle** — the assumption `OPEN -> GUARANTEED` flow has no code.
- **Heile-Welt coping** — no mechanism yet; reality mismatches (GPU present,
  driver loads) surface at runtime, outside the kernel's determinism boundary.

## Housekeeping / smells

- `stripTailPunct` (`Kernel/Engine/Value.hs`) duplicates `stripTrailingPunct`
  (`Kernel/Lang/Pattern.hs`) — same rule, two copies kept "in step" by comment.
  A shared definition would remove the drift risk (the comment flags it).

# TODO

## Next up (priority order)

1. **Mint schema tool** — plan
   `docs/superpowers/plans/2026-07-26-mint-schema-tool-plan.md`. The mint stops
   guessing option names and types: one shipped pi extension registers exactly
   one tool, `query_options`, which shells out to a new read-only `lips options`
   verb over the pinned schema. The answer's granularity adapts to the match set
   (exact `path : type` leaves when few; namespaces ranked by match count when
   many), because an alphabetical slice of a large match set hides the answer —
   measured: `nginx` matches 1,514 paths whose first 40 alphabetically omit
   `services.nginx` itself. `callPi` switches `-nt` to `-nbt` plus the extension
   and keeps the hermetic subtraction, so that one tool is the mint's whole
   world, and every lookup enters `.generation` (invariant 6: a tool result the
   model read is an input). No tool judges an engine: informing is safe to
   expose, deciding is not.

2. **Mint prompt rewrite** — plan
   `docs/superpowers/plans/2026-07-26-mint-prompt-rewrite-plan.md`. Move the
   prompt out of escaped Haskell literals into `assets/mint/*.md` embedded with
   `file-embed` (byte-identical first), then rewrite it for the agent doing the
   job: where it sits, the machine its engine drives stage by stage, the schema
   lookup tool and its limit, the output contract, one reference subsection per
   construct with each prohibition stated once, design guidance, two worked
   examples, a self-review checklist. A suite guard parses every fenced
   `lips-engine` example block, so an example cannot outlive its grammar.

3. **Gap report (`<program>.gap`)** — §13 Missing, tagged "cheap; do soon".
   When `generate` refuses because physics is missing, write a machine-readable
   artifact (refused lines, missing capability / extension point, minimal repro,
   model+prompt fingerprint) instead of on-screen-only text. Operationalizes the
   cross-repo escalation workflow (DESIGN Doctrine). The `gap` block already
   supplies the producer and prints on both paths; this item is only the file
   writer.

4. **Live host deployment** — the headline missing proof (§13 Shortest Summary).
   Wire one realized module into `~/nixos` on `wolf`. Reduced to "import one
   file"; proves survival on a real system, not just a VM boot.

5. **Template grammar completeness** (completeness plan Target 2). The value
   grammar is complete-by-construction over the Nix value algebra minus
   computation; the template grammar is only "complete over observed line
   shapes" — a weaker, honest claim. Missing capture forms: unquoted multi-token
   holes (bind several words up to a literal), and true parent-child block
   aggregation (a decision owning a list). Close these to make the template
   claim match the value claim.

## Backlog (larger / deferred by design)

- **Mint round loop** — deferred on 2026-07-26, with the analysis kept so it is
  not redone. The idea: when the gate rejects an engine, re-prompt the model with
  the findings instead of dying, bounded by `--max-rounds`. Why it waits: a fresh
  `pi -p` process has no memory, so every round re-emits the whole engine (output
  tokens, the expensive kind) and triggers a fresh nix gate run, and Anthropic's
  prompt-caching docs name the shape as a mistake — a prompt whose tail changes
  every request puts the automatic cache breakpoint on the varying block, so it
  pays a 1.25x cache write every round and never gets a 0.1x read, making it
  worse than no caching. A growing tool conversation is the opposite case and is
  a documented target of caching. So if the loop returns it belongs *around* an
  agent that asks (item 1's tool), never instead of one. Two sub-ideas were
  worked out and can be recovered from git history: a `query` reply item (made
  redundant by the tool) and a three-way gate verdict via `Lips.Generate.Gate`
  (extraction has no second call site until the loop exists). Permanently
  rejected, do not revive: `lips dry-run` as a model-callable tool, because a
  rehearsal verb is a second call site for the gate and can drift from the gate
  that commits.

- **Mint internet access** — a second `registerTool` beside `query_options`
  (item 1), routing a question to a web search. pi has no built-in web tool, so
  it is a custom tool either way, and the extension item 1 creates makes it a
  ~20-line addition. Argument for: the mint's world knowledge is today invisible
  training data that never enters `.generation`, whereas a recorded lookup is
  auditable evidence — the same move deduce-or-fail already makes for values.
  Argument for waiting: no mint has yet failed for want of a world fact (the one
  refusal on record, the httpserver example at confidence 0.35, was kernel
  expressiveness). Add when a real mint fails for lack of a fact, not before.

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

### From survey F (theory under the calculus)

All four trace to `docs/superpowers/survey/f-decision-calculus-theory.md`; the
first has landed, these are the rest, ranked.

- **Minimal conflict explanation (QuickXplain).** A conflict names two competing
  decisions today. When the contradiction is derived several refinement steps
  down, the author needs the smallest set of *program lines* that cannot hold
  together. Junker (AAAI 2004) computes it in a logarithmic number of
  consistency checks, and strength already supplies the preference order the
  algorithm needs. Deterministic, domain-blind, offline; sized like the overlap
  milestone.
- **Static pattern overlap** — the pattern-layer sibling of the rule overlap
  check that landed. `crystallize` reports `Overlapping` dynamically, so a
  language can ship two templates no example line separates. Harder half:
  templates are token sequences with multi-token tail holes, not fixed-length
  tuples, so unification is not the same three lines.
- **Merge against the IC postulates.** Record which of Konieczny & Pino Pérez's
  merging postulates lips's merge satisfies, which it violates and why
  (arbitration over majority, with `Append` as the stated exception). A written
  audit, not code.
- **Two decisions to make before they surprise someone**: whether an obligation
  survives an override (Nickel propagates contracts onto the winner; lips drops
  them — deferred deliberately, no engine emits obligations yet), and whether
  specificity beats generality (*lex specialis*; strength is *lex superior*
  only). Both recorded in DESIGN.md §11.

## Housekeeping / smells

- `stripTailPunct` (`Kernel/Engine/Value.hs`) duplicates `stripTrailingPunct`
  (`Kernel/Lang/Pattern.hs`) — same rule, two copies kept "in step" by comment.
  A shared definition would remove the drift risk (the comment flags it).

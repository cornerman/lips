# TODO

## Next up (priority order)

0. ~~**Mint `examples/greet.lips`.**~~ DONE (ca09f97 committed
   `examples/greet/`). `check-expect` and `lipsModules-eval` stay RED for the
   three programs still without an engine (`examples/{board,habit,logscan}.lips`),
   which is item 1's job. The original text follows for its target-shape notes.

   One line,
   `install a command greet that prints "hello from lips"`, the smallest
   program that builds a runnable command. It is committed with no engine, so
   `just check-expect` and the `lipsModules-eval` flake check both fail: each
   iterates every `examples/*.lips` and a program without its `<language>/`
   folder fails loud. Mint it, `git add examples/greet`, confirm both green.

   The target engine shape is already proven offline by hand: one
   `writeShellApplication` artifact and one option path, realizing to
   `environment.systemPackages = [ artifact.greet ]`, with
   `nix run …#artifact.greet` printing the program's text. No compiler, no
   `vendorHash`, no source file. The mint must write NO `.expect` assertion:
   the only option the engine fills is derivation-valued, and
   `uncheckableExpects` rightly refuses an assertion on such an option (see
   `docs/gaps/README.md` finding 5, which is that guard followed through to its
   uncomfortable conclusion).

1. **CLI-tool physics** — evidence and analysis in `docs/gaps/README.md`, with
   `docs/gaps/{board,habit,logscan}.lips` as committed repros. Six mints on
   2026-07-27 (three programs x qwen3-coder:30b and claude-sonnet-5) produced no
   engine and six findings. Ranked:

   a. **Silent concept demotion (deduce-or-fail's blind spot).** VISIBILITY
      DONE (`diagInert`, ledger §13): `check` now names the lines that realize
      nothing. Still open, the harder half: nothing stops a mint demoting an
      assertion to decoration in the first place, and a compiled artifact does
      not record which program lines its source depends on, so an edit to one of
      them still compiles to an unchanged binary. Candidate: record the source's
      line dependencies at mint and fail loud when one changes.

   b. ~~**Capture-keyed artifact names.**~~ CLOSED (see ledger §13). A capture
      now keys an artifact and fills a value, so `install a command greet that
      prints "..."` is writable and both values flow from the sentence.

   c. **Language branching.** No way to branch a builder on a captured language
      token, so `write the tool in go` either hardcodes `buildGoModule` (and
      silently keeps it when the word changes, per finding a) or becomes
      decoration. Branching is computation, so this is glue or it is permanently
      out of scope with a loud failure as the honest answer.

   d. **Templated source, two fresh repros** (extends the existing backlog item
      below): the command name must reach `pname` and the Go module inside the
      artifact, and source heredocs have no holes.
      Half closed (see ledger §13, "One name grammar"): a composite artifact
      name (`<self>-core`, `<name>-core`) is now physics, so the
      compiled-core-plus-`writeShellApplication`-wrapper shape a mint reaches
      for is writable, and an unfilled name fails loud at realize instead of
      reaching the module. Still open: a hole inside a source heredoc, which is
      the "source is a fixed blob" half.

   e. **A CLI engine has nothing to pin.** Every option it fills is
      derivation-valued, so its contract is necessarily empty, and an empty
      contract passes vacuously. Invariant 5 has no force for this class.

   f. **Two hole namespaces, one syntax** (pattern holes named by the template
      vs the rule side's fixed `<value>`). A weaker model confuses them
      reliably, which makes it a format question, not a prompt question.

1. **Mint prompt rewrite** — plan
   `docs/superpowers/plans/2026-07-26-mint-prompt-rewrite-plan.md`. Move the
   prompt out of escaped Haskell literals into `assets/mint/*.md` embedded with
   `file-embed` (byte-identical first), then rewrite it for the agent doing the
   job: where it sits, the machine its engine drives stage by stage, the schema
   lookup tool and its limit, the output contract, one reference subsection per
   construct with each prohibition stated once, design guidance, two worked
   examples, a self-review checklist. A suite guard parses every fenced
   `lips-engine` example block, so an example cannot outlive its grammar.

2. **Gap report (`<program>.gap`)** — §13 Missing, tagged "cheap; do soon".
   When `generate` refuses because physics is missing, write a machine-readable
   artifact (refused lines, missing capability / extension point, minimal repro,
   model+prompt fingerprint) instead of on-screen-only text. Operationalizes the
   cross-repo escalation workflow (DESIGN Doctrine). The `gap` block already
   supplies the producer and prints on both paths; this item is only the file
   writer.

3. **Live host deployment** — the headline missing proof (§13 Shortest Summary).
   Wire one realized module into `~/nixos` on `wolf`. Reduced to "import one
   file"; proves survival on a real system, not just a VM boot.

4. **Template grammar completeness** (completeness plan Target 2). The value
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
  (now landed), routing a question to a web search. pi has no built-in web tool, so
  it is a custom tool either way, and `assets/mint-tools.ts` makes it a
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

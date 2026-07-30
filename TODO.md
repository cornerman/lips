# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

1. **CLI-tool physics — remaining open questions** (context: `board`, `habit`,
   `logscan` are committed, minted CLI engines; `examples/{http,postgres}`
   were re-minted honest. See DESIGN §13 for what landed getting there.)

   a. **Silent concept demotion — three cases still open** (`diagInert` and
      `droppedValues` cover the rest; DESIGN §13):
      (i) a PARTIAL drop — a rule reading `<value.1>` of a value built from two
      holes silently drops the second; needs a sound static map from holes to
      token positions (a multi-token capture breaks the naive one).
      (ii) a per-hole DECORATIVE report — a hole demoted to a `Concept` on a
      line that otherwise realizes is invisible, since `diagInert` works per
      line, not per hole. Call sites exist: `board`, `habit`, `logscan` each
      emit several `Concept`s.
      (iii) a compiled artifact records no dependency on the program lines its
      baked source came from, so an edit to one of them compiles to an
      unchanged binary. Candidate: record the source's line dependencies at
      mint and fail loud when one changes.

   b. **An option's own semantics can make an honest engine wrong.** postgres's
      re-mint emits `ensureUsers = [ { name = "app"; ensureDBOwnership = true;
      } ]`, but NixOS grants ownership of the database that shares the USER's
      name, so a program naming a user and a database differently would
      realize a silently wrong config. The words are spent (the dropped-value
      guard is satisfied), so lips sees nothing wrong, and the kernel cannot
      know option semantics either. Candidate: nothing kernel-side — belongs
      in the mint's own review, or as a `gap` the mint should have filed.

2. **Template grammar completeness — the one deferred piece.** True
   parent-child block aggregation (a decision owning a list) is deferred:
   subject-keyed bulleted items plus `Append` already carry every list the
   corpus states. Revisit when a program needs a block no subject can key.

## Backlog (larger / deferred by design)

- **Mint round loop** — deferred, analysis kept so it is not redone. The idea:
  when the gate rejects an engine, re-prompt the model with the findings
  instead of dying, bounded by `--max-rounds`. Why it waits: a fresh `pi -p`
  process has no memory, so every round re-emits the whole engine (expensive
  output tokens) and triggers a fresh nix gate run, and a prompt whose tail
  changes every request defeats prompt caching (pays a cache-write penalty
  every round, never a cache-read discount). So if the loop returns it
  belongs *around* an agent that asks (the schema lookup tool), never instead
  of one. Permanently rejected, do not revive: `lips dry-run` as a
  model-callable tool (a rehearsal verb is a second call site for the gate
  and can drift from the gate that commits).

- **Mint internet access** — a second `registerTool` beside `query_options`,
  routing a question to a web search. Argument for: a recorded lookup is
  auditable evidence, the same move deduce-or-fail already makes for values.
  Argument for waiting: no mint has yet failed for want of a world fact. Add
  when a real mint fails for lack of a fact, not before.

- **Glue** — the one deliberate incompleteness (computation inside the
  decision layer). `Glue` is a `Kind` with no rigor-downgrade mechanism.
  Blocks a *computed value*, not building a program (that is artifacts,
  done).

- **Dependency-fetching builders** (cargo/vendor hashes) — untried. The
  proven path is no-dependency source (Go stdlib with `vendorHash = null`);
  fetching a real dependency graph at generate time is unexplored.

- **Language migration** — no diff/migration path when a `.lang` regenerates
  to a different shape.

- **Multi-language composition** — the prototype runs one engine; composing
  several languages in one Solution is unbuilt (dual of instance reuse).

- **Kernel modules** — loadable, test-gated units extending the closed
  grammars at declared extension points (successor of the vocabulary
  milestone).

- **Guarantee lifecycle** — the assumption `OPEN -> GUARANTEED` flow has no
  code.

- **Heile-Welt coping** — no mechanism yet; reality mismatches (GPU present,
  driver loads) surface at runtime, outside the kernel's determinism
  boundary.

### From survey F (theory under the calculus)

Trace to `docs/superpowers/survey/f-decision-calculus-theory.md`.

- **Minimal conflict explanation (QuickXplain).** A conflict names two
  competing decisions today. When the contradiction is derived several
  refinement steps down, the author needs the smallest set of *program
  lines* that cannot hold together. Junker (AAAI 2004) computes it in a
  logarithmic number of consistency checks, and strength already supplies
  the preference order the algorithm needs. Deterministic, domain-blind,
  offline.

- **Merge against the IC postulates.** Record which of Konieczny & Pino
  Pérez's merging postulates lips's merge satisfies, which it violates and
  why (arbitration over majority, with `Append` as the stated exception). A
  written audit, not code.

- **Two decisions to make before they surprise someone**: whether an
  obligation survives an override (Nickel propagates contracts onto the
  winner; lips drops them — deferred deliberately, no engine emits
  obligations yet), and whether specificity beats generality (*lex
  specialis*; strength is *lex superior* only). Both recorded in
  `DESIGN.md` §11.

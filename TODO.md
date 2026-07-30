# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

1. **Honesty gates, structural half** (decided 2026-07-30; these two need no
   new representation, so they ship before the meaning spec).

   a. **`<value.N>` must keep the author's quotes** (closes 3d, and gives 3a(i)
      a sound hole-to-field map). Root cause: `Lang/Pattern.hs` tokenizes a
      program line quote-aware, so `body "hello world"` is ONE token, but it
      strips the quotes into the surface, so the fact assertion becomes
      `200 hello world`; `Engine/Data.hs:196` then re-guesses the boundary with
      `T.words` and `<value.2>` silently takes `hello`. Fix: keep the quotes in
      the assertion, and make the fill split quote-aware and unquote the picked
      field, reusing `Pattern.tokens` / `Pattern.unquote` on both sides, so one
      tokenizer governs program and rule alike. Rejected: a joined-tail hole
      `<value.N..>` (an unquoted multi-word value still truncates and the
      hole-to-token map stays unsound); refusing a multi-word value
      (cannot-express is a kernel bug too). Cost: `.decisions` shows
      `200 "hello world"`.

   b. **`generate` must build the artifact and stat what the module names**
      (closes 3c). Build each `artifact.<name>`, then collect every
      `${artifact.<name>}/rel/path` in realized output (the kernel's artifact-ref
      extraction in `Engine/Value.hs` already finds them) and assert each exists
      and is executable in the build result. Building alone is not enough: the
      defect that shipped twice was a unit naming `/bin/hello` while `go.mod`
      said `module server`, which compiles fine. `check` stays offline and
      nixpkgs-free; `generate` is already online and already builds a pinned
      nixpkgs for grounding, so it pays this cost.

2. **The meaning dimension: observable claims + source-line provenance**
   (design decided 2026-07-30, spec not yet written; supersedes the "no remedy"
   verdicts in 3a(iii), 3a(iv) and 3b, and is the honesty half that needs new
   physics).

   The diagnosis: every gate lips has reads the MAP (the module text) and none
   observes the TERRITORY (a running thing). So a program can only say what
   becomes a `path = value` assignment. Behavior gets frozen into baked source,
   cut off causally from the lines it came from, and cross-program relations are
   unsayable. Two mechanisms close this, and neither closes it alone.

   a. **Source-line provenance** makes a specification sentence causal again:
      stamp baked source with the program lines it was minted from, and let a
      stamped line that changes make `compile` fail loud, naming the remedy
      (re-mint). This, not the claims below, is what kills the reword hole
      (3a(iv)): an author's example written for `equals` still passes after the
      sentence is reworded to `differs`.

   b. **Observable claims** hold the implementation, and every future re-mint,
      accountable to behavior the author stated.
      - WITNESS: the author supplies it, in the program ("given `{"a":1}` with
        `--a 1`, print it unchanged"). Examples are intent, so they belong in
        the only file the author owns; nothing is invented and deduce-or-fail
        holds. Rejected: mint-invented witnesses, since a reworded sentence
        leaves them untouched.
      - REPRESENTATION: no new file and no new machinery. A minted pattern
        crystallizes the example line, and a minted rule emits into a reserved
        emit-path head, exactly as `artifact.*` already does: `claim.<id>.run`
        (the command, may hold `${artifact.<name>}` refs), `.stdin`, `.stdout`,
        `.exit` (default 0). Comparison is EXACT, not containment: containment
        is what let a minted `"200\n404"` become `"200n404"` unseen. No
        `stderr` field until a program needs one. The closed value grammar is
        unchanged, so a claim cannot compute. `.expect` pins claim slots through
        the artifact-slot mechanism it already has, so a re-mint that drops an
        example trips the existing gate.
      - PLACE, derived and never declared: a `run` naming only `${artifact.*}`
        becomes a plain derivation in the nix sandbox (fast, no KVM, no
        network); anything else becomes a `nixosTest` that boots the module and
        runs the command inside the machine. The kernel already tracks artifact
        refs, so the place needs no new syntax and a CLI program never pays for
        a boot.
      - ENTRY POINT: `compile` emits the experiments as a `#claims` rung and
        prints it, and `lips check` builds that rung, so one implementation
        serves author and CI. An experiment that cannot run (a machine claim
        without KVM) is a LOUD failure naming the remedy, never a skip: "not
        verified" must never render as verified.
      - OBLIGATION: `generate` refuses an engine that bakes source unless at
        least one experiment pins it. Pure-config programs are unaffected. For
        the 3b shape (a word spent into an option that means something else)
        claims stay ADVISORY, with an LSP diagnostic beside `diagInert` when a
        behavior sentence reaches no claim. Stated plainly rather than sold as a
        universal gate.

   c. **Names reserved for composition** (no implementation here; the backlog's
      cross-program item owns that): the emit head `export.*` for a program's
      public surface, and a third value ref beside `${pkgs...}` and
      `${artifact...}`, namely `${program.<instance>.<path>}`, resolved at
      compile from the sibling's committed engine BY NAME. Composition is then
      an existing demand answered by an exported decision, one namespace up,
      with claims marking which part of that surface is verified. Reserved now
      because renaming a claim or artifact subject later is a re-blessing event
      for every committed engine.

   d. **Verification of the work itself**: conformance cases in
      `kernel/test/Spec.hs` for quote-preserving fill, the artifact path check,
      claim parsing, place derivation, the 2b refusal and the stale-source
      failure. Re-mint afterwards: `logscan`, `board`, `habit` (artifact-bearing,
      so newly obliged) and `hello.http.lips`.

3. **CLI-tool physics — the record behind items 1 and 2** (context: `board`, `habit`,
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
      unchanged binary. DECIDED (item 2a): record the source's line dependencies
      at mint and fail loud when one changes.
      (iv) STRUCTURE is enforced by nothing. Doctrine (DESIGN §13, "Repeating
      source") puts the algorithm, the format and the protocol in baked source,
      so a behavior sentence is a specification for the mint and correctly not a
      decision -- `logscan` says "keep a line only when every field ... equals
      the value given with it" and reaches output through hand-written source
      only. Reword `equals` to `differs` without re-minting and every gate stays
      green (the V6 source-specification gate catches DELETION only). No trace
      can fix this: the words never appear in the code. DECIDED (item 2): the
      reword is caught by source-line provenance (2a); claims cannot catch it,
      since an example written for `equals` still passes. The behavioral
      assertion (2b) is built anyway, for the other reason: it holds the
      implementation and every re-mint to stated observables.

   b. **An option's own semantics can make an honest engine wrong.** postgres's
      re-mint emits `ensureUsers = [ { name = "app"; ensureDBOwnership = true;
      } ]`, but NixOS grants ownership of the database that shares the USER's
      name, so a program naming a user and a database differently would
      realize a silently wrong config. The words are spent (the dropped-value
      guard is satisfied), so lips sees nothing wrong, and the kernel cannot
      know option semantics either. DECIDED (item 2b, OBLIGATION): a system
      claim falsifies both shapes when the author states one (`systemctl
      is-active api` fails, since nginx runs under the unit `nginx`), so the
      remedy exists but stays advisory, plus an LSP diagnostic. No static
      remedy: teaching the target layer what each option MEANS is an open list
      the kernel would have to enumerate, which the doctrine forbids.
      Second instance (2026-07-30, `examples/web` re-mint): the program line
      "run it as a systemd service named api" is spent into
      `services.nginx.virtualHosts.api.serverName`, but nginx runs under the
      unit `nginx` and `serverName` is a HOSTNAME, so the sentence is honored by
      an option that means something else. Every gate is green. Same shape as
      postgres, same absent remedy.

   c. **`generate` accepts an engine whose binary does not exist.** DECIDED,
      see item 1b. The http
      re-mint of 2026-07-30 emitted `ExecStart = "${artifact.hello}/bin/hello"`
      with `module server` in `go.mod`, so the unit named a binary called
      `server`: past the mint gate, past `check`, caught only by the flake check
      `lipsArtifacts-build` (which is why that check exists -- the same defect
      shipped once before with `module app`). The gate lives in the flake because
      `check` must stay offline and nixpkgs-free, but `generate` is already
      online and already builds a pinned nixpkgs for the option schema, so it
      could run this build itself and refuse. Cost: one build per mint, seconds
      to minutes. Until then, run `nix build
      .#checks.x86_64-linux.lipsArtifacts-build` by hand after every mint.

   d. **`<value.N>` cannot carry a multi-word tail.** DECIDED, see item 1a.
      (Filed by the `web` mint
      itself as gap `multiword-route-body`, 2026-07-30; the refusal report is
      recoverable from that mint's `.gap` in this branch's history.) A route's
      status and body are one fact (`"<status> <body>"`) so both reach one
      `extraConfig` option through `<value.1>`/`<value.2>`. `<value.N>` takes
      exactly token N, so `- /msg returns status 200 with body "hello world"`
      would silently truncate to `hello`. The grammar has no "rest from token
      N" hole. Silent wrong output, not a loud failure, and the committed
      `examples/web` engine has the shape today; only the corpus's single-word
      bodies keep it from firing.


2. **Invariant 6 is verified by nothing.** DESIGN's sixth invariant says every
   minted line is stamped `@gen:<id>` and the id must re-hash from the
   committed `.generation` record, but no code re-hashes anything: `check`
   reads the stamps as text. So a change to what the record contains silently
   invalidates every committed engine's stamps while all gates stay green.
   This is not hypothetical -- the schema-pin work adds a `schema:` line to the
   record, which changes every generation hash, and main noticed nothing.
   Remedy: `check` recomputes `genId` from the `.generation` beside the engine
   and refuses when a `@gen:` stamp disagrees, which makes a re-mint sweep
   verifiable instead of a matter of remembering. Deterministic, offline,
   domain-blind. Blocked until the schema-pin branch ff-merges, since the gate
   must call the same `genId` that branch is changing (`Lips.Generate.Record`).

## Backlog (larger / deferred by design)

- **Cross-program composition (one program naming another).** Nix composes;
  lips does not yet. Two shapes, both wanted. SAME WORLD: a kubenix program
  importing what a sibling program realized (a shared namespace, a config map
  another program owns). ACROSS WORLDS: a program whose whole point is built
  SOURCE -- an artifact today -- becoming an OCI image that a kubenix
  Deployment's `image` field names, so "build this service" and "run it in the
  cluster" are two programs, each in its own language, composed instead of
  merged. Today an `artifact.<name>` is reachable only inside its own program's
  realized module (a `let` binding), and no grammar names another program's
  artifact or option. What is needed: a reference that stays deduce-or-fail (a
  NAME resolved at compile from the sibling program's identity, never a
  computation), plus a stated rule for the cross-world case -- the module shape
  is world-specific, only the artifact is world-neutral, so the artifact is the
  natural seam. kubenix already ships `modules/docker.nix` and
  `docker-image-from-package.nix`, so image-from-derivation is upstream physics
  lips can reach by name rather than invent. Dual of the existing
  "Multi-language composition" item (several engines in one Solution): same
  axis, one level up.

- **A world's vocabulary is not fixed: CRDs and house conventions.** Two gaps
  the kubenix target makes visible, both target-tier, neither a kernel change.
  (i) GROUNDING STOPS AT UPSTREAM. The kubenix schema is built from the pinned
  flake's generated Kubernetes API, so a cluster's CRDs (cert-manager, Istio,
  ArgoCD) are absent and a rule naming `kubernetes.resources.certificates.*`
  is refused as unknown although the cluster has it. The schema source must be
  able to take extra resource definitions (kubenix's own imported-CRD path)
  and record what it took, or grounding is honest only for vanilla clusters.
  (ii) CONVENTION HAS NO WORLD-LEVEL CHANNEL. Label keys, naming, namespace
  policy, resource limits are mechanism taste -- exactly what
  `<language>.direction` carries -- but nothing today states a direction shared
  by every language minted into one world. Candidate: a per-world direction
  file beside the per-program one, entering the generation record the same way,
  so a house convention is stated once instead of re-typed per language.

- **Targets as external plugins.** A world is four knobs: mint preamble
  (markdown, already data), schema source (a Nix expression plus an output
  sub-path, nearly data), schema reshaping (Haskell -- kubenix needed three
  operations: re-key an alias, drop inner nodes, unwrap optionals), and the run
  harness (Haskell emitting flake text and printed rungs). Two of four are data
  today. Now that terranix has landed there is evidence on the open question:
  the reshaping knob DOES factor (terranix needed none at all, reusing
  `parseNixOptionsJson`), while the other two did not shrink -- the schema source
  was a bespoke Nix expression reaching into terranix's own internals (its
  published options helper deletes the namespaces programs write), and the
  harness was per-world flake text either way. So a plugin format would still be
  "ship a Nix expression plus flake text", i.e. code, not data. Counter-argument to weigh then: a
  plugin's harness is arbitrary Nix, i.e. an arbitrary-code channel into
  compiled output, while the closed set keeps every world reviewed in-tree.

- **terranix grounding is path-blind below the top level.** Live as of the
  terranix target (DESIGN §13): terranix's core options (`resource`, `data`,
  `provider`, `output`) are one free-form "magic merge" valueType, so lips
  confirms the top-level namespace (`resourse` is refused) and nothing under it.
  A misspelled resource type or field reaches `config.tf.json` unchallenged and
  fails at `tofu plan`, not at generate. Two things soften it today, both
  shipped: the mint preamble states the limit and tells the mint to refuse rather
  than guess a field, and a lookup inside a free-form region answers `Freeform`,
  saying in words that the name was not checked. The remedy is a different schema
  source -- `terraform providers schema -json`, a per-provider network fetch at
  generate time -- which generate could afford (it is already online). What holds
  it back: that schema is per provider AND per provider version, so it needs a
  pin per program to stay reproducible, which is a new recorded knob, not just a
  new parser.

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

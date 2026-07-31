# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

1. **The meaning dimension: observable claims + source-line provenance**
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
      `kernel/test/Spec.hs` for quote-preserving fill, claim parsing, place
      derivation, the (b) refusal and the stale-source failure. Re-mint
      afterwards: `logscan`, `board`, `habit` (artifact-bearing, so newly
      obliged) and `hello.http.lips`. The artifact path check landed already
      (`realizeArtifactPaths` + the build gate, DESIGN §13), and its runner is
      what an artifact-only claim's "place" reuses: a plain derivation in the nix
      sandbox, no boot, no KVM.

2. **CLI-tool physics -- the record behind item 1** (context: `board`, `habit`,
   `logscan` are committed, minted CLI engines; `examples/{http,postgres}`
   were re-minted honest. See DESIGN §13 for what landed getting there.)

   a. **Silent concept demotion -- three cases still open** (`diagInert` and
      `droppedValues` cover the rest; DESIGN §13):
      (i) a PARTIAL drop -- a rule reading `<value.1>` of a value built from two
      holes silently drops the second. The static map this needed is now cheap:
      a several-part value stores ONE quoted part per hole (see DESIGN §13, "A
      several-part value"), so part N of an assertion is hole N by construction.
      What is missing is the gate that uses it, in `Engine/Reach.dropOf`, whose
      `carries` still counts any `<value*>` use as carrying every hole. Same
      place would catch two siblings for free: a statically out-of-range
      `<value.N>` (today a loud runtime Left, but only if a program reaches it),
      and a `<value.tail>` over a several-part value, which splits the parts'
      WORDS again (`Engine/Value.fillV` sees the joined text `pick` returns, not
      the parts) -- no committed engine does it, and nothing refuses it.
      (ii) a per-hole DECORATIVE report -- a hole demoted to a `Concept` on a
      line that otherwise realizes is invisible, since `diagInert` works per
      line, not per hole. Call sites exist: `board`, `habit`, `logscan` each
      emit several `Concept`s.
      (iii) a compiled artifact records no dependency on the program lines its
      baked source came from, so an edit to one of them compiles to an
      unchanged binary. DECIDED (item 1a): record the source's line dependencies
      at mint and fail loud when one changes.
      (iv) STRUCTURE is enforced by nothing. Doctrine (DESIGN §13, "Repeating
      source") puts the algorithm, the format and the protocol in baked source,
      so a behavior sentence is a specification for the mint and correctly not a
      decision -- `logscan` says "keep a line only when every field ... equals
      the value given with it" and reaches output through hand-written source
      only. Reword `equals` to `differs` without re-minting and every gate stays
      green (the V6 source-specification gate catches DELETION only). No trace
      can fix this: the words never appear in the code. DECIDED (item 1): the
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
      know option semantics either. DECIDED (item 1b, OBLIGATION): a system
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

   c. **`generate` accepts an engine whose binary does not exist.** CLOSED
      2026-08-01 (DESIGN §13, "The artifact build gate"): `generate` builds each
      `artifact.<name>` against the pinned nixpkgs and requires every path the
      output names inside one to be there, so the defect that shipped twice (a
      unit naming `/bin/hello` beside `module server` in `go.mod`) is refused
      before anything is written. What is deliberately NOT checked: whether such
      a path is executable. A file under `bin/` that exists but cannot run has
      not been observed; add the check when it is, not before.

3. **The 18 committed engines predate the recorded schema pin, so their stamps
   no longer re-hash.** The generation record gained a `schema:` line (the locked
   flakeref, or `options-json:<hash>`, that grounded the mint -- DESIGN §13
   "Option-schema grounding"), which changes every record's `genId`. Every
   committed `.lang` is stamped `@gen:<id>` from a record written before that
   line existed, so re-hashing a committed `.generation` today yields a different
   id than its engine carries: invariant 6 is broken for every language in
   `examples/`, and item 4 is why nothing says so. The remedy is a re-mint sweep
   of all 18 languages, so each record and its stamps agree again. Open question
   to settle first: mint the sweep with sonnet-5 rather than opus (cheaper, and
   the gates rather than the model's taste decide what is admitted); the risk is
   a weaker engine on the harder languages, so compare `.expect` survival per
   language and keep opus for any that regress. First datapoint, from the
   punctuation re-mint of `examples/function` (DESIGN §13): sonnet-5 regressed it
   twice, dropping the built artifact for `echo` ExecStart lines and demoting the
   declaration to a concept, while opus-5 kept the Go build and generalized
   further -- so budget opus for the artifact-bearing languages at least.
   Order matters: sweep first, then
   land item 4 -- a verifier landed first would turn the whole repo red.

4. **Invariant 6 is verified by nothing.** DESIGN's sixth invariant says every
   minted line is stamped `@gen:<id>` and the id must re-hash from the
   committed `.generation` record, but no code re-hashes anything: `check`
   reads the stamps as text. So a change to what the record contains silently
   invalidates every committed engine's stamps while all gates stay green.
   This is not hypothetical -- the schema pin added a `schema:` line to the
   record, which changed every generation hash, and no gate noticed (item 3).
   Remedy: `check` recomputes `genId` from the `.generation` beside the engine
   and refuses when a `@gen:` stamp disagrees, which makes a re-mint sweep
   verifiable instead of a matter of remembering. Deterministic, offline,
   domain-blind. Do it after item 3's sweep, or every committed engine fails
   the new gate at once.

5. **The schema pin is recorded, but nothing relates it to the nixpkgs the
   module is evaluated with** (open half of the schema-pin work, DESIGN §13
   "Option-schema grounding"; the mechanism landed cbd3f1f). Four separate
   questions, in the order they hurt:

   a. TWO NIXPKGS, NO RELATION. A mint is grounded against the `schema:` pin,
      while the realized module is evaluated against whatever nixpkgs the
      importing flake has -- and a compiled directory's own `flake.nix` says
      `inputs.nixpkgs.url = "flake:nixpkgs"`, resolved ambiently on purpose. So
      an engine can be grounded against one option set and evaluated against
      another, and nothing compares them. Loud in the common case (a renamed or
      absent option fails the user's eval), silent in the bad case (an option
      that survived but changed meaning). Candidate: `check` reads the pin from
      `.generation` and, when nix is available, warns when the ambient nixpkgs
      differs -- but `check` must stay nixpkgs-free, so this may belong in the
      flake helper (`lib.modulesFromDir`, which already has a `pkgs`) instead.
      Decide where before building anything.

   b. THE PIN IS NOT STICKY, BY DECISION. A re-mint defaults to the pin baked
      into the running binary, not the one the committed record names: a re-mint
      is the moment you want fresh grounding, and replay is impossible anyway
      (the model is nondeterministic), so the record is an audit trail, not a
      lock to obey. Consequence nobody is warned about: re-minting with a newer
      lips silently re-grounds, and the `schema:` line only shows it afterwards.
      Candidate if that ever bites: `generate` prints the old and new pin when
      they differ, which is one line of prose and no new knob.

   c. `--schema` IS PER INVOCATION AND REMEMBERED NOWHERE. A caller on a stable
      channel must pass it on every mint of every language, and forgetting it
      silently reverts to the baked pin (the record shows which, after the fact).
      Deliberate for now -- a per-directory default would be the lock file this
      design rejected, since the engine and its pin already travel together in
      `.generation`. Revisit only with a real user who mints often enough to be
      hurt; the honest cheap fix is (b)'s printed diff, not new state.

   d. `LIPS_OPTIONS_JSON` PINS BY CONTENT, NOT BY ORIGIN. A supplied document is
      recorded as `options-json:<hash>` of its bytes, which is checkable but
      says nothing about which nixpkgs produced it. Fine for the suite's offline
      fixture (its whole point is to be nixpkgs-free); a real caller who builds
      the document themselves loses the ref. Candidate: accept a ref alongside
      the path, or nothing at all -- prefer `--schema` for that caller.

6. **A demand cannot name a subject rooted at `<k:key>`, so the mint gate
   refuses engines that are correct** (found 2026-07-31 while re-minting
   `examples/website` for the punctuation physics; two of five opus mints died
   on it, which by invariant 4 makes it kernel physics, not a prompt problem).

   `Engine/Answerable.emittedFamilies` builds a nested pattern's family by
   substituting every hole in scope with itself, so a pattern emitting
   `fact <k:key>.target` yields the family `<k>.target`, TWO segments. But `<k>`
   binds the whole SUBJECT of the block's heading, which is itself several
   segments (`button.<n>`), so the only demand that can ever be met is the
   literal `<k>.target`, which no author can state and no honest mint writes.
   The mint writes `demand button.<n>.target`, three segments,
   `subjectsUnify` says no, and the refusal blames the mint for a demand its own
   patterns do answer -- the same wrong-side blame the module's habit story
   documents.

   Remedy, domain-blind and static: expand `<k>` to the emitted families of the
   pattern's PARENTS (`Lang.Nest` already knows them) instead of to a one-segment
   placeholder, so a nested family is `parent-family ++ rest`. Then
   `demand button.<n>.target` unifies. Same expansion belongs anywhere else a
   `<k>`-rooted family is compared segment for segment; check `Engine/Reach` and
   `Engine/Overlap` for the same assumption before fixing one call site.

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
  The recording half is now solved in shape: a mint's grounding is pinned in the
  record as `schema:` and overridable with `--schema` (DESIGN §13), so the CRD
  work is "let the schema source take extra definitions and pin each of them",
  not "invent a way to record a schema source".
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
  new parser. Half of that knob now exists: the generation record carries a
  `schema:` pin and `--schema` overrides it (DESIGN §13), so what is missing is
  per-provider granularity -- one pin per provider and version, recorded beside
  the world's own pin, rather than the single pin per event there is today.

- **Mint round loop** -- deferred, analysis kept so it is not redone. The idea:
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

- **Mint internet access** -- a second `registerTool` beside `query_options`,
  routing a question to a web search. Argument for: a recorded lookup is
  auditable evidence, the same move deduce-or-fail already makes for values.
  Argument for waiting: no mint has yet failed for want of a world fact. Add
  when a real mint fails for lack of a fact, not before.

- **Glue** -- the one deliberate incompleteness (computation inside the
  decision layer). `Glue` is a `Kind` with no rigor-downgrade mechanism.
  Blocks a *computed value*, not building a program (that is artifacts,
  done).

- **Dependency-fetching builders** (cargo/vendor hashes) -- untried. The
  proven path is no-dependency source (Go stdlib with `vendorHash = null`);
  fetching a real dependency graph at generate time is unexplored.

- **Language migration** -- no diff/migration path when a `.lang` regenerates
  to a different shape.

- **Multi-language composition** -- the prototype runs one engine; composing
  several languages in one Solution is unbuilt (dual of instance reuse).

- **Kernel modules** -- loadable, test-gated units extending the closed
  grammars at declared extension points (successor of the vocabulary
  milestone).

- **Guarantee lifecycle** -- the assumption `OPEN -> GUARANTEED` flow has no
  code.

- **Heile-Welt coping** -- no mechanism yet; reality mismatches (GPU present,
  driver loads) surface at runtime, outside the kernel's determinism
  boundary.

### From survey F (theory under the calculus)

Trace to `docs/superpowers/survey/f-decision-calculus-theory.md`. The
correctness/completeness argument these items back is now written out in
DESIGN.md §2 ("Correctness, by theory" and following). Ranked by payoff over
cost. Sequencing note: items 3 and 4 in "Next up" (the stale `@gen` stamps
and the unverified invariant 6) outrank everything here -- a critic who
re-hashes a committed `.generation` today falsifies invariant 6 for every
example, which is a sharper critique than any missing audit below.

- **IC postulate audit** (~1 day; prose plus property tests). Record which
  of Konieczny & Pino Pérez's merging postulates (IC0–IC8) `Base.resolve`
  satisfies, which it violates and why (arbitration over majority, with
  `Append` as the stated exception; strength structural, never authored).
  Pin the order-independence claim with property tests in
  `kernel/test/Spec.hs`: commutativity, associativity and idempotence of
  `resolve` (today only two tests touch these properties). Done when the
  audit lives in DESIGN.md and the properties run in the suite. Until then
  "merge is a set operation" is a promise, not a theorem.

- **Lex specialis: decide or refuse** (one paragraph in DESIGN.md §11).
  Strength is *lex superior* only (higher authority wins). Defeasible
  deontic logic also has *lex specialis* (the more specific subject wins),
  which is what an author may expect when a per-instance decision meets a
  language-wide default. Adopt it as physics or record the refusal with the
  reason; refusal is a valid answer, an undecided question is not. Done
  when §11 no longer lists it as open.

- **Minimal conflict explanation (QuickXplain)** (~1 week; code,
  deterministic, domain-blind, offline). A conflict names two competing
  decisions today. When the contradiction is derived several refinement
  steps down, the author needs the smallest set of *program lines* that
  cannot hold together. Junker (AAAI 2004) computes it in a logarithmic
  number of consistency checks; provenance chains and the strength order
  already supply the inputs. Honest caveat on urgency: while every
  committed engine emits only `Fact`, derived multi-step contradictions
  barely occur, so this is milestone hygiene, not observed pain -- build it
  as a self-contained milestone, not as a fire.

- **The deontic seam stays closed until an engine opens it** (blocked on
  usage, not on theory -- not buildable now by the repo's own YAGNI rule).
  Three items share one trigger: obligation survival under override
  (Nickel propagates contracts onto the winner; lips drops them wholesale,
  `Base.resolve` groups by subject and `Kind` never drives merge),
  contrary-to-duty coping (Heile-Welt, Chisholm 1963), and the guarantee
  lifecycle (`OPEN -> GUARANTEED`, no code). The trigger: the first minted
  engine that emits `Oblige`/`Forbid`/`Invariant` -- every rule in every
  committed `.lang` emits `Fact` today. When it fires, read input/output
  logic (Makinson & van der Torre 2000) before fixing obligation semantics
  in the kernel. Recorded in DESIGN.md §11 so the moment is recognized.

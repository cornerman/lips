# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

1. **Witnesses for the programs that cannot yet be observed** (opened 2026-07-31
   by the meaning-dimension work, DESIGN §13; the closed half of what used to be
   item 1).

   Claims landed and four programs carry one (`logscan`, `hello.http`, `board`,
   `habit`). Two baked-source programs still state no observable, so nothing holds
   their minted source to their sentences, and -- since the obligation is a gate on
   `generate` -- neither can be re-minted until this is settled. That makes this a
   PREREQUISITE for every re-mint item 7 wants.

   a. CLOSED 2026-08-03 (DESIGN §13, "A program that can be FED can be
      observed"): `board` and `habit` read their input from a named file or
      standard input instead of an absolute host path, `habit`'s row spans the
      log's own dates rather than today's, and both were re-minted with a witness
      that generate observed in the sandbox.
   b. `function` and `website` bake source and state no witness either; both are
      plain enough that an example should be cheap. Check when item 7 touches
      them.
   c. Not decided: whether a machine claim should RETRY its observation until it
      holds, bounded. A booted system converges (a unit may not be listening the
      instant `multi-user.target` is reached), so a single shot can be flaky, and
      flaky verification is worse than none. Retry-until-deadline is domain-blind
      and would be uniform for every claim. Deferred until a real claim actually
      flakes -- the one machine claim exercised so far did not.
   d. Watch the narrowing the `http` re-mint showed: told to prefer an observable
      over the program's own binary, the mint added a `-check` mode to its source
      and observed the handler in the sandbox instead of the booted service, so
      the port and unit wiring stay unobserved. Honest but narrower than it
      reads. If this recurs, the preamble should say when the booted machine is
      the only faithful place.
   e. A witness sentence listing N items freezes its pattern at that arity: both
      models minting `habit` filed the same gap (`fixed-arity-witness`,
      `witness-entry-count`), since the grammar repeats a sub-match only in a
      BULLETED block, never inside one prose line. The engine is honest (a
      program with two or four entries simply fails to crystallize, loud), so
      this is a completeness question, not a soundness one. Cheapest honest
      answer if it recurs: write the witness as a bulleted block, which the
      grammar already repeats -- try that before touching the kernel.

2. **CLI-tool physics -- the record behind item 1** (context: `board`, `habit`,
   `logscan` are committed, minted CLI engines; `examples/{http,postgres}`
   were re-minted honest. See DESIGN §13 for what landed getting there.)

   a. **Silent concept demotion -- two cases still open** (`diagInert` and
      `droppedValues` cover the rest; DESIGN §13):
      (i) CLOSED 2026-08-05 (DESIGN §13, "A rule reads one part, not the value"):
      the partial drop, the out-of-range `<value.N>` and the `<value.tail>` over
      a several-part value are all refused statically.
      (ii) CLOSED 2026-08-05 (DESIGN §13, "A word read as decoration is now
      said out loud"): `Engine.Reach.decorativeValues` names a hole whose only
      landing is a concept, per HOLE rather than per line, and `check` and the
      LSP report it. It found `function`'s demoted declaration on the corpus
      immediately.
      (iii) a compiled artifact records no dependency on the program lines its
      baked source came from. PARTLY CLOSED: a claim now holds the built source
      to the author's stated observable, so an edit that changes what the program
      DOES is caught by running it. An edit that changes a specification sentence
      without changing any observable is caught only where that sentence is a
      concept (the source-spec gate); a value edit that the source hard-codes
      independently of its fill remains invisible to both, and no static gate can
      see it.
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
      Related, and cheaper where it applies: item 7 (plurality). A singleton
      behaviour sentence gives the mint no reason to build the dispatch a claim
      would then verify, so enriching the program removes the defect where a
      claim would only have detected it.

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

3. **Which model to budget for a re-mint** (the record left over from the
   sweep that turned out to be unnecessary; see DESIGN §13, "Invariant 6 held
   all along"). Any re-mint (item 7's plurality edits, item 1b's witnesses)
   faces the same choice, so the datapoints are kept here rather than lost with
   the sweep:

   - `examples/function` (artifact-bearing): sonnet-5 regressed it twice,
     dropping the built artifact for `echo` ExecStart lines and demoting the
     declaration to a concept; opus-5 kept the Go build and generalized further.
   - The claims re-mints (2026-07-31): opus-4-5 twice prefixed its reply with
     reasoning prose, which the strict item parser refuses; opus-5 minted
     `logscan` and `http` cleanly, including a block-nested witness pattern.
   - `board`/`habit` (2026-08-03): sonnet-5 minted `board` cleanly with three
     `check_draft` calls, but on `habit` its passing attempt installed the built
     script twice so the claim's path would exist; opus-5 minted `habit` clean
     first try.

   Budget opus-5 for anything artifact-bearing. `check_draft` (DESIGN §13) is
   what makes sonnet-5 worth trying elsewhere: in the one measured A/B it turned
   a failing artifact-bearing mint into a passing one, but both arms were one
   run.

   PRECONDITION for any baked-source re-mint (2026-07-31): `generate` refuses an
   engine that bakes source and states no observable, so `function` and
   `website` need a witness in their program FIRST (item 1b).

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

7. **The corpus is minted from singleton programs, so its engines understand
   one instance each** (found 2026-08-02 by the website plurality experiment;
   DESIGN §13 "Plurality is what makes a baked-source hole mean anything" and
   the doctrine entry beside it).

   Every program in `examples/` is 1 to 9 lines, and most declare exactly one
   of whatever the language is about. For an option-backed hole that is fine
   (nixpkgs grounds it). For a hole reaching BAKED SOURCE it is not: with one
   instance a hole and a constant are indistinguishable, so the mint folds the
   words into the source and the resulting engine accepts sentences it cannot
   honour. `website` was fixed by enriching the program to three buttons and
   re-minting, which cost no kernel change and produced a closed action enum,
   a real dispatch, and a loud refusal of an unsupported action.

   `board` and `habit` were treated this way on 2026-08-03 (three columns, one of
   them empty; two contrasted mark characters), together with the feedability item
   1a needed. Remaining candidates, in order of how much they bake:
   `logscan` (55 lines of source, 4 of 5 program lines are `Concept`, all
   singleton behaviour sentences), `http` (24), `function` (23, and note the
   reverse experiment: cutting its three calls to one should demote the call to a
   constant). Each is one program edit plus one `generate --renew`, so this is
   cheap and does not wait on items 1-5.

   Not decided: whether to make it a GATE. A baked-source hole binding only one
   distinct value across the program is statically visible and domain-blind, so
   it could join `diagInert` as an LSP diagnostic ("this hole is never
   contrasted, so nothing holds the source to it"). Deliberately deferred: the
   remedy is an author writing a richer program, an advisory report may be
   enough, and item 1's claims falsify the same defect by observation rather
   than by counting. Revisit after the re-mints above supply more datapoints.

8. **The logic axis: DONE, reviewed, and repaired** (falsifier opened
   2026-08-02, run and PASSED 2026-08-04; full review 2026-08-05). All ten plan
   tasks landed. The review of the finished branch found five defects and three
   grammar gaps, all fixed and pinned:
   `docs/superpowers/learnings/2026-08-05-logic-axis-review-and-repair.md`.

   The three that mattered, each proven against the real binary before being
   fixed: a claim could name anything (a minted `(system "...")` spawned a shell
   and reported `ok`, and "every clause is observed" was satisfied by a claim
   observing nothing); `clause.main.extra` silently shadowed `clause.main`; and a
   constant `main` satisfied the runtime's entry, producing a binary that died on
   first run with every gate green.

   State: suite 732 examples, corpus 21 programs clean, `nix flake check` and
   `check-expect` green, validation 8 scenarios / 41 cases / 0 failures.

   a. **Compile emits a runnable site** (plan Task 7). DONE.
   b. **Clause claims inside `check`** (plan Task 8). DONE.
   c. **DONE, and it failed at first: two mints disagreed on the representation.**
      The mint now emits clauses (`assets/mint/body.md`, contract list rendered
      from the shipped vocabulary so prompt and gate cannot drift). Two live
      mints of `examples/logscan.lips` produced six clauses and no source in one
      run, and 94 lines of Go behind a shell wrapper in the other
      (`experiments/logscan-mints/`, both engines kept). Cause identified and it
      is not the prompt: the clause path cannot install a program or read its
      arguments, so a model optimizing for a working engine correctly picks Go.
      Two holes to close before re-running, and they are now item 10.

      One bug the live mint found, since fixed: realize was rendering clauses
      into the module as option assignments, which no gate caught and which made
      the module unparseable.

10. **Both holes the live mint found are CLOSED** (opened and closed
    2026-08-04). `${site}` is a value-grammar reference bound in the module's
    `let` (and in `claims.nix`, and in every temp dir a gate materializes), with
    `site.name` carrying the executable name; `arguments` is an effect contract
    the guile adapter provides, the in-memory adapter serves from a list, and a
    `claim.<id>.args` section varies. Verified: `experiments/clause-site` still
    runs and its claim holds through the entry `(main (arguments))`.

    Four bugs came out of the live mints, each invisible to the suite because
    each needed a model to write the shape that triggers it. All fixed with
    regression tests: realize rendered clauses INTO the module as option
    assignments; the site binding was decided from option values only, so a
    reference from an artifact ARGUMENT produced an undefined variable; the
    claims file needed the same binding; and every gate that materializes a
    module into a temp directory had to stage the site beside it, not just
    `artifacts/`.

11. **Falsifier check (c) is ANSWERED, and it passes behaviourally**
    (2026-08-04, `experiments/logscan-mints/`, mints `e` and `f`). Both mints of
    the same five-line program chose clauses, neither wrote a line of source,
    both cores are seven traceable definitions, and the two binaries agree
    byte-for-byte on thirteen probes including every case where the two Go mints
    diverged. They do NOT agree textually: the two cores factor the loop
    differently. So the honest verdict is that two mints differ where the program
    does not in TEXT, and not at all in BEHAVIOUR.

    Two qualifications kept in the open: thirteen probes are evidence, not proof;
    and both mints invented the same unstated policy for a non-JSON line (drop
    it), which is now visible in a traceable clause instead of buried in Go, but
    is still invention. Closing that is the author's job (state the line) or a
    demand's (ask for it), not a gate's.

    The run caught one defect no gate had: both mints defined `(define (main) ...)`
    against an entry calling `(main (arguments))`, so both binaries died on first
    run with every gate green. Fixed by deriving what the core must define from
    the entry expression itself.

12. **The contract set reaches stdin-to-stdout text tools and nothing else**
    (measured 2026-08-04 by `experiments/validate/`, scenario `rotate`). Asked
    to sweep three directories of files older than 14 days, the mint wrote 97
    lines of Go and never considered clauses: there is no contract for a file, a
    clock, a process or a socket, so there was nothing to name. The grounding
    counter reported it honestly ("0 clauses, 101 lines vouched by nothing"), and
    the fallback itself is correct -- but it is the whole clause axis stopping at
    the edge of one program shape.

    Do NOT invent `list-directory` and friends. That breaks the vocabulary
    scaling law, which is why the configuration axis works: lips reaches as far
    as some EXTERNAL named typed vocabulary reaches, and inventing an effect
    interface makes lips the authority for one it must then maintain forever.
    The named candidate is already in the 2026-08-02 decision (§10): WIT, which
    names behaviour without naming an implementation language, with WASI's
    filesystem and clock interfaces as the typed authority. Adopting one is a
    design pass, not an errand.

13. **Remaining known gaps on the clause axis** (none blocking).

    a. **RESOLVED, and it was never a grammar gap.** Four mints wrote witness
       patterns with one hole per example line, which reads a three-line program
       and refuses a four-line one. `Lang/Nest.hs` already carries the case, and
       its header says why the kernel must not carry it any other way ("the
       kernel would otherwise be dictating a collection syntax"): a block is a
       header pattern plus a child under it keyed by `<n:index>`, and `Append`
       assembles one list from the N contributors. Demonstrated with one
       hand-written engine over three and five items, no model. Fixed in the mint
       prompt ("NEVER FIX A COUNT IN A TEMPLATE"), not in the kernel. Watch the
       next mints to confirm they use a block.
    b. **`app/Main.hs` is 2000 lines.** `writeSite` was extracted to `Lips.Site`
       when it grew four jobs; the gates around it deserve the same treatment,
       and that is real work with real regression risk, not a logic-axis errand.
    c. **Several sites at once is refused, not built** (plan Task 10 landed as
       shape only). No committed example needs a second place; the refusal makes
       growing to several a kernel change nobody can stumble into.
   d. **Sites** (plan Task 10). A program states where it runs, coverage runs
      per site over one shared core, and compile writes one directory per site.
      This is what lets a rule hold in a browser and on a server without two
      implementations that drift.

14. **The no-blob doctrine, with its gate** (agreed 2026-08-04, deliberately
   deferred until item 8c lands so doctrine and enforcement arrive together).

   The rule: **no per-program source written by a model.** A blob is admissible
   only when it is not per program and reviewed once (an adapter under
   `assets/runtime/`, serving every program), or when it is somebody else's
   package reached by name. The escape for genuine one-offs is a VALUE, never a
   file: `greet`'s four words of bash are bounded by sitting in one assertion
   attached to one program line, where a staged tree has no such bound and grew
   to 80 lines in `logscan`.

   Two grades, deserving different trust. AUTHOR glue, where the foreign text is
   in the program, is legitimate without qualification. MINT glue, where the
   model chose it (`echo` in `greet`), is admissible but must be marked, counted
   and pinned by a claim, since it is exactly what a re-mint rewrites.

   What exists: the counting (`Lips.Kernel.Grounding`, printed on every check).
   What is missing: the `Glue` kind is declared in `Decision.hs` and used
   nowhere, so glue is counted structurally rather than marked as such; and no
   gate refuses a new staged tree. Both land with 8c, when `logscan`'s line moves
   from "80 lines vouched by nothing" to "8 clauses (contracts)".

## Backlog (larger / deferred by design)

- **Cross-program composition (one program naming another).** Nix composes;
  lips does not yet. Names RESERVED for it, so nothing squats on them and a
  later rename is not a re-blessing event for every committed engine: the emit
  head `export.*` (a program's public surface) and a third value ref beside
  `${pkgs...}` and `${artifact...}`, namely `${program.<instance>.<path>}`,
  resolved at compile from the sibling's committed engine BY NAME. The kernel's
  reserved heads are now `artifact.*` and `claim.*`; claims are what would mark
  which part of an exported surface is actually verified. Two shapes, both wanted. SAME WORLD: a kubenix program
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
cost. Sequencing note: the sharpest critique this list used to rank behind --
that invariant 6 was verified by nothing -- is answered (DESIGN §13, "Invariant
6 held all along"), so these are now the outstanding theory gaps.

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

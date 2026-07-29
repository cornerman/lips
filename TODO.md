# TODO

## Next up (priority order)

0. ~~**Mint `examples/greet.lips`.**~~ DONE (ca09f97 committed
   `examples/greet/`). ~~`check-expect` and `lipsModules-eval` stay RED for the
   three programs still without an engine~~ -- `examples/{board,habit,logscan}`
   are committed (f0e8d13) and all 13 example programs `check` green.
   **Correction (2026-07-29 review): `lipsModules-eval` is still RED**, for an
   unrelated reason -- `nix/modulesFromDir.nix` cannot parse a singleton
   `<language>.lips` name (item V1 below). The
   original text follows for its target-shape notes.

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
   `uncheckableExpects` rightly refuses an assertion on such an option (see the
   gap report's finding 5, `git show ca09f97^:docs/gaps/README.md`, which is that guard followed through to its
   uncomfortable conclusion).

1. **CLI-tool physics** — three CLI engines now committed (f0e8d13: `board`,
   `habit`, `logscan`; each `buildGoModule` + `home.packages`, each artifact
   instantiating and running). Two gates landed getting them there: staged
   sources (1e, half) and answerable demands (new, ledger §13). Remaining
   sub-items below. Evidence and analysis in the gap report (deleted with
   `ca09f97`; read it with `git show ca09f97^:docs/gaps/README.md`), with
   `examples/{board,habit,logscan}.lips` as committed repros. Six mints on
   2026-07-27 (three programs x qwen3-coder:30b and claude-sonnet-5) produced no
   engine and six findings. Ranked:

   a2. **Re-mints DONE (2026-07-30).** The two engines that named their own defect
      (`http`, `postgres`) are re-minted and honest; see DESIGN 13, "The two
      dishonest engines re-minted". Three new findings came out of it, none of
      which any lips gate can see today:
      (i) **no gate looks INSIDE a build.** The first http re-mint kept
      `module app` in `go.mod`, so the binary was `app` while
      `ExecStart = "${artifact.hello}/bin/hello"` named `hello`: a service that
      cannot start, past `check`, past `lipsArtifacts-eval` (which instantiates,
      never builds), caught only by running the binary by hand. The prompt now
      states the obligation ("a path inside a build must exist"), which is a plea,
      not a guard. Candidate: a flake check that BUILDS each committed artifact and
      asserts every `${artifact.<name>}/...` path the module names exists in the
      result. Cheap to write, minutes to run, and it is the only thing between a
      green repo and a dead unit.
      (ii) **an option's own semantics can make an honest engine wrong.** postgres
      emits `ensureUsers = [ { name = "app"; ensureDBOwnership = true; } ]`, but
      NixOS grants ownership of the database that shares the USER's name, so a
      program naming a user and a database differently would realize a silently
      wrong config. The words are spent (the dropped-value guard is satisfied), so
      lips sees nothing; the kernel cannot know option semantics either. Candidate:
      nothing kernel-side -- it belongs in the mint's own review, or as a `gap` the
      mint should have filed.
      (iii) **duplicate list elements survive assembly.** Two lines mentioning the
      same database give `ensureDatabases = [ "app" "app" ]`. Harmless for postgres,
      noise in the output, and a reviewer trips over it. Open decision: should
      `Append` assembly drop an element a previous contributor already stated (a
      set-like merge), or is order-and-multiplicity part of what a list states?

   a. **Silent concept demotion (deduce-or-fail's blind spot).** Two halves
      landed (ledger §13): `diagInert` names the lines that realize nothing, and
      `droppedValues` makes a word the language reads and then discards a static
      defect, refused at the mint gate and reported per line for engines already
      committed. Three cases stay open:
      (i) a PARTIAL drop — a rule reading `<value.1>` of a value built from two
      holes silently drops the second; a sound static map from holes to token
      positions is the missing piece (a multi-token capture breaks the naive one).
      (ii) a per-hole DECORATIVE report — a hole demoted to a `Concept` on a line
      that otherwise realizes is invisible, since `diagInert` works per line.
      This now has call sites: `board`, `habit` and `logscan` emit `Concept`s (2,
      3 and 4 decorative lines). The bigger question those mints raise is item V6
      below (a mint may pass every gate by declaring the program decorative).
      (iii) a compiled artifact still records no dependency on the program lines
      its baked source came from, so an edit to one of them compiles to an
      unchanged binary. Candidate: record the source's line dependencies at mint
      and fail loud when one changes.
      RESOLVED by the 2026-07-30 re-mints (item a2 above); the original text
      follows. Two committed engines now name their own defect under (the closed
      half of) this item and need a re-mint: `examples/http` (`<lang>` read into a steer, rule emits the literal
      `buildGoModule`) and `examples/postgres` (`<dbname>` bound in *who owns the
      app database* and emitted nowhere, while the rule asserts the constant
      `ensureDBOwnership = true`; NixOS `ensureUsers` may have no option that can
      honor a foreign database, which would make it a `gap`, not a rule fix).

   b. ~~**Capture-keyed artifact names.**~~ CLOSED (see ledger §13). A capture
      now keys an artifact and fills a value, so `install a command greet that
      prints "..."` is writable and both values flow from the sentence.

   c. ~~**Language branching.**~~ CLOSED by design (ledger §13, DESIGN §11): a
      word that SELECTS a mechanism is a template LITERAL, not a hole, so editing
      it stops the line matching and `check` fails loud naming `lips generate`.
      Regeneration is the branch; the `.lang` is disposable by design. The
      `droppedValues` gate refuses the dishonest alternative (a hole bound and
      ignored), the prompt now states the split, and the gate's refusal names all
      three remedies. No kernel change was needed: the shape was always
      expressible. What remains is empirical -- re-mint the engines that predate
      the split (see item 1a's list).

   d. **CLOSED (2026-07-30) by source fills** -- see DESIGN 13, "Source fills".
      An artifact declares `artifact.<name>.fill.<marker>` (an ordinary value, so
      every hole mechanism applies) and its source names `@marker@`; lips
      substitutes when it stages the tree, at compile, offline. Both directions
      are checked, so neither a declared fill no file names nor a marker no fill
      declares can pass. That kills the `postInstall` shell workaround below and
      lets a captured command name reach `go.mod`. What remains is NOT this item:
      a REPEATING structure inside source (one code block per route) has no
      marker form and stays a gap to file (`repeating-source`), which is what the
      httpserver repro needs. The original text follows for its evidence.

      **Templated source, two fresh repros** (extends the existing backlog item
      below): the command name must reach `pname` and the Go module inside the
      artifact, and source heredocs have no holes.
      Half closed (see ledger §13, "One name grammar"): a composite artifact
      name (`<self>-core`, `<name>-core`) is now physics, so the
      compiled-core-plus-`writeShellApplication`-wrapper shape a mint reaches
      for is writable, and an unfilled name fails loud at realize instead of
      reaching the module. Still open: a hole inside a source heredoc, which is
      the "source is a fixed blob" half.
      **Third repro, and the first with a workaround attached** (`logscan` mint,
      2026-07-28, claude-sonnet-5, thinking max): needing the captured command
      name inside `go.mod` (which it had to write as `module app`), the mint
      renamed the built binary from a shell loop smuggled into a build argument --
      `args.postInstall "for n in $out/bin/*; do if [ $n != $out/bin/<value> ];
      then mv $n $out/bin/<value>; fi; done"`. The value grammar forbids
      computation, but a build arg is an opaque string, so shell walks straight
      through it. By invariant 4 this is the signal that the fix belongs in the
      format (a hole inside `source`), not in the output: a human reading that
      line would flag it. The mint did not file a gap for it ("No gaps.
      postInstall and home.packages are ordinary derivation/option mechanics"),
      so it is recorded here by hand. Note this is the mint's own answer to the
      question 1d asks -- how a program's word reaches inside a compiled
      artifact -- and it answers it with shell.

   e. **A CLI engine has nothing to pin** — no longer theoretical: it shipped a
      broken build. **CLOSED 2026-07-29** (see the decision at the end of this
      item). Earlier half (ledger §13, "Staged sources"): every relative
      path a module names must exist in the staged tree, checked at `check` and at
      `generate`, which refuses the two staging repros on record (the `habit` mint
      staging its source under the literal directory `<name>`, and a renamed
      command leaving `./artifacts/kb` pointing at nothing). Offline, no nix eval.
      Still open below: a malformed *builder argument* set (`pname` with no
      `version`), which no path check can see. The first `board` mint (2026-07-28, claude-sonnet-5) emitted
      `args.pname` with no `args.version`, so nixpkgs could not derive a name and
      `nix run …#artifact.board` died with `attribute 'name' missing` — a raw nix
      error naming neither lips, the program, the artifact, nor a remedy, past
      every lips gate, with `check` reporting "all 2 checks pass".
      Why no gate caught it: `runExpects` is the only evaluation lips performs,
      and an artifact is unreachable by it three times over — it returns early on
      an empty contract (`greet`: 0 checks, zero evaluation), nix is lazy so
      forcing board's two string options never touches `home.packages`, and
      `uncheckableExpects` forbids an expect on a derivation-valued option, so no
      contract may ever name an artifact.
      Verified remedy, and the honest answer to this item: **an artifact's own
      instantiability is its contract.** Force each artifact's `drvPath` against
      the pinned nixpkgs the binary already bakes as `LIPS_NIXPKGS_FLAKE` (the
      same pin behind the option schema). Domain-blind and complete: nix judges,
      so the kernel needs no list of builder arg names, and every malformed
      artifact fails for every builder. Tested against the corpus with the exact
      expression a gate would build: board FAILS (`attribute 'name' missing`),
      greet and http INSTANTIATE, so it refuses the bad mint with no false
      positives.
      DECIDED and CLOSED (2026-07-29), in two halves, neither of which costs
      `check` its offline, nixpkgs-free property:
      (1) **an artifact arg is assertable.** `expect artifact.greet.args.text from
      cmd.greet.msg` is judged by the kernel against the GROUND base
      (`Lips.Kernel.Expect.checkArtifactValues`) -- no nix, since an arg is a
      literal there, and a builder consumes it so no eval could reach it anyway.
      `uncheckableExpects` no longer sweeps these up, and the mint prompt now
      requires one whenever a program value lands in an arg instead of an option.
      This is what an artifact-only program (`greet`, `logscan`) can pin at all;
      before it, their contracts were necessarily empty.
      (2) **instantiability is checked where nixpkgs already lives**: the flake
      check `lipsArtifacts-eval` forces every committed example artifact's
      `drvPath` (instantiate, do not build), so a malformed builder arg set fails
      in `nix flake check` in seconds. Rejected: running it in `check` (drags
      nixpkgs into the offline verb) and in `generate` only (leaves an engine
      committed before the gate broken). Rejected on sight, as before: a kernel
      rule requiring `name`/`pname`/`version`, which enumerates nixpkgs arg names
      inside a domain-blind kernel.

   f. **Two hole namespaces, one syntax** (pattern holes named by the template
      vs the rule side's fixed `<value>`). A weaker model confuses them
      reliably, which makes it a format question, not a prompt question.

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

5. **Template grammar completeness** (completeness plan Target 2) — the
   multi-token hole LANDED (2026-07-30, DESIGN 13): `<name.words>` binds several
   words anywhere in a template, matched shortest-first with backtracking, and
   retires the end-of-line-only `<name.tail>` spelling. Deferred with its reason:
   true parent-child block aggregation (a decision owning a list), because
   subject-keyed bulleted items plus `Append` already carry every list the corpus
   states — revisit when a program needs a block a subject cannot key.
   What still separates the template claim from the value claim is soundness, not
   capture forms: static pattern overlap (survey F below) is dynamic today, and a
   multi-token hole makes the unification harder.

## Verified breakages (review of 2026-07-29, all reproduced on 95e80f7)

Each is stated with its promise in DESIGN §13, "Verified Breakages". Ranked by
blast radius; V1-V4 are small, local fixes with tests missing.

### The plan (execution order) -- ALL FOUR WAVES LANDED 2026-07-29

Wave 3 (the three decisions) landed too, each as decided with the owner:
V6 by the source-specification gate, V8 by `compile --no-contract` at the three
nix call sites, and TODO 1e by both halves (an artifact arg is assertable; the
new flake check `lipsArtifacts-eval` forces every artifact's `drvPath`).



Landed on branch `breakages` (one commit per item, suite 356 green, all 13
examples `check` clean, `nix build .` and `lipsModules-eval` green, every
compiled example byte-identical except the intended `artifact.nix` shape):
V1, V2, V3, V4, V5, V7 and simplification items 10-14. What remains is wave 3,
which needs a decision, not a patch: V6 (the concept escape), V8 (the deploy
path's missing gate) and TODO 1e (the artifact contract).

One deviation from the plan, recorded because the plan preferred the other
branch: V1 kept the naming rule duplicated in Nix instead of adding a read-only
`lips identify`. Output ATTRIBUTE NAMES must be known at eval time, so having the
derivation ask the binary would require import-from-derivation. The Nix copy now
carries a comment naming it as a duplicate, and `lipsModules-eval` forces both
target worlds, so a drift breaks the build (forcing only `nixosModules` is what
hid the bug: all four singleton programs are home-manager ones).

### The plan as written

One worktree under `.worktrees/`, TDD per item, one single-line commit per item,
rebase + ff-merge, ledger §13 updated as each lands. Each numbered step names
its own proof, so "done" is never an assertion.

**Wave 1 -- red build and silent-wrong output (do together, one branch).**

1. V2 `artifact.nix` recursive. Test first: a two-artifact ground base
   (`core` + a wrapper whose `args.runtimeInputs` holds `${artifact.core}`)
   through `realizeArtifactFile`; assert the file evaluates. Then `rec {`.
   Proof: the new test, plus `nix eval` of the compiled `artifact.nix`.
2. V3 dangling refs in artifact args. Test first: the same base with the
   wrapper naming `${artifact.nosuch}`; assert `RDangling ["nosuch"]`. Then
   collect names from artifact groups beside option values in `renderModule`,
   and do the same in `realizeArtifactFile` (today it checks nothing at all).
   Proof: the new test; all 13 examples still realize byte-identically.
3. V1 one naming rule, not two. Delete `parse` from
   `nix/modulesFromDir.nix` and let the binary answer instead -- add a
   read-only `lips identify <program>` (or `--print-paths`) that prints the
   instance, language and language dir, and have the derivation read it. If
   that verb is judged too much surface, the fallback is to mirror
   `Lips.Identity`'s rule in Nix with a comment naming it as a duplicate.
   Proof: `nix build .#checks.x86_64-linux.lipsModules-eval` green with the
   four singleton examples committed (it is red today).
4. V7 refuse a non-`.lips` program. Test first: `resolveLangDir`-level (or a
   new `programPath`) rejection of `x.backup.txt` and of a `.lang` passed as a
   program, naming the marker. Then one fail-loud check in `Lips.Identity`,
   called by every verb that takes a PROGRAM. Proof: the tests, plus
   `lips check examples/backup/backup.lang` failing with a sentence about
   `.lips`.

**Wave 2 -- grammar completeness and capability symmetry.**

5. V4 one quote-aware emit splitter. Test first: round-trip a rule whose rhs
   contains `" ; "` (`environment.etc.foo.text "cd /x ; ls"`) through
   `renderRuleBody`/`parseRuleBody`, and a QuickCheck property over generated
   values so the case cannot regress. Then lift `splitEmits`/`unescapedQuotes`
   out of `Kernel/Lang/Store.hs` into one shared home (they are the same rule
   the pattern side already uses) and call it from `parseRuleBody`. Proof: the
   tests; every committed engine parses byte-identically.
6. V5 `<self>` fills by occurrence in an expect path. Test first: an expect on
   `...<self>-core...` binds to `<instance>-core`. Then replace the literal
   comparison in `bindSelfExpect` with `fillName`, the call the rule side makes.
   Proof: the test; existing contracts unchanged (a whole `<self>` renders the
   same).

**Wave 3 -- the two decisions (argue before coding; both are doctrine).**

7. V6 the concept escape. Not a patch: pick one of (a) a `Concept` must be
   answered by a realizing sibling under the same subject prefix, (b) an
   artifact records the program lines its source came from (item 1a(iii)) so a
   decorative behavior line becomes a dropped word, (c) `generate` refuses an
   engine with zero checkable assertions unless every option it fills is
   derivation-valued. Whichever wins, `examples/logscan` is the repro and the
   acceptance test; write the decision into DESIGN §11 (with the refusal
   recorded if the answer is "live with it").
8. V8 the deploy path's missing gate. Decide whether
   `lib.modulesFromDir`/`vm-smoke`/`artifact-vm` are gate-free by design (the
   gate ran at `check` time, in the repo, and a derivation has no `nix`) or
   whether compile takes an explicit `--no-contract` so the skip is stated.
   Either way the choice lands in DESIGN §13 and the README paragraph that now
   only warns about it.
9. TODO 1e's artifact contract (an artifact's instantiability is its contract)
   is the natural sequel to wave 1: with V2 and V3 fixed, forcing each
   artifact's `drvPath` is the last hole between a green `check` and a broken
   `nix run`.

**Wave 4 -- simplification, no behavior change (each its own commit).**

10. `Kernel/Run.hs` exports `runGround`; `runBase`/`runBaseArtifact`/
    `runBaseStaged` become pure projections of one result, and `validate` runs
    the pipeline once instead of three times (`compile` once instead of four).
    Proof: all examples compile byte-identically.
11. Collapse the duplicated helpers: `parseQuoted` (three copies), `kindText`
    (three), `stripTailPunct`/`stripTrailingPunct` (two). Proof: suite green,
    output byte-identical.
12. Retire the `*Replace` wrappers (`resolveReplace`, `realizeReplace`,
    `runReplace`, `runBaseReplace`) in favour of test helpers, so the suite
    stops paying for production surface.
13. Replace the shell-outs with `directory`/`temporary` calls (`mktemp`,
    `mkdir -p` with hand-rolled quoting, `cp -rT`), and make the staging copy
    fail loud instead of swallowing every error.
14. Cosmetics: the double `Data.Maybe` import in `Kernel/Engine/Data.hs`, the
    `pAttrKey` comment that contradicts its code (hyphens and `'` are
    accepted; its char list repeats `-`), and the `@print@` verb in
    `Kernel/Refine.hs` and `Kernel/Realize.hs` comments.

Done already (6e0471c): the documentation half of this review -- stale ledger
claims corrected in DESIGN/README/AGENTS/kernel README, this section written,
and the breakages recorded in DESIGN §13.

V1. FIXED (5df0bc2). **`lib.modulesFromDir` cannot read a singleton program, so `nix flake
    check` is red.** `nix/modulesFromDir.nix` takes filename element 0 as the
    instance and element 1 as the language, so `board.lips` becomes language
    `lips` and the build dies with `Path 'examples/lips/lips.lang' does not
    exist`. Fix: derive the pair the way `Lips.Identity` does (last extension
    before `.lips` is the language; a missing instance defaults to it). Better:
    stop duplicating the rule in Nix -- have the derivation ask the binary
    (`lips` already knows), so one implementation answers.

V2. FIXED (7a7e022). **`artifact.nix` is not recursive.** `realizeArtifactFile` emits `{ ... }`,
    so an artifact arg holding `${artifact.<other>}` renders an undefined
    variable; the module escapes it only because a Nix `let` is recursive. Fix:
    `rec {`, plus a conformance test over a core-plus-wrapper base.

V3. FIXED (7a7e022). **A dangling `${artifact.<name>}` inside an artifact ARG is not caught.**
    `renderModule` scans option assignments only, so `RDangling` misses
    artifact-to-artifact references and the failure lands inside nix as
    `attribute '<name>' missing`. Fix: collect names from the artifact group's
    args too (one `concatMap`).

V4. FIXED (68c9bc8). **A rule rhs may not contain `" ; "`.** `parseRuleBody` splits emits with a
    naive `T.splitOn " ; "`; the pattern side already has the quote-aware
    `splitEmits` (its comment names this defect). A shell text
    (`"cd /x ; ls"`) fails to parse, reported as "unterminated string". Fix:
    share one quote-aware splitter; a missing grammar case is a kernel bug.

V5. FIXED (3aa8103). **`<self>` binds only as a whole segment in an expect path.**
    `bindSelfExpect` compares literally instead of using the shared `fillName`,
    so `<self>-core` never binds and the assertion silently reads `null`. Fix:
    use `fillName`, the same call the rule side makes.

V6. FIXED (2026-07-29), see DESIGN 13 "Verified Breakages" for the mechanism.
    Reproducing it first narrowed the hole to DELETION (a reworded or added line
    is already unmatched), and the fix is the source-specification gate: where a
    language bakes source, a concept the mint saw and the program no longer
    states fails loud, compared against the corpus the `.generation` record
    stores verbatim. **The concept escape as found: a mint may declare the
    program decorative and pass every gate.** `logscan` reads 4 of its 5 lines as `Concept`s and keeps the
    behavior in baked Go source, so editing the sentences changes nothing while
    `check` reports success -- with an empty contract, so nothing is pinned
    either. The thesis says the program is the source of truth; here it is a
    comment. Not obviously fixable in a domain-blind kernel (counting words is
    exactly what the kernel may not do); candidates worth arguing:
    (a) require a `Concept` line to be answered by SOME realizing sibling under
    the same subject prefix, (b) make an artifact record the program lines its
    source came from (item 1a(iii)) so a decorative behavior line becomes a
    dropped word, (c) refuse an engine with zero checkable assertions in
    `generate` unless every option it fills is derivation-valued.

V7. FIXED (5f7c6c0). **A program file's extension is never checked.** `x.backup.txt` is read as
    language `backup`, and `examples/backup/backup.lang` as a program. Fix: one
    fail-loud check on the `.lips` marker in `Lips.Identity`.

V8. DECIDED and FIXED (2026-07-29): the deploy path is gate-free by design and
    now says so, via `compile --no-contract` at each of the three call sites.
    **As found: `lib.modulesFromDir` compiles without the contract.** Its derivation (and
    the `vm-smoke`/`artifact-vm` checks) copies only the `.lang`, so
    `expectGate` finds no `.expect` and prints "no behavioral contract yet"
    instead of gating -- and the derivation has no `nix` on PATH, so copying the
    contract in would fail loud rather than pass. Decide it: either the deploy
    path is documented as gate-free (the gate ran at `check` time, in the repo)
    or the compile-in-derivation drops the gate explicitly with a flag, so the
    skip is a stated choice instead of a missing file.

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
- **Artifacts: repeating source** — a WHOLE VALUE inside source now flows at
  compile through a fill (item 1d, closed); what has no form is REPETITION: N
  routes need N code blocks, and a marker replaces text, it cannot repeat a
  block. Also: dependency-fetching builders (cargo/vendor hashes)
  untried. Concrete repro (2026, `server.lips` httpserver example): a route's
  status/mimetype/body must land inside the compiled Go source per route
  (keyed by `<path>`), but `source` heredocs are verbatim text with no holes
  and no per-item (capture-keyed) binding into source text; `generate` rightly
  refuses these three (confidence 0.35) rather than fake it. Needs a per-ITEM
  binding into source text (the `<capture>` mechanism fanning one block out per
  matching item), plus a decision on whether the repetition is rendered at
  generate (the model writes the loop, and an added route needs a fresh mint) or
  at compile (the kernel repeats a marked block, which is a second grammar).

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
- ~~**Static pattern overlap**~~ — LANDED 2026-07-30 (DESIGN §13, §11). A product
  walk over the two token templates decides "could one line match both" exactly;
  a template repeating a hole name is skipped rather than approximated, and all 11
  committed engines pass, so the gate refuses nothing that works today.
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

All items in this section were cleared on 2026-07-29 (wave 4 of the review plan);
kept as a record of where the duplication was, since each has a single home now:

- the sentence-punctuation rule, the transport quoting and the quote-aware
  separators live in `Kernel/Surface.hs`; the kind/strength words beside their
  type in `Kernel/Decision.hs` (e079a8a).
- `Kernel/Run.hs` exports one `Realization` from one pipeline run, and `compile`
  materializes the realization `check` validated (20816c7, 6bd3398).
- the four `*Replace` wrappers are test helpers in `test/Spec.hs` (20816c7).
- the CLI uses `directory`/`unix` calls, removes its temp dirs, and propagates a
  staging error instead of discarding it (a16c19b).
- the double `Data.Maybe` import, the `pAttrKey` comment and the `@print@` verb
  in comments are gone (68c9bc8, e079a8a).

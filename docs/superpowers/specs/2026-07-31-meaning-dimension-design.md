# The Meaning Dimension: Observable Claims + Source-Line Provenance

Status: approved design, 2026-07-31. Implements TODO item 1 (decided
2026-07-30). Supersedes the "no remedy" verdicts in TODO 2a(iii), 2a(iv)
and 2b.

## Diagnosis

Every gate lips has reads the MAP (the module text) and none observes the
TERRITORY (a running thing). So a program can only say what becomes a
`path = value` assignment; behavior gets frozen into baked source, cut off
causally from the lines it came from. Two mechanisms close this, and neither
closes it alone:

- **Source-line provenance** keeps a specification sentence causal: a
  mint-time line the baked source was written from that changes or vanishes
  makes `compile` fail loud, naming the remedy (re-mint).
- **Observable claims** hold the implementation, and every future re-mint,
  accountable to behavior the author stated, by running it.

## Current State (verified 2026-07-31, corrects the TODO)

The reword hole is narrower than TODO 2a(iv) records. Verified by
experiment and code reading:

- Rewording `equals` to `differs` in `examples/logscan.lips` fails loud
  today: the sentence's pattern is all-literal, so the reworded line is
  unmatched (`ParseRejected`), and compile points to `lips generate`.
- `retiredConcepts` (`Kernel/Lang/Diagnose.hs`) compares mint-time vs
  current concepts by subject AND text, so a reword swallowed by a hole in
  a concept-emitting pattern is also caught by `sourceSpecGate` — the TODO's
  "catches DELETION only" is out of date.
- What remains open: (a) the recorded-section escape — a program the
  `.generation` record holds no section for (added or renamed after mint)
  is silently skipped by `sourceSpecGate`; (b) nothing pins the closure as
  a tested invariant, so a future kernel change could reopen it unnoticed;
  (c) a value that flows into an option while the baked source hard-codes
  the same fact is invisible to any static gate — that case belongs to
  claims, by observation.

## Decisions (from the interview, 2026-07-31)

1. Provenance first, claims second: one plan, two landed milestones, plus a
   re-mint milestone.
2. Provenance mechanism: generalize `sourceSpecGate`; no new file, no
   in-source stamps (comment syntax is per-language knowledge the
   domain-blind kernel must not have), no per-artifact line sets (a minted
   declaration the model can get wrong, with no observed need).
3. A machine claim in a non-NixOS world is refused at generate, stated in
   the mint preamble. Artifact-only claims work in every world.
4. Re-mint scope: exactly the four TODO 1d names (`logscan`, `board`,
   `habit`, `hello.http`). The 18-language sweep stays TODO item 3.

## Milestone 1 — Source-Line Provenance

Scope: close the recorded-section escape, sibling-safe, and pin the whole
closure with conformance cases.

Mechanism. `sourceSpecGate` today reads the mint-time program section from
`.generation` (`recordedProgram`) and dies on `retiredConcepts`. Two changes:

- **Unrecorded program, baked source.** When the language bakes source (a
  committed `artifacts/` tree) and the record holds no section for this
  program, every `Concept` decision the current program states must appear
  (subject + assertion text) in the union of ALL recorded sections'
  crystallized concepts. An unrecorded concept fails loud: the baked source
  was written for a specification that never contained this sentence.
  Sibling reuse survives: `photos.backup.lips` states only concepts the
  recorded corpus already states (all-literal patterns force the exact
  text), so it passes with no re-mint. A missing or unreadable
  `.generation` beside a baked `artifacts/` tree is itself loud.
- **Pure judgment, testable.** The gate's decision logic moves into a pure
  function so the conformance suite reaches it:

      -- Kernel/Lang/Diagnose.hs
      data SourceSpecVerdict
        = SpecHolds
        | SpecRetired [Decision]     -- mint-time concepts no longer stated
        | SpecUnrecorded [Decision]  -- stated concepts the record never saw
      sourceSpecVerdict :: Maybe Base -> [Base] -> Base -> SourceSpecVerdict
      -- (recorded section for this program, if any; all recorded sections;
      --  the current program's base)

  `Main.hs` keeps only the IO shell (read record, crystallize, report).

Conformance cases (kernel/test/Spec.hs): deletion of a recorded concept →
`SpecRetired`; reword through a holed concept pattern → `SpecRetired`;
unrecorded program stating an unrecorded concept → `SpecUnrecorded`;
unrecorded program stating only recorded concepts → `SpecHolds`; language
without baked source → gate not consulted (existing behavior, pinned at the
caller level by leaving `sourceSpecGate`'s `baked` guard in place).

## Milestone 2 — Observable Claims

### Witness

The author supplies the example, in the program ("given `{"a":1}` with
`--a 1`, print it unchanged"). Examples are intent, so they belong in the
only file the author owns; nothing is invented and deduce-or-fail holds.
Rejected: mint-invented witnesses — a reworded sentence leaves them
untouched. There is no reserved program syntax: a minted pattern
crystallizes the example line like any other, and a minted rule emits into
the reserved head below.

### Representation

No new file. A reserved emit-path head beside `artifact.<name>`:

    claim.<id>.run     string value; may hold ${artifact.<name>} refs
    claim.<id>.stdin   optional string
    claim.<id>.stdout  optional string
    claim.<id>.exit    optional integer, default 0

- `<id>` follows the artifact name grammar (literal text with
  `<self>`/`<capture>` occurrences, `nameTokens` machinery reused), so a
  family of witness lines fans out to one claim per match.
- An unknown section under `claim.<id>` is an engine defect, loud
  (mirrors the `artifactEntries` section check).
- The closed value grammar is unchanged: a claim cannot compute.
- `OptionType` reserves the `claim` root beside `artifact`, so
  admissibility never grounds a claim path against the target schema.
- Comparison is EXACT: byte-equal, with exactly one trailing newline
  stripped from the observed stdout before comparing (a program that
  prints a line ends it in `\n`; the author states the line). Containment
  stays banned — it is what let `"200\n404"` become `"200n404"` unseen.
  No `stderr` field until a program needs one.

### Projection and Place

New projection beside `realizeArtifactFile`:

    -- Kernel/Claim.hs (new)
    data ClaimPlace = PlaceDerivation | PlaceMachine
    data Claim = Claim
      { clId :: Text, clRun :: Value, clStdin :: Maybe Text
      , clStdout :: Maybe Text, clExit :: Int, clPlace :: ClaimPlace }

    -- Kernel/Realize.hs
    realizeClaims :: ... -> Base -> Either RealizeError [Claim]

`Realization` (Run.hs) carries `rlClaims :: [Claim]`. Place is derived,
never declared: a `run` whose refs are only `${artifact.*}` (plus literals)
is `PlaceDerivation` — a plain derivation in the nix sandbox, fast, no KVM,
no network. Anything else (including `${pkgs.*}`) is `PlaceMachine` — a
`nixosTest` that boots the realized module and runs the command inside the
machine. The kernel already tracks artifact refs structurally
(`valueArtifactNames`), so place needs no new syntax and a CLI program
never pays for a boot.

### Entry Point

- `compile` renders `claims.nix` beside `artifact.nix` in the compiled
  directory (kernel renders the text; deterministic from the ground base):
  one attribute per claim. A `PlaceDerivation` claim is a `runCommand`
  that pipes `stdin`, captures stdout and exit, applies the exact
  comparison, and fails naming claim id, expected and observed. A
  `PlaceMachine` claim is a `pkgs.nixosTest` importing `default.nix`,
  its testScript running the command via the machine and applying the
  same comparison.
- The flake gains a `claims` output (an aggregate derivation depending on
  every claim), and `compile` prints the rung:
  `nix build path:<dir>#claims`. Only for programs that state claims; a
  claim-free program's output is byte-identical to today.
- `lips check` builds that rung. A claim that cannot run — a machine claim
  on a host without `/dev/kvm` — is a LOUD failure naming the remedy,
  never a skip: "not verified" must never render as verified.

### `.expect` Pinning

A claim slot is a ground-base subject, exactly like an artifact slot.
`isArtifactExpect` generalizes to both reserved roots (`artifact`,
`claim`); judgment stays `checkArtifactValues` against the ground base (no
nix, no eval). `uncheckableExpects` (Minting) admits claim paths the same
way it admits artifact paths. So a re-mint that drops an authored example
trips the existing `.expect` gate — no new gate.

### Obligation at Generate

- An engine that bakes source (the mint ships source files) is refused
  unless at least one claim is realized across the corpus. Pure-config
  programs are unaffected. The refusal names the discipline: the author
  states an example; the mint crystallizes it.
- A `PlaceMachine` claim minted for a non-NixOS target is refused at the
  gate (there is no machine to boot in that world).
- The mint gate RUNS every `PlaceDerivation` claim (reusing the
  `artifactGate` runner: a nix build in the sandbox); an engine whose
  claims fail is refused before anything is written. A `PlaceMachine`
  claim at mint requires KVM; absent KVM the mint refuses loudly rather
  than admitting an unverified engine.
- Advisory half (the TODO 2b shape — a word spent into an option that
  means something else): claims stay ADVISORY there. LSP diagnostic beside
  `diagInert`: in a language that bakes source, when the program realizes
  zero claims, each concept-only line gets a warning ("nothing observes
  this sentence"). Stated plainly, not sold as a universal gate.
- Mint preamble (`assets/mint/`): a claims section — the head's grammar,
  the exact-comparison rule, the obligation, the world limit. Data, not
  kernel branches.

### Conformance Cases (TODO 1d)

Spec.hs: claim parsing (sections, defaults, unknown-section refusal);
place derivation (artifact-only → derivation; pkgs ref or bare command →
machine); quote-preserving fill (a JSON witness value like `{"a":1}`
survives crystallize → rule fill → `realizeClaims` byte-exact); the
obligation refusal (baked source, zero claims); exact-comparison semantics
(trailing-newline rule) on the pure comparison function.

## Milestone 3 — Re-Mint the Four

`logscan`, `board`, `habit`, `hello.http.lips`: add authored witness lines
to each program, `lips generate --renew`, verify each engine emits claims,
`.expect` pins them, and `just ci` exercises the derivation claims (the
`hello.http` machine claim needs KVM, same as the existing VM checks).
Update DESIGN.md §13 (milestone ledger) and TODO.md as items land.

Budget note (from TODO item 3's datapoint): these are artifact-bearing
languages; mint with opus.

## Reserved, Not Built (TODO 1c)

For cross-program composition, reserved now because renaming a claim or
artifact subject later is a re-blessing event for every committed engine:
the emit head `export.*` (a program's public surface) and a third value
ref beside `${pkgs...}`/`${artifact...}`, namely
`${program.<instance>.<path>}`, resolved at compile from a sibling's
committed engine BY NAME. No implementation in this plan.

## Invariants Respected

- compile/check never call a model; claims run under stock nix.
- The kernel stays domain-blind: `claim` is a closed grammar head the
  engine fills; place is derived structurally; no domain word enters the
  kernel.
- Illegal states unrepresentable: claims live in the closed value grammar;
  computation has no constructor.
- Failures are loud and name the remedy; an unrunnable claim never skips.
- Regeneration stays gated: claim slots enter `.expect`.

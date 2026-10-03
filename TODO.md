# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

-1. **The growth mint: an author's feedback cycle** (design settled 2026-08-20,
   `docs/superpowers/specs/2026-08-20-mint-feedback-cycle-design.md`; nothing
   built). Adding one sentence shape to a working language costs a full re-mint
   (4-6 minutes, opus, the whole engine re-emitted), which is the one act that
   leaves the zero-AI edit loop and the act an author hits every time a language
   grows. ALL THREE ERRANDS LANDED 2026-08-20 (DESIGN §13: "A mint now says what
   it cost", "The growth mint", "compile --watch"): a mint records what it cost,
   generate patches a committed engine by id (4.4x less wall time and 7.1x fewer
   output tokens than a fresh mint of a SMALLER program), and the edit loop
   recompiles on save with `g` to grow the language. This item stays only for
   what is NOT done: nothing measures the patch path on a language with several
   worlds or with artifacts, and the model default was left alone deliberately
   (whether a patch is sonnet-able is now a cheap experiment against the timing
   file rather than an assumption).

   Superseded description kept for the reader who wants what was decided: (2)
   generate inherits the committed engine and takes a PATCH
   keyed by id (new id adds, known id replaces, unmentioned id inherited),
   default inherit with `--fresh` to rewrite, `basis:` recorded as a sealed
   input -- sound because the gates, not the rewrite, are what guard an engine.

0. **The patched retry is measured, on one run per side** (2026-09-10; the item
   that stood here is CLOSED -- DESIGN §13, "A retry restates a line, not an
   engine"). Rerunning the thinking experiment's medium arm against the new
   binary took a growth patch of libero's season table from 295s / 3 submissions
   / 22,061 output tokens / $0.94 to 269s / 4 / 15,856 / $0.77, accepted and
   `check` green, with submissions 2-4 beginning at `a1`, `r10` and `d1` instead
   of `p7`. What is still open is only the sample: one run per side, and output
   is mostly thinking, so the 28 percent is a datapoint, not a mean. Repeat the
   arm the next time a mint runs for another reason rather than as its own
   errand, and only then decide whether a patch is sonnet-able.

1. **Three open questions about claims** (opened 2026-07-31 by the
   meaning-dimension work; the mechanism and the corpus landed, DESIGN §13).

   a. Not decided: whether a machine claim should RETRY its observation until it
      holds, bounded. A booted system converges (a unit may not be listening the
      instant `multi-user.target` is reached), so a single shot can be flaky, and
      flaky verification is worse than none. Retry-until-deadline is domain-blind
      and would be uniform for every claim. Deferred until a real claim actually
      flakes -- the one machine claim exercised so far did not.
   b. Watch the narrowing the first `http` claims mint showed (2026-07-31): told
      to prefer an observable over the program's own binary, the mint added a
      `-check` mode to its source and observed the handler in the sandbox instead
      of the booted service, so the port and unit wiring stayed unobserved.
      Honest but narrower than it reads. That engine is gone (the 2026-08-06
      re-mint bakes no source), so this is a warning, not a live defect: if it
      recurs, the preamble should say when the booted machine is the only
      faithful place.
   c. A witness sentence listing N items freezes its pattern at that arity: both
      models minting `habit` filed the same gap (`fixed-arity-witness`,
      `witness-entry-count`), since the grammar repeats a sub-match only in a
      BULLETED block, never inside one prose line. The engine is honest (a
      program with two or four entries simply fails to crystallize, loud), so
      this is a completeness question, not a soundness one.
      CLOSED FOR THE PATTERN 2026-09-19 (DESIGN §13 "A list within one
      sentence"): a list hole `<p.list:,|or>` cuts a run into items on the
      engine's own separators and repeats every emit that mentions it, and an
      item pattern `p10.each.p9.e` reads ONE item when that item binds several
      holes. `examples/policy` re-minted from 30 patterns to 8; `examples/habit`
      re-minted onto both, and its witness now reads at any entry count (a
      two-entry and a five-entry program each pass their clause claim, which
      runs the built tool). `board` and `logscan` were re-minted 2026-09-20
      (DESIGN §13, "A patch mint may answer by changing nothing") and BOTH
      REFUSED to move, filing the output half as the blocker instead: `board`'s
      gap `fixed-example-arity` argues that freeing the input side while the
      expected output stays pinned is worse than the present symmetry, and
      `logscan` tried `<in.list:,|and>` in its first submission and went back to
      the fixed form in the one it submitted. So the witness arity is one errand
      now, not two, and it is KERNEL work: until the expected output aggregates,
      no mint takes the list hole for a witness.
      THE OUTPUT HALF CLOSED 2026-09-26 (DESIGN §13, "An expected output that
      aggregates"): `claim.<id>.equals-lines` is the dual of `feed`, and `board`
      re-minted onto it, its witness now free of both item counts. Still open
      in 1c: `habit`, `function` and `logscan` each keep a one-expression
      `equals` witness. Let each one's next re-mint move it if its example has
      printed lines that grow; do not re-mint them for this alone. A command
      claim's `stdout` is still ONE string (YAGNI: no program has asked).
   d. CLOSED 2026-09-20 (DESIGN §13, "The two expect-gate holes `logscan`
      filed close"): `<self>` now binds inside `expandExpects`, and a template
      carrying `#<` fills through `fillSexp`, as the rule does. Still open:
      `logscan.expect` pins neither value yet. Let its next re-mint add them,
      because hand-editing a minted contract breaks invariant 4.

2. **The schema pin is recorded, but nothing relates it to the nixpkgs the
   module is evaluated with** (open half of the schema-pin work, DESIGN §13
   "Option-schema grounding"; the mechanism landed cbd3f1f). Three separate
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

      One corpus instance, 2026-09-18: `examples/nono.world` grounds against
      nono 0.68.0 (the pinned nixpkgs) while the compiled directory's ambient
      `flake:nixpkgs` resolved to nono 0.74.0, so the schema that admitted the
      rules and the validator that judged the render were two different
      versions of the same tool. Both accepted this profile, and nothing
      compared them.

   b. `--schema` IS PER INVOCATION AND REMEMBERED NOWHERE. A caller on a stable
      channel must pass it on every mint of every language, and forgetting it
      silently reverts to the baked pin (the record shows which, after the fact,
      and generate now prints both pins when they differ). Deliberate for now --
      a per-directory default would be the lock file this design rejected, since
      the engine and its pin already travel together in `.generation`. Revisit
      only with a real user who mints often enough to be hurt.

   c. `LIPS_OPTIONS_JSON` PINS BY CONTENT, NOT BY ORIGIN. A supplied document is
      recorded as `options-json:<hash>` of its bytes, which is checkable but
      says nothing about which nixpkgs produced it. Fine for the suite's offline
      fixture (its whole point is to be nixpkgs-free); a real caller who builds
      the document themselves loses the ref. Candidate: accept a ref alongside
      the path, or nothing at all -- prefer `--schema` for that caller.

3. **Plurality is not a gate** (the open half of the plurality work, DESIGN §13
   "Plurality is what makes a baked-source hole mean anything"; every committed
   program has been enriched, so no candidate is left in the corpus).

   With ONE instance a hole and a constant are indistinguishable, so a mint
   folds the program's words into baked source and the engine then accepts
   sentences it cannot honour. That is statically visible and domain-blind -- a
   baked-source hole binding one distinct value across the whole program -- so it
   could join `diagInert` as an LSP diagnostic ("this hole is never contrasted,
   so nothing holds the source to it").

   Deliberately deferred: the remedy is an author writing a richer program, an
   advisory report may be enough, and the claims falsify the same defect by
   observation rather than by counting.
   THE EXPERIMENT RAN 2026-10-02 (DESIGN §13, "A singleton call stays a hole";
   `experiments/plurality-function/`) and argues AGAINST the counting
   diagnostic. One call did not demote the call to a constant. The defect did
   appear, on the control's never-contrasted type word (`x: Int` compiles and
   prints), but it shares its syntactic position with three harmless singletons.
   Across the corpus and both mints, counting flags 14 clause-landing holes to
   find 1 defect, and no domain-blind exemption narrows that. Left open: (a)
   whether a word whose only landing is a dead clause branch is worth a
   reachability check (a direction, not a proposal); (b) the remedy plurality
   points at (two declarations of different types) is not expressible until
   7c's `identifier-from-program` closes.

4. **The contract set reaches stdin-to-stdout text tools and nothing else**
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

5. **Delete the staged-source machinery** (NEXT ERRAND; the gate it served
   landed 2026-10-03, DESIGN §13 "The no-blob doctrine is gated, and glue is
   marked"). Model-written source is refused at generate, at the draft door
   and at check, so everything that staged, filled or judged a source tree is
   unreachable: `Lips.Stage` fills and `stagedSizes`, `Lips.Gate.sourceSpecGate`,
   `gStaged`, `claimlessBakedSource`, `unnamedSources`, the committed-source
   half of `sharedFileViolations`, the `artifact.<n>.fill.*` emit and its
   prompt remnants. Keep the `source` block PARSER, so the refusal can name the
   files. Delete with tests, one concern per commit.

   Still open from the doctrine, none blocking:
   a. Code inside an OPTION string is measured (`N mint-written words inside
      option strings`), never marked or gated. Telling computation from prose
      there needs shape guessing, so this is a limit by decision. `website`
      carries 57 such words, pinned only by a claim asserting HTTP 200 on `/`;
      the `website-vm` flake check (this repo's CI, not a gate a user's engine
      brings) asks `/data/button/2/label` for the word `leeren`. Its gap
      `browser-behaviour` (no contract reaches a document, an element or a
      click) stays a gap, not a design item, until a program makes the cost
      concrete. `http`'s 19 nginx words are watched the same way by `nginx-vm`.
   b. The committed `greet` carries unpinned MINT glue (`echo` in two
      `args.text`, no claim). `check` reports it as `glue (mint, unpinned)`;
      its next re-mint must claim it. Do not re-mint it for this alone.
   c. A word is a whitespace token, so `echo \"<value>\"` counts as three mint
      words. Refine only if a count misleads someone.
   d. Watch the loophole the `function` re-mint found before clause sequencing
      existed: a mint that lands the program's words only in CLAIMS and mints
      behaviour that ignores them. The guard, if it recurs, is the twin of
      `diagInert`: a word whose only landing is a claim is inert.

6. **A world's gate pins only nixpkgs** (the open half of the render gate,
   which landed 2026-10-03: DESIGN §13, "A world's own gate runs at mint time").
   `worldGate` overrides the compiled flake's `nixpkgs` input with the locked
   pin and nothing else, so a world whose flake carries another input (kubenix's
   `github:hall/kubenix`, terranix's) would build its gate against whatever that
   URL resolves to today. That is why kubenix and terranix declare no gate,
   although both render cheaply and kubenix refuses an unknown Kubernetes field
   at evaluation. The missing piece is a relation between a world's flake inputs
   and the pins lips bakes (`schema-pin:` names an env var, the `inputs` slot
   names an input, and nothing says they are the same flake). Decide that
   relation before declaring either gate. nixos has no gate candidate cheaper
   than a system build, so it declares none.

7. **Remaining known gaps on the clause axis** (none blocking).

   a. **`app/Main.hs` grew back to 1761 lines** (990 after the 2026-08-05
      extraction, 2135 before it; the worlds arc and the mint-feedback work
      added the difference, and the compiled-directory writer moved out to
      `Lips.Stage.writeCompiled` on 2026-10-03, from 1775). Four
      seams moved out then: `Lips.Report` (every message it prints, pure),
      `Lips.Schema` (flakeref locking, option JSON, the `options` verb, the
      admissibility gate), `Lips.Stage` (staging trees into a temp dir) and
      `Lips.Gate` (every gate judging one realization against the outside).
      The next coherent seam is now visible: reading and writing a language
      folder (`readRecordedWorld`, `writeWorld`, the joint-vs-own record
      precedence and its cleanup) is one concern with one truth
      (`Lips.Identity` paths) spread through verb code. Extract when it is
      touched next, not as an errand.
   b. **Several sites at once is refused, not built** (plan Task 10 landed as
      shape only). No committed example needs a second place; the refusal makes
      growing to several a kernel change nobody can stumble into.
   c. **A program value cannot become a clause's own identifier** (filed by the
      `function` re-mint as `identifier-from-program`, 2026-08-06). A hole
      outside a Scheme string must be typed (int/float/bool), and a capture
      fills an emit PATH but is not substituted into an s-expression, so
      `function println_to_stdout(x: String)` realizes the fixed clause
      `(define (print-line line) ...)` and the declared name reaches only
      `site.<self>.command`. Renaming the parameter costs a fresh mint. Honest
      today (the name still governs the installed command, so no word is
      inert), and the fix is not obvious: a program word becoming a defined
      NAME has to survive the gate's grounding walk, which resolves names
      before any program is seen. Revisit if a program wants two differently
      named functions.

8. **`generate` without `-t` should mint into the worlds the language already
   holds** (filed 2026-10-03 by the render-gate re-mint, DESIGN §13 "A world's
   own gate runs at mint time"; nothing built). `Lips.Cli.defaultTargetName` is
   `nixos` whatever the language folder holds, so re-minting a language
   committed only in `nono` without `-t nono` silently mints and writes a nixos
   world beside it. It happened once and cost $0.29 (72s, opus-5) before the
   stray `nixos/` folder was deleted. Candidate: with no `-t`, take the worlds
   `Lips.Language.mintedWorlds` finds for the language, and fall back to `nixos`
   only for a language with no world yet. Adding a world stays an explicit `-t`.
   Open before building: whether a no-`-t` run over a language holding SEVERAL
   worlds mints all of them, which is a full joint re-mint and the expensive
   case, or refuses and asks for `-t`.

## Backlog (larger / deferred by design)

- **Defects no gate can catch** (the residue of the CLI-tool work; see DESIGN
  §13 for what landed getting there). Accepted, with no remedy: recorded so a
  later session does not rediscover them as news.

  a. **Silent concept demotion -- two cases still open** (`diagInert`,
     `droppedValues` and `decorativeValues` cover the rest; DESIGN §13):
     (i) a compiled artifact records no dependency on the program lines its
     baked source came from. PARTLY CLOSED: a claim now holds the built source
     to the author's stated observable, so an edit that changes what the program
     DOES is caught by running it. An edit that changes a specification sentence
     without changing any observable is caught only where that sentence is a
     concept (the source-spec gate); a value edit that the source hard-codes
     independently of its fill remains invisible to both, and no static gate can
     see it.
     (ii) STRUCTURE is enforced by nothing. Doctrine (DESIGN §13, "Repeating
     source") puts the algorithm, the format and the protocol in baked source,
     so a behavior sentence is a specification for the mint and correctly not a
     decision. Reword a behaviour sentence without re-minting and every gate
     stays green (the V6 source-specification gate catches DELETION only). No
     trace can fix this: the words never appear in the code. DECIDED: the reword
     is caught by source-line provenance (i); claims cannot catch it, since an
     example written for the old wording still passes.
     Related, and cheaper where it applies: the plurality item. A singleton
     behaviour sentence gives the mint no reason to build the dispatch a claim
     would then verify, so enriching the program removes the defect where a
     claim would only have detected it.

  b. **An option's own semantics can make an honest engine wrong.** postgres's
     re-mint emits `ensureUsers = [ { name = "app"; ensureDBOwnership = true;
     } ]`, but NixOS grants ownership of the database that shares the USER's
     name, so a program naming a user and a database differently would
     realize a silently wrong config. The words are spent (the dropped-value
     guard is satisfied), so lips sees nothing wrong, and the kernel cannot
     know option semantics either. DECIDED (OBLIGATION): a system claim
     falsifies both shapes when the author states one (`systemctl is-active
     api` fails, since nginx runs under the unit `nginx`), so the remedy exists
     but stays advisory, plus an LSP diagnostic. No static remedy: teaching the
     target layer what each option MEANS is an open list the kernel would have
     to enumerate, which the doctrine forbids.
     Second instance (2026-07-30, `examples/web` re-mint): the program line
     "run it as a systemd service named api" is spent into
     `services.nginx.virtualHosts.api.serverName`, but nginx runs under the
     unit `nginx` and `serverName` is a HOSTNAME, so the sentence is honored by
     an option that means something else. Every gate is green. Same shape as
     postgres, same absent remedy.

- **Demand duplication across worlds** (accepted 2026-08-09). Two worlds needing
  the same fact write the same demand twice, and the diagnosis prints the open
  question once per world. A shared demand would break the rule that a line's
  subject prefix decides which file it lives in. Left until it costs more than
  that rule.

- **Reply size at many worlds** (accepted 2026-08-09). One call answers with the
  grammar plus one rule set, one contract and one report per world, which will
  strain output limits at four or five. The staged path already exists: mint two
  now, add the third later against a frozen language level. Measure before
  building anything.

- **Grammar changes cost one full re-mint of every world** (accepted
  2026-08-11). `grammarIsFrozen` refuses a pattern change unless every
  committed world is in the same run, so a one-pattern tweak on a language
  with N worlds is one call carrying N schemas and rewriting N rule sets. The
  invariant is right (the shared contract must be authored by a party seeing
  all its parties) and at two worlds the cost is invisible; at four or five the
  pressure will be for a cheaper path (re-lowering unchanged worlds
  mechanically when the appended pattern provably reaches none of them).
  Deliberately unbuilt: no committed language holds more than two worlds, and
  the remedy already has one honest shape (name every world, a `-t` each).
  Measure before building anything -- same trigger as reply size above.

- **A record lives in two places** (accepted 2026-08-11). A single-world mint
  writes `.generation` in the world's folder; a joint mint writes ONE record at
  the language level and removes the per-world pair (`writeWorld`), and
  `readRecordedWorld` prefers the world's own record over the joint one. Two
  shapes for one concept, held by a documented precedence and a cleanup step.
  The cause is structural: records are SEALED, so committed single-world
  examples cannot migrate to a one-shape layout without re-minting them.
  Collapse to "always at language level, listing the worlds it covers, even
  when that is one" only if a corpus-wide re-mint happens for some other
  reason; never as its own errand.

- **Nothing records WHICH lips wrote a language folder, or what format its
  engine files are in** (raised 2026-08-09, immediately after worlds became
  data; design NOT settled).

  What is pinned today: `.generation` records the model, the thinking level, the
  confidence threshold, the locked schema ref, the world name and the world
  file's content hash, and (since worlds became data) `format: 1` for the
  record's own shape; `<world>.world` carries its own `format:`. What is pinned
  nowhere: the lips that ran, and the format of the engine files themselves
  (`.grammar`, `.rules`, `.expect`).

  Why that is the interesting hole. Invariant 6 pins every INPUT of a
  generation event, and the reader is not one of them. The kernel's physics --
  merge, refine, realize, the value grammar, the capture grammar -- decide what
  a committed engine MEANS, so a lips whose physics moved reads the same bytes
  differently, with every gate green and every hash still matching, because
  nothing in the repository names the interpreter. Every other input is
  recorded precisely because leaving one out lets something steer the result
  unaccounted for; this is the last one, and it is the one lips itself controls.

  Constraint that shapes any answer: a record is SEALED (its bytes hash to the
  id every minted line is stamped with), so this cannot be back-filled into
  committed records. Whatever lands is written by new mints only, and old
  folders read as "a lips that did not say" -- exactly the format-0 rule the
  world work already established.

  Open, in the order they decide each other:
  (i) WHERE. A line in `.generation` is free (it is already the receipt of the
      event, and a multi-world language then honestly carries one answer per
      world, since its worlds may well have been minted by different lips
      versions). A separate `<language>/.lips-version` file is more visible but
      is a second place to keep true. A header in every machine-written file is
      the most robust and the most repetition.
  (ii) WHAT a version IS. lips has no release number; the honest identifier is
      the flake revision of the lips that ran, which the packaged binary can
      bake exactly as it bakes the four `LIPS_*_FLAKE` pins. A dirty tree has
      no revision, and the choice there is real: refuse to mint (pure, and
      hostile to development) or record `dirty` (honest about being unpinnable).
  (iii) WHAT LIPS DOES with a mismatch. Refusing on any difference makes every
      upgrade a corpus-wide re-mint, which is absurd, so the version is
      provenance and nothing more. The CHECKABLE half is the format number: a
      file declaring a newer format must refuse naming the remedy, which is the
      rule `Lips.World.parseWorld` already implements ("this file declares
      format N; this lips reads M -> upgrade lips"). Copy it rather than invent
      a second policy.
  (iv) WHETHER the engine files gain a `format:` header at all. They are
      decision lists parsed line by line and `readLang` already skips `#`
      comments, so a header line is cheap; the question is whether a format
      number that nothing has ever bumped earns its place, or whether the first
      real format change should introduce it (and then cannot, since old files
      carry no header -- which is the same absence-is-format-0 rule again, so
      the answer is probably yes, add it now).

- **A fill-the-holes UI (`lips ui`): the form derived from the engine**
  (raised 2026-08-09; design NOT settled, this entry is the knowledge gathered
  so the next session starts warm). Instead of writing the `.lips` file, you
  fill the holes in a browser and compile.

  Why it is on-thesis rather than a gadget: the form is DERIVED from `.lang`
  data (patterns give the sentence skeletons and their holes, demands give the
  question text), so a language nobody foresaw gets a UI with no per-language
  code. That is the kernel-knows-nothing test one level up, and the LSP already
  passes it the same way.

  Settled in the raising session:
  1. A LOCAL authoring tool on localhost, kernel running natively, nix
     reachable. Not a public WASM playground (that was the alternative, and it
     would lose the contract check and every build).
  2. FILL-ONLY. The UI can express only sentences the language already reads,
     so it structurally cannot produce the unreadable line that sends an author
     to `generate`. Accepted, not fixed: growing a language stays a terminal
     act, and the UI never mints.
  3. QUESTIONNAIRE-FIRST. The demands are the main view (their question text
     was written for exactly this), the pattern rows are the detail behind
     them, and the live `.lips` text sits underneath, because that file stays
     the artifact the human owns.
  4. PANES: live `.decisions` ("did it understand me?") and the live realized
     `default.nix`, both pure and instant, plus buttons that shell out to the
     real `lips compile` / `lips check` and stream their output.

  Open, in rough dependency order: how the screen is reached (one program named
  on the command line, mirroring `lips compile <program>`, versus `lips ui` in a
  directory with a list and a "new instance of this language" button -- the
  latter turns the no-AI reuse promise into a button, at the cost of a
  file-listing concept the CLI does not otherwise have); the save model (browser
  buffer plus explicit save, versus write-through on every keystroke); how an
  ambiguous doorway is shown when two patterns could answer one question; how
  much of `diagnose` reaches the rows (inert, restated, unfit, decorative); and
  the serving stack.

  Feasibility already established, so nobody re-derives it:
  - `Lips.Lsp.Derive` is the pure core that already produces the material:
    `completionItems` renders every pattern as a sentence form with its holes
    and their types (`Engine.Typing.wordTypes`), `diagsOf` and `hoverAt` give
    the per-line verdict and what a line becomes. The UI is a second frontend
    over existing physics, not new physics.
  - The doorway (which sentence answers this question, in which hole) is a pure
    function over engine data: a `DemandSpec` carries `dsSubject`, a
    `Pattern`'s `PatEmit` carries the subject it emits
    (`Kernel/Lang/Pattern.hs`, `Kernel/Engine/Data.hs`), and `matchSubject`
    handles capture-bearing subjects. The relation is not 1:1 -- `backup`'s
    `p1` feeds `source`, `dest` and `schedule` from one line -- which is why
    the PATTERN must own the row and the demand only points at it.
  - Pre-filling from an existing program is `classifyLines`
    (`Kernel/Lang/Crystallize.hs`), the same matcher `diagnose` runs, so the
    captured values land in the inputs and the UI cannot disagree with the CLI.
  - The live panes need no nix: crystallize and realize are pure, and only the
    contract check and builds reach for nix (which is what `--no-contract`
    already exists for).
  - No web dependency exists today. `flake.nix` gives ghc exactly hspec,
    QuickCheck, aeson, optparse-applicative and file-embed, and the LSP is
    hand-rolled over stdio (`Lips/Lsp/Server.hs`, 340 lines). So the stack is a
    real complexity decision: warp/wai as a new dependency versus a hand-rolled
    localhost HTTP loop, and one embedded HTML file with vanilla JS (file-embed
    is already in use) versus any JS toolchain. No npm.

  The risk to weigh before building any of it: a GUI is a second authoring
  surface for an artifact whose whole point is being small plain text a human
  owns. It earns its keep only while the form stays fully derived (zero
  per-language code) and the `.lips` file stays visibly the truth; otherwise it
  is the complexity daemon with a nicer font.

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
  lips can reach by name rather than invent. Under the GitOps assumption (git
  is the source of truth; a reconciler performs push/apply from what is
  merged) the cross-world value is DERIVABLE at compile, not just stated:
  a content-addressed image tag from the artifact's own Nix output hash makes
  the export true by construction, and eventual consistency (pull retry until
  the push lands) is the reconciler's semantics, not lips'. See
  `docs/superpowers/specs/2026-08-07-multi-world-builds-design.md`. Dual of the existing
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
  not "invent a way to record a schema source" -- and the source itself is now
  data, kubenix.world's `schema` slot, so taking CRDs in is an edit to a world
  file (yours, if you copy it) rather than to lips.
  (ii) CONVENTION HAS NO WORLD-LEVEL CHANNEL. Label keys, naming, namespace
  policy, resource limits are mechanism taste -- exactly what
  `<language>.direction` carries -- but nothing today states a direction shared
  by every language minted into one world. Candidate: a per-world direction
  file beside the per-program one, entering the generation record the same way,
  so a house convention is stated once instead of re-typed per language. Worlds
  are data now, so the cheap version already exists: copy a world file, edit its
  `preamble` slot, and the copy is pinned in the record like any other -- what is
  missing is only the shared-direction channel that avoids forking a world for
  taste alone.

- **terranix grounding is path-blind below the top level.** Live as of the
  terranix target (DESIGN §13): terranix's core options (`resource`, `data`,
  `provider`, `output`) are one free-form "magic merge" valueType, so lips
  confirms the top-level namespace (`resourse` is refused) and nothing under it.
  A misspelled resource type or field reaches `config.tf.json` unchallenged and
  fails at `tofu plan`, not at generate. Two things soften it today, both
  shipped: the mint preamble states the limit and tells the mint to refuse rather
  than guess a field, and a lookup inside a free-form region answers `Freeform`,
  saying in words that the name was not checked. Where a richer source would plug
  in is now one place, in data: terranix.world's `schema` slot, whose only
  contract is that its output is the options JSON. The remedy is a different schema
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
  of one. WHAT A REFUSED ROUND COSTS, so the trade is priced: the `website` mint
  of 2026-08-20 paid $3.23 to discover a boot failure and learn nothing a
  machine could carry forward -- a human turned that finding into the direction
  file that made the next call work. The 2026-09-20 re-mint was accepted on its
  first attempt ($3.00), so the refusal rate is not yet high enough to price the
  loop against. Permanently rejected, do not revive: `lips dry-run` as a
  model-callable tool (a rehearsal verb is a second call site for the gate
  and can drift from the gate that commits).

- **Mint internet access** -- a second `registerTool` beside `query_options`,
  routing a question to a web search. Argument for: a recorded lookup is
  auditable evidence, the same move deduce-or-fail already makes for values.
  Argument for waiting: no mint has yet failed for want of a world fact. Add
  when a real mint fails for lack of a fact, not before.

- **Glue** -- the one deliberate incompleteness (computation inside the
  decision layer). Builder arguments are marked `Glue` and mint glue must be
  run by a claim (DESIGN §13); no property testing over glue exists. Blocks a
  *computed value*; building a program from model-written source is refused.

- **Dependency-fetching builders** (cargo/vendor hashes) -- untried. The
  proven path is no-dependency source (Go stdlib with `vendorHash = null`);
  fetching a real dependency graph at generate time is unexplored.

- **Naming foreign derivations (external artifact kinds).** Discussed
  2026-08-07, unresolved by design: no format chosen yet because there is no
  common artifact concept to enumerate -- a real application is human-written,
  lives in its own repo with its own flake, and lips should NAME its build
  rather than mint it (the same move as `${pkgs.nginx}`). Candidate shapes,
  none picked: a pinned flake-ref value form (`${flake:<pin>#<output>}`), an
  artifact whose `args.src` is a flake input, or wrapping the foreign build in
  a sibling lips program once `${program...}` exists. Constraint from the
  discussion: whatever lands must be externally defined and unenumerated, like
  worlds and builders -- the kernel learns one closed reference form, never a
  list of artifact kinds. Blocks any real application (the football-manager
  case) more than the world axis does, together with dependency-fetching
  builders above.

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

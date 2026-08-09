# TODO

Closed items are dropped from this file once they land; the record of what
closed and why lives in `DESIGN.md` §13 (the milestone ledger). This file
tracks only what is still open.

## Next up (priority order)

0. **A fact only one world needs** (opened 2026-08-09 by the first live joint
   mint; design sketched, not settled).

   One mint for many worlds is BUILT (DESIGN §13), and the neutrality problem it
   was built for is closed: one call decomposes a notation-divergent value
   because the same answer writes the rule that spends it. What the live run
   then exposed is the other half. `examples/nightly.timer.lips` states a
   command and a time; kubenix also needs a container image, and demanded one,
   correctly. But once the program states that image, NixOS has nothing to do
   with it, and a ground decision no rule of a world places makes that world
   report the program unportable. So a program cannot state a fact that only one
   of its worlds needs -- which is exactly what genuinely different worlds ask
   for.

   Sketch, in the shape the design already uses: the world's own rules DECLARE
   what they knowingly ignore, as data, with the reason.

       0.9 i1 @nixos ignore fact job.image "a machine runs the script directly, so there is no image"

   Then the kernel rule stands unchanged in spirit (every ground decision is
   placed OR explicitly ignored), nothing is silent, the review artifact says
   which world drops which word and why, and the knowledge stays in the engine
   rather than the kernel. It needs a closed grammar arm in `Lips.Kernel.Run`
   (an ignore set beside the rules and demands) and one item kind in the reply.

   Rejected while sketching: tolerating an unmapped decision when some other
   world places it (silent, and it removes the guarantee that every word reaches
   an output), and letting the program name the world a line is for (the program
   states intent, never deployment).

1. **Witnesses for the programs that cannot yet be observed** (opened 2026-07-31
   by the meaning-dimension work, DESIGN §13).

   Claims landed and three programs carry one (`logscan`, `board`, `habit`;
   `hello.http` shed its claim with its source on 2026-08-06). `website` bakes
   source and states no witness, which is no longer a blocker: measured
   2026-08-06, the mint deduces the observable from the program's own words
   (opus-5 minted `examples/function.lips` unmodified and deduced four claims;
   the `http` re-mint needed no witness sentence at all), and the refusal wording
   now says so.

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
      The bulleted block is NOT the answer, measured 2026-08-06: it aggregates
      into a Nix list, and only `claim.<id>.feed` and `.args` are Nix lists.
      `ccEquals` and `ccCall` are `parseSexp` of ONE assertion, and a command
      claim's `stdin`/`stdout` are single strings with embedded newlines (which
      is how `board` freezes at five input and three output lines). So a block
      fixes a witness's INPUT side and cannot reach its OUTPUT side.
      The `function` re-mint filed this independently as `per-line-expected-
      output`, adding a second reason one claim per statement is unusable: the
      claim adapters share their output list, so the second claim's `(emitted)`
      still holds the first claim's lines. It worked around both by carrying the
      stated lines in `claim.args` and asserting `(equal? (emitted) (arguments))`
      -- honest and exact, but a detour that reads as if the program consumed its
      argv. The candidate remedy is now named: an aggregating expected-output
      section, the dual of `feed`, so an author's example stops freezing its item
      count. Deferred until a third program wants it.

2. **CLI-tool physics -- the record behind item 1** (context: `board`, `habit`,
   `logscan` are committed, minted CLI engines; `examples/{http,postgres}`
   were re-minted honest. See DESIGN §13 for what landed getting there.)

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
      Related, and cheaper where it applies: item 5 (plurality). A singleton
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

3. **Which model to budget for a re-mint** (the record left over from the sweep
   that turned out to be unnecessary; see DESIGN §13, "Invariant 6 held all
   along"). Any re-mint (item 5's plurality edits, item 1a's witnesses) faces the
   same choice, so the datapoints are kept:

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

   The `http` re-mint (2026-08-06) adds one: opus-5, `--compat none`, one program
   edit, and the whole Go tree became nginx options in a single attempt.

   The old PRECONDITION here (a baked-source program needs a witness sentence
   before it can be re-minted) is void: the mint deduces the observable, and
   where the re-mint bakes no source it needs none (item 1).

4. **The schema pin is recorded, but nothing relates it to the nixpkgs the
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

5. **The corpus is minted from singleton programs, so its engines understand
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
   them empty; two contrasted mark characters), together with the feedability
   they needed, and `logscan` stopped baking source altogether when it was
   re-minted as clauses. `function` stopped baking source on 2026-08-06 with no
   program edit at all, once clause sequencing let its three calls compose into
   one entry point (DESIGN §13). Its plurality was already right, and the reverse
   experiment is still untried: cutting its three calls to one should demote the
   call to a constant.

   `http` was treated on 2026-08-06 and is the sharpest datapoint so far: three
   contrasted routes instead of one blanket response, and the mint dropped 62
   lines of Go for nginx locations (DESIGN §13). Plurality did not just harden a
   hole, it removed the reason to write source at all.

   No plurality candidate is left in the corpus. What still bakes source
   (`website` 220 lines, `habit` 78, `board` 40) is already plural, so those
   trees wait on the clause axis (item 6), not on a program edit.

   Not decided: whether to make it a GATE. A baked-source hole binding only one
   distinct value across the program is statically visible and domain-blind, so
   it could join `diagInert` as an LSP diagnostic ("this hole is never
   contrasted, so nothing holds the source to it"). Deliberately deferred: the
   remedy is an author writing a richer program, an advisory report may be
   enough, and item 1's claims falsify the same defect by observation rather
   than by counting. Revisit after the re-mints above supply more datapoints.

6. **The contract set reaches stdin-to-stdout text tools and nothing else**
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

7. **The no-blob doctrine, with its gate** (agreed 2026-08-04; its precondition
   landed 2026-08-04, when the mint began emitting clauses and `logscan` moved
   from "80 lines vouched by nothing" to 5 clauses and 0 unvouched assertions).

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
   gate refuses a new staged tree. Three committed programs still carry one
   (`website` 220 lines, `habit` 78, `board` 40; `function` shed its 21 and
   `http` its 62 on 2026-08-06), so a gate landing today would refuse the corpus
   it ships with: the trees move to clauses first, then the gate closes the door
   behind them.

   The `http` re-mint also showed the second grade in the open: with the Go tree
   gone, its route bodies became 19 mint-written words of nginx configuration
   inside option strings, each bounded by one program line, which is the
   admissible VALUE form. Nothing static can read them (an expect compares the
   option's string, not what nginx does with it), so the flake's `nginx-vm` boots
   the module and asks every route. A booted check is what MINT glue costs.

   Watch for the loophole the `function` re-mint found before clause sequencing
   existed: told that every word it reads must reach output, a mint satisfied it
   by landing the program's words in CLAIMS and minting behaviour that ignored
   them. A claim is an observation, not a realization. The guard, if this
   recurs, is the twin of `diagInert`: a word whose only landing is a claim is
   inert in the same sense and should be named.

8. **Remaining known gaps on the clause axis** (none blocking).

   a. **`app/Main.hs` is 990 lines** (2135 before 2026-08-05). Four seams moved
      out: `Lips.Report` (every message it prints, pure -- one voice per defect,
      readable without the control flow around it), `Lips.Schema` (locking a
      flakeref, building the option JSON, the `options` verb and the mint's
      admissibility gate), `Lips.Stage` (staging a language's trees into a temp
      dir, filling markers, writing the site) and `Lips.Gate` (every gate that
      judges one realization against something outside the module text).
      What is left is verb-level composition: which gates a verb runs, the mint
      round, and reading and writing a language folder. No further seam is
      obvious, so this stops being an item unless Main grows again.
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

## Backlog (larger / deferred by design)

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

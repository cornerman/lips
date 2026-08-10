# lips kernel (reference implementation)

The decision calculus of lips, as pure Haskell. This is the deterministic
core the design doc names the source of truth (spec v2, section 12.4); it
contains no LLM and no I/O. Only `generate` (not built here) needs a model.

## What Is Here

| Module | Spec | Role |
|---|---|---|
| `Lips.Kernel.Decision` | section 2 | the atom: `Decision`, `Subject`, `Strength`, `Provenance`, `Kind` |
| `Lips.Kernel.Base` | section 2.1-2.2 | decision base, merge by strength, conflict with both provenances |
| `Lips.Kernel.Refine` | section 2.4, 4 | refinement to fixpoint, orthogonality (`Overlap`), stamped provenance |
| `Lips.Kernel.Demand` | section 2.5 | demands and open questions, completeness |
| `Lips.Kernel.Reader` | section 2 | canonical stored form: `readBase`/`renderBase`, round-tripping diffable text |
| `Lips.Kernel.Surface` | section 2, 5 | the surface conventions every lips text layer shares: transport quoting, quote-aware separators (`splitOutsideQuotes`), trailing sentence punctuation |
| `Lips.Kernel.Realize` | section 10 | projects a ground base to a NixOS module (`realize`), refusing conflicts |
| `Lips.Kernel.Run` | section 5 | the deterministic pipeline; `RunError` is the spec's four run outcomes, `Realization` the module/artifacts/staged-paths projections of ONE run |
| `Lips.Kernel.Source` | ledger 13 | source fills: the `@marker@` grammar of an artifact's baked source and the two-way check that its markers and the engine's declared fills agree |
| `Lips.Kernel.Expect` | ledger 13 | the `.expect` behavioral contract: relational option-value assertions, parsed/rendered/judged (pure) |
| `Lips.Kernel.Lang.Pattern` | section 5 | a crystallization pattern: token template with holes -> one decision |
| `Lips.Kernel.Lang.Nest` | ledger 13 | blocks: the pattern-nesting relation, a line's scope in the block it sits in (ancestors' captures, `<n:index>`, `<k:key>`), and the checks that close it |
| `Lips.Kernel.Lang.Crystallize` | section 5 | loose text x language -> decision base, deterministically (three outcomes) |
| `Lips.Kernel.Lang.Store` | section 5 | the stored engine form: the whole engine as `meta` decisions, round-tripping. A language folder splits it by subject -- `<language>.grammar` (patterns) plus one world's `<language>.rules` -- and reads the two back as their concatenation |
| `Lips.Kernel.Engine.Data` | section 5 | the engine's back half as data: minted rules (`match ... => options`) and demands, interpreted generically |
| `Lips.Kernel.Engine.Value` | section 5 | the closed rhs value grammar (string/list/bool/int/float/path/null, attrsets, s-expressions; holes, typed holes and `${pkgs...}`/`${artifact...}` refs only) -- computation and injection unrepresentable |
| `Lips.Kernel.Hole` | ledger 13 | the type a hole coerces a program word into, shared by BOTH value grammars so `<value:int>` cannot come to mean two things |
| `Lips.Kernel.Sexp` | logic axis | the closed clause grammar: s-expressions parsed, rendered and hole-filled, never evaluated. A symbol is the only way a clause names anything, and no constructor turns a program word into code |
| `Lips.Kernel.Clause.Vocabulary` | logic axis | what grounds a name in a clause, as data: definers, binders, forms, base procedures, contracts. The kernel reads it and enumerates nothing |
| `Lips.Kernel.Clause.Gate` | logic axis | the subset gate: every free identifier must be grounded, every clause must name a program line, and `reachedContracts` reports the program's whole reach into the world |
| `Lips.Kernel.Clause.Catalogue` | logic axis | runtimes as data, and `coveringRuntime`: which runtime covers a program's contracts and stated properties, failing rather than guessing |
| `Lips.Kernel.Grounding` | logic axis | what vouches for each assertion, counted: schema, contracts, author, or nothing. Names the unvouched so a blob cannot grow unwatched |
| `Lips.Runtime` | logic axis | loads the shipped `assets/runtime/` data (Scheme vocabulary, guile adapters) and hands the kernel a `Vocabulary`, keeping the kernel a reader |
| `Lips.Site` | logic axis | what a compiled site holds, decided purely: which runtime covers the clauses, which adapters link, what to assemble, what is stale. The IO shell only writes what it returns |
| `Lips.Kernel.Engine.Aggregate` | ledger 13 | list aggregation: `Append` mode derived from the rule emits, and the assembly of N same-subject list decisions (a set by default, a list where the engine declares it) |
| `Lips.Kernel.Engine.Overlap` | ledger 13 | static orthogonality, both layers: critical pairs over rule left-hand sides (`ruleOverlaps`, `subjectsUnify`) and a product walk over token templates (`patternOverlaps`) |
| `Lips.Kernel.Engine.Reach` | ledger 13 | a program word the language reads and then discards (`droppedValues`) |
| `Lips.Kernel.Engine.Answerable` | ledger 13 | a demand no pattern can ever answer (`unanswerableDemands`) |
| `Lips.Kernel.Capture` | ledger 13 | the one capture/name grammar shared by rules, expects and demands (`matchSubject`, `nameParse`, `fillName`) |
| `Lips.Kernel.Lang.Diagnose` | ledger 13 | the authoring report: per-line outcome, open questions, inert lines, discarded words |
| `Lips.Kernel.OptionType` | ledger 13 | domain-blind option grounding over a typed `OptionSchema`, plus the schema lookup the mint's `query_options` tool asks |
| `Lips.Nix.Options` / `Lips.Nix.Flake` | ledger 13 | the `optionsJSON` shape every world's schema parses as, and the `flake.nix` assembled from a world's slots |
| `Lips.World` / `Lips.World.Builtin` / `Lips.World.Resolve` | ledger 13 | a world as DATA: the `<world>.world` format and its strict parser, the four lips ships (embedded), and how a name becomes one |
| `Lips.Identity` | ledger 13 | the only place that knows the file layout (`<instance>.<language>.lips` -> language folder, one folder per world, `out/`) |
| `Lips.Language` | ledger 13 | what holds ACROSS a language's worlds: which worlds it has (a subdirectory carrying this language's rules), whether the shared level is frozen, and that every fact a world ignores is placed by some world |
| `Lips.Cli` | ledger 13 | the whole CLI grammar as one `optparse-applicative` parser (verbs, flags, completion) |
| `Lips.Lsp.Derive` / `Lips.Lsp.Server` | ledger 13 | the language server: pure completion/diagnostics core, and its stdio JSON-RPC shell |
| `Lips.Generate.Harness` | section 5 | the `Confidence` unit the deduce-or-fail gate speaks in (the resampling harness was removed as speculative) |
| `Lips.Generate.PiJson` | section 5 | parsing pi's json event stream: the reply, the model used, and the tool transcript |
| `Lips.Generate.Record` | section 5 | the pinned generation record and its content id; every minted line is stamped `@gen:<id>`, and must name one of its language's records (one per world) |
| `Lips.Generate.Minting` | section 5 | the model-facing half of `generate`: system prompt (every world's preamble, each scoped) + whole-engine candidate parser, each item tagged with the world it is for (pure) |
| `Lips.Generate.Readme` | section 5 | the mint's `report` and `gap` blocks rendered as README.md, filed at the scope of the event (the language folder for a call covering several worlds, the world's folder for one minted alone) |

## The Loop

    lips generate examples/ingest.feed.lips   # AI step: mints feed/feed.grammar + feed/nixos/*, validates by a full run
    lips compile examples/ingest.feed.lips    # deterministic: crystallize -> refine -> realize -> module dir (no AI)
    lips check   examples/ingest.feed.lips    # deterministic: the committed .expect contract must hold (no AI)
    lips lsp                                  # the domain-blind language server (stdio)
    lips options services.restic              # read-only: option paths and types in the pinned schema (no AI)
    # (paths are relative to the repo root, where examples/ lives)

Every path is derived from the program name by `Lips.Identity`: a program
`<instance>.<language>.lips` keeps everything the machine writes in a
`<language>/` folder beside it: the shared `feed/feed.grammar`, one folder per
world it was minted into (`feed/nixos/feed.rules`, `feed/nixos/feed.expect`,
`feed/nixos/feed.generation`, `feed/nixos/nixos.world`) and `feed/artifacts/`,
with derived output under `feed/out/` (`out/ingest.decisions`, the compiled dir
`out/ingest/nixos/`). Running is
not a lips verb: `compile` prints the stock `nix` commands over the compiled
directory.

`generate` is the one step where a model runs (spec section 5). The model mints
a whole *engine* -- patterns (the language), rules (the
mechanisms, as `match <kind> <subject> => <option.path> "<rhs>" ; ...`, where
`<rhs>` is a value in a closed grammar, never a Nix expression), and
demands -- and it never states the meaning of the program. The kernel then
crystallizes the program with that engine, validates it by a full run, a
Nix parse (`nix-instantiate --parse`), and an option-schema check (every minted
rule must fill a NixOS option that exists in the pinned nixpkgs, with a
compatible value type, or the engine is rejected -- deduce-or-fail), and only
then writes the grammar and the world's rules, the
per-instance crystal witness `out/<instance>.decisions`, and a `.generation`
audit record. It
routes the model call through `pi` in json print mode, hermetic by explicit
subtraction (`pi -p -nbt -nc --no-extensions --no-skills --no-prompt-templates
--no-session --mode json --system-prompt <prompt> --thinking <level> -e
<mint-tools>`); lips bakes in no model, so by default `--model` is
omitted and pi's own configured default applies. A model is named with
`-m/--model` (there is no positional model argument). Either way lips reads the model pi actually used back
out of the json stream and records it in `.generation`, so provenance stays
concrete without a vendor model in the deliverable. No domain vocabulary is compiled in: the model invents
the subjects, and closure is checked (unmapped decision, unmet demand,
uncovered line, invalid Nix, or an unknown/mistyped NixOS option each rejects
the engine), not trusted. The option schema is domain-blind in the kernel
(`Lips.Kernel.OptionType`, a typed `OptionSchema`); the NixOS `optionsJSON`
shape and its type-string wording live in `Lips.Nix.Options`. `generate` builds
the schema lazily from the pinned nixpkgs baked into the packaged binary
(`LIPS_NIXPKGS_FLAKE`), announcing the one-time build; `compile`/`check`
never touch it. Two overrides, in order of explicitness: `--schema <flakeref>`
names another flake to build this world's schema from (a stable channel, a
company nixpkgs), and `LIPS_OPTIONS_JSON` supplies a prebuilt `options.json`,
which the suite uses for an offline fixture. Whichever is used, `generate`
resolves it once, before the model call, and writes it into `.generation` as a
`schema:` line: a flakeref as the locked url `nix flake metadata` reports, a
supplied document as `options-json:<hash>` of its bytes. So the grounding is an
input of the generation event like the model and the prompt, and it enters the
record's own id.

`compile` takes the loose program directly and crystallizes it with the
language's grammar, then lowers it through every world the language holds, with
no model. Edits that stay within the language (changing a value or
instance a hole binds) flow through unchanged; an edit that escapes the
language fails loud and names `generate` as the remedy.

## The AI Boundary (the inversion)

Only the model call inside `generate` is non-deterministic; everything else is
pure. The model delivers *grammar*, never *meaning*: it mints patterns, and the
kernel derives the program's decisions from them by deterministic template
matching. AI may invent grammar; only the kernel assigns meaning to the program
text. The boundary is explicit in the code:

- `Lips.Generate.Minting` holds the *pure* minting logic: the system prompt (a
  versioned artifact, spec section 5 layer 3) and the parser that turns the
  model's confidence-prefixed pattern lines into candidates. The prompt itself
  is not a Haskell string: the world-neutral body is markdown under
  `assets/mint/`, and each world's steering preamble is the `preamble` slot of
  its own `<world>.world` file (`assets/worlds/`, or a house world beside the
  program), both embedded at compile time with `file-embed`, so each reads and
  reviews like the document it is.
- `generate` refuses to write a language it is unsure of: any pattern below the
  confidence threshold (default 0.7, overridable with `--confidence <0..1>` and
  pinned into the generation record) aborts the write (deduce-or-fail). The minted
  language is then validated by crystallizing the actual program and running it
  end to end; nothing is written unless the whole loop succeeds.
- The model call itself lives in the CLI shell (`app/Main.hs`, `callPi`), which
  runs pi hermetically by explicit subtraction and loads exactly two tools,
  both in `assets/mint-tools.ts`: the `query_options` lookup, which shells back
  into the `lips options` verb, and `check_draft`, which shells into
  `lips check --draft` over the engine the model is about to answer with. The
  mint can therefore confirm an option name instead of recalling it, and learn
  which gate rejects its draft while it can still fix it, but cannot read a
  file, run a command, or judge its own engine: the deciding gate runs
  afterwards, in Haskell.
  Every lookup and its answer land in the `.generation` record, so nothing the
  model saw escapes `genId`.

The whole engine is data: patterns (front half) and rules + demands (back
half) are one flat list of decisions, split across the grammar and one world's
rules, and interpreted by generic kernel
executors (`Lips.Kernel.Engine.Data`). Nothing problem-specific is compiled into the
kernel; there is no hand-written engine anymore. Minted rules emit only ground
(`Meta`) decisions, so a minted engine terminates in one refinement pass by
construction (cascades stay a hand-written-`Rule` capability until a real
program needs them minted). An emit's `<value>` hole takes the matched
decision's assertion verbatim; `<value.N>` takes its Nth whitespace token --
kernel physics absorbed from the first live run, where the model otherwise
unpacked packed values with Nix `splitString` gymnastics.

`.decisions` is no longer a source artifact: it is the cached crystal, derived
from the loose text plus the grammar (so it is the same in every world), safe to
delete -- which is why it lives under
the language folder's self-ignoring `out/`. The only irrecoverable
artifact is the loose program itself.

The canonical form is one decision per line,
`id kind subject strength "assertion" [@file:line | <-ids via rule] [-- rationale]`,
with `#` comments and blank lines ignored. It is the on-disk, diffable
representation (text diff approximates set diff); it is not the loose
authoring text, which only `generate` turns into decisions.

`test/Spec.hs` is the seed conformance suite: every block cites the spec
invariant it pins.

`app/Main.hs` is the reference `lips` CLI. With a minted engine beside the
program, it crystallizes a loose program to a NixOS module with no AI (run from
the repo root, where the flake and `examples/` live):

    nix run . -- compile examples/ingest.feed.lips    # crystallize + realize -> module dir, no AI
    nix run . -- compile examples/ledger.backup.lips  # a second, non-feed domain

This reads the program, its language's grammar and every world's rules. An unmet demand, an escaping
line, or a missing language instead fails loud and names `generate` as the
remedy.

## Design Choices (answering spec section 11)

- **Subject** is an attribute path and serves as the merge key: decisions
  compete only when they share a subject.
- **Strength** is the total order `Default < Stated < Law` (the NixOS priority
  mechanism promoted to kernel physics). Cross-language strength is deferred.
- **Orthogonality by construction**: a decision matched by more than one rule
  is an `Overlap` error, so rewriting is a function and refinement is confluent
  for free.
- **Provenance by construction**: the refiner, not the rule author, stamps each
  derived decision with `Derived [parent] rule`.
- **Termination** is guarded by a step budget; a runaway rule fails loud as
  `Nonterminating`.

## Running the Suite

From the repo root (the flake lives there, not in `kernel/`):

    nix flake check          # compiles with -Wall and runs the suite (+ VM smoke)
    nix develop              # then: cd kernel && ghc -Wall -isrc -itest test/Spec.hs -o /tmp/spec && /tmp/spec

Offline (network-restricted) note: the flake pulls nixpkgs from GitHub. Where
that is blocked but a nixpkgs checkout is already in the store, build the same
compiler with
`nix-build -E 'with import <path-to-nixpkgs> {}; haskellPackages.ghcWithPackages (p:[p.hspec p.QuickCheck])'`
and invoke its `ghc` directly.

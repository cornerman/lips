# Composition Plumbing: What Is Left

Date: 2026-08-12. Design:
`docs/superpowers/decisions/2026-08-12-cross-program-composition.md` (read it
first; it holds the rejected alternatives and the reasons).

The kernel half of cross-program composition is built and merged. This file is
the handoff for the remaining plumbing, written so the work can resume with no
memory of the session that produced it.

## State: Built

- `Decision.Kind` has `Uses` (subject = language, assertion = instance).
  Parsing and rendering came free, since `kindTable` derives from the enum.
  Two instances named for one language conflict through the existing merge, with
  no composition-specific rule anywhere.
- `Run.runGround` drops a `Uses` decision instead of reporting it unmapped, the
  third sound way to reach no option (beside `Concept` and a world's declared
  ignore), and `Run.rlUses :: [(Text, Text)]` carries it on the realization.
- `Run.composeWith :: [Realization] -> Realization -> Realization` links imported
  cores ahead of the program's own. Only the core travels: a dependency lends
  behaviour, never its module.
- `Main.resolveImports` resolves each dependency to `<instance>.<language>.lips`
  (or the singleton `<language>.lips` when the instance IS the language), beside
  the importer, and dies naming the file it looked for when absent. It runs
  BEFORE the gates, so claims judge the site a run would link.
- `Engine.Gate.clausesNamespaced` refuses a clause a language did not name after
  itself (`clause.match-duel` for `.match`). Namespacing is done by the mint, and
  the kernel only checks, so emitting stays a serialization
  (`parse . render = id`).
- The runtime's entry takes a hole: `entry (<language>-main)` in
  `assets/runtime/guile/runtime`, filled by `Catalogue.entryFor` at site
  planning, so no name is reserved.
- `Language.exportedClauses :: EngineData -> [(Text, Maybe Int)]` reports what a
  language exports for another to call, arity read off each definition.
- Eight committed engines were migrated once by
  `nix/migrate-clause-namespace.py` and re-verified (`function`, `hello`,
  `logscan`, `website`, `board`, `habit`, and libero's `match`, `training`).

Suite: 875 examples, 0 failures, `-Wall` clean.
Fast loop: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`.

## State: Not Built

Only task 4 is left: libero's own two-language acceptance test, which costs two
mints. Tasks 1 to 3 landed on 2026-08-12 (`lips exports`, `query_language`, the
prompt), and the path was proven end to end offline with a hand-written
two-language fixture through the draft door, so what remains is libero's real
vocabulary rather than any kernel work.

## DONE Task 1: A CLI Verb for Exports

Add `lips exports -t <world> <language>`, printing one `name arity` pair per
line (`-` where arity is unknown), from `Language.exportedClauses` over the
engine loaded for that language and world.

- Parser and handler in `kernel/app/Main.hs`, beside the `options` command
  (`command "options"`, around line 156 for the parser).
- Load the engine with `loadLangOrDie` and resolve paths through
  `Lips.Identity` (`resolveLangDir`, `rulesPathIn`, `grammarPathIn`).
- Exports are per world, because rules are per world; refuse a world the
  language was not minted into, naming `mintedWorlds`.
- Human-facing too: `lips exports player` is how an author sees the vocabulary a
  dependency gives them.

Verify: `lips exports -t nixos match` in `libero/` lists the 32 `match-*`
clauses.

## DONE Task 2: The query_language Tool

Mirror `query_options` exactly; it is 60 lines in `assets/mint-tools.ts` and the
new tool is a thinner version of it.

- Tool name `query_language`, one parameter (the language name), plus `world`
  only if the mint writes several.
- `spawnSync(bin, ["exports", "--target", world, lang])`, returning stdout on
  success and stdout+stderr on failure, exactly as `query_options` does and for
  the reason its comment gives (progress lines corrupt a list a model counts).
- Answers need no new recording: `callPi`'s transcript already enters
  `.generation` and the generation hash.
- Deduce-or-fail: a language that does not resolve is an error result naming
  what was looked for, never an empty list, since an empty list reads as "that
  language exports nothing" and invites a local definition.

## DONE Task 3: Tell the Mint

Two or three sentences in `assets/mint/body.md`, in its voice, saying: a line
that names another language is a question, not a definition; ask
`query_language`; call the names it returns, and never define one of them
yourself. Also state that every clause you write is named `<language>-<name>`,
since `clausesNamespaced` refuses anything else and a refusal inside the draft
door costs a round trip.

Keep it domain-blind. No football, no example from libero.

## Task 4: The Acceptance Test

In `libero/`:

1. `player.lips` defines the shared vocabulary in the house notation
   (`contribution(p) := rating(p) times fitness(p), per mille.` and friends).
   Mint it. It is a singleton, so its instance is `player`.
2. Rewrite `training.lips` to say where its players come from and to call
   `contribution(p)`. Mint it.
3. Exactly one of two things must happen: the call resolves to
   `player-contribution`, or lips refuses by name. Silently becoming a local
   JSON field read (what happened on 2026-08-12, see
   `libero/docs/slice-one-measurement.md`) must be unreachable.
4. Second test, for namespacing: two languages that both define `report`
   compose into one site with no renaming by either author.

## Working Notes Worth Keeping

- **Build the binary once**: `nix build ~/projects/lips -o /tmp/lips-bin`, then
  call `/tmp/lips-bin/bin/lips`. `nix run` re-evaluates and rebuilds with GHC,
  which was most of the first mint's wait.
- **Run mints detached**: `nohup … > /tmp/mint.log 2>&1 &`, then poll. A
  cancelled foreground call loses the whole thing.
- **A mint takes about half an hour** at sonnet-5, thinking medium, for a
  26-line program, and sonnet-5 was enough for a 32-clause football engine.
- **Comments never reach the mint** since 2026-08-12: prose for the model goes
  in `<language>.direction`.
- **Numerals become holes; formulas stated once become constants.** To make a
  quantity tunable without a re-mint, write it as a numeral in the program.
- **Migration lesson**, if another engine-format change comes: a Scheme name may
  end in `?`, and an engine may use `clause.<name>` as a FACT subject as well as
  an emit path, so a rename must move the grammar with the rules.

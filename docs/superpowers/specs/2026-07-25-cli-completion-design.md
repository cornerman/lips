# CLI Completion via optparse-applicative

Date: 2026-07-25

## Principle

Shell tab-completion is not a script bolted onto the CLI after the fact; it is
a property the CLI's own argument parser must be able to answer truthfully.
A hand-rolled parser (today's `Lips.Generate.Args` plus the `case args of`
dispatch in `Main.hs`) cannot answer "what comes next" without duplicating
its own logic in a second, drifting artifact (a static `.bash` completion
file). So the fix is not "add a completion script"; it is "replace the
hand-rolled parser with one that can be *asked*", and the shell scripts fall
out as a free, always-in-sync side effect. This is the same shape as the
lang/kernel split elsewhere in lips: one source of truth (the parser),
derived artifacts regenerated from it, never hand-maintained.

`optparse-applicative` is that parser. It already ships
`--bash-completion-script` / `--zsh-completion-script` /
`--fish-completion-script` on any `execParser`-run program, generated from the
same `Parser` value that parses real invocations — they cannot drift.

## Why the Current Parser Blocks This

`Lips.Generate.Args.parseGenerate` guesses whether a bare leading positional
is a model id or a program file (`looksLikeModel`: contains `/`, final
path component has no `.`). This heuristic:

- cannot be completed correctly (a completer cannot know the user's *intent*
  for an ambiguous bare word — is `foo/bar` a model or a typo'd path?);
- is itself bad CLI design — the well-known model ids on more or less every
  competing tool (`gh`, `aws`, `docker`) are named with an explicit flag, not
  guessed from shape;
- only exists because `generate`'s original signature let a model ride in as
  an optional leading positional before the parser had `--model` at all.

Deleting the heuristic and requiring `-m/--model` removes the one piece of
this CLI that a completer cannot express as a closed grammar. Every other
piece (subcommands, flags, file/dir arguments) is already a closed grammar in
the hand-rolled parser; `optparse-applicative` just makes that grammar
declarative and introspectable instead of an ad hoc `case`.

## Scope Confirmation: Domain Errors Are Untouched

lips' elaborate failure reports (`report`/`reportHead`: headline + indented
detail + `→` action line) are produced by `compile`/`check`/`generate` *after*
arguments parse successfully — they diagnose the *program* (a `.lips` file),
never the *command line*. `optparse-applicative`'s own error rendering (a
usage line + `--help` hint) only ever fires on a malformed invocation, which
today either silently falls through to the fixed `usage` text or (for
`generate`) prints that same `usage` on `Nothing`. Replacing that path changes
nothing downstream of a successful parse. No `report`/`reportHead` call site
changes.

## The New Grammar

Four subcommands, all declared through `hsubparser` (so all four list in
`lips --help`, none hidden):

```
lips generate [-t|--target nixos|home-manager] [--confidence <0..1>]
              [--renew] [-v|--verbose] [-m|--model <id>] <program>...
lips compile  [-o|--out <dir>] <program>
lips check    <program>
lips lsp
```

Decisions and why:

- **`-m/--model` is the only way to name a model.** No positional guessing.
  `generate` without `-m` omits `--model` from the `pi` invocation entirely, so
  `pi`'s own configured default applies — unchanged behavior, just reached
  through one path instead of two.
- **Short aliases**: `-t/--target`, `-m/--model`, `-o/--out`, `-v/--verbose`.
  These are the flags used interactively and worth typing fast.
  **`--renew` stays long-only** — it re-blesses a committed behavioral
  contract (rewrites `.expect`), a rare and deliberate action; a short alias
  would invite a fat-fingered `-r` to silently widen scope. This is the same
  judgment call as today's code (no existing short flags at all), just
  applied selectively instead of uniformly.
- **`compile` keeps exactly one program**, unlike `generate`'s `some` (one or
  more). No forced symmetry: `compile` realizes into a single output
  directory (`--out <dir>` or `dropExtension file`), which has no multi-file
  reading; `generate` mints one language from a *corpus* of programs by
  design (anti-unification over examples, see `Main.hs` `generate`). Making
  `compile` variadic to match `generate` would either silently compile only
  the first file (surprising) or invent a directory-per-file convention
  nobody asked for (YAGNI).
- **`lsp` gains no flags** (it has none today) but becomes a first-class,
  documented subcommand instead of a `case` arm `usage` never mentions. No
  behavior change, just consistency — a real gap in the current CLI, not
  cosmetic: someone tab-completing `lips <TAB>` today would not discover it.
- **No `--version` flag.** YAGNI: no version numbering or release process
  exists in this repo (`DESIGN.md` §13 tracks milestones, not releases); a
  `--version` flag with nothing meaningful to print is worse than none.

### Argument Types

- `<program>` : `FilePath` (`strArgument`), no existence check at parse time —
  `readProgramOrDie` already gives a clean error if the path is wrong, and
  parse-time stat-ing would be a second, redundant failure path.
  Completion comes from `Lips.Cli.programCompleter`, which lists `*.lips`
  files plus directories to descend into. The earlier assumption that the
  shells' own filename completion would fill the gap was wrong: the generated
  scripts route every word to the binary, so an argument without a completer
  completes to nothing. `action "file"` was rejected for two reasons: it is a
  `bash`/`zsh`-only convention with no portable fish equivalent, and a bare
  file completer would offer the machine-written neighbours (`.lang`,
  `.expect`, `.generation`, `out/`) as if a human could pass them. Listing in
  Haskell works in all three shells alike.
- `--target` : `nixos | home-manager`, parsed by the existing
  `Lips.Nix.Target.parseTarget`; wrapped in an `eitherReader` so an unknown
  value fails through `optparse-applicative`'s own error path (a parse error,
  not a domain error — see Scope Confirmation above) rather than silently
  defaulting.
- `--confidence` : `Double` in `[0, 1]`, `eitherReader` combining `readMaybe`
  and the range check — the exact validation `parseGenerate` does today,
  moved into the reader.
- `--model` : `Maybe String`, no validation (an unrecognized model id is
  `pi`'s failure to report, not lips').
- `--out` : `Maybe FilePath`.
- `--renew`, `--verbose` : `switch`.

## Tests

`kernel/test/Spec.hs` keeps its existing pure-function test style. Today's
`parseGenerate 0.7 [...]` calls become `execParserPure defaultPrefs
generateParserInfo [...]` (or a small local `parseArgs :: [String] -> Maybe
Result` wrapper), read via `getParseResult`. Only the one test that exercises
implicit-model detection (`parseGenerate 0.7 ["anthropic/claude", "a.backup.lips", "b.backup.lips"]`)
needs rewriting — to explicit `["--model", "anthropic/claude", "a.backup.lips", "b.backup.lips"]`
— because the behavior it tests (guessing) no longer exists. Every other
existing case (`--target`, `--confidence`, `--renew`, `--verbose`, the
duplicate/malformed-flag failures) re-expresses directly.

## Packaging Change

`kernel` has no `.cabal`/`package.yaml`; the flake compiles it directly with
`ghc -isrc -iapp app/Main.hs`, and dependencies are supplied as a GHC package
set built by `haskellPackages.ghcWithPackages` (`flake.nix`, function `ghc`).
Add `p.optparse-applicative` to that list. It is referenced from three call
sites in `flake.nix` (`devShells.default`, `packages.default`,
`checks.kernel-tests`) — all pull from the same `ghc` function, so one edit
covers all three.

Ship the completion scripts by generating them at build time from the just-
built binary, using `installShellFiles` in `packages.default`:

```nix
pkgs.runCommand "lips" { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper pkgs.installShellFiles ]; } ''
  ...existing ghc build + makeWrapper...
  installShellCompletion --cmd lips \
    --bash <($out/bin/lips --bash-completion-script $out/bin/lips) \
    --zsh  <($out/bin/lips --zsh-completion-script  $out/bin/lips) \
    --fish <($out/bin/lips --fish-completion-script $out/bin/lips)
''
```

This runs the wrapped binary during the build (no network, no AI call —
`--bash-completion-script` is a pure parser-introspection path that never
reaches `callPi`), so it stays hermetic. `nixos`'s `programs.bash.enableCompletion`
/ `environment.pathsToLink` machinery then picks these up automatically for any
system with `lips` installed via `home.packages`/`environment.systemPackages` —
no extra wiring needed on the consuming side.

## Migration

- `kernel/src/Lips/Generate/Args.hs` → replaced by a new module (e.g.
  `Lips.Cli`) exporting the top-level `Parser` and the four per-command
  parsers; `Main.hs`'s `case args of` dispatch is replaced by
  `customExecParser` over the top-level parser, dispatching on the parsed
  sum type.
- `Main.hs`'s hand-rolled `usage` function is deleted; `optparse-applicative`
  generates `--help` from the same parser (subcommand descriptions carry the
  prose `usage` held, via `progDesc`/`briefDesc` on each `hsubparser` command).
- `justfile`'s `generate` recipe currently relies on the positional-model
  heuristic (`nix run . -- generate "{{model}}" "{{program}}"` when `model` is
  set — this only worked because a bare leading arg containing `/` guessed as
  a model). Update it to `nix run . -- generate --model "{{model}}" "{{program}}"`.
- `README.md` usage block (wherever it mirrors today's `usage` text) gets
  updated to show `-m/--model` etc.
- `DESIGN.md` §13 gets a milestone entry once this lands.
- `TODO.md`: this feature is not yet listed; add it to "Next up" during
  planning, or drop it once shipped (it doesn't appear in the current ledger).

## Out of Scope

- No change to `Lips.Nix.Target`, `Lips.Kernel.*`, or any `report`/`reportHead`
  call site — this is purely the argument-parsing layer.
- No new flags beyond what exists today; this is a parser-technology swap, not
  a CLI feature expansion.
- Editor/LSP completion (`.lips` program content) is a separate, already-
  existing concern (`Lips.Lsp.Server`) and untouched by this change — this
  design is shell completion of the `lips` *command line*, not of program text.

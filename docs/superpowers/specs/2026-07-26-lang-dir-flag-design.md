# `--lang-dir`: Sharing a Language Across Directories

Date: 2026-07-26

## Problem

`Lips.Identity.langDir` derives the language folder purely from a program's
own path: `<dir>/<language>/`, always a sibling. Language reuse across
*instances* already works when programs are co-located
(`examples/ledger.backup.lips` + `examples/photos.backup.lips` both resolve to
`examples/backup/`), but a repo with several service directories
(`services/a/`, `services/b/`, …) that all want one language minted once has
no way to share it without moving programs into one directory. This design
opens that gate with a CLI flag.

## Scope

`compile` and `check` gain an optional `--lang-dir DIR` flag. `generate` and
`lsp` get nothing: a shared language is always minted beside the programs
that grow it (`cd services/a && lips generate *.backup.lips`); a directory
that only *consumes* a language never mints or rewrites it. This keeps
`generate`'s existing behavior (and every call site in `Main.hs`'s `generate`
function) untouched.

## Semantics

`--lang-dir DIR` redirects only where lips *reads* the four **committed**
language files: `<language>.lang`, `<language>.expect`,
`<language>.generation`, `artifacts/`. It does not move **derived** output:
`out/<instance>.decisions` and the compiled module dir still land under the
*program's own* directory (`outDir file`, unchanged). So a borrowing program
never writes into the lending directory — the shared folder can be read-only,
or owned by a directory a different command never runs `compile`/`check` in
concurrently with this one, with no output collision.

This mirrors how multiplicity already works for co-located instances: several
instances of one language share `<language>.lang` (an input) but each gets its
own `out/<instance>.decisions` and `out/<instance>/` (their own output),
keyed by instance name. `--lang-dir` extends the *sharing* half of that split
across a directory boundary without touching the *per-instance output* half.

## Validation: the Folder Must Be Named After the Program's Language

A program declares its language in its own filename
(`photos.backup.lips` → language `backup`). `--lang-dir` must point at a
folder named after that same language, checked before anything else runs:

```
lips check --lang-dir services/a/archival services/b/photos.backup.lips
```

fails loud, naming both sides:

```
services/b/photos.backup.lips is written in .backup, but
services/a/archival is named .archival.

→ point --lang-dir at a folder named backup, or rename the program.
```

This is deduce-or-fail, the same posture as a missing `.lang`: lips never
silently reads one language's files under another language's name. The check
is pure (folder basename vs. `languageName file`) and runs first, before any
file IO against the resolved directory.

A `--lang-dir` that does not exist yet (a typo, or a language not minted
there) falls through to the existing "isn't set up yet, run generate" message
— technically correct (generate always mints locally per Scope above) but
worth a one-line callout since it can read oddly to someone expecting an
already-shared folder. Not a new error path; not solved further here (YAGNI —
this is a rare, self-correcting mistake: the path in the message tells them
where lips looked).

## Code Shape

**`Lips.Identity`** gains:

- `resolveLangDir :: FilePath -> Maybe FilePath -> Either Text FilePath` — pure.
  `Nothing` returns today's sibling-derived `langDir file`; `Just d` checks
  `takeFileName (dropTrailingPathSeparator d) == languageName file` and
  returns `Right d` or a `Left` message naming both sides (see above).
- Explicit-directory variants of the four committed-file paths, taking the
  *resolved* directory instead of re-deriving it from `file`:
  `langPathIn`, `expectPathIn`, `generationPathIn`, `artifactsPathIn`
  (`dir -> FilePath -> FilePath`). The existing zero-argument-derived
  `langPath`/`expectPath`/`generationPath`/`artifactsPath` stay as they are
  (used by `generate`, tests, and as the `Nothing`-case implementation these
  `*In` variants delegate to).
- `outDir`, `decisionsPath`, `compiledPath`, `directionPath` are unchanged —
  derived output and the human-owned `.direction` file stay local to the
  program's own directory regardless of `--lang-dir`.

**`Lips.Cli`**:

- `CompileOpts` gains `coLangDir :: Maybe FilePath`.
- `Check FilePath` becomes `Check CheckOpts`, a new record
  (`ceFile :: FilePath`, `ceLangDir :: Maybe FilePath`), mirroring
  `CompileOpts` so both subcommands parse the flag the same way
  (`long "lang-dir" <> metavar "DIR" <> help "..."`, no short alias — this is
  a deliberate, occasional override, not a fast-typed everyday flag, the same
  judgment already applied to `--renew`).

**`Main.hs`**:

- `compileLoose`/`checkLoose` resolve the directory once via
  `resolveLangDir`, `die`-ing on `Left` with the message above, then thread
  the resolved `FilePath` through to `loadLangOrDie`, `expectGate`,
  `readRecordedTarget`, and `stageFromDisk` — each of these changes from
  taking just `file` to taking `(dir, file)` and calling the `*In` variants
  instead of re-deriving `langDir file` internally.
- `generate` is untouched (no `Maybe FilePath` threaded in; it never sees a
  `--lang-dir`).

## Tests

- `resolveLangDir` (pure): default case (`Nothing` → today's `langDir`),
  matching override (`Right d`), mismatched override (`Left`, message names
  both the program's language and the folder's basename), and a trailing
  slash on `DIR` (`services/a/backup/` must still match `backup`).
- CLI parse tests (`kernel/test/Spec.hs`, `optparse-applicative` style
  already established for `--target`/`--confidence`): `compile --lang-dir
  DIR PROGRAM` and `check --lang-dir DIR PROGRAM` parse to the right
  `coLangDir`/`ceLangDir`; omitting the flag parses to `Nothing`.
- One integration-level case (matching the existing `check`/`compile`
  conformance style): two example programs in separate directories, one
  language minted in the first, `check --lang-dir` and `compile --lang-dir`
  from the second succeed and their derived output lands under the second
  directory's own `out/`.

## Out of Scope

- No change to `generate`, `lsp`, or any `Lips.Kernel.*` module — this is
  entirely the CLI/shell layer (`Lips.Cli`, `Lips.Identity`, `Main.hs`).
- No pointer-file or symlink convention — this design is the CLI-flag
  approach only (chosen over a `<language>.langref` file and over a bare
  language-folder symlink, both considered and set aside: see session notes;
  the flag is the explicit, per-invocation form, accepting that the sharing
  decision then lives in whatever script or muscle memory invokes `compile`/
  `check`, not in a file the repo's own listing reveals).
- No change to `directionPath`, `outDir`, `decisionsPath`, or `compiledPath`.

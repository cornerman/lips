# CLI Output Rework — one voice, live mint

Date: 2026-08-02. Branch: `cli-output`.

## Why

Two defects, one cause. The mint blocks silently inside
`readCreateProcessWithExitCode` (app/Main.hs `callPi`) for minutes with no sign
of life, so a user cannot tell a working model from a hung one. And every verb
invented its own wording: `compile` says `compiled X -> Y` on stderr, `check`
says `X: all 7 checks pass.` on stdout, `generate` dumps a whole module on
stdout after prose on stderr. Nothing decides, in one place, what lips sounds
like.

The cause is that formatting lives at ~40 scattered call sites in `Main.hs`. Fix
the cause: one module owns every byte lips prints, and each verb becomes the
same sequence of named steps.

## Standards (decided with the owner)

- Glyphs: `·` running, `✓` held, `✗` failed, `→` remedy. Dim and bold only, no
  hues. All styling dropped when stderr is not a tty or `NO_COLOR` is set.
- A step prints `· <label>` while it runs and `✓ <label> (1.2s)` when it holds.
  Piped: plain lines, no cursor control, same words.
- The mint shows one dim line per pi tool call (key argument + short verdict)
  and a spinner carrying state plus elapsed seconds.
- `--verbose` shows everything, live and untruncated: the system prompt,
  direction and corpus as sent; the model's prose as it streams; full tool
  arguments and results; the raw reply at the end.
- stdout carries only what a machine asked for: `options`' answer, `check`'s
  diagnosis table. Everything else is stderr.
- Verb and flag names do not change. Only printed text and help text change.

## Tasks

### 1. `Lips/Cli/Output.hs` — the single voice

New module. Interface, deliberately small:

```haskell
data Style = Style { stTty :: Bool }      -- resolved once, at startup
resolveStyle :: IO Style                  -- hIsTerminalDevice stderr + NO_COLOR
step   :: Style -> Text -> IO a -> IO a   -- · running / ✓ held (1.2s), ✗ on throw
note   :: Style -> Text -> IO ()          -- one dim detail line under a step
report :: Text -> [Text] -> Text -> Text  -- moved verbatim from Main.hs
reportHead :: Text -> [Text] -> Text      -- moved verbatim from Main.hs
```

Tests (pure): the rendered step line for tty and non-tty, the elapsed-time
formatting, `report` unchanged output (a regression pin, since every error text
in the suite flows through it).

Gotcha: a step whose action calls `die` must not leave a half-drawn line. `step`
prints the `✗` form from an exception handler and rethrows.

### 2. Streamed `callPi`

Replace `readCreateProcessWithExitCode` with `createProcess` over pipes:

- one `forkIO` writes the prompt to the child's stdin and closes it,
- one `forkIO` drains stderr into an accumulator (needed for the failure
  report),
- the main loop reads stdout line by line, appends each to an accumulator, and
  renders it live.

base only (`Control.Concurrent`, `MVar`); no new dependency.

The full accumulated stdout still feeds `parsePiReply`, so `.generation`,
`genId` and invariant 6 are untouched.

### 3. `PiJson.progressLine` — pure event rendering

Add to `Lips/Generate/PiJson.hs`:

```haskell
data PiEvent = PiTool Text Text | PiToolDone Text Text Bool | PiState Text | PiProse Text
progressEvent :: Text -> Maybe PiEvent   -- one JSONL line -> what to show
```

Pure, so the display is unit-tested against captured event lines (fixtures
under `kernel/test/fixtures/`). `Main.hs` maps a `PiEvent` to `note`/spinner
state; `--verbose` prints the untruncated form.

### 4. Convert the verbs

Same step sequence everywhere, no formatting left in `Main.hs`:

- `check`: crystallize → contract → claims.
- `compile`: the check's steps → write directory → the `nix` commands.
- `generate`: read programs → schema → mint → parse reply → engine gate →
  option names → crystallize (per program) → nix parse → staged sources →
  contract → artifact build → claims → write files.

Drop `generate`'s module dump to stdout (the one behaviour change; `compile`
writes the directory, nothing in the repo pipes it).

### 5. Help text

New top-line: `lips builds a Nix configuration from a program you wrote in your
own plain sentences.` Rewrite every `progDesc` and flag `help` in the same
voice, in `Lips/Cli.hs`. No renames.

### 6. Verify

`just test` (-Wall clean), `just check-expect`, one real `lips generate` against
an example to watch the live view, then ledger section 13.

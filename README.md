# lips

Write intent, not code. You state what a system should do in a few plain
lines; a machine turns that into a running NixOS configuration, and keeps doing
so deterministically, with no AI in the loop after the first step.

The point: AI now writes code faster than anyone can review it. lips moves the
human-owned artifact up to intent and keeps execution deterministic below it,
so the thing you read and version is a handful of lines of domain truth instead
of thousands of lines of mechanism.

## The Loop

1. **Write** a loose-text program: a few lines saying what you want.
2. **Generate** once (the only AI step): a model reads your lines and mints a
   small formal *language* plus an *engine* for that problem. This is written
   to `<program>.lang` and committed. The model never runs again after this.
3. **Run** any time: the engine crystallizes your loose text into decisions and
   realizes them as a NixOS module, deterministically and offline. Edit values
   in the program and re-run, no model needed. Write a line the language cannot
   read and it fails loud, pointing you back to `generate`.

So `generate` is authoring; `run` is a compiler. Unplug the network and delete
the model, and `run` still works, bit-identical, forever.

## Try It

Tools come from the flake. With direnv, `direnv allow` once and `ghc` + `just`
are on your path; otherwise prefix commands with `nix develop -c`.

    just                            # list commands
    just run examples/backup.loose  # loose text -> NixOS module (offline)
    just test                       # conformance suite
    just check                      # suite + boot the realized module in a VM

The example program (`examples/backup.loose`) is three lines:

    back up /var/lib/ledger to /backup/ledger daily.
    keep 14 daily snapshots.
    credentials come from /etc/ledger-backup.env.

`just run` turns that into a `services.restic.backups.ledger` module. Change a
path or the retention count and run again: the change flows through with no AI.

To mint a language for your own program (needs `pi` on your path for the model
call):

    just generate path/to/my.loose            # default model
    just generate path/to/my.loose <model>    # e.g. anthropic/claude-sonnet-5
    just run path/to/my.loose

## What Is the Program

Only the loose-text file is yours. Everything else is derived:

- `<program>.lang` — the minted language and engine (AI-authored once, pinned).
- `<program>.generation` — the audit record of that one generation event; every
  engine line is stamped with its content id, so each maps back to the event
  that produced it.
- The NixOS module — never stored, reproduced by `run` on every invocation.

If the machine burned down, the loose-text file is the only thing you could not
regenerate. That is the whole design.

## Layout

- `kernel/` — the deliverable: the decision calculus (Haskell reference
  implementation) plus its conformance suite. See `kernel/README.md` for the
  module map.
- `examples/` — demonstration programs (loose text plus their minted `.lang`),
  not part of the deliverable.
- `docs/superpowers/specs/` — the design doc (start with
  `2026-07-18-lipsidea-design.md`), the plans, and the surveys behind them.
- `flake.nix` — build, dev shell, and checks (conformance suite + VM smoke).
- `justfile` — every command; `just` lists them.

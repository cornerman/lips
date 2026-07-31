# The Run Axis

Date: 2026-07-24

> **Amendment (2026-07-24, post-implementation).** The `container` (systemd-nspawn)
> rung described below was implemented, then **dropped**. Live testing showed a
> hand-rolled nspawn boot is fragile (machined/nsresourced, networking, /etc,
> root) and the robust path (`extra-container`) is a dependency needing sudo.
> Since `vm` already builds *and* boots the whole system and `nix build …#vm`
> is a KVM-free "does it build" check, a build-only container was redundant and
> a run-container bought nothing reliable. The shipped run axis is therefore
> **exec / shell / vm**. A portable OCI image (nginx, a Go server) built with
> `dockerTools` is a future PACKAGE-axis output (distribution), not a run rung.
> Read the `container` references below as rejected-alternative history.

## Principle

Running a lips program is not a lips verb. `compile` is the sole
materialization; every way to run is a stock `nix` command over the compiled
directory. lips' job shrinks to two things: emit a directory `nix` can address
(a flake), and print the applicable commands. The obvious path (drive `nix`
yourself) and the lips path are the same path.

## Verb Changes

Verbs after this change: `generate`, `compile`, `check`. The `run` command and
its Haskell (`runVm`, `bootVm`, `vmExpr`, home-manager `runEvalOnly`) are
deleted. Net negative code: the VM-boot logic moves from runtime Haskell into
an emitted `flake.nix` that `nix` evaluates.

## What `compile` Emits

The compiled directory keeps `default.nix` as the module fragment (so
`imports = [ ./out ]` and future deploy still work) and `artifacts/` staged
source. It gains a `flake.nix` (the addressable entry) and, when the program
declares artifacts, an `artifact.nix` holding the authoritative artifact
derivation(s) that both `default.nix` (for `${artifact.<name>}` references) and
`flake.nix` consume, so the derivation has one definition (DRY).

```
out/
  flake.nix      # addressable entry (NEW)
  default.nix    # module fragment (imports ./artifact.nix) — for imports/deploy
  artifact.nix   # authoritative artifact derivation(s), only if declared (NEW)
  artifacts/     # staged source
```

Flake outputs, derived purely from the program's shape (the shell asks only:
is there an `artifact.*`? is there a module? which recorded world?), so the
kernel stays domain-blind:

- `packages.<sys>.artifact.<name>` = `import ./artifact.nix` — build the binary
- `apps.<sys>.artifact.<name>` = run the artifact via Nix `mainProgram` — exec
- `apps.<sys>.vm` = `eval-config [qemu-vm, ./default.nix].config.system.build.vm`
- `apps.<sys>.container` = `systemd-nspawn` over
  `eval-config [./default.nix, { boot.isContainer = true; }].config.system.build.toplevel`
- `nixosModules.default` / `homeManagerModules.default` = `import ./default.nix`

Nixpkgs stays ambient (registry `flake:nixpkgs`, lockless/impure), so `compile`
fetches nothing, stays nixpkgs-free, and emits bit-identical text. This is the
same Heile-Welt softness the old `<nixpkgs>`-based `vmExpr` already carried.

## The Four Rungs

Each rung is a stock `nix` command. Commands use `path:./out#…` because the
compiled dir is derived and gitignored; `path:` copies the directory verbatim,
bypassing flake's git rules.

| Rung | Needs | Run | Build |
|------|-------|-----|-------|
| exec | artifact | `nix run path:./out#artifact.helloserver` | `nix build path:./out#artifact.helloserver` |
| shell | artifact | `nix shell path:./out#artifact.helloserver` | — |
| container | module | `nix run path:./out#container` | `nix build path:./out#container` |
| vm | module | `nix run path:./out#vm` | `nix build path:./out#vm` |

`exec`/`shell` run the artifact bare: there is no init in those modes, so no
services and no service env (`PORT`/`RESPONSE`); the printed hint states this.
(Amended 2026-07-31: the shell rung closes the env half. `nix develop
…#service-<unit>` gives the tools shell plus that unit's `environment`,
derived by subtracting a bare eval's `systemd.services` names, so the vars the
module states need no manual `export`. It remains a shell: lips does not
emulate systemd, so `User`/`StateDirectory`/`EnvironmentFile` stay `vm`'s
business.)
`container` boots a full NixOS userspace (all services, users, activation)
sharing the host kernel — no KVM, seconds to start, complete for every current
example. `vm` adds the kernel/boot/hardware layer and is the specialist for
intent that touches it. `nix build …#container` is a cheap "does the whole
system build" check needing neither KVM nor root.

## Clash Avoidance

Rung app names (`vm`, `container`) are lips-fixed; artifact names are
domain-minted. They cannot collide because artifacts are namespaced under
`artifact.<name>` while rungs stay top-level: `artifact.vm` never equals the
rung `vm`. Impossible by construction, no reserved-word check. The word
`artifact` (singular) mirrors the decision grammar (`artifact.helloserver.*`
in `.lang`), so no new vocabulary.

Implementation caveat: nesting makes `apps.<sys>.artifact` a non-leaf set,
which `nix flake check` may reject though `nix run`/`nix build` resolve dotted
attrpaths. Default to the dotted form; if nix forces it, fall back to a flat
separator (`artifact-helloserver`). Verify with a one-line `nix run` probe.

## Discovery Print

After a successful `compile`, print only the commands whose rung the program's
shape supports (pure artifact → exec/shell/build-binary; pure system config →
container/vm; both → all). This replaces mode validation entirely: you only
ever see commands that work. home-manager (no machine) prints its build/import
hint, no vm/container.

## Invariants Preserved

- `compile` gates then writes (TODO #1): any directory that exists is
  contract-valid, so `nix`-over-dir is safe and the behavioral gate lives in
  `compile`, not in a run verb.
- Deduce-or-fail: only valid commands are printed; a wrong attr errors loudly
  via `nix`.
- Kernel knows nothing: outputs derive from shape, no per-program branch.
- `compile` stays offline, nixpkgs-free, bit-identical.

## Out of Scope (Named Future Axes)

- Package / deliverable axis: Docker image, ISO, standalone binary. An artifact
  always needs a consumer, so "build to nowhere" is a non-thing; distribution
  formats are their own realize output shapes, designed when a concrete need
  lands. `nix build` already yields a `result` symlink for hand-off.
- Deploy axis: import `default.nix` into `~/nixos` on `wolf` (TODO #3),
  persistent and privileged, its own explicit verb later.

## Migration

- Update `README.md`, `justfile` (`just run`), `DESIGN.md` §13.
- Re-express the `vm-smoke` / `artifact-vm` flake checks as `nix build` / apps
  over the compiled dir (`vm-smoke` can become a lighter `nix build …#container`).
- Delete `run`, `runVm`, `bootVm`, `vmExpr`, `runEvalOnly`.

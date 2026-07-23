# Realization Target: NixOS and home-manager

Status: approved design (brainstormed 2026-07-22). Specifies how a lips engine
targets a Nix world (NixOS or home-manager), how that world is chosen and
pinned, and how a realized module integrates into an owner's system
configuration (`$HOME/nixos`).

## 1. Thesis

lips does not produce "a NixOS module" or "a home-manager module." It projects
a ground decision base to a set of `path = value` assignments wrapped as
`{ config, lib, pkgs, ... }: { ... }`. NixOS and home-manager are two option
vocabularies over the same Nix module-merge substrate; lips is agnostic to
which one owns the paths a given engine names.

The kernel therefore stays world-blind, exactly as it is domain-blind. The
world is per-problem knowledge, and per the project's own law that knowledge
lives in the engine (data), reached by name: `services.restic.backups` is a
name inherited from nixpkgs the same way `systemd.user.services` is a name
inherited from the home-manager module set. The kernel knows neither.

## 2. The World Lives in the Paths

There is no world-neutral option for a given intent. "Back up daily" is
`services.restic.backups.<self>.*` in NixOS and
`systemd.user.services.backup.*` + `home.packages` in home-manager; the
vocabularies do not overlap. Writing a rule's option path *is* choosing the
world.

Consequently an engine is **born into a world**. `backup.lang`, whose rules
name `services.restic.backups.*`, is a NixOS engine permanently, because those
paths exist only there. The world is not a declared field in the `.lang`; it is
implied by every path the rules emit. Importing an engine into the wrong world
fails loud at eval ("option does not exist"), which is the correct
deduce-or-fail behavior, never a silent wrong result.

lips never rewrites paths between worlds. Translating `services.restic.backups`
into `systemd.user.*` would require the kernel to know what restic is; that is
forbidden. A user-service backup is a *different intent*, minted into a
different engine that names `systemd.user.*` paths.

## 3. What Differs Between the Two Worlds

Identical: the realized module text
(`{ config, lib, pkgs, ... }: { <path> = <value>; }`) and the module-merge
machinery that consumes it. This identity is why `print` is world-blind.

Different:

- **Option namespace.** NixOS: `services.*`, `systemd.services.*`,
  `environment.*`, `networking.*`, `boot.*`, `users.*`, system-wide.
  home-manager: `programs.*`, `systemd.user.services.*`, `home.packages`,
  `home.file.*`, `xdg.*`, one user's `$HOME`.
- **Grounding schema.** NixOS grounds against the pinned nixpkgs `optionsJSON`
  (`config.system.build.manual.optionsJSON`, file at
  `share/doc/nixos/options.json`). home-manager grounds against home-manager's
  own `optionsJSON` (flake output `packages.<system>.docs-json`, file at
  `share/doc/home-manager/options.json`). Both are the same JSON shape
  (`{ "option.path": { type, ... } }`, produced by `nixosOptionsDoc`), so
  `Lips.Nix.Options.parseNixOptionsJson` parses both unchanged; only the
  derivation that builds the schema differs per target.
- **Run semantics.** NixOS builds `config.system.build.vm` and boots a QEMU VM;
  there is a machine. home-manager has no machine to boot (its runtime is a
  per-user activation), so its `run` is eval-only (section 5).
- **Scope and privilege.** NixOS: root, whole machine. home-manager:
  unprivileged, per-user.

Notably, the `.expect` gate is **world-blind**: it applies the bare realized
module with stubbed arguments (`config = {}; lib = {}; pkgs = {}`) and reads
the assigned values straight from the returned attrset. It verifies that a
program value reaches a path, never that the path is a real option in a world.
So neither `check` nor the gate needs a world evaluator, and home-manager adds
no eval harness. Per-world validity is established once, by grounding at
generate (section 6).

## 4. Target as a Generate-Time, Pinned Input

Because the world is fixed the moment rules are minted, `generate` must know
it, for two mechanical reasons: to steer the mint prompt into the right
namespace, and to ground minted paths against that world's `optionsJSON`.

- `lips generate [--target <world>] ...`, default `nixos`. The flag selects the
  namespace the mint targets and the schema it grounds against; grounding at
  generate (currently NixOS-only) becomes parameterized by world.
- The world is recorded in the `.generation` record as a `target: <world>`
  field, exactly as `confidence-threshold` is recorded. It therefore enters
  `genId` (which hashes the whole record), so every minted line's
  `@gen:<id>` stamp re-hashes with the target included. Regenerating under a
  different target is a distinct generation event, gated by the committed
  `.expect` contract; re-blessing a world change is deleting `.expect` and
  regenerating, never silent.
- No separate committed target field beyond the record. The emitted paths are
  the operative record of the world; `.generation` pins the *event* that chose
  it.

## 5. Run Picks a Harness; Check Is Target-Independent

`check` and `run` never rewrite paths and never re-ground (grounding lives at
generate; re-grounding here would pull nixpkgs into their closure, breaking the
standing invariant that nixpkgs never enters `print`/`run`/`check`).

- `lips check <program>` is target-independent. Its `.expect` gate is
  world-blind (section 3), so the check is identical whatever world the engine
  was minted for. No `--target` flag.
- `lips run <program>` reads the world the engine was minted for from its
  `.generation` record and picks a harness: `nixos` boots a QEMU VM (today's
  behavior, unchanged); `home-manager` is **eval-only** -- realize the module
  and run the world-blind `.expect` gate, no boot, no activation build. There is
  no machine to boot for a per-user environment, and the world-blind gate
  already proves the program values reach their paths. A stronger future check
  can reuse the QEMU harness via `home-manager.users.<self> = <module>` inside a
  NixOS VM; deferred. An optional `run --target <world>` override exists for
  completeness but defaults to the recorded world.

## 6. Generate's Guarantee

`generate` retains "a bad mint costs you nothing," now with the world known:
crystallize every program, realize to module text, ground every emitted path
against the target world's `optionsJSON`, and run the world-blind `.expect`
gate before writing anything. Grounding is the sole per-world step, and it is
where per-world validity is established: `generate --target home-manager`
grounds against the home-manager schema, so a rule naming a NixOS-only path is
rejected at mint time. The target world's schema is built from a pinned flake
baked into the binary (`LIPS_NIXPKGS_FLAKE` for nixos, a new `LIPS_HM_FLAKE`
for home-manager), overridable by `LIPS_OPTIONS_JSON`; only `generate` ever
builds a schema, so print/run/check stay nixpkgs-free.

## 7. Integration Into `$HOME/nixos`

The realized module is derived, not owned, like `.decisions`. It is never
committed. lips is a flake *input* of the owner's system; each program instance
is exposed as a flake output built by a derivation that runs `lips print` over
the git-tracked `program + .lang` (offline, deterministic).

- `lips print <program>` stays the pure printer (crystallize, realize, module
  text to stdout), world-blind.
- A flake helper discovers the instances and exposes each under the label
  matching its recorded world: a NixOS engine under `nixosModules.<instance>`,
  a home-manager engine under `homeManagerModules.<instance>`. The label is
  chosen from the `.generation` target, so it is never a broken half-symmetry.
- The owner wires one line into the matching evaluator, e.g.
  `imports = [ inputs.lips.nixosModules.ledger ]` or
  `imports = [ inputs.lips.homeManagerModules.myTimer ]`. Pinning rides
  `flake.lock`.
- Instance discovery: the helper takes an explicitly given directory and
  exposes every `*.lips` under it as an output, labeled by its recorded target.
  One explicit knob (the directory, which is itself the semantic index of
  instances), zero per-file repetition, and no surprising outputs from a stray
  file elsewhere in the repo. A blind repo-wide glob and a hand-maintained
  per-file list are both rejected (surprise, and DRY-violating repetition of
  what the filesystem already states).

Accepted cost: the `lips print` derivation puts the lips binary in the owner's
system eval/build closure. Acceptable on the owner's own machine.

## 8. Consequences and Risks

- home-manager's only new machinery is a second grounding schema at generate
  (its `docs-json` `optionsJSON`, pinned via `LIPS_HM_FLAKE`) and an eval-only
  `run` branch. The `.expect` gate is world-blind, so no `homeManagerConfiguration`
  eval harness is needed. This is far less than the ledger's original
  "home-manager realization target" estimate.
- The dual-label symmetry is decided against: one engine, one world, one label,
  read from the recorded target. This matches the reality that an engine's
  paths validate in exactly one world.
- Grounding at generate is parameterized by world; the mint prompt gains a
  world-steering section derived from `--target`.
- Generate's guarantee splits only nominally: grounding still runs at generate,
  just against the target's schema. Nothing weakens; a bad mint still writes
  nothing.
- The invariant "nixpkgs never enters print/run/check" is preserved: grounding
  stays at generate, and `run` for home-manager is eval-only (no nixpkgs
  eval, no home-manager eval).

## 9. Out of Scope

- Cross-world path translation. Forbidden by "the kernel knows nothing."
- A single engine valid in both worlds. An engine is born into one world;
  targeting the other is a separate mint.
- Live host deployment (`nixos-rebuild` / `home-manager switch` against the
  real machine). Remains an explicit, privileged step outside lips.

## 10. Future Targets

The target axis is not NixOS-specific. Any target that is a NixOS-module-system
consumer (it defines config through `lib.evalModules` as `path = value`
assignments and renders that to some artifact) slots in as another `Target`
with zero kernel change, because the kernel already emits only `path = value`
and the world lives in the emitted paths.

Adding a target is three knobs, all outside the kernel:

1. A mint-prompt preamble naming the world's option namespaces (as
   `worldSection` does for NixOS and home-manager).
2. A grounding schema source: the world's `optionsJSON`, built from a pinned
   flake baked as a `LIPS_<world>_FLAKE` ref.
3. A run harness: how the realized module is executed, degrading from "boot a
   machine" (NixOS) to "eval-only / render-only" where there is no machine.

Two concrete candidates:

- **terranix** (`terranix.*` -> Terraform JSON). Already named in DESIGN.md
  section 10 as proof the machinery retargets. Run harness: render the
  Terraform JSON (a `terraform plan` against a throwaway backend is the
  stronger, deferred check).
- **Kubernetes via kubenix** (`kubernetes.resources.*` -> Kubernetes
  manifests). kubenix is a NixOS-module-system consumer, so print/realize are
  unchanged and the world lives in the `kubernetes.*` paths. Run harness:
  render manifests and run the world-blind `.expect` gate (a throwaway
  `kind`/`k3d` cluster is the machine-equivalent, deferred like the
  home-manager-in-a-VM idea).

One caveat specific to these targets: their option schemas are *generated*
(kubenix from the Kubernetes OpenAPI swagger; terranix from provider schemas),
so the option tree is large and deeply nested, and much of it classifies as
`OTOther` (freeform submodules). Grounding therefore degrades to
path-existence and prefix-acceptance rather than tight type checks -- the same
graceful degradation the schema layer already applies to submodule descents,
but worth verifying a clean `optionsJSON` is buildable for the target before
promising it. This grounding-schema availability is the only real friction; it
is harness work, never kernel work.

## 11. Target vs Solution Kind (a Separate Axis)

The realization design has two orthogonal axes. Do not conflate them; in
particular, `--target` must never grow to mean `mkShell`/app/devShell.

**Axis 1 -- Target (this spec).** *Which option namespace a module lands in.*
NixOS, home-manager, kubenix, terranix all emit the same shape,
`{ config, lib, pkgs, ... }: { <path> = <value>; }`, consumed by some
`evalModules`; only the vocabulary differs. Selected by `--target`, recorded in
`.generation`, zero kernel change. The world lives in the emitted paths.

**Axis 2 -- Solution kind.** *What realize's top-level output IS.* A module of
option assignments (all of Axis 1), versus a top-level derivation: a devShell
(`pkgs.mkShell { ... }`, run by `nix develop`), a runnable app (a flake `app`
or package, run by `nix run`), or packages on PATH (`nix shell`). `mkShell` is
a function call producing a derivation, so it does not fit the `path = value`
module shape at all. This is a different realize *form*, not a different
namespace.

What the two axes share: both reach concrete Nix things by name (builders,
`mkShell`, packages), never by kernel special-casing, and both change how a
Solution is run (boot -> activate -> render -> enter-shell / `nix run`). What
differs: a target is a namespace swap over one fixed output shape (no kernel
change); a solution kind is a new top-level output shape for `realize`, which
today hardcodes the `{ config, lib, pkgs, ... }:` module wrapper.

Design decisions recorded from the 2026-07-22 discussion:

- Solution kind is a distinct, later milestone (the ledger's "artifacts /
  Solution-kinds" line). The **artifacts** milestone already built the
  derivation-emission mechanism (`artifact.<name>` groups gathered into a
  `let` block, referenced by `${artifact.<name>}`); a devShell/app reuses that
  *kind* of mechanism -- a top-level derivation -- not an option namespace.
- Adding a solution kind is a closed grammar extension to `realize` (the "new
  emission type" the Kernel-modules / grammar-completeness milestone
  anticipates), never a per-problem kernel branch.
- Consistent with "the world lives in what's emitted," solution kind is
  **inferred** from the emission shape (option paths vs a top-level
  `mkShell`/artifact derivation), with `run` reading it to pick its harness.
  No new flag. Gated behind a real need (YAGNI).

## 12. Open Points

None outstanding; the two prior open points (home-manager run semantics, flake
instance discovery) are decided in sections 5 and 7.

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
  (the existing "option-schema grounding" milestone). home-manager grounds
  against home-manager's own `optionsJSON`, a separate schema that needs
  home-manager pinned as an input.
- **Evaluator.** NixOS: `nixpkgs.lib.nixosSystem` over the `<nixpkgs/nixos>`
  module set. home-manager: `home-manager.lib.homeManagerConfiguration` over
  the home-manager module set (not in nixpkgs).
- **Run semantics.** NixOS builds `config.system.build.vm` and boots a QEMU VM;
  there is a machine. home-manager builds `config.home.activationPackage` and
  runs activation (`home-manager switch`); there is no machine to boot.
- **Scope and privilege.** NixOS: root, whole machine. home-manager:
  unprivileged, per-user.

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

## 5. Target as a Check/Run Harness Selector

`check` and `run` do not rewrite paths. The engine already committed to a world
through its option paths; `--target` there selects only the harness and the
grounding schema to verify against.

- `lips check [--target <world>] <program>` grounds every emitted option path
  against that world's `optionsJSON`, evaluates the module through that world's
  evaluator, and runs the `.expect` gate against it. An engine is "valid for
  target T" iff every emitted path exists in T's schema; a mismatch fails loud.
- `lips run [--target <world>] <program>` realizes and then runs: NixOS boots a
  QEMU VM; home-manager builds and runs the activation package (no boot).
- Default: `--target` defaults to the world recorded in `.generation`, so the
  correct world is used without the owner remembering it. Passing a mismatched
  world is allowed and fails loud (paths absent), which is a diagnostic, not a
  feature.

## 6. Generate's Guarantee

`generate` retains "a bad mint costs you nothing," now with the world known:
crystallize every program, realize to module text, ground every path against
the target world's schema, and run the `.expect` gate against that world's
evaluator before writing anything. The world is a generate input, so all four
checks are available at mint time as they are today; nothing about the
guarantee weakens.

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

Accepted cost: the `lips print` derivation puts the lips binary in the owner's
system eval/build closure. Acceptable on the owner's own machine.

## 8. Consequences and Risks

- Home-manager needs a parallel harness (its own `optionsJSON` pinning,
  `homeManagerConfiguration` eval for the `.expect` gate, activation-package
  run in place of VM boot). This is the ledger's "home-manager realization
  target" item and is the bulk of the build work; NixOS is already wired.
- The dual-label symmetry is decided against: one engine, one world, one label,
  read from the recorded target. This matches the reality that an engine's
  paths validate in exactly one world.
- Grounding at generate is parameterized by world; the mint prompt gains a
  world-steering section derived from `--target`.

## 9. Out of Scope

- Cross-world path translation. Forbidden by "the kernel knows nothing."
- A single engine valid in both worlds. An engine is born into one world;
  targeting the other is a separate mint.
- Live host deployment (`nixos-rebuild` / `home-manager switch` against the
  real machine). Remains an explicit, privileged step outside lips.

## 10. Open Points

- The exact home-manager run semantics in the sandbox: activation-package run
  under a throwaway user versus a lighter eval-only smoke check. The NixOS side
  boots a VM; the home-manager side has no boot, so its `run` and its smoke
  test must be specified against activation.
- Whether the flake helper auto-discovers instances from the tree or takes an
  explicit instance list. Auto-discovery is more convenient; an explicit list
  is more legible and avoids surprising outputs.

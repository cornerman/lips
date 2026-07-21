# Artifacts: Program-Derived Builds Run in the Config

Status: planned, not started. Companion to `2026-07-18-lipsidea-design.md`
(spec v2, milestone ledger section 13, "Artifacts" under Missing). Written so
the work resumes from this document alone.

## Why This Matters

Most Solutions today wire *prebuilt* packages (`${pkgs.nginx}`) into services.
The next capability is a Solution that needs a *real program built from
source*, for example an HTTP server: the program is written for it, Nix
compiles it, and a service runs the result. This is normal software delivery,
not an escape hatch, and it is distinct from glue.

Glue and artifacts are separate axes. Glue is inline computation inside the
decision layer (a computed value), and stays deferred as far as possible. An
artifact is a program derived from the intent, built by Nix, run in the config.
This plan builds artifacts only.

## The Completeness Law (non-negotiable)

The kernel knows nothing about any language or builder. It must never enumerate
`rust | go | ...` or special-case a program's shape. A language nobody foresaw
must work with zero kernel change. Completeness comes by inheritance from
nixpkgs: a builder is a *name* into nixpkgs (`rustPlatform.buildRustPackage`,
`buildGoModule`, and whatever exists next year), reached exactly as
`${pkgs.<path>}` names a package without the kernel knowing what it is. See
AGENTS.md, "The Kernel Knows Nothing".

## Current State (kernel/, on main)

- `realize` (`Kernel/Realize.hs`) projects a ground base to a flat NixOS module
  attrset: each decision becomes one `path = expr;` assignment, sorted by
  option path, deterministic.
- The rhs value grammar (`Kernel/Engine/Value.hs`) is the Nix value algebra
  minus computation: string (with `${pkgs.<path>}` refs and `<value>` holes),
  list, bool, int, float, path, null, typed holes. No function application, no
  injection, by construction.
- A subject is an attribute path and the merge key (`Kernel/Decision.hs`,
  `Kernel/Base.hs`), so nesting is already expressed by subject paths.

## Design

### An artifact is a subject-path group of ordinary decisions

Reuse the existing subject-path model rather than adding nested-attrset values.
An artifact is a group of one-line decisions sharing the `artifact.<name>.`
prefix:

    a1 artifact artifact.myserver.builder       stated "rustPlatform.buildRustPackage" @gen:...
    a2 artifact artifact.myserver.args.pname     stated "myserver"                       @gen:...
    a3 artifact artifact.myserver.args.cargoHash  stated "sha256-..."                      @gen:...
    a4 artifact artifact.myserver.src            stated "@src:<hash>"                      @gen:...

Nesting (the builder's argument attrset) is expressed by subject paths
(`args.pname`, `args.cargoHash`), exactly as NixOS option nesting already is.
Each argument value is a plain closed value from the existing grammar. This
keeps one-decision-per-line for all metadata and needs no new value nesting
(the deferred `VAttr` stays deferred).

### Source lives in a hashed sibling file

The multi-line generated source does not belong on a decision line. It lives as
a real sibling file (reviewed and diffed as source, with normal tooling), and
the `artifact.<name>.src` decision references it by content hash (`@src:<hash>`).
The hash covers the *pre-fill template*, so the pin is stable under value edits.
The source is templated with the same `<value>` holes as everything else and is
filled at realize, so a value edit flows through deterministically; a shape
change re-enters generate (the two-phase story, unchanged).

Storage layout (beside `.lang`, since it is derived and regenerable): to be
pinned during step 1, for example `<program>.artifacts/<name>/<file>`.

### Realize emits a let-bound derivation

`realize` gathers each `artifact.<name>.*` group, writes the filled source into
the store (`writeText` / a source tree), applies the named builder to the
argument attrset, and binds it above the module:

    let
      myserver = pkgs.rustPlatform.buildRustPackage {
        pname = "myserver";
        cargoHash = "sha256-...";
        src = <written source>;
      };
    in {
      systemd.services.myserver.serviceConfig.ExecStart = "${myserver}/bin/myserver";
    }

The builder name is spliced as a name under `pkgs` (never parsed as code); the
arguments are rendered by the existing value renderer. Output stays
deterministic (groups sorted by name, args by key).

### The `${artifact.<name>}` reference

The value string grammar gains one piece beside `${pkgs.<path>}`: an
`${artifact.<name>}` reference, resolved at realize to the corresponding
let-bound name. A name, not computation; injection stays closed. An
`${artifact.<name>}` naming a group that does not exist fails loud (deduce-or-
fail), the same discipline as an unmapped decision.

### Invariants preserved

AI runs only at generate; the builder name, arguments, and source template are
pinned and fingerprinted (`@gen`, `@src`). `print`/`run` build and run offline
and deterministically. The behavioral gate covers it: the VM boots, the service
unit is active, and (for a server) it answers. Glue is not involved.

## Boundaries (deferred, on purpose)

- A build needing *arbitrary* Nix (custom overlays, hand-built multi-derivation
  graphs) is glue, deferred. The named-builder-to-data shape covers "build a
  program in language X", which is the completeness that matters.
- A builder that fetches from the network (crates.io, Go proxy) moves the fetch
  to generate, where the hash (`cargoHash`, `vendorHash`) is computed and
  pinned; run stays offline. This is a Heile-Welt property of the builder, not
  a kernel concern. First cut may use a no-dependency source (compiled with the
  language toolchain directly, e.g. `runCommand` + the compiler) to avoid the
  network entirely; dependency-fetching builders follow.

## Implementation Plan (TDD, small commits)

Worktree under `.worktrees/`, suite stays `-Wall` clean, ledger updated on
landing.

1. Types and storage: an `artifact` decision kind and the `artifact.<name>.*`
   subject convention; the sibling-source layout and the `@src:<hash>` pin
   (hash over the template). Reader round-trips them. Pure tests.
2. Value grammar: add the `${artifact.<name>}` string piece beside
   `${pkgs.<path>}` in `Kernel/Engine/Value.hs`; parse, render, and keep
   injection closed. Tests including a dangling reference.
3. Realize: gather `artifact.<name>.*` groups, fill and write source, emit the
   `let`-bound builder application above the module attrset, resolve
   `${artifact.<name>}`; fail loud on a missing group. Deterministic-order
   tests; output parses as valid Nix.
4. Minting: extend the system prompt so generate emits artifact groups and
   their source files; admit them through the harness; write the sibling
   source and the `@src` pin. Keep the prompt domain-blind (no language
   special-casing).
5. Behavioral gate + example: one small real service built from generated
   source (language chosen only to exercise the pipeline, not privileged).
   `.expect` asserts the built path; extend `vm-smoke` to boot it and assert
   the unit is active (and, for a server, that it answers).
6. End-to-end: generate once, then a value edit flows through the source
   template offline; a shape change re-enters generate; the gate still holds.

## Out of Scope

Dependency-fetching builders as the first cut (network at generate), arbitrary-
Nix builds (glue), multi-artifact composition beyond independent groups, and
container/registry push (Heile-Welt coping). Each is its own later step.

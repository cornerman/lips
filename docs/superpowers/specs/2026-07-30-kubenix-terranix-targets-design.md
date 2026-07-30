# kubenix and terranix as Targets

Date: 2026-07-30
Status: design approved pending review; phase 1 (kubenix) implements first.

## Summary

lips gains `--target kubenix` and, in a second phase, `--target terranix`. Both
worlds consume the module shape lips already emits, so the kernel does not
change: the work is the three target knobs named in
`2026-07-22-realization-target-design.md` (mint preamble, grounding schema
source, run harness), all under `Lips.Nix.*`, `assets/mint/` and `app/Main.hs`.

Two facts, measured against the real flakes on 2026-07-30, drive the design.

kubenix grounds properly. `nixosOptionsDoc` over `kubenix.evalModules.<system>`
builds a 21 MB `options.json` with 31478 entries in roughly four minutes
(cached afterwards), carrying real types:
`kubernetes.api.resources.deployments.<name>.spec.replicas :: null or signed
integer`. kubenix also refuses an unknown field at evaluation
(`The option kubernetes.api.resources.apps.v1.Deployment.web.spec.bogusField
does not exist`), so rendering is a second, independent gate.

terranix grounds weakly, and the design says so instead of pretending. Its core
options (`resource`, `data`, `provider`) are one freeform "magic merge"
`valueType`, so an `options.json` from `terranix.lib.terranixOptions` documents
the core only and every provider path below it is accepted unchecked.

## Why the Kernel Does Not Change

The realized module is `{ config, lib, pkgs, ... }: { <path> = <value>; }`, and
both worlds are `evalModules` consumers of exactly that shape. The `.expect`
gate applies the module as a bare function (`m { config = {}; lib = {}; pkgs =
{}; }` in `Lips.Kernel.Expect.evalExpr`), never through a module system, so
`check` stays offline and world-blind for the new targets. `pkgs` is available
as a module argument under kubenix's `evalModules` (verified), so the fixed
module header keeps working.

The kernel therefore learns no k8s and no Terraform word. It reaches the
concrete world only by name, through option paths the engine emits and a flake
ref inherited from Nix.

## Phase 1 — kubenix

### Knob 1: the World

`Lips.Nix.Target` gains `Kubenix`, slug `kubenix`. `assets/mint/kubenix.md`
becomes the world preamble, naming the vocabulary the mint may use:

- resources live at `kubernetes.resources.<kindPlural>.<self>.…`, the idiomatic
  alias every published kubenix example writes (`…deployments.web.spec.replicas`);
- `<self>` binds to the program's instance name, so `web.deploy.lips` realizes
  `kubernetes.resources.deployments.web.*` and a sibling instance composes
  without collision, exactly as with NixOS instances;
- nothing from `services.*` / `programs.*` exists in this world.

### Knob 2: Grounding

`LIPS_KUBENIX_FLAKE` (baked by the packaged binary as
`github:hall/kubenix/${kubenix.rev}`, pinned in lips's own `flake.lock`) is the
schema source. `schemaExpr Kubenix` builds `nixosOptionsDoc` over
`kubenix.evalModules.<system>` with `kubenix.modules.k8s` imported; the output
file sits at `/share/doc/nixos/options.json`, the same shape the other two
worlds already parse.

A new `Lips.Nix.Kubenix` reshapes that document into the kernel's
`OptionSchema`, reusing `Lips.Nix.Options.parseNixOptionsJson` (the type
wordings are nixpkgs wordings). It does three kubenix-specific things:

1. **Re-key** `kubernetes.api.resources.*` onto `kubernetes.resources.*`, in
   both spellings the alias accepts (`deployments.<name>` and
   `apps.v1.Deployment.<name>`), because the typed tree and the user-facing path
   differ by an alias.
2. **Drop the alias entries** the document lists under `kubernetes.resources`.
   This is correctness, not tidying: that option is typed `attribute set of
   (attribute set)`, and `checkEmits` accepts any path that descends into a
   declared option, so keeping the entry would swallow every misspelled path and
   grounding would silently degrade to nothing.
3. **Unwrap `null or X`** before classification (k8s optionals), so
   `null or (string)` grounds as a string instead of falling back to `OTOther`.

`lips options --target kubenix <query>` answers off the same schema, so a human
browses `kubernetes.resources.*` with the paths the mint must emit.

### Knob 3: the Run Harness

`flakeText Kubenix` adds `inputs.kubenix.url = "github:hall/kubenix"` — ambient
and unpinned, the same Heile-Welt softness `flake:nixpkgs` already carries — and
emits:

- `kubenixModules.default = import ./default.nix;` (no upstream convention
  exists; lips names it so another config can import the program and compose);
- `packages.<system>.manifest` = `config.kubernetes.resultYAML`, kubenix's own
  multi-document YAML output;
- `packages.<system>.manifest-json` = `config.kubernetes.result`, kubenix's own
  JSON output;
- `apps.<system>.manifest` and `apps.<system>.manifest-json`, each a script
  printing the corresponding file to stdout;
- `devShells.default` = a shell holding `kubectl`.

Both rendered outputs are kubenix's own options, so lips converts nothing and
owns no format code. The artifact rungs stay exactly as they are.

`runCommands Kubenix` prints, as compile already prints for every world:

```
  write the manifests:    nix run   path:<dir>#manifest > manifests.yaml
  check it renders:       nix build path:<dir>#manifest
  the JSON form:          nix run   path:<dir>#manifest-json > manifests.json
  a shell with kubectl:   nix develop path:<dir>
```

`nix build` keeps its stock `result` symlink; that is nix's default and the
nixos rungs already behave that way. A per-resource file tree is deliberately
absent: kubenix declares no such output, so lips would have to invent a filename
convention from `kind` and `metadata.name`, and stock `yq` splits the
multi-document file in one command when someone wants a tree.

### Examples

`examples/web.deploy.lips` (an nginx deployment plus its service) is minted and
committed, proving grounding, rendering and the `.expect` contract end to end,
as `examples/web` does for NixOS. A CronJob program reads oddly in a language
called `deploy`, so it lands as a second program in its own language
(`report.cron.lips`) once the first holds.

### Tests

`kernel/test/Spec.hs` gains: `parseTarget "kubenix"` / `targetSlug`; a
`systemPromptFor Kubenix` check naming `kubernetes.resources` and rejecting
`services.`; the three `Lips.Nix.Kubenix` reshaping properties (re-key,
alias-drop, `null or` unwrap) against a small fixture document; and
`flakeText`/`runCommands Kubenix` assertions (the manifest rungs present, the
vm rungs absent). The suite stays `-Wall` clean and offline: no test builds the
21 MB schema.

## Phase 2 — terranix

Same three knobs, one honest weakness.

- **World.** Slug `terranix`, preamble `assets/mint/terranix.md` naming
  `resource.<type>.<name>.…`, `data.*`, `provider.*`, `output.*`.
- **Grounding.** `LIPS_TERRANIX_FLAKE` plus `terranix.lib.terranixOptions`
  yields an `options.json` of the core options only. Because `resource` is a
  declared freeform option, `checkEmits` accepts everything under it: grounding
  confirms the top-level namespace and nothing more. The design records this
  rather than hiding it. The remedy — `terraform providers schema -json`, a
  per-provider network fetch at generate time — is deferred to `TODO.md`, since
  no minted program has been hurt yet and generate is already online.
- **Harness.** `packages.<system>.config` = the `config.tf.json` terranix
  builds; `apps.<system>.config` prints it; `devShells.default` holds
  `opentofu`. Printed rungs mirror kubenix:
  `nix run path:<dir>#config > config.tf.json`, `nix build path:<dir>#config`,
  `nix develop path:<dir>`. No apply rung: piping into `tofu` stays explicit,
  the same choice kubenix makes about `kubectl`.

## Rejected Alternatives

- **Emitting the typed tree directly** (`kubernetes.api.resources.*`). Grounding
  would need no alias mapping, but every emitted module would look unlike
  published kubenix code. Rejected: the alias mapping is ten lines in the shell
  layer, and readable output is worth more.
- **A lips-owned Nix walker producing the schema.** Rejected once the
  `nixosOptionsDoc` measurement came back practical: one mechanism for every
  world beats a second schema producer.
- **An `apply` rung** (`kubectl apply` / `tofu apply`). Rejected: a lips-written
  script that mutates a live cluster or cloud account buys nothing over an
  explicit pipe, and hermetic cluster testing (`kind`/`k3d`) is a separate,
  deferred idea already recorded in the target spec.
- **A per-resource YAML tree.** Rejected as the one piece of the design with no
  analogue in any other world (terranix renders a single file) and with a
  filename convention lips would own forever.
- **Pinning `kubernetes.version` explicitly.** Rejected: kubenix's own default
  applies, so there is no extra recorded knob. The cost is that grounding and
  rendering can drift if the pinned schema flake and the ambient compile-time
  flake diverge; the same softness `flake:nixpkgs` already accepts.

## Ledger

On landing phase 1, update `DESIGN.md` §13 (targets: nixos, home-manager,
kubenix), `README.md` (the sentence saying terranix and kubenix are queued), and
`TODO.md` (add the terranix provider-schema grounding gap).

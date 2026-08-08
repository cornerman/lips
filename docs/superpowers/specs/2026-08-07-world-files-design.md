# World Files: A World Is Data, Not a Constructor

Status: design, agreed in discussion 2026-08-07. No code. Successor of the
backlog item "Targets as external plugins" and of the `--target` half of
`2026-07-30-kubenix-terranix-targets-design.md`.

## The Defect

`Lips.Nix.Target` says the quiet part in its own comment:

```haskell
-- | The Nix worlds lips targets. A closed set: adding a world (darwin, nix-on-droid)
-- is a deliberate extension here plus a schema source, never an open
-- list the kernel enumerates.
data Target = Nixos | HomeManager | Kubenix | Terranix
```

A closed set of four named worlds *is* the open list, enumerated. Apply the
project's own completeness test with "world" substituted for "language": a
world nobody foresaw must work without a code change. Today nix-darwin,
nix-on-droid, flake-parts or a Helm-shaped world each need a constructor, a
parse arm, a schema arm, a reshaping function and roughly a dozen arms in the
flake harness. That is `if language == rust` one tier up.

The rule this restores: **the kernel knows the shape of a world, never the list
of worlds** -- exactly as it knows `${pkgs.<path>}` is a name without knowing
what nginx is.

## What a World Currently Has

Measured in the tree on 2026-08-07:

| # | Knob | Where today | Shape |
|---|---|---|---|
| 1 | slug | `Nix/Target.hs`, 41 lines, 4 arms | data, trivially |
| 2 | mint preamble | `assets/mint/<world>.md`, 15-39 lines | already data |
| 3 | schema pin, expression, sub-path | `Schema.hs`: `bakedPinVar`, `schemaExpr`, `schemaSubPath` | one env var, one Nix expression, one path |
| 4 | schema reshaping | `schemaFor`: three worlds reuse `parseNixOptionsJson`, kubenix needs `Nix/Kubenix.hs` (85 lines) | code, and avoidable (see below) |
| 5 | flake harness | `Nix/Flake.hs`, 426 lines, 34 world references | slots, see below |
| 6 | claim placement | `unplaceableClaims target` in `Main.hs` | a list of claim kinds |

Knobs 2 and 3 are data or nearly so. Knob 6 is a list. Knobs 4 and 5 carry the
design work.

## Decisions

1. **Cross-compilation reaches any world.** A program is not bound to the world
   it was first minted for. Minting a second backend for the same language is
   an ordinary event. When the target world needs a fact the program never
   states (a namespace, an image, a provider), the mint refuses loudly and
   names the missing fact. No notion of "world families" enters the kernel:
   one mechanism, deduce-or-fail, one tier up.

2. **A world is data**, a file named `<world>.world`. `data Target` disappears.

3. **Anyone may write one.** lips ships nixos, home-manager, kubenix and
   terranix as ordinary world files embedded in the binary at build time, the
   same way `assets/mint/*.md` is embedded today, and so eats its own format.

4. **The resolved world file is copied into the language folder** at mint time
   and hashed into `.generation`. `compile` then resolves nothing, reads no
   ambient file, and stops depending on the lips binary version. Today
   `readRecordedTarget` reads a *name* from the record and takes the harness
   from the binary, so compiled output silently tracks the lips version; after
   this change a world moving under you is a visible diff.

5. **Resolution at generate time:** `./<name>.world` beside the program, else
   the built-in of that name. Built-in names are reserved: a local
   `nixos.world` is refused rather than silently shadowing, so `nixos` means
   one thing everywhere and a house variant must be named `house-nixos.world`.
   `--worlds DIR` overrides the directory, mirroring `--lang DIR` (no short
   alias, a deliberate occasional override). No search up the tree and no home
   directory: the repo-wide direction file was rejected for exactly that
   ambiguity, and `generate` is the one step whose entire input set is hashed
   for audit.

6. **Sharing between repos is deferred to Nix.** When a world file needs to be
   shared, the answer is a pinned flake ref (`--target github:you/worlds#name`)
   recorded like every other pin, not a dotfile convention. Until then a
   symlink costs no code.

## The Harness Factors as Slots, Not as a Template

Reading all 426 lines of `Nix/Flake.hs`: the per-world parts share no shape.
NixOS needs `eval-config.nix`, a `subtractLists` derivation of the shell and
`serviceShells`; kubenix needs `kubenix.evalModules` and `resultYAML`; terranix
needs `terranixConfiguration`. Those are three different programs, so a hole
template cannot express them, and any design that tries will grow conditionals
until it is a programming language.

What *is* common is the seam, and it is small and stable:

- **World-neutral, lips owns it and evolves it centrally:** `description`,
  `inputs.nixpkgs`, `systems` / `forSystems` / `pkgsFor`, and the `artifact.*`,
  `site`, `site-claims` and `claims` outputs with their rungs. This is where
  lips' own physics lives.
- **World-supplied, at a closed set of slots:** extra flake inputs, one `builds`
  let binding, attrset expressions for `packages` / `apps` / `devShells`, the
  module output attribute name, the rung list, and the claim kinds the world
  can host.

The slot set is the grammar the kernel knows; the slot content is Nix text the
kernel never inspects. Same move as the value grammar, one tier up.

### One Simplification Falls Out

The only conditional in the per-world Nix today is
`nixosBuildsLet target hasArtifacts`, which appends artifacts to the shell
packages. Make `compile` always emit `artifact.nix` (`{ }` when the program has
none) and the conditional disappears: world text references it
unconditionally. The slot language then needs no `if`, and stays plain text.

## The File Format

`key: value` header lines plus blocks delimited by `--- <slot> ---`, the shape
`.generation` already uses, so the parser and the reading habit both exist.

```
world: nixos
module-attr: nixosModules
schema-pin: LIPS_NIXPKGS_FLAKE
claims: sandbox machine

--- preamble ---
TARGET WORLD: NixOS. ...            (today's assets/mint/nixos.md, verbatim)

--- schema ---
                                    (a Nix expression, in scope: <flakeref>;
                                     evaluates to a derivation whose output is
                                     the canonical options JSON)

--- inputs ---
                                    (empty for nixos; kubenix writes
                                     inputs.kubenix.url = "github:hall/kubenix";)

--- builds ---
system:
  let ... in { inherit vm shell serviceShells; }

--- packages ---
{ vm = (builds system).vm; }

--- apps ---
{ vm = { type = "app"; program = "${(builds system).vm}/bin/run-lips-vm"; }; }

--- devShells ---
{ default = (builds system).shell; } // (builds system).serviceShells

--- rungs ---
run in a VM         | run     | vm  | (full system, all services; needs KVM)
build the system    | build   | vm  | (checks it builds; no KVM)
a shell of its tools| develop | .   | (what the config puts on PATH)
```

### Slot Contracts

| Slot | Type | In scope | Read by |
|---|---|---|---|
| `preamble` | markdown | -- | generate |
| `schema` | Nix expression, evaluates to a derivation whose output is canonical options JSON | `<flakeref>` | generate, options |
| `inputs` | flake input lines | -- | compile |
| `builds` | Nix function of `system` | `nixpkgs`, `pkgsFor`, world inputs | compile |
| `packages` | Nix attrset expression | `system`, `builds`, `pkgsFor` | compile |
| `apps` | Nix attrset expression | same | compile |
| `devShells` | Nix attrset expression | same | compile |
| `rungs` | lines: `label \| verb \| attr \| note`, or a literal line | -- | compile |
| `module-attr` | identifier | -- | compile |
| `claims` | list of claim kinds the world can host | -- | generate, check |

Two fixed names carry the whole interface: the binding is always `builds` and
it is always a function of `system`. One name means no world may invent one, so
two worlds can never collide and a reader knows where to look.

`rungs` needs two forms because home-manager's rung is not a command at all: it
prints `imports = [ <dir> ];`. So a rung is either a command (label, verb,
attribute, note) or a literal line. Two forms, closed.

### Knob 4 Disappears Into the Schema Slot

The `schema` slot evaluates to a *derivation whose output is canonical options
JSON*, so any reshaping a world needs happens in Nix (or in `jq` inside that
derivation), where the world author can do it, and lips keeps exactly one
parser (`parseNixOptionsJson`). kubenix's 85 lines of Haskell (re-key an alias,
drop inner nodes, unwrap optionals) become a transformation in its own world
file.

**Risk, stated rather than assumed:** that this rewrite is feasible in Nix or
`jq` at acceptable cost is untested. If it turns out not to be, the honest
fallback is a `schema-shape:` header naming one of a small closed set of
document shapes, which is a much smaller enumeration than a world list, and it
is about JSON document shapes rather than about worlds.

## The Trust Question, Answered Rather Than Avoided

A world file is arbitrary Nix at declared points, which is exactly what the
backlog item feared: "a plugin's harness is arbitrary Nix, i.e. an
arbitrary-code channel into compiled output, while the closed set keeps every
world reviewed in-tree."

Two facts blunt it. The file is committed, hashed into `.generation` and
reviewed like any human artifact. And `artifacts/` already puts AI-*written*
source into compiled output today, so human-written Nix at declared slots is
strictly better provenance than what lips already ships. The trust boundary
moves from "lips' release process" to "your repo's review", which is where the
program and the engine already sit.

## What This Does Not Decide

- **Multi-target engine layout.** One language with several backends needs a
  split between what is shared across worlds (the patterns, which are the
  cross-world contract) and what is per world (rules, demands, `.expect`).
  Open, discussed separately.
- **Cross-world composition.** A program naming another program's output
  (`export.*`, `${program.<instance>.<path>}`) is a different axis and unrelated
  to world files. See the backlog item "Cross-program composition".
- **A migration path** for the four in-tree worlds, the `.generation` records
  that name them, and `lib.modulesFromDir`'s per-world attribute names.

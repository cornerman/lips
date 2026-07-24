# TODO

## Next up (priority order)

1. **Behavioral gate enforced at every deterministic verb — DONE (2026-07-24).**
   `check` is the gate alone; `compile` gates then writes; `run` gates then
   boots (nixos `runVm` and `compileLoose` both call the same gate and die on a
   violation before their side effect; home-manager `run` gates too). So the
   headline offline verb never emits or boots a module that dropped a pinned
   value (Failproof: the safe path is the obvious path). Nix is the compile
   target, so the gate's `nix eval` is no new dependency and the emitted module
   stays bit-identical. See DESIGN §13 Partial entry.

2. **Gap report (`<program>.gap`)** — §13 Missing, tagged "cheap; do soon".
   When `generate` refuses because physics is missing, write a machine-readable
   artifact (refused lines, missing capability / extension point, minimal repro,
   model+prompt fingerprint) instead of on-screen-only text. Operationalizes the
   cross-repo escalation workflow (DESIGN Doctrine).

3. **Live host deployment** — the headline missing proof (§13 Shortest Summary).
   Wire one realized module into `~/nixos` on `wolf`. Reduced to "import one
   file"; proves survival on a real system, not just a VM boot.

4. **Template grammar completeness** (completeness plan Target 2). The value
   grammar is complete-by-construction over the Nix value algebra minus
   computation; the template grammar is only "complete over observed line
   shapes" — a weaker, honest claim. Missing capture forms: unquoted multi-token
   holes (bind several words up to a literal), and true parent-child block
   aggregation (a decision owning a list). Close these to make the template
   claim match the value claim.

## Backlog (larger / deferred by design)

- **Glue** — the one deliberate incompleteness (computation inside the decision
  layer). `Glue` is a `Kind` with no rigor-downgrade mechanism. Blocks a
  *computed value*, not building a program (that is artifacts, done).
- **Artifacts: templated source** — source is a fixed blob baked at generate; a
  value that must appear inside the compiled program needs regeneration, not a
  `compile`-time flow. Also: dependency-fetching builders (cargo/vendor hashes)
  untried.
- **Language migration** — no diff/migration path when a `.lang` regenerates to
  a different shape.
- **Multi-language composition** — the prototype runs one engine; composing
  several languages in one Solution is unbuilt (dual of instance reuse).
- **Kernel modules** — loadable, test-gated units extending the closed grammars
  at declared extension points (successor of the vocabulary milestone).
- **Guarantee lifecycle** — the assumption `OPEN -> GUARANTEED` flow has no code.
- **Heile-Welt coping** — no mechanism yet; reality mismatches (GPU present,
  driver loads) surface at runtime, outside the kernel's determinism boundary.

## Housekeeping / smells

- `stripTailPunct` (`Kernel/Engine/Value.hs`) duplicates `stripTrailingPunct`
  (`Kernel/Lang/Pattern.hs`) — same rule, two copies kept "in step" by comment.
  A shared definition would remove the drift risk (the comment flags it).

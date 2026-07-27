# lips — command index. The deliverable (calculus + suite) lives in kernel/;
# examples/ holds demonstration programs; the flake ties them together.
# Recipes are thin wrappers over nix so nothing is installed globally.

# Recipes run from the justfile directory (repo root), where the flake lives.
# Using "." (not "path:.") keeps nix on git semantics, so untracked runtime
# dirs like .corral stay out of the flake tree.

# List available recipes.
default:
    @just --list

# Build the lips binary (nix package) and print its path.
build:
    nix build . --print-out-paths

# Run the conformance suite (fast: compiles Spec.hs in the dev shell).
test:
    nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs \
      -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'

# Full verification: conformance suite + VM boot of the realized module.
# This is the CI gate (nothing calls it automatically yet -- run it by hand
# before a merge); named `ci`, not `check*`, since it is not the same check
# as `lips check` (that one program-vs-contract verb is the `check` recipe
# and `check-expect` below, both host-side and KVM-free).
ci:
    nix flake check -L

# Behavioral contracts: every example's .expect must hold against its realized
# module (relational option-value gate, ledger 13). Host-side (uses nix eval),
# no KVM. This is the same check generate runs before accepting an engine.
check-expect:
    #!/usr/bin/env bash
    set -euo pipefail
    # Programs are <instance>.<language>.lips (the .lips marker is what every
    # editor and language server associates) and are the only files at this
    # level: everything minted lives in the <language>/ folder beside them.
    for p in examples/*.lips; do
      nix run . -- check "$p"
    done

# Deterministic realize: program + .lang -> a module directory (default.nix +
# artifacts/), no model, offline. Writes <language>/out/<instance>/ by default.
compile program:
    nix run . -- compile "{{program}}"

# Running is not a lips verb: `compile` prints the exact `nix run`/`nix build`
# commands over the compiled dir (exec/shell for an artifact, container/vm for a
# system module). Run one of those printed commands to run the program.

# Verify one program's committed behavioral contract against its realized module.
# Mirrors `lips check <program>` one-to-one; the full suite is `just ci`.
check program:
    nix run . -- check "{{program}}"

# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{model}}" ]; then
      nix run . -- generate --model "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi

# Look an option path or a domain word up in the pinned schema: the same lookup
# the mint gets through its one tool, so you can see exactly what it would read.
# Read-only, no AI.
options query target="nixos":
    nix run . -- options --target "{{target}}" "{{query}}"

# Rebuild only the VM smoke check with streamed logs (needs KVM).
vm-smoke:
    nix build .#checks.x86_64-linux.vm-smoke -L

# Drop into the dev shell (ghc with hspec/QuickCheck + just on PATH).
shell:
    nix develop

# Remove local build artifacts (nix outputs live in /tmp and the store).
clean:
    rm -rf /tmp/lips-build /tmp/lips-spec result

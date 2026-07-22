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
check:
    nix flake check -L

# Behavioral contracts: every example's .expect must hold against its realized
# module (relational option-value gate, ledger 13). Host-side (uses nix eval),
# no KVM. This is the same check generate runs before accepting an engine.
check-expect:
    #!/usr/bin/env bash
    set -euo pipefail
    for p in examples/*.loose; do
      nix run . -- check "$p"
    done

# Deterministic realize: program + .lang -> NixOS module text (no model, offline).
print program:
    nix run . -- print "{{program}}"

# Literally run: realize the program and boot it as a local NixOS VM (needs KVM).
run program:
    nix run . -- run "{{program}}"

# Verify one program's committed behavioral contract against its realized module.
check-program program:
    nix run . -- check "{{program}}"

# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Deduce-or-fail: generate checks every minted rule against the pinned
    # NixOS option schema (built from this flake's nixpkgs).
    export LIPS_OPTIONS_JSON="$(nix build .#nixosOptionsJson --no-link --print-out-paths)/share/doc/nixos/options.json"
    if [ -n "{{model}}" ]; then
      nix run . -- generate "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi

# Rebuild only the VM smoke check with streamed logs (needs KVM).
vm-smoke:
    nix build .#checks.x86_64-linux.vm-smoke -L

# Drop into the dev shell (ghc with hspec/QuickCheck + just on PATH).
shell:
    nix develop

# Remove local build artifacts (nix outputs live in /tmp and the store).
clean:
    rm -rf /tmp/lips-build /tmp/lips-spec result

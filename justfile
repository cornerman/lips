# lips — command index. Everything runs against the reference implementation
# in kernel/; recipes are thin wrappers over nix so nothing is installed
# globally.

kernel := justfile_directory() / "kernel"

# List available recipes.
default:
    @just --list

# Build the lips binary (nix package) and print its path.
build:
    nix build "path:{{kernel}}" --print-out-paths

# Run the conformance suite (fast: compiles Spec.hs in the dev shell).
test:
    cd {{kernel}} && nix develop -c ghc -Wall -isrc -itest test/Spec.hs \
      -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec

# Full verification: conformance suite + VM boot of the realized module.
check:
    cd {{kernel}} && nix flake check -L

# Deterministic run: program + .lang -> NixOS module (no model, offline).
run program:
    nix run "path:{{kernel}}" -- run "{{program}}"

# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{model}}" ]; then
      nix run "path:{{kernel}}" -- generate "{{model}}" "{{program}}"
    else
      nix run "path:{{kernel}}" -- generate "{{program}}"
    fi

# Rebuild only the VM smoke check with streamed logs (needs KVM).
vm-smoke:
    cd {{kernel}} && nix build .#checks.x86_64-linux.vm-smoke -L

# Drop into the dev shell (ghc with hspec/QuickCheck on PATH).
shell:
    cd {{kernel}} && nix develop

# Remove local build artifacts (kernel outputs live in /tmp and the store).
clean:
    rm -rf /tmp/lips-build /tmp/lips-spec {{kernel}}/result

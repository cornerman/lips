#!/usr/bin/env bash
# Run the claims over single definitions. No VM, no build, no binary.
set -euo pipefail
GJ=$(nix build --no-link --print-out-paths nixpkgs#guile-json)
cd "$(dirname "$0")"
exec nix shell nixpkgs#guile --command env \
  GUILE_LOAD_PATH="$GJ/share/guile/site/3.0" \
  GUILE_LOAD_COMPILED_PATH="$GJ/lib/guile/3.0/site-ccache" \
  guile --no-auto-compile -s claims.scm

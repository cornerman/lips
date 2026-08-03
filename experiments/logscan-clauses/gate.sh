#!/usr/bin/env bash
# The subset gate over the minted core. No adapter is linked: it reads the
# clauses as data, so nothing runs.
set -euo pipefail
cd "$(dirname "$0")"
exec nix shell nixpkgs#guile --command guile --no-auto-compile -s gate.scm

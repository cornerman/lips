#!/usr/bin/env bash
# One offline probe: copy an engine folder beside an edited program, compile,
# build and run the program's own executable. No model anywhere.
set -u
L=/tmp/lips-plurality-exp-result/bin/lips
# usage: probe.sh <engine folder> <name> <program line>...
eng=$1; name=$2; shift 2
d=/tmp/lips-plurality-exp/probe/$name
rm -rf "$d"; mkdir -p "$d"; cp -r "$eng" "$d/function"; rm -rf "$d/function/out"
printf '%s\n' "$@" > "$d/function.lips"
cd "$d"
if $L compile function.lips > compile.log 2>&1; then
  out=$(nix run path:./function/out/function/nixos#site 2>run.err | tr '\n' '|')
  echo "$name: compiled; runs -> [$out]"
else
  echo "$name: REFUSED: $(grep -E 'no match|refus|fail|✗|error' compile.log | head -3 | tr '\n' ' ')"
fi

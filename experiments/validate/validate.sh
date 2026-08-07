#!/usr/bin/env bash
# Validate every clause scenario end to end: compile it, build its site, run it
# against a table of cases, and report each case as ok or FAIL.
#
# This is the loop that answers "does the direction hold", so it runs the REAL
# path: lips compile, nix build, a process fed on stdin. Nothing is stubbed.
#
#   ./validate.sh              every scenario
#   ./validate.sh tally        one of them
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
lips=${LIPS_BIN:-lips}
only=${1:-}
total=0; bad=0

for dir in "$here"/scenarios/*/; do
  name=$(basename "$dir")
  [ -n "$only" ] && [ "$only" != "$name" ] && continue
  prog=$(ls "$dir"/*.lips 2>/dev/null | head -1)
  [ -z "$prog" ] && { echo "== $name: no program"; bad=$((bad+1)); continue; }
  echo "== $name"

  if ! out=$("$lips" compile "$prog" 2>&1); then
    echo "   COMPILE FAILED"; echo "$out" | tail -5 | sed 's/^/   /'
    bad=$((bad+1)); continue
  fi
  outdir=$(printf '%s' "$out" | grep -o 'path:[^ ]*#site' | head -1 | sed 's/^path://; s/#site$//')
  if [ -z "$outdir" ]; then
    echo "   NO SITE (a configuration-only program states no behaviour)"
    continue
  fi
  if ! store=$(nix build --no-link --print-out-paths "path:$outdir#site" 2>&1 | tail -1); then
    echo "   BUILD FAILED"; echo "$store" | tail -5 | sed 's/^/   /'
    bad=$((bad+1)); continue
  fi
  # The site is installed under the name the PROGRAM chose ("install the tool as
  # the command x"), which is the same name the realized module binds. So the
  # binary is found rather than assumed: hardcoding bin/site passed only while
  # the flake and the module disagreed about what to call the thing.
  bins=("$store"/bin/*)
  if [ "${#bins[@]}" -ne 1 ]; then
    echo "   EXPECTED ONE BINARY, got: ${bins[*]}"; bad=$((bad+1)); continue
  fi
  bin="${bins[0]}"

  # cases: one per line, | separated (NOT tab: bash strips a leading empty field
  # when IFS is whitespace, which silently shifts every column)
  #   args | stdin (\n for newline) | expected stdout (\n) | expected exit
  while IFS= read -r line; do
    # Skip a comment or a blank line by looking at the WHOLE line: an empty args
    # field is legitimate (a program run with no arguments), so testing the first
    # field instead would silently skip every such case.
    case "$line" in '#'*|'') continue;; esac
    IFS='|' read -r args stdin want code <<<"$line"
    got=$(printf '%b' "$stdin" | $bin $args 2>/dev/null); gotcode=$?
    wantText=$(printf '%b' "$want")
    total=$((total+1))
    if [ "$got" = "$wantText" ] && [ "$gotcode" = "$code" ]; then
      printf '   ok    %-16s %s\n' "[$args]" "$(printf '%b' "$stdin" | tr '\n' '~')"
    else
      bad=$((bad+1))
      printf '   FAIL  %-16s in=[%s] got=[%s|%s] want=[%s|%s]\n' \
        "[$args]" "$(printf '%b' "$stdin" | tr '\n' '~')" \
        "$(echo "$got" | tr '\n' '~')" "$gotcode" \
        "$(echo "$wantText" | tr '\n' '~')" "$code"
    fi
  done < "$dir/cases"
done

echo
echo "$total cases, $bad failures"
[ "$bad" = 0 ]

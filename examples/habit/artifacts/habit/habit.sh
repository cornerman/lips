#!/usr/bin/env bash
set -euo pipefail

habit="$1"
if [ "$#" -ge 2 ]; then
  input="$2"
else
  input="/dev/stdin"
fi

mindate=""
maxdate=""
declare -A seen

while IFS=$'\t' read -r d h; do
  [ -z "${d:-}" ] && continue
  if [ "$h" = "$habit" ]; then
    seen["$d"]=1
  fi
  if [ -z "$mindate" ] || [[ "$d" < "$mindate" ]]; then
    mindate="$d"
  fi
  if [ -z "$maxdate" ] || [[ "$d" > "$maxdate" ]]; then
    maxdate="$d"
  fi
done < "$input"

out=""
cur="$mindate"
end_epoch=$(date -d "$maxdate" +%s)
while [ -n "$cur" ] && [ "$(date -d "$cur" +%s)" -le "$end_epoch" ]; do
  if [ "${seen[$cur]:-}" = "1" ]; then
    out="${out}@present@"
  else
    out="${out}@absent@"
  fi
  cur=$(date -d "$cur + 1 day" +%Y-%m-%d)
done

printf '%s\n' "$out"
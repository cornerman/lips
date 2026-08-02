#!/usr/bin/env bash
set -euo pipefail

columns_raw="@columns@"
IFS=',' read -ra _cols <<< "$columns_raw"
columns=()
for c in "${_cols[@]}"; do
  c="${c# }"
  columns+=("$c")
done

input="$(cat "${1:-/dev/stdin}")"

declare -A cards
for col in "${columns[@]}"; do
  cards["$col"]=""
done

current=""
while IFS= read -r line; do
  if [[ "$line" == "## "* ]]; then
    current="${line#\#\# }"
  elif [[ "$line" == "- "* ]]; then
    text="${line#- }"
    if [[ -n "$current" ]]; then
      if [[ -z "${cards[$current]:-}" ]]; then
        cards["$current"]="$text"
      else
        cards["$current"]="${cards[$current]}, $text"
      fi
    fi
  fi
done <<< "$input"

for col in "${columns[@]}"; do
  if [[ -n "${cards[$col]:-}" ]]; then
    echo "$col: ${cards[$col]}"
  else
    echo "$col:"
  fi
done
#!/usr/bin/env bash
set -euo pipefail

LOG="@logpath@"
DAYS=@days@
HABIT="${1:-}"

if [ -z "$HABIT" ]; then
  echo "usage: $(basename "$0") <habit-name>" >&2
  exit 1
fi

declare -A seen
if [ -f "$LOG" ]; then
  while IFS=$'\t' read -r date name; do
    if [ "$name" = "$HABIT" ]; then
      seen["$date"]=1
    fi
  done < "$LOG"
fi

today=$(date +%Y-%m-%d)
for ((i = DAYS - 1; i >= 0; i--)); do
  day=$(date -d "$today - $i days" +%Y-%m-%d)
  if [ -n "${seen[$day]:-}" ]; then
    printf '#'
  else
    printf '.'
  fi
done
printf '\n'
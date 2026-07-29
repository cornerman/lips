#!/usr/bin/env bash
set -euo pipefail

FILE="@BOARD_PATH@"
COLUMNS_RAW="@COLUMNS@"

IFS=',' read -ra COLS <<< "$COLUMNS_RAW"

for col in "${COLS[@]}"; do
  col_trimmed="$(echo "$col" | sed 's/^ *//;s/ *$//')"
  echo "=== ${col_trimmed} ==="
  awk -v section="$col_trimmed" '
    BEGIN { show = 0 }
    /^##[ \t]*/ {
      title = $0
      sub(/^##[ \t]*/, "", title)
      show = (title == section) ? 1 : 0
      next
    }
    show && NF > 0 { print "  - " $0 }
  ' "$FILE"
  echo
done
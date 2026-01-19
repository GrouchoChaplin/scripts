#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./insert_headers.sh native
#
# Result:
#   // === native/libs/CMakeLists.txt ===
#   // === native/libs/GDALUtils/GDALUtils.cpp ===
#   ...

TOPDIR="${1:?Usage: $0 <topdir>}"
TOPDIR="${TOPDIR%/}"

PARENT_DIR="$(dirname "$TOPDIR")"
BASE_DIR="$(basename "$TOPDIR")"

# Only touch these file types (extend as needed)
EXTENSIONS=(
  '*.c'
  '*.h'
  '*.cpp'
  '*.hpp'
  'CMakeLists.txt'
)

# Build find expression
FIND_EXPR=()
for ext in "${EXTENSIONS[@]}"; do
  FIND_EXPR+=( -name "$ext" -o )
done
unset 'FIND_EXPR[-1]'

(
  cd "$PARENT_DIR" || exit 1

  find "$BASE_DIR" -type f \( "${FIND_EXPR[@]}" \) \
    | LC_ALL=C sort \
    | while IFS= read -r file; do

        header="// === $file ==="

        # If first line already matches header, skip
        if head -n 1 "$file" | grep -Fqx "$header"; then
          continue
        fi

        tmp="$(mktemp)"

        {
          echo "$header"
          echo
          cat "$file"
        } > "$tmp"

        mv "$tmp" "$file"
      done
)

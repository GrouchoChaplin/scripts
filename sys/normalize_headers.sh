#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./normalize_headers.sh <topdir>

TOPDIR="${1:?Usage: $0 <topdir>}"
TOPDIR="${TOPDIR%/}"

PARENT_DIR="$(dirname "$TOPDIR")"
BASE_DIR="$(basename "$TOPDIR")"

EXTENSIONS=(
  '*.c'
  '*.h'
  '*.cpp'
  '*.hpp'
  'CMakeLists.txt'
  '*.cmake'
  '*.sh'
  '*.py'
)

# Any legacy header: // === ... ===  or  # === ... ===

(
  cd "$PARENT_DIR" || exit 1

  find "$BASE_DIR" -type f \( \
    -name '*.c' -o \
    -name '*.h' -o \
    -name '*.cpp' -o \
    -name '*.hpp' -o \
    -name 'CMakeLists.txt' -o \
    -name '*.cmake' -o \
    -name '*.sh' -o \
    -name '*.py' \
  \) \
  | LC_ALL=C sort \
  | while IFS= read -r file; do

      # Choose correct comment style
      case "$file" in
        *.c|*.h|*.cpp|*.hpp)
          COMMENT='//'
          ;;
        *)
          COMMENT='#'
          ;;
      esac

      new_header="$COMMENT === $file ==="
      tmp="$(mktemp)"

      awk -v header="$new_header" '
        NR == 1 {
          # If first line is an old header, replace it
          if ($0 ~ /^[[:space:]]*(\/\/|#)[[:space:]]*=== .* ===$/) {
            print header
            print ""
            next
          }
          # Otherwise, insert header before content
          print header
          print ""
        }
        { print }
      ' "$file" > "$tmp"

      if ! cmp -s "$tmp" "$file"; then
        mv "$tmp" "$file"
      else
        rm "$tmp"
      fi
    done
)

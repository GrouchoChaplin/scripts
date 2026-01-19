#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./list_relative.sh native
# Output:
#   native/apps/CMakeLists.txt

TOPDIR="${1:?Usage: $0 <topdir>}"

# Normalize: strip trailing slash
TOPDIR="${TOPDIR%/}"

# Extract parent + basename
PARENT_DIR="$(dirname "$TOPDIR")"
BASE_DIR="$(basename "$TOPDIR")"

# Run from parent so BASE_DIR is preserved
(
  cd "$PARENT_DIR" || exit 1
  find "$BASE_DIR" -type f -printf '%p\n'
)

#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# latest_dart.sh
#
# Find the most recently modified Dart files.
#
# Defaults:
#   - tracked files only
#   - roots: lib test generated
#   - show 1 file
#
# Options:
#   -a, --all           Include untracked files (use find)
#   -n, --num N         Number of files to list (use "all" for no limit)
#   -h, --help          Show help
#
# Usage:
#   ./latest_dart.sh
#   ./latest_dart.sh --all
#   ./latest_dart.sh -n 5
#   ./latest_dart.sh --all -n all lib test
# ------------------------------------------------------------

show_help() {
  cat <<EOF
Usage: latest_dart.sh [OPTIONS] [ROOTS...]

Options:
  -a, --all           Include untracked files
  -n, --num N         Number of files to list (default: 1, use 'all' for unlimited)
  -h, --help          Show this help

Roots (default):
  lib test generated

Examples:
  latest_dart.sh
  latest_dart.sh -n 5
  latest_dart.sh --all
  latest_dart.sh --all -n all lib test
EOF
}

# -----------------------
# Defaults
# -----------------------
TRACKED_ONLY=true
NUM=1
ROOTS=(lib test generated)

# -----------------------
# Parse args
# -----------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--all)
      TRACKED_ONLY=false
      shift
      ;;
    -n|--num)
      NUM="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      ROOTS=("$@")
      break
      ;;
  esac
done

# -----------------------
# Sanity checks
# -----------------------
if $TRACKED_ONLY; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "❌ Not inside a git repository (required for tracked-only mode)"
    exit 1
  }
fi

# -----------------------
# Collect files
# -----------------------
if $TRACKED_ONLY; then
  FILES=$(git ls-files "${ROOTS[@]}" | grep -E '\.dart$' || true)
else
  FILES=$(find "${ROOTS[@]}" -type f -iname '*.dart' 2>/dev/null || true)
fi

# -----------------------
# Emit timestamps
# -----------------------
RESULTS=$(echo "$FILES" | while read -r f; do
  [[ -f "$f" ]] && printf '%s %s\n' "$(stat -c '%Y' "$f")" "$f"
done | sort -nr)

# -----------------------
# Output
# -----------------------
if [[ "$NUM" == "all" ]]; then
  echo "$RESULTS" | cut -d' ' -f2-
else
  echo "$RESULTS" | head -n "$NUM" | cut -d' ' -f2-
fi

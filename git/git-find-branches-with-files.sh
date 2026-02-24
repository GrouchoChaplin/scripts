#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# git-find-branches-with-files.sh
#
# Find branches that contain files matching
# a given regex pattern, and report which
# files matched in which branches.
#
# Usage:
#   git-find-branches-with-files.sh 'Data/.*\.nvdb$'
#
# ----------------------------------------

PATTERN="${1:-}"

if [[ -z "$PATTERN" ]]; then
  echo "Usage: $0 <regex-pattern>"
  echo "Example: $0 'Data/.*\\.nvdb$'"
  exit 1
fi

# Collect all real branches (local + remote), skip symbolic refs
mapfile -t BRANCHES < <(
  git for-each-ref \
    --format='%(refname:short)' \
    refs/heads refs/remotes \
  | grep -v 'HEAD$'
)

TOTAL=${#BRANCHES[@]}
COUNT=0
MATCHED_BRANCHES=0

echo "🔍 Searching $TOTAL branches for pattern:"
echo "    $PATTERN"
echo

for BR in "${BRANCHES[@]}"; do
  COUNT=$((COUNT + 1))

  # Progress line (overwritten)
  printf "\r[%d/%d] Scanning %-45s" "$COUNT" "$TOTAL" "$BR"

  # Collect matches (tree-only, no checkout)
  MATCHES=$(git ls-tree -r --name-only "$BR" 2>/dev/null | grep -E "$PATTERN" || true)

  if [[ -n "$MATCHES" ]]; then
    printf "\n\n=== %s ===\n" "$BR"
    printf "%s\n" "$MATCHES"
    MATCHED_BRANCHES=$((MATCHED_BRANCHES + 1))
  fi
done

echo
echo
echo "✅ Done."
echo "Branches with matches: $MATCHED_BRANCHES / $TOTAL"

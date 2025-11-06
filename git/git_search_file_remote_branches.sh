#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# git_search_file_branches.sh
# Search all (or selected) branches for files matching a given path or pattern,
# showing the last commit date, hash, and author — sorted by commit date.
#
# Usage:
#   ./git_search_file_branches.sh <file_path_or_pattern> [options]
#
# Options:
#   --local-only       Search only local branches
#   --remote-only      Search only remote branches
#   --limit N          Show only the newest N results
#   --pattern          Treat input as a glob pattern (e.g., *.cpp)
#
# Example:
#   ./git_search_file_branches.sh src/main.cpp
#   ./git_search_file_branches.sh --pattern "*.sh" --limit 5
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Guard: prevent sourcing ---
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    echo "⚠️  This script should be executed, not sourced."
    return 1 2>/dev/null || exit 1
fi

# --- Default flags ---
SEARCH_LOCAL=true
SEARCH_REMOTE=true
LIMIT=0
USE_PATTERN=false

# --- Parse arguments ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <file_path_or_pattern> [--local-only|--remote-only] [--limit N] [--pattern]"
    exit 1
fi

FILE_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-only)
            SEARCH_REMOTE=false
            ;;
        --remote-only)
            SEARCH_LOCAL=false
            ;;
        --limit)
            LIMIT="$2"
            shift
            ;;
        --pattern)
            USE_PATTERN=true
            ;;
        -*)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
        *)
            FILE_PATH="$1"
            ;;
    esac
    shift
done

if [[ -z "$FILE_PATH" ]]; then
    echo "❌ Missing file path or pattern argument."
    exit 1
fi

# --- Ensure inside Git repo ---
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ Not inside a Git repository."
    exit 1
fi

# --- Fetch remotes if needed ---
if $SEARCH_REMOTE; then
    echo "🔄 Fetching all remote branches..."
    git fetch --quiet --all --prune
fi

echo
echo "🔍 Searching for: $FILE_PATH"
echo "──────────────────────────────────────────────"

TMPFILE=$(mktemp)

# --- Collect branches ---
BRANCHES=""
if $SEARCH_LOCAL; then
    BRANCHES+=$(git for-each-ref --format='%(refname:short)' refs/heads)
    BRANCHES+=" "
fi
if $SEARCH_REMOTE; then
    BRANCHES+=$(git for-each-ref --format='%(refname:short)' refs/remotes)
fi

# --- Iterate over all branches ---
for branch in $BRANCHES; do
    FILE_LIST=$(git ls-tree -r "$branch" --name-only || true)
    if $USE_PATTERN; then
        MATCHED=$(grep -E "$(echo "$FILE_PATH" | sed 's/\*/.*/g')" <<< "$FILE_LIST" || true)
    else
        MATCHED=$(grep -Fx "$FILE_PATH" <<< "$FILE_LIST" || true)
    fi

    if [[ -n "$MATCHED" ]]; then
        for f in $MATCHED; do
            info=$(git log -1 --pretty=format:"%ci|%h|%an" "$branch" -- "$f" 2>/dev/null || true)
            if [[ -n "$info" ]]; then
                printf "%s|%s|%s\n" "$branch" "$f" "$info" >> "$TMPFILE"
            fi
        done
    fi
done

if [[ ! -s "$TMPFILE" ]]; then
    echo "⚠️  No matches found for '$FILE_PATH'."
    rm -f "$TMPFILE"
    exit 0
fi

# --- Sort results by date (newest → oldest) ---
SORTED=$(sort -r -t'|' -k4,4 "$TMPFILE")

# --- Limit results if requested ---
if (( LIMIT > 0 )); then
    SORTED=$(head -n "$LIMIT" <<< "$SORTED")
fi

# --- Find newest branch for highlighting ---
LATEST_BRANCH=$(head -n 1 <<< "$SORTED" | cut -d'|' -f1)
LATEST_FILE=$(head -n 1 <<< "$SORTED" | cut -d'|' -f2)

# --- Color codes ---
GREEN="\033[1;32m"
RESET="\033[0m"

echo
echo "📜 Branches containing '$FILE_PATH' (sorted by last commit date):"
echo "──────────────────────────────────────────────"
echo
printf "%-35s %-40s %-22s %-10s %-15s\n" "Branch" "File" "Commit Date" "Hash" "Author"
printf "%-35s %-40s %-22s %-10s %-15s\n" "──────────────────────────" "───────────────────────────────" "──────────────────────" "──────────" "────────────"

while IFS='|' read -r branch file date hash author; do
    if [[ "$branch" == "$LATEST_BRANCH" && "$file" == "$LATEST_FILE" ]]; then
        printf "${GREEN}%-35s %-40s %-22s %-10s %-15s${RESET}\n" "$branch" "$file" "$date" "$hash" "$author"
    else
        printf "%-35s %-40s %-22s %-10s %-15s\n" "$branch" "$file" "$date" "$hash" "$author"
    fi
done <<< "$SORTED"

echo
echo "✅ Newest version of '$FILE_PATH' is in: ${GREEN}${LATEST_BRANCH}${RESET}"
echo

rm -f "$TMPFILE"

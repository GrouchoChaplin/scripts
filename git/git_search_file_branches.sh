#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# git_search_file_branches.sh
# Search all (or selected) branches for a file or pattern, showing commit info.
#
# Usage:
#   ./git_search_file_branches.sh <file_or_pattern> [options]
#
# Options:
#   --local-only       Search only local branches
#   --remote-only      Search only remote branches
#   --limit N          Show only newest N results
#   --pattern          Treat <file_or_pattern> as glob (*.cpp)
#   --since DATE       Show only commits after this date (YYYY-MM-DD)
#   --committer        Show committer instead of author
#
# Example:
#   ./git_search_file_branches.sh src/main.cpp
#   ./git_search_file_branches.sh --pattern "*.cpp" --limit 5 --since 2024-01-01
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Guard: prevent sourcing ---
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    echo "⚠️  This script should be executed, not sourced."
    return 1 2>/dev/null || exit 1
fi

# --- Defaults ---
SEARCH_LOCAL=true
SEARCH_REMOTE=true
LIMIT=0
USE_PATTERN=false
SINCE_DATE=""
USE_COMMITTER=false

# --- Parse args ---
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <file_or_pattern> [--local-only|--remote-only] [--limit N] [--pattern] [--since YYYY-MM-DD] [--committer]"
    exit 1
fi

FILE_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --local-only) SEARCH_REMOTE=false ;;
        --remote-only) SEARCH_LOCAL=false ;;
        --limit) LIMIT="$2"; shift ;;
        --pattern) USE_PATTERN=true ;;
        --since) SINCE_DATE="$2"; shift ;;
        --committer) USE_COMMITTER=true ;;
        -*)
            echo "❌ Unknown option: $1"
            exit 1 ;;
        *)
            FILE_PATH="$1" ;;
    esac
    shift
done

if [[ -z "$FILE_PATH" ]]; then
    echo "❌ Missing file or pattern argument."
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
[[ -n "$SINCE_DATE" ]] && echo "📅 Since: $SINCE_DATE"
[[ $USE_COMMITTER == true ]] && echo "👤 Showing committer instead of author"
echo "──────────────────────────────────────────────"

TMPFILE=$(mktemp)

# --- Gather branch list ---
BRANCHES=""
if $SEARCH_LOCAL; then
    BRANCHES+=$(git for-each-ref --format='%(refname:short)' refs/heads)
    BRANCHES+=" "
fi
if $SEARCH_REMOTE; then
    BRANCHES+=$(git for-each-ref --format='%(refname:short)' refs/remotes)
fi

# --- Iterate branches ---
for branch in $BRANCHES; do
    FILE_LIST=$(git ls-tree -r "$branch" --name-only || true)
    if $USE_PATTERN; then
        MATCHED=$(grep -E "$(echo "$FILE_PATH" | sed 's/\*/.*/g')" <<< "$FILE_LIST" || true)
    else
        MATCHED=$(grep -Fx "$FILE_PATH" <<< "$FILE_LIST" || true)
    fi

    if [[ -n "$MATCHED" ]]; then
        for f in $MATCHED; do
            if $USE_COMMITTER; then
                FORMAT="%ci|%h|%cn"
            else
                FORMAT="%ci|%h|%an"
            fi

            if [[ -n "$SINCE_DATE" ]]; then
                info=$(git log -1 --since="$SINCE_DATE" --pretty=format:"$FORMAT" "$branch" -- "$f" 2>/dev/null || true)
            else
                info=$(git log -1 --pretty=format:"$FORMAT" "$branch" -- "$f" 2>/dev/null || true)
            fi

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

# --- Sort newest → oldest ---
SORTED=$(sort -r -t'|' -k4,4 "$TMPFILE")

# --- Limit results ---
if (( LIMIT > 0 )); then
    SORTED=$(head -n "$LIMIT" <<< "$SORTED")
fi

# --- Highlight newest ---
LATEST_BRANCH=$(head -n 1 <<< "$SORTED" | cut -d'|' -f1)
LATEST_FILE=$(head -n 1 <<< "$SORTED" | cut -d'|' -f2)

# --- Colors ---
GREEN="\033[1;32m"
RESET="\033[0m"

echo
echo "📜 Branches containing '$FILE_PATH' (sorted by last commit date):"
echo "──────────────────────────────────────────────"
echo
printf "%-35s %-40s %-22s %-10s %-20s\n" "Branch" "File" "Commit Date" "Hash" "User"
printf "%-35s %-40s %-22s %-10s %-20s\n" "──────────────────────────" "───────────────────────────────" "──────────────────────" "──────────" "────────────────────"

while IFS='|' read -r branch file date hash user; do
    if [[ "$branch" == "$LATEST_BRANCH" && "$file" == "$LATEST_FILE" ]]; then
        printf "${GREEN}%-35s %-40s %-22s %-10s %-20s${RESET}\n" "$branch" "$file" "$date" "$hash" "$user"
    else
        printf "%-35s %-40s %-22s %-10s %-20s\n" "$branch" "$file" "$date" "$hash" "$user"
    fi
done <<< "$SORTED"

echo
echo "✅ Newest version of '$FILE_PATH' is in: ${GREEN}${LATEST_BRANCH}${RESET}"
echo

rm -f "$TMPFILE"

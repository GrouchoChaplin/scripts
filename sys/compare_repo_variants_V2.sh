#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# DEFAULTS
# ────────────────────────────────────────────────────────────────
ROOT="."
REPO=""
OUTPUT=""
SORT="timestamp"
BEST=""
TMPFILE=$(mktemp)

# Colors
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ────────────────────────────────────────────────────────────────
usage() {
cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [options]

Options:
  --output json       Output JSON
  --output csv        Output CSV
  --sort timestamp    Sort by newest commit (default)
  --sort name         Sort by repo path name
  --sort dirty        Dirty repos first
  --best              Highlight BEST VERSION repo
  -h, --help          Show help

Example:
  $0 --root-folder /backup/Nightly --repo-name jsig.optimized_shader --best
EOF
exit 1
}

# ────────────────────────────────────────────────────────────────
# ARGUMENT PARSE
# ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in

        --root-folder)
            ROOT="$2"; shift 2;;
        --repo-name)
            REPO="$2"; shift 2;;
        --output)
            OUTPUT="$2"; shift 2;;
        --sort)
            SORT="$2"; shift 2;;
        --best)
            BEST="yes"; shift;;
        -h|--help)
            usage;;
        *)
            echo "Unknown option: $1"; usage;;
    esac
done

[[ -z "$REPO" ]] && { echo "❌ Missing --repo-name"; usage; }
[[ ! -d "$ROOT" ]] && { echo "❌ Root folder does not exist: $ROOT"; exit 1; }

echo -e "🔍 Searching: $CYAN$ROOT$RESET"
echo -e "🔎 Looking for repos matching: $YELLOW${REPO}*$RESET"
echo

# ────────────────────────────────────────────────────────────────
# FIND CANDIDATES
# ────────────────────────────────────────────────────────────────
mapfile -t DIRS < <(
    find "$ROOT" -maxdepth 8 -type d -name "${REPO}*" -not -path "*/.git/*"
)

if [[ ${#DIRS[@]} -eq 0 ]]; then
    echo "❌ No matching directories found."
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# PROCESS CANDIDATES
# ────────────────────────────────────────────────────────────────
for dir in "${DIRS[@]}"; do
    [[ ! -d "$dir/.git" ]] && continue

    pushd "$dir" >/dev/null

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    hash=$(git rev-parse --short HEAD)
    timestamp=$(git log -1 --format="%ct" 2>/dev/null || echo "0")
    timestamp_hr=$(git log -1 --format="%ci" 2>/dev/null || echo "NO COMMITS")

    # dirty?
    dirty="clean"
    if [[ -n "$(git status --porcelain)" ]]; then
        dirty="dirty"
    fi

    # ahead/behind?
    ahead="0"
    behind="0"
    if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
        ahead=$(git rev-list --left-only --count @{u}...HEAD)
        behind=$(git rev-list --right-only --count @{u}...HEAD)
    fi

    # Write row to temp file (sort-safe structured)
    echo -e "$timestamp\t$dir\t$branch\t$hash\t$dirty\t$ahead\t$behind\t$timestamp_hr" >> "$TMPFILE"

    popd >/dev/null
done

# ────────────────────────────────────────────────────────────────
# SORTING
# ────────────────────────────────────────────────────────────────
case "$SORT" in
    timestamp)
        sortcmd="sort -nr" ;;  # newest first
    name)
        sortcmd="sort -k2" ;;
    dirty)
        sortcmd="sort -k5" ;;
    *)
        sortcmd="sort -nr" ;;  # default
esac

SORTED=$(mktemp)
eval "$sortcmd \"$TMPFILE\"" > "$SORTED"

# ────────────────────────────────────────────────────────────────
# BEST VERSION HEURISTIC
# ────────────────────────────────────────────────────────────────
BEST_PATH=""
if [[ "$BEST" == "yes" ]]; then
    # Heuristic:
    # 1. Dirty repos first
    # 2. Newest timestamp
    # 3. Repos ahead of others
    BEST_PATH=$(awk -F'\t' '{
        dirty=$5;
        ts=$1;
        ahead=$6;
        score = (dirty=="dirty"?1000:0) + (ahead*10) + ts;
        print score "\t" $2;
    }' "$SORTED" | sort -nr | head -n1 | cut -f2)
fi

# ────────────────────────────────────────────────────────────────
# COLORIZED TERMINAL OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ -z "$OUTPUT" ]]; then
    printf "%-64s | %-20s | %-20s | %-8s | %-6s | %s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%s\n" "$(printf '—%.0s' {1..150})"

    while IFS=$'\t' read -r ts dir branch hash dirty ahead behind ts_hr; do
        if [[ "$dir" == "$BEST_PATH" ]]; then
            color=$GREEN
        elif [[ "$dirty" == "dirty" ]]; then
            color=$YELLOW
        else
            color=$CYAN
        fi

        printf "${color}%-64s${RESET} | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
            "$dir" "$branch" "$ts_hr" "$dirty" "$ahead" "$behind"

    done < "$SORTED"

    echo
    [[ -n "$BEST_PATH" ]] && echo -e "🏆 BEST VERSION: $GREEN$BEST_PATH$RESET"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# JSON OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "json" ]]; then
    echo "["

    first=true
    while IFS=$'\t' read -r ts dir branch hash dirty ahead behind ts_hr; do
        [[ $first == false ]] && echo ","
        first=false
        cat <<EOF
  {
    "repo_path": "$(echo "$dir")",
    "branch": "$branch",
    "last_commit": "$ts_hr",
    "timestamp": $ts,
    "dirty": "$dirty",
    "ahead": $ahead,
    "behind": $behind,
    "hash": "$hash",
    "best": "$( [[ "$dir" == "$BEST_PATH" ]] && echo true || echo false )"
  }
EOF
    done < "$SORTED"
    echo "]"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# CSV OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "csv" ]]; then
    echo "repo_path,branch,last_commit,timestamp,dirty,ahead,behind,hash,best"

    while IFS=$'\t' read -r ts dir branch hash dirty ahead behind ts_hr; do
        echo "\"$dir\",\"$branch\",\"$ts_hr\",$ts,\"$dirty\",$ahead,$behind,\"$hash\",\"$( [[ "$dir" == "$BEST_PATH" ]] && echo true || echo false )\""
    done < "$SORTED"
    exit 0
fi

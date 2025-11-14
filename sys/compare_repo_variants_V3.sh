#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# DEFAULTS
# ────────────────────────────────────────────────────────────────
ROOT="."
REPO=""
OUTPUT=""
BEST=""

TMPFILE=$(mktemp)
SORTED=$(mktemp)
FINAL=$(mktemp)

# ────────────────────────────────────────────────────────────────
# COLORS
# ────────────────────────────────────────────────────────────────
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
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
  --best              Highlight BEST VERSION repo
  -h, --help          Show help

Sort order (fixed):
  Dirty → Newest → Ahead → Behind → Alphabetical

Example:
  $0 --root-folder /run/media/.../Nightly --repo-name jsig.optimized_shader --best
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
        --best)
            BEST="yes"; shift;;
        -h|--help)
            usage;;
        *)
            echo "Unknown option: $1"
            usage;;
    esac
done

[[ -z "$REPO" ]] && { echo "❌ Missing --repo-name"; usage; }
[[ ! -d "$ROOT" ]] && { echo "❌ Root folder does not exist: $ROOT"; exit 1; }

echo -e "🔍 Searching: $CYAN$ROOT$RESET"
echo -e "🔎 Looking for repos matching: $YELLOW${REPO}*$RESET"
echo

# ────────────────────────────────────────────────────────────────
# FIND CANDIDATE DIRECTORIES
# ────────────────────────────────────────────────────────────────
mapfile -t DIRS < <(
    find "$ROOT" -maxdepth 8 -type d -name "${REPO}*" -not -path "*/.git/*"
)

if [[ ${#DIRS[@]} -eq 0 ]]; then
    echo "❌ No matching directories found."
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# PROCESS EACH REPO
# ────────────────────────────────────────────────────────────────
for dir in "${DIRS[@]}"; do
    [[ ! -d "$dir/.git" ]] && continue

    pushd "$dir" >/dev/null

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    hash=$(git rev-parse --short HEAD)
    ts_raw=$(git log -1 --format="%ct" 2>/dev/null || echo "0")
    ts_hr=$(git log -1 --format="%ci" 2>/dev/null || echo "NO COMMITS")

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

    # store required fields (tab-separated)
    # ts_raw   dir  branch  hash  dirty  ahead  behind  ts_hr
    echo -e "$ts_raw\t$dir\t$branch\t$hash\t$dirty\t$ahead\t$behind\t$ts_hr" \
        >> "$TMPFILE"

    popd >/dev/null
done

# ────────────────────────────────────────────────────────────────
# ADVANCED MULTI-LEVEL SORT
# Dirty → Newest → Ahead → Behind → Name
# ────────────────────────────────────────────────────────────────

awk -F'\t' '
{
    ts=$1; dir=$2; br=$3; hash=$4; dirty=$5; ahead=$6; behind=$7; ts_hr=$8;

    dirtflag = (dirty=="dirty" ? 1 : 0);

    # output sortable prefix + original line
    # dirtflag | ts | ahead | behind | dir | orig_line
    print dirtflag "\t" ts "\t" ahead "\t" behind "\t" dir "\t" $0;
}
' "$TMPFILE" \
| sort -t $'\t' -k1,1nr -k2,2nr -k3,3nr -k4,4n -k5,5 \
> "$SORTED"

# Strip off the sortable prefix (first 5 fields)
cut -f6- "$SORTED" > "$FINAL"

# ────────────────────────────────────────────────────────────────
# BEST VERSION CALCULATION
# ────────────────────────────────────────────────────────────────

BEST_PATH=""
if [[ "$BEST" == "yes" ]]; then
    # Score:
    # dirty*1000 + ahead*10 + timestamp – behind
    BEST_PATH=$(
        awk -F'\t' '
        {
            ts=$1; dir=$2; br=$3; hash=$4; dirty=$5; ahead=$6; behind=$7;
            d=(dirty=="dirty"?1:0);
            score = (d*1000) + (ahead*10) + ts - behind;
            print score "\t" dir;
        }' "$FINAL" \
        | sort -nr | head -n1 | cut -f2
    )
fi

# ────────────────────────────────────────────────────────────────
# COLORIZED HUMAN OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ -z "$OUTPUT" ]]; then
    printf "%-64s | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%s\n" "$(printf '—%.0s' {1..150})"

    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        if [[ "$dir" == "$BEST_PATH" ]]; then
            color=$GREEN
        elif [[ "$dirty" == "dirty" ]]; then
            color=$YELLOW
        else
            color=$CYAN
        fi

        printf "${color}%-64s${RESET} | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
            "$dir" "$br" "$ts_hr" "$dirty" "$ahead" "$behind"

    done < "$FINAL"

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
    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        [[ $first == false ]] && echo ","
        first=false
cat <<EOF
  {
    "repo_path": "$dir",
    "branch": "$br",
    "last_commit": "$ts_hr",
    "timestamp": $ts,
    "dirty": "$dirty",
    "ahead": $ahead,
    "behind": $behind,
    "hash": "$hash",
    "best": $( [[ "$dir" == "$BEST_PATH" ]] && echo "true" || echo "false" )
  }
EOF
    done < "$FINAL"
    echo "]"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# CSV OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "csv" ]]; then
    echo "repo_path,branch,last_commit,timestamp,dirty,ahead,behind,hash,best"
    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        echo "\"$dir\",\"$br\",\"$ts_hr\",$ts,\"$dirty\",$ahead,$behind,\"$hash\",\"$( [[ "$dir" == "$BEST_PATH" ]] && echo true || echo false )\""
    done < "$FINAL"
    exit 0
fi


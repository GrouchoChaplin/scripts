#!/usr/bin/env bash
# =============================================================================
# list_env_vars.sh
# =============================================================================
# 🧭 DESCRIPTION:
#   Lists environment variables (1 per line) in KEY=VALUE format.
#   Supports filtering (--grep), saving (--save), JSON export (--json),
#   diffing (--diff), summary (--summary), compact (--compact),
#   machine (--machine), timestamps (--timestamp), verbose (--verbose),
#   color control (--color=auto|always|never), and CI/CD exit codes.
#   Uses SCRIPT_LOGS environment variable for default save directory.
#
# 📦 VERSION:
#   v10.2 — 2025-11-10
#
# 💡 EXAMPLES:
#   ./list_env_vars.sh
#   ./list_env_vars.sh --grep PATH
#   ./list_env_vars.sh --save
#   ./list_env_vars.sh --diff ~/old_env.log
#   ./list_env_vars.sh --diff ~/old_env.log --compact
#   ./list_env_vars.sh --diff ~/old_env.log --machine
#   ./list_env_vars.sh --color=never --summary
#   ./list_env_vars.sh --verbose --timestamp
#
# 💻 EXIT CODES:
#   0  No differences or successful non-diff operation
#   1  Differences detected
#   2  Error (missing args, invalid file, etc.)
#
# =============================================================================

set -euo pipefail

SCRIPT_VERSION="10.2"
SCRIPT_DATE="2025-11-10"

# --- Defaults ---
GREP_FILTER=""
SAVE_LOG=false
JSON_OUTPUT=false
OUTFILE=""
DIFF_FILE=""
COLOR_MODE="auto"
SUMMARY_ONLY=false
VERBOSE=false
COMPACT=false
TIMESTAMP=false
MACHINE=false
EXIT_CODE=0

# --- ANSI colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

disable_colors() { RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""; }

# --- Timestamp helper ---
ts() { $TIMESTAMP && date -u "+[%Y-%m-%dT%H:%M:%SZ] "; }

# --- Usage ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --grep <pattern>        Filter environment vars matching <pattern>
  --save [<file>]         Save output to a log file (optional filename)
  --json                  Output current env as JSON
  --diff <file>           Compare current env to a previously saved file
  --summary               Show only counts of added/removed/changed vars
  --compact               One-line diff summary (+VAR, -VAR, ~VAR old→new)
  --machine               Output diff results as JSON (for automation)
  --timestamp             Prepend UTC timestamps to output lines
  --verbose               Print detailed mode and log path information
  --color=<mode>          Set color mode: auto (default), always, never
  --help, -h              Show this help message and exit

Environment Variables:
  SCRIPT_LOGS             Directory to save log files when using --save

Version:
  list_env_vars.sh v${SCRIPT_VERSION} (${SCRIPT_DATE})

Exit Codes:
  0 = no change or success
  1 = differences detected
  2 = error
EOF
    exit 0
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --grep) GREP_FILTER="${2:-}"; shift 2 ;;
        --save)
            SAVE_LOG=true
            if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
                OUTFILE="$2"; shift
            else
                LOG_DIR="${SCRIPT_LOGS:-$HOME}"
                mkdir -p "$LOG_DIR"
                OUTFILE="$LOG_DIR/env_vars_$(date +%Y-%m-%d_T%H-%M-%S).log"
            fi
            shift ;;
        --json) JSON_OUTPUT=true; shift ;;
        --diff) DIFF_FILE="${2:-}"; [[ -z "$DIFF_FILE" ]] && { echo "❌ Missing argument for --diff"; exit 2; }; shift 2 ;;
        --summary) SUMMARY_ONLY=true; shift ;;
        --compact) COMPACT=true; shift ;;
        --machine) MACHINE=true; shift ;;
        --timestamp) TIMESTAMP=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        --color=*) COLOR_MODE="${1#*=}"; shift ;;
        --help|-h) usage ;;
        *) echo -e "${YELLOW}⚠️  Unknown option: $1${RESET}"; usage ;;
    esac
done

# --- Color mode ---
case "$COLOR_MODE" in
    never) disable_colors ;;
    always) : ;;
    auto)
        if ! [ -t 1 ]; then disable_colors; fi ;;
    *) echo "❌ Invalid --color mode. Use auto|always|never"; exit 2 ;;
esac

# --- Verbose info ---
if $VERBOSE; then
    echo -e "$(ts)${CYAN}🔧 Verbose Mode Enabled${RESET}"
    echo -e "  Version: v${SCRIPT_VERSION} (${SCRIPT_DATE})"
    echo -e "  Host:   $(hostname)"
    echo -e "  User:   $USER"
    echo -e "  Log Dir: ${SCRIPT_LOGS:-$HOME}"
    echo -e "  Save Log: $SAVE_LOG"
    echo -e "  JSON Output: $JSON_OUTPUT"
    echo -e "  Diff File: ${DIFF_FILE:-None}"
    echo -e "  Summary: $SUMMARY_ONLY"
    echo -e "  Compact: $COMPACT"
    echo -e "  Machine: $MACHINE"
    echo -e "  Timestamp: $TIMESTAMP"
    echo -e "  Color Mode: $COLOR_MODE"
    echo "--------------------------------------------------"
fi

# --- Gather environment ---
if [[ -n "$GREP_FILTER" ]]; then
    ENV_DATA="$(printenv | grep -E "$GREP_FILTER" | sort || true)"
else
    ENV_DATA="$(printenv | sort)"
fi

# --- JSON mode for current env ---
if $JSON_OUTPUT && ! $MACHINE; then
    ENV_JSON="{"
    while IFS='=' read -r key val; do
        val_escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
        ENV_JSON+="\"$key\":\"$val_escaped\","
    done <<< "$ENV_DATA"
    ENV_JSON="${ENV_JSON%,}}"
    echo "$ENV_JSON"
    exit 0
fi

# --- Save env ---
if $SAVE_LOG; then
    echo "$ENV_DATA" > "$OUTFILE"
    echo -e "$(ts)✅ Environment saved to: ${CYAN}$OUTFILE${RESET}"
fi

# --- Diff mode ---
if [[ -n "$DIFF_FILE" ]]; then
    [[ ! -f "$DIFF_FILE" ]] && { echo -e "$(ts)${RED}❌ Diff file not found: $DIFF_FILE${RESET}"; exit 2; }

    TMP_CUR=$(mktemp)
    echo "$ENV_DATA" | sort > "$TMP_CUR"
    TMP_OLD=$(mktemp)
    sort "$DIFF_FILE" > "$TMP_OLD"

    ADDED_VARS=$(comm -13 "$TMP_OLD" "$TMP_CUR")
    REMOVED_VARS=$(comm -23 "$TMP_OLD" "$TMP_CUR")
    CHANGED_VARS=$(join -t= -j1 <(sort "$TMP_OLD") <(sort "$TMP_CUR") | awk -F'=' '
        NR==FNR { old[$1]=$0; next }
        {
            split($0, a, "=")
            k=a[1]
            if (old[k] && old[k]!=$0) print k"|"substr(old[k], index(old[k], "=")+1)"|"substr($0, index($0, "=")+1)
        }' "$TMP_OLD" "$TMP_CUR")

    ADDED_COUNT=$(echo "$ADDED_VARS" | grep -c . || true)
    REMOVED_COUNT=$(echo "$REMOVED_VARS" | grep -c . || true)
    CHANGED_COUNT=$(echo "$CHANGED_VARS" | grep -c . || true)

    [[ $ADDED_COUNT -gt 0 || $REMOVED_COUNT -gt 0 || $CHANGED_COUNT -gt 0 ]] && EXIT_CODE=1

    if $MACHINE; then
        echo "{"
        echo "  \"version\": \"$SCRIPT_VERSION\","
        echo "  \"date\": \"$SCRIPT_DATE\","
        echo "  \"added\": ["
        echo "$ADDED_VARS" | sed 's/^/    "/; s/$/"/' | paste -sd, -
        echo "  ],"
        echo "  \"removed\": ["
        echo "$REMOVED_VARS" | sed 's/^/    "/; s/$/"/' | paste -sd, -
        echo "  ],"
        echo "  \"changed\": ["
        echo "$CHANGED_VARS" | awk -F'|' '{printf "    {\"var\":\"%s\",\"old\":\"%s\",\"new\":\"%s\"},\n",$1,$2,$3}' | sed '$ s/,$//'
        echo "  ],"
        echo "  \"summary\": {\"added\": $ADDED_COUNT, \"removed\": $REMOVED_COUNT, \"changed\": $CHANGED_COUNT}"
        echo "}"
        rm -f "$TMP_CUR" "$TMP_OLD"
        exit $EXIT_CODE
    fi

    if $SUMMARY_ONLY; then
        echo -e "$(ts)${GREEN}Added:${RESET} $ADDED_COUNT  ${RED}Removed:${RESET} $REMOVED_COUNT  ${YELLOW}Changed:${RESET} $CHANGED_COUNT"
        rm -f "$TMP_CUR" "$TMP_OLD"; exit $EXIT_CODE
    fi

    if $COMPACT; then
        echo -e "$(ts)${CYAN}🔍 Compact Diff vs ${DIFF_FILE}${RESET}"
        echo "-------------------------------------------------"
        echo "$ADDED_VARS" | while read -r line; do [[ -n "$line" ]] && echo -e "$(ts)${GREEN}+${RESET} $line"; done
        echo "$REMOVED_VARS" | while read -r line; do [[ -n "$line" ]] && echo -e "$(ts)${RED}-${RESET} $line"; done
        echo "$CHANGED_VARS" | while IFS='|' read -r k old new; do
            [[ -n "$k" ]] && echo -e "$(ts)${YELLOW}~${RESET} $k $old → $new"
        done
        echo -e "$(ts)${CYAN}Summary:${RESET} Added=$ADDED_COUNT Removed=$REMOVED_COUNT Changed=$CHANGED_COUNT"
        rm -f "$TMP_CUR" "$TMP_OLD"; exit $EXIT_CODE
    fi

    echo -e "$(ts)🔍 Comparing current environment with: ${CYAN}$DIFF_FILE${RESET}"
    echo "-------------------------------------------------"
    echo -e "$(ts)${GREEN}🟩 Added:${RESET}"
    echo "$ADDED_VARS" | sed 's/^/  + /'
    echo
    echo -e "$(ts)${RED}🟥 Removed:${RESET}"
    echo "$REMOVED_VARS" | sed 's/^/  - /'
    echo
    echo -e "$(ts)${YELLOW}🟨 Changed:${RESET}"
    echo "$CHANGED_VARS" | while IFS='|' read -r k old new; do
        [[ -n "$k" ]] && {
            echo -e "$(ts)  ${CYAN}$k${RESET}"
            echo -e "$(ts)    ${RED}OLD:${RESET} $old"
            echo -e "$(ts)    ${GREEN}NEW:${RESET} $new"
            echo
        }
    done
    echo -e "$(ts)${CYAN}Summary:${RESET} Added=$ADDED_COUNT, Removed=$REMOVED_COUNT, Changed=$CHANGED_COUNT"
    rm -f "$TMP_CUR" "$TMP_OLD"
    exit $EXIT_CODE
fi

# --- Default output (non-diff mode) ---
echo "$ENV_DATA"
exit 0

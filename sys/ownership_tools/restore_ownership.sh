#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# restore_ownership.sh
# Restore ownerships and permissions from take_ownership.sh log
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ownership_common.sh"

LOG_FILE_IN=""
PARALLEL_JOBS="$(nproc)"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log) LOG_FILE_IN="$2"; shift ;;
        --parallel) PARALLEL_JOBS="$2"; shift ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) grep '^#' "$0" | sed -E 's/^# ?//' | head -n 30; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

[[ -z "$LOG_FILE_IN" || ! -f "$LOG_FILE_IN" ]] && { echo "Need valid --log file"; exit 1; }

RESTORE_LOG="${LOG_FILE_IN%.log}_restore_$(date +'%H-%M-%S').log"
touch "$RESTORE_LOG"

banner "RESTORE OWNERSHIP"
echo "Reading log: $LOG_FILE_IN"
echo "Restore log: $RESTORE_LOG"

declare -A ORIGINAL_OWNER ORIGINAL_PERM

while IFS= read -r line; do
    if [[ $line =~ changed[[:space:]]ownership[[:space:]]of[[:space:]]\'(.+)\'[[:space:]]from[[:space:]]\'([^\']+)\' ]]; then
        ORIGINAL_OWNER["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    elif [[ $line =~ mode[[:space:]]of[[:space:]]\'(.+)\'[[:space:]]changed[[:space:]]from[[:space:]]([0-9]+) ]]; then
        ORIGINAL_PERM["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
done < "$LOG_FILE_IN"

_restore_entry() {
    local path="$1"
    local owner="${ORIGINAL_OWNER[$path]:-}"
    local perm="${ORIGINAL_PERM[$path]:-}"

    [[ ! -e "$path" ]] && { echo -e "${RED}✖ Missing:${RESET} $path"; return; }

    [[ -n "$owner" ]] && {
        echo -e "${YELLOW}→ Restoring owner:${RESET} $path → $owner"
        [[ "$DRY_RUN" == false ]] && sudo chown -v "$owner" "$path" >> "$RESTORE_LOG" 2>&1
    }

    [[ -n "$perm" ]] && {
        echo -e "${YELLOW}→ Restoring mode:${RESET} $path → $perm"
        [[ "$DRY_RUN" == false ]] && sudo chmod -v "$perm" "$path" >> "$RESTORE_LOG" 2>&1
    }
}

export -f _restore_entry
export DRY_RUN RESTORE_LOG ORIGINAL_OWNER ORIGINAL_PERM GREEN YELLOW RED RESET

printf "%s\n" "${!ORIGINAL_OWNER[@]}" | parallel -j"$PARALLEL_JOBS" _restore_entry {}

echo -e "${GREEN}✅ Restore complete.${RESET}"
[[ "$DRY_RUN" == true ]] && echo -e "${YELLOW}Dry-run: no changes made.${RESET}"

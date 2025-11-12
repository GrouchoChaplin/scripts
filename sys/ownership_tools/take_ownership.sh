#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# take_ownership.sh
# Safely assign current user/group ownership to targets and remove world perms
#
# Usage:
#   take_ownership.sh <path> [--recursive] [--file list.txt]
#                     [--parallel N] [--verbose]
#
# Example:
#   ./take_ownership.sh /opt/data --recursive --parallel 8 --verbose
#
# Notes:
#   - Prompts for sudo password if needed (no NOPASSWD assumed).
#   - Logs all activity to $SCRIPT_LOGS or /tmp/ownership_YYYY-MM-DD.log.
#   - Uses GNU Parallel if available; otherwise runs sequentially.
#   - --verbose prints `chown`/`chmod` results live.
# ---------------------------------------------------------------------------

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ownership_common.sh"

# --- Check sudo availability ---
if ! sudo -v 2>/dev/null; then
    echo -e "${YELLOW}🔐 Sudo password required for ownership operations...${RESET}"
    sudo -v || { echo -e "${RED}❌ Unable to gain sudo privileges.${RESET}"; exit 1; }
fi

# --- Silence GNU Parallel citation notice (once) ---
if command -v parallel &>/dev/null; then
    parallel --citation >/dev/null 2>&1 || true
fi

# --- Core worker function ---
_process_target() {
    local target="$1"
    local recursive_flag="$2"
    local verbose_flag="$3"
    local username groupname flags cmd
    username=$(id -un)
    groupname=$(id -gn)
    [[ "$recursive_flag" == "true" ]] && flags="-R" || flags=""

    echo "[$(ts)] START target=$target" >> "$LOG_FILE"

    if [[ ! -e "$target" ]]; then
        echo -e "${RED}❌ Missing:${RESET} $target"
        echo "[$(ts)] ERROR: Not found: $target" >> "$LOG_FILE"
        return
    fi

    # --- Change ownership ---
    cmd=(sudo chown $flags -v "${username}:${groupname}" "$target")

    if [[ "$verbose_flag" == "true" ]]; then
        echo -e "${YELLOW}→ Changing ownership:${RESET} $target"
        "${cmd[@]}" | tee -a "$LOG_FILE"
    else
        "${cmd[@]}" &>>"$LOG_FILE"
    fi

    # Check result
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo -e "${GREEN}✔ Ownership set:${RESET} ${username}:${groupname}"
    else
        echo -e "${RED}✖ chown failed:${RESET} $target"
        echo "[$(ts)] ERROR: chown failed $target" >> "$LOG_FILE"
        return
    fi

    # --- Remove world permissions ---
    if [[ "$verbose_flag" == "true" ]]; then
        echo -e "${YELLOW}→ Removing world permissions (chmod o-rwx):${RESET} $target"
        sudo chmod -v o-rwx "$target" | tee -a "$LOG_FILE"
    else
        sudo chmod -v o-rwx "$target" &>>"$LOG_FILE"
    fi

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo -e "${GREEN}✔ Permissions hardened${RESET}"
    else
        echo -e "${RED}✖ chmod failed:${RESET} $target"
        echo "[$(ts)] ERROR: chmod failed $target" >> "$LOG_FILE"
        return
    fi

    echo "[$(ts)] DONE target=$target" >> "$LOG_FILE"
}

# --- Argument parsing ---
recursive_flag=false
verbose_flag=false
parallel_jobs="$(nproc)"
target_file=""
declare -a targets=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recursive|-r) recursive_flag=true ;;
        --file) target_file="$2"; shift ;;
        --parallel) parallel_jobs="$2"; shift ;;
        --verbose|-v) verbose_flag=true ;;
        --help|-h) grep '^#' "$0" | sed -E 's/^# ?//' | head -n 40; exit 0 ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *) targets+=("$1") ;;
    esac
    shift
done

# --- Collect targets ---
if [[ -n "$target_file" && -f "$target_file" ]]; then
    mapfile -t file_targets < <(grep -vE '^\s*$' "$target_file")
    targets+=("${file_targets[@]}")
elif [[ ! -t 0 ]]; then
    mapfile -t stdin_targets
    targets+=("${stdin_targets[@]}")
fi

if [[ ${#targets[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No targets specified.${RESET}"
    exit 1
fi

banner "TAKE OWNERSHIP"
echo "Log file: $LOG_FILE"
[[ "$verbose_flag" == "true" ]] && echo -e "${YELLOW}Verbose mode enabled.${RESET}"

# --- Export for parallel ---
export -f _process_target ts
export LOG_FILE recursive_flag verbose_flag GREEN YELLOW RED RESET

# --- Execute ---
if command -v parallel &>/dev/null; then
    printf "%s\n" "${targets[@]}" | \
        parallel -j"$parallel_jobs" --bar _process_target {} "$recursive_flag" "$verbose_flag"
else
    echo -e "${YELLOW}⚠️ GNU Parallel not found; running sequentially.${RESET}"
    for t in "${targets[@]}"; do _process_target "$t" "$recursive_flag" "$verbose_flag"; done
fi

echo -e "\n${GREEN}✅ All operations complete.${RESET}"
echo "See log: $LOG_FILE"

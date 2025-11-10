#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# take_ownership.sh
# Safely assign current user/group ownership to targets and remove world perms
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ownership_common.sh"

_process_target() {
    local target="$1"
    local recursive_flag="$2"
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

    echo -e "${YELLOW}→ Changing ownership:${RESET} $target"
    cmd=(sudo chown $flags -v "${username}:${groupname}" "$target")
    if "${cmd[@]}" &>>"$LOG_FILE"; then
        echo -e "${GREEN}   ✔ Ownership set${RESET}"
    else
        echo -e "${RED}   ✖ chown failed${RESET}"
        return
    fi

    if sudo chmod -v o-rwx "$target" &>>"$LOG_FILE"; then
        echo -e "${GREEN}   ✔ Permissions hardened${RESET}"
    else
        echo -e "${RED}   ✖ chmod failed${RESET}"
        return
    fi

    echo -e "${GREEN}✅ Done:${RESET} $target"
    echo "[$(ts)] DONE target=$target" >> "$LOG_FILE"
}

recursive_flag=false
parallel_jobs="$(nproc)"
target_file=""
declare -a targets=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --recursive|-r) recursive_flag=true ;;
        --file) target_file="$2"; shift ;;
        --parallel) parallel_jobs="$2"; shift ;;
        --help|-h) grep '^#' "$0" | sed -E 's/^# ?//' | head -n 30; exit 0 ;;
        --*) echo "Unknown option: $1"; exit 1 ;;
        *) targets+=("$1") ;;
    esac
    shift
done

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

export -f _process_target
export LOG_FILE recursive_flag GREEN YELLOW RED RESET -f ts

if command -v parallel &>/dev/null; then
    printf "%s\n" "${targets[@]}" | parallel -j"$parallel_jobs" --bar _process_target {} "$recursive_flag"
else
    for t in "${targets[@]}"; do _process_target "$t" "$recursive_flag"; done
fi

echo -e "${GREEN}✅ All done.${RESET}"

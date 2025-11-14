# lib/common.sh — shared utilities

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
MAGENTA="\033[35m"
NC="\033[0m"

log_info()  { echo -e "${CYAN}$1${NC}"; }
log_warn()  { echo -e "${YELLOW}$1${NC}"; }
log_error() { echo -e "${RED}$1${NC}" >&2; }
log_good()  { echo -e "${GREEN}$1${NC}"; }

human_time() {
    local epoch="$1"
    if [[ -z "$epoch" || "$epoch" == "0" ]]; then
        echo "N/A"
    else
        date -d "@$epoch" "+%Y-%m-%d %H:%M:%S"
    fi
}

# Safe numeric delta: returns absolute difference |a-b|
abs_diff() {
    local a="$1" b="$2"
    if (( a > b )); then
        echo $((a-b))
    else:
        echo $((b-a))
    fi
}

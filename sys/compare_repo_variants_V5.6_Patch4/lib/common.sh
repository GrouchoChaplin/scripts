#!/usr/bin/env bash
#
# common.sh — shared utilities for compare_repo_variants_V5.6_Patch4

##############################################
# COLOR SUPPORT
##############################################
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

colorize() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${RESET}"
}

##############################################
# SAFE PRINTING
##############################################
info()    { echo -e "🔍 $1"; }
warn()    { echo -e "⚠️  $1"; }
error()   { echo -e "❌ $1" >&2; }
success() { echo -e "✅ $1"; }

##############################################
# TIMESTAMP HELPERS
##############################################
fmt_ts() {
    # Convert epoch to human timestamp
    local epoch="$1"
    if [[ -z "$epoch" || "$epoch" == "0" ]]; then
        echo "N/A"
        return
    fi
    date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S"
}

now_ts() {
    date "+%Y-%m-%d_%H-%M-%S"
}

##############################################
# STRING PADDING (for table output)
##############################################
pad_right() {
    local str="$1"
    local width="$2"
    printf "%-${width}s" "$str"
}

##############################################
# TABLE HEADER RENDERING
##############################################
print_header() {
    printf "%-65s | %-22s | %-19s | %-7s | %-6s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%0.s—" {1..150}
    echo
}

##############################################
# AHEAD/BEHIND DETECTION
##############################################
git_ahead() {
    local repo="$1"
    git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $2}'
}

git_behind() {
    local repo="$1"
    git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $1}'
}

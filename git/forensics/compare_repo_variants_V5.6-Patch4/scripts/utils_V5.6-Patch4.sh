\
    #!/usr/bin/env bash
    #
    # utils_V5.6-Patch4.sh
    #
    # Shared helpers for the V5.6-Patch4 git forensics toolkit.
    #
    # This file is designed to be sourced, not executed directly.
    #

    set -o pipefail

    if [[ -n "${UTILS_V5_6_PATCH4_SOURCED:-}" ]]; then
        return 0 2>/dev/null || exit 0
    fi
    readonly UTILS_V5_6_PATCH4_SOURCED=1

    # --- Colors (safe-ish; degrade gracefully if TERM doesn't support) ---
    if [[ -t 1 ]]; then
        _c_red=$'\e[31m'
        _c_grn=$'\e[32m'
        _c_ylw=$'\e[33m'
        _c_blu=$'\e[34m'
        _c_mag=$'\e[35m'
        _c_cyn=$'\e[36m'
        _c_rst=$'\e[0m'
    else
        _c_red=''
        _c_grn=''
        _c_ylw=''
        _c_blu=''
        _c_mag=''
        _c_cyn=''
        _c_rst=''
    fi

    ts() {
        date +"%Y-%m-%d %H:%M:%S"
    }

    log_info() {
        printf '[%s] %sINFO%s  %s\n' "$(ts)" "$_c_cyn" "$_c_rst" "$*"
    }

    log_warn() {
        printf '[%s] %sWARN%s  %s\n' "$(ts)" "$_c_ylw" "$_c_rst" "$*"
    }

    log_error() {
        printf '[%s] %sERROR%s %s\n' "$(ts)" "$_c_red" "$_c_rst" "$*"
    }

    # Get file epoch (portable-ish Linux/macOS)
    get_file_epoch() {
        local f="$1"
        if stat -c '%Y' -- "$f" 2>/dev/null; then
            return 0
        elif stat -f '%m' -- "$f" 2>/dev/null; then
            return 0
        else
            echo 0
            return 1
        fi
    }

    epoch_to_human() {
        local e="$1"
        if [[ -z "$e" || "$e" == "0" ]]; then
            echo "-"
            return
        fi
        if date -d @"$e" +'%Y-%m-%d %H:%M:%S' 2>/dev/null; then
            return 0
        elif date -r "$e" +'%Y-%m-%d %H:%M:%S' 2>/dev/null; then
            return 0
        else
            echo "$e"
        fi
    }

    # Resolve absolute path
    abspath() {
        local p="$1"
        if [[ -d "$p" ]]; then
            (cd "$p" && pwd)
        else
            (cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")")
        fi
    }

    # Simple command check
    require_cmd() {
        local c
        for c in "$@"; do
            if ! command -v "$c" >/dev/null 2>&1; then
                log_error "Required command not found: $c"
                return 1
            fi
        done
    }

#!/usr/bin/env bash
# =============================================================================
#   fast-dirsize-external.sh
#   Optimized for external HDDs – shows immediate subdirs ≥ threshold, with color
# =============================================================================

set -u

# ==================== Configuration ====================

MIN_SIZE="${MIN_SIZE:-100M}"           # Change with --min-size 500M etc.
COLORS=1                               # 0 = disable ANSI colors

# ANSI colors
C_RED='\033[0;31m'
C_YELLOW='\033[1;33m'
C_GREEN='\033[0;32m'
C_RESET='\033[0m'

# ==================== Argument parsing ====================

TARGET="."
EXTRA_DU_OPTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--min-size)  MIN_SIZE="$2"; shift 2 ;;
        --no-color)     COLORS=0; shift ;;
        --apparent-size|--bytes|--inodes|--time|--X|--exclude-from=*)
                        EXTRA_DU_OPTS+=("$1"); shift ;;
        --exclude=*)    EXTRA_DU_OPTS+=("$1"); shift ;;
        -*)
            printf "Warning: passing through unknown option: %s\n" "$1" >&2
            EXTRA_DU_OPTS+=("$1")
            shift
            ;;
        *)  TARGET="$1"; shift ;;
    esac
done

[[ ! -d "$TARGET" ]] && { printf "Error: '%s' is not a directory\n" "$TARGET" >&2; exit 1; }

TARGET="$(realpath -m -- "$TARGET")"

# ==================== Execution ====================

printf "Scanning top-level subdirectories in: %s\n" "$TARGET"
printf "Showing only ≥ %s  (use --min-size to adjust)\n\n" "$MIN_SIZE"

# Core command – very fast on external drives
du -sh --max-depth=1 --threshold="$MIN_SIZE" "${EXTRA_DU_OPTS[@]}" "$TARGET"/* 2>/dev/null \
    | sort -hr \
    | while IFS=$'\t' read -r size path; do
        # Skip total line & non-directories
        [[ "$path" == "$TARGET/." || "$path" == "." || ! -d "$path" ]] && continue

        # Optional: convert to bytes for threshold/color logic if needed
        size_bytes=$(numfmt --from=iec-i "$size" 2>/dev/null || echo 0)
        min_bytes=$(numfmt --from=iec-i "$MIN_SIZE" 2>/dev/null || echo 0)

        (( size_bytes < min_bytes )) && continue

        # Color scaling (relative to threshold)
        color=""
        if (( COLORS )); then
            if   (( size_bytes >= 10 * min_bytes )); then color="$C_RED"
            elif (( size_bytes >=  3 * min_bytes )); then color="$C_YELLOW"
            else                                          color="$C_GREEN"
            fi
        fi

        # Nice formatting: size padded + basename only
        printf "%s%10s  %s%s\n" "$color" "$size" "${path##*/}" "$C_RESET"
    done

printf "\n"




# Fastest built-in
#du -sh --max-depth=1 --threshold=200M /mnt/external/* 2>/dev/null | sort -hr

# With color via tput (very approximate coloring)
#du -sh --max-depth=1 /mnt/external/* 2>/dev/null | sort -hr | \
#awk '{if ($1 ~ /[0-9]+[GTP]/) c="\033[0;31m"; else if ($1 ~ /[0-9]+[M]/ && $1+0 > 500) c="\033[0;33m"; else c="\033[0;32m"; printf "%s%10s  %s\033[0m\n", c, $1, substr($0, index($0,$2))}'
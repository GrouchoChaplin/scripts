#!/usr/bin/env bash
# -------------------------------------------------------------------
# find_shaders_sha256.sh
# Scans for volumetric_cloud_shader files, computes file stats,
# and optionally sorts results by epoch time if --epoch is specified.
# -------------------------------------------------------------------

# Default values
PROCS="$(($(nproc) - 4))"
EXCLUDE_STRINGS=()
SORT_BY_EPOCH=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --exclude-strings)
            shift
            while [[ $# -gt 0 && ! $1 = -* ]]; do
                EXCLUDE_STRINGS+=("$1")
                shift
            done
            ;;
        --epoch)
            SORT_BY_EPOCH=true
            shift
            ;;
        *)
            echo "Usage: $0 [--epoch] [--exclude-strings \"str1\" \"str2\" ...]"
            echo "Example: $0 --epoch --exclude-strings \"DEBUG\" \"2025_10_08_T17_11_15\""
            exit 1
            ;;
    esac
done

# --- Build exclude filter safely ---
build_exclude_filter() {
    if [[ ${#EXCLUDE_STRINGS[@]} -eq 0 ]]; then
        cat
        return
    fi
    local patterns=()
    for s in "${EXCLUDE_STRINGS[@]}"; do
        patterns+=(-e "$s")
    done
    grep -v -F "${patterns[@]}"
}

# --- Generate timestamp for log file ---
LOG_TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="find_shaders_sha256.${LOG_TIMESTAMP}.log"

# --- Redirect all output to log file AND print to stdout ---
exec > >(tee "$LOG_FILE") 2>&1

# --- Print header ---
printf "%-19s %-10s %-6s %-8s %-8s %-64s %-s\n" \
       "TIMESTAMP" "EPOCH" "LINES" "SIZE_KB" "SIZE_MB" "SHA256" "FILEPATH"

# --- Collect and process shader data ---
find /run/media/peddycoartte/MasterBackup/Nightly/2025-10-??/projects \
    -type d -name Shaders -print0 2>/dev/null | \
xargs -0 -P "$PROCS" -I {} bash -c '
    shader_dir="$1"
    [ -d "$shader_dir/Volume" ] || exit 0
    find "$shader_dir/Volume" -type f -name "volumetric_cloud_shader*.*" \
        -printf "%T@ %TY-%Tm-%Td %TH:%TM:%.2TS %p\n" 2>/dev/null
' _ {} | \
build_exclude_filter | \
{
    if [[ "$SORT_BY_EPOCH" == true ]]; then
        sort -nr  # newest first by epoch
    else
        sort -k2,2  # default: sort by timestamp string
    fi
} | \
while IFS= read -r line; do
    # Extract epoch, timestamp, and filepath
    epoch=$(echo "$line" | awk '{print $1}')
    timestamp=$(echo "$line" | awk '{print $2 " " $3}')
    filepath=$(echo "$line" | cut -d' ' -f4-)

    # Get file stats
    lines=$(wc -l < "$filepath" 2>/dev/null || echo 0)
    size_bytes=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
    size_kb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / 1024}")
    size_mb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / (1024*1024)}")
    sha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}')

    # Output formatted row
    printf "%-19s %-10s %-6s %-8s %-8s %-64s %s\n" \
           "$timestamp" "$epoch" "$lines" "$size_kb" "$size_mb" "$sha256" "$filepath"
done

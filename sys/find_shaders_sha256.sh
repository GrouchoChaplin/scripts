#!/usr/bin/env bash
# Default values
PROCS="$(($(nproc) - 4))"
EXCLUDE_STRINGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --exclude-strings)
            shift
            while [[ $# -gt 0 && ! $1 = -* ]]; do
                EXCLUDE_STRINGS+=("$1")
                shift
            done
            ;;
        *)
            echo "Usage: $0 [--exclude-strings \"str1\" \"str2\" ...]"
            echo "Example: $0 --exclude-strings \"DEBUG\" \"2025_10_08_T17_11_15\""
            exit 1
            ;;
    esac
done

# Build grep command safely
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

# Print left-justified header
printf "%-19s %-6s %-8s %-8s %-64s %-s\n" "TIMESTAMP" "LINES" "SIZE_KB" "SIZE_MB" "SHA256" "FILEPATH"

find /run/media/peddycoartte/MasterBackup/Nightly/2025-10-??/projects \
    -type d -name Shaders -print0 2>/dev/null | \
xargs -0 -P "$PROCS" -I {} bash -c '
    shader_dir="$1"
    [ -d "$shader_dir/Volume" ] || exit 0
    find "$shader_dir/Volume" -type f -name "volumetric_cloud_shader*.*" \
        -printf "%T@ %TY-%Tm-%Td %TH:%TM:%.2TS %p\n" 2>/dev/null
' _ {} | \
sort -n | \
cut -d' ' -f2- | \
build_exclude_filter | \
while IFS= read -r line; do
    # Extract timestamp and filepath
    timestamp=$(echo "$line" | awk '{print $1 " " $2}')
    filepath=$(echo "$line" | cut -d' ' -f3-)

    # Get file stats
    lines=$(wc -l < "$filepath" 2>/dev/null || echo 0)
    size_bytes=$(stat -c%s "$filepath" 2>/dev/null || echo 0)
    size_kb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / 1024}")
    size_mb=$(awk "BEGIN {printf \"%.2f\", $size_bytes / (1024*1024)}")
    sha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}')

    # Output left-justified
    printf "%-19s %-6s %-8s %-8s %-64s %s\n" "$timestamp" "$lines" "$size_kb" "$size_mb" "$sha256" "$filepath"
done
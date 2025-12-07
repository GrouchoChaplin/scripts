#!/bin/bash
# =============================================================================
# findfile.sh - Search for files by name in a directory and list by modification time
# Default: newest first (like ls -lt)
# =============================================================================

set -euo pipefail

# Default values
REVERSE=false

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] -d <directory> -f <filename>

Options:
    -d <dir>      Root directory to start searching from (required)
    -f <name>     Filename or pattern to search for (required, supports wildcards)
    -r            Reverse order: show oldest files first (instead of newest)
    -i            Case-insensitive search (uses -iname instead of -name)
    -h            Show this help

Examples:
    $(basename "$0") -d /home/user -f "report.pdf"
    $(basename "$0") -d /var/log -f "*.log" -r
    $(basename "$0") -d ~/Documents -f "budget*.xlsx" -i
EOF
    exit 1
}

# Parse arguments
while getopts "d:f:rih" opt; do
    case $opt in
        d) SEARCH_DIR="$OPTARG" ;;
        f) FILENAME="$OPTARG" ;;
        r) REVERSE=true ;;
        i) CASE_INSENSITIVE=true ;;
        h|*) usage ;;
    esac
done

# Required arguments check
if [[ -z "${SEARCH_DIR:-}" || -z "${FILENAME:-}" ]]; then
    echo "Error: Both -d (directory) and -f (filename) are required."
    echo
    usage
fi

# Safety: expand ~ and resolve path
SEARCH_DIR="$(realpath -e "$SEARCH_DIR" 2>/dev/null || echo "$SEARCH_DIR")"

if [[ ! -d "$SEARCH_DIR" ]]; then
    echo "Error: Directory '$SEARCH_DIR' does not exist or is not accessible."
    exit 1
fi

# Build the find command
FIND_NAME_OPT="-name"
[[ "${CASE_INSENSITIVE:-false}" == true ]] && FIND_NAME_OPT="-iname"

echo "Searching for: $FILENAME"
echo "In directory: $SEARCH_DIR"
echo "Case insensitive: $( [[ ${CASE_INSENSITIVE:-false} == true ]] && echo Yes || echo No )"
echo "Order: $((REVERSE)) && echo "Oldest first" || echo "Newest first")"
echo "------------------------------------------------------------"

# Main search command
if $REVERSE; then
    # Oldest first → use ls -lrt
    find "$SEARCH_DIR" -type f "$FIND_NAME_OPT" "$FILENAME" -exec ls -lrt {} +
else
    # Newest first → use ls -lt
    find "$SEARCH_DIR" -type f "$FIND_NAME_OPT" "$FILENAME" -exec ls -lt {} +
fi

# Summary
FOUND=$(find "$SEARCH_DIR" -type f "$FIND_NAME_OPT" "$FILENAME" | wc -l)
echo "------------------------------------------------------------"
echo "Found $FOUND file(s) matching '$FILENAME'"

exit 0
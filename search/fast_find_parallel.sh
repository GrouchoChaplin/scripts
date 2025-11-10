#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fast_find_parallel.sh
#
# Ultra-fast recursive parallel file finder using GNU Parallel and find.
#
# Usage:
#   fast_find_parallel.sh --folder <root_dir> --file <pattern1> [pattern2 ...]
#                         [--parallel N] [--verbose]
#
# Example:
#   ./fast_find_parallel.sh --folder /run/media/peddycoartte/MasterBackup \
#       --file "*.glsl" "*.frag" "*.vert" --parallel 28 --verbose
# ---------------------------------------------------------------------------

set -euo pipefail

FOLDER=""
PARALLEL_JOBS="$(nproc)"
VERBOSE=false
declare -a FILE_PATTERNS=()

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --folder) FOLDER="$2"; shift ;;
        --file)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                FILE_PATTERNS+=("$1")
                shift
            done
            continue ;;
        --parallel) PARALLEL_JOBS="$2"; shift ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            grep '^#' "$0" | sed -E 's/^# ?//' | head -n 40
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if [[ -z "$FOLDER" || ${#FILE_PATTERNS[@]} -eq 0 ]]; then
    echo "Usage: $0 --folder <dir> --file <pattern1> [pattern2 ...] [--parallel N] [--verbose]"
    exit 1
fi
if [[ ! -d "$FOLDER" ]]; then
    echo "❌ Folder not found: $FOLDER"
    exit 1
fi
if ! command -v parallel &>/dev/null; then
    echo "❌ GNU parallel not installed. Install via: sudo dnf install parallel"
    exit 1
fi

# --- Silence GNU Parallel citation notice ---
parallel --citation >/dev/null 2>&1 || true

LOG_FILE="/tmp/fast_find_$(date +'%Y-%m-%d_%H-%M-%S').log"

echo "------------------------------------------------------------"
echo " FAST PARALLEL RECURSIVE FILE SEARCH"
echo "------------------------------------------------------------"
echo "Folder:   $FOLDER"
echo "Patterns: ${FILE_PATTERNS[*]}"
echo "Parallel: $PARALLEL_JOBS"
echo "Log:      $LOG_FILE"
[[ "$VERBOSE" == true ]] && echo "Verbose:  enabled"
echo "------------------------------------------------------------"

# --- Build the combined -iname expression for multiple patterns ---
pattern_expr=""
for pattern in "${FILE_PATTERNS[@]}"; do
    [[ -n "$pattern_expr" ]] && pattern_expr+=" -o "
    pattern_expr+="-iname '$pattern'"
done

# --- Function: find recursively in one subpath ---
find_recursive() {
    local path="$1"
    # shellcheck disable=SC2086
    eval find "\"$path\"" -type f \( $pattern_expr \) 2>/dev/null
}
export -f find_recursive
export pattern_expr

# --- Gather all directories under $FOLDER recursively ---
# Splitting work among subtrees makes this very fast on large trees
DIRS=$(find "$FOLDER" -type d 2>/dev/null)

# --- Run the recursive search in parallel ---
if [[ "$VERBOSE" == true ]]; then
    echo -e "Searching recursively...\n"
    echo "$DIRS" | parallel -j"$PARALLEL_JOBS" --bar find_recursive {} | tee "$LOG_FILE"
else
    echo "$DIRS" | parallel -j"$PARALLEL_JOBS" find_recursive {} >> "$LOG_FILE" 2>/dev/null
fi

echo "------------------------------------------------------------"
echo "✅ Done. Results saved to: $LOG_FILE"

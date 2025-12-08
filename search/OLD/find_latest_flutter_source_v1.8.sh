#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.8
#
# - Search base root folder for sub-folders matching a pattern (e.g., *ir_imagery_too*)
# - For each folder, gather all .dart files, group them by filename, and sort by modification time
#
set -euo pipefail

DEBUG=0  # Set to 1 to enable debug output
INCLUDE_INSTANCES=0   # Default: do not show per-file instance details

# Default log file name
DEFAULT_LOG_FILE="find_latest_flutter_source.log"
LOG_FILE="$DEFAULT_LOG_FILE"  # Default log file

########################################
# Color helpers
########################################
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'
  GREEN=$'\e[32m'
  CYAN=$'\e[36m'
  YELLOW=$'\e[33m'
  RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; CYAN=""; YELLOW=""; RESET=""
fi

bold()  { printf '%b%s%b' "$BOLD" "$1" "$RESET"; }
green() { printf '%b%s%b' "$GREEN" "$1" "$RESET"; }
cyan()  { printf '%b%s%b' "$CYAN" "$1" "$RESET"; }
yellow(){ printf '%b%s%b' "$YELLOW" "$1" "$RESET"; }

# debug function
debug() {
  if [[ $DEBUG -eq 1 ]]; then
    echo "$(yellow "[DEBUG]") $*" >&2
  fi
}

# Logging function
log() {
  echo "$1" | tee -a "$LOG_FILE"
}

########################################
# Usage
########################################
usage() {
  cat <<EOF
$(bold "find_latest_flutter_source.sh – Flutter Source Version Finder v1.8")

Options:
  --paths DIR1 [DIR2 ...]   One or more directories or glob patterns to scan
  --pattern PATTERN          Subdirectory pattern to match (default: *ir_imagery_too*)
  --top N                    Show top N modified files (default: 20)
  --latest-per-file          Compute latest-modified .dart file per group key
  --group-by MODE            Group key for --latest-per-file:
                            MODE is one of: basename | relpath | fullpath
  --include-instances       Include per-instance file details (mtime, SHA256, size). Default OFF.                            
  --log-file FILE            Log output to a specified file (default: $DEFAULT_LOG_FILE)
  -h, --help                 Show this help
EOF
}

########################################
# Argument parsing
########################################
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths)
      shift
      BASE_DIR="$1"; shift ;;
    --pattern)
      shift
      PATTERN="$1"; shift ;;
    --top)
      TOP_FILES="$2"; shift 2 ;;
    --latest-per-file)
      LATEST_PER_FILE=1; shift ;;
    --group-by)
      GROUP_BY_MODE="$2"; shift 2 ;;
    --log-file)
      shift
      LOG_FILE="$1"; shift ;;
    --include-instances)
      INCLUDE_INSTANCES=1
      shift
      ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$BASE_DIR" ]]; then
  log "Error: You must specify a base directory with --paths."
  exit 1
fi

log "Starting search in $BASE_DIR for directories matching pattern '$PATTERN'..."

########################################
# Search subfolders matching pattern
########################################
SCAN_DIRS=()
log "Searching for directories matching pattern '$PATTERN' under '$BASE_DIR'..."

# Find subdirectories matching the pattern
SCAN_DIRS=($(find "$BASE_DIR" -type d -name "$PATTERN"))

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  log "No subdirectories found matching pattern '$PATTERN'."
  exit 1
fi

debug "Found subfolders: ${SCAN_DIRS[*]}"

########################################
# Scan Dart files in each subdirectory
########################################
declare -A dart_files

# Loop over each folder and gather .dart files
for dir in "${SCAN_DIRS[@]}"; do
  log "Scanning directory: $dir"
  
  # Find all .dart files in the directory (recursive)
  while IFS= read -r file; do
    # Check if it's a Dart file
    if [[ "$file" == *.dart ]]; then
      # Group by file name (basename)
      base_name=$(basename "$file")
      
      # Store the file's timestamp and path
      timestamp=$(stat -c %Y "$file")
      filesize=$(stat -c %s "$file")
      sha256sum=$(sha256sum "$file" | cut -d ' ' -f1)
      dart_files["$base_name"]+="$timestamp,$file,$sha256sum,$filesize"$'\n'
    fi
  done < <(find "$dir" -type f -name "*.dart")
done

########################################
# Process each Dart file group
########################################
log "Processing Dart file groups..."

for file in "${!dart_files[@]}"; do
  log "Processing group: $file"
  
  # Sort the files by modification time (newest to oldest)
  sorted_files=$(echo -e "${dart_files[$file]}" | sort -t ',' -k1,1nr)
  
  # Output the most recent file summary
  latest_file=$(echo "$sorted_files" | head -n 1)
  latest_timestamp=$(echo "$latest_file" | cut -d ',' -f1)
  latest_path=$(echo "$latest_file" | cut -d ',' -f2-)

  log "Most recent version of '$file' is: $latest_path (modified: $(date -d @$latest_timestamp))"

  ############################################################
  # Per-instance output — only when --include-instances is ON
  ############################################################
  if [[ $INCLUDE_INSTANCES -eq 1 ]]; then
      echo "" | tee -a "$LOG_FILE"

      echo "Instances of '$file':" | tee -a "$LOG_FILE"
      echo "Modification Time, SHA256, Full Path, Filesize" | tee -a "$LOG_FILE"

      while IFS=',' read -r file_time file_path file_sha256 file_size; do
          mod_time=$(date -d @$file_time)

          echo "$mod_time, $file_sha256, $file_path, ${file_size} bytes" \
              | tee -a "$LOG_FILE"
      done <<< "$sorted_files"

      echo "" | tee -a "$LOG_FILE"
  fi

done


log "Done!"

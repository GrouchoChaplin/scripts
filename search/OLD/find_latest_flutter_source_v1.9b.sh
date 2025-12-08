#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.9b (FULL VERSION)
#
# PURPOSE:
#   Search multiple backup directories for Dart files, group matching files,
#   identify the newest versions, optionally display and export full metadata.
#
# FEATURES:
#   - Recursively find subdirectories matching a pattern
#   - Group files by basename | relpath | fullpath
#   - Determine the newest version in each group
#   - Conditional per-instance reporting
#   - Diff-vs-latest metadata comparison
#   - CSV export
#   - JSON export
#   - Color-highlight newest instance
#   - Full structured logging
#
set -euo pipefail

VERSION="1.9"

##############################################
# DEFAULT OPTIONS
##############################################

BASE_DIR=""
PATTERN="*"
LOG_FILE="find_latest_flutter_source.log"
DEBUG=0

GROUP_BY_MODE="basename"      # basename | relpath | fullpath
INCLUDE_INSTANCES=0
DIFF_VS_LATEST=0
COLOR_NEWEST=0

CSV_EXPORT=""
JSON_EXPORT=""
JSON_ROWS=""

##############################################
# COLOR DETECTION
##############################################
if [[ -t 1 ]]; then
  GREEN=$'\e[32m'
  BOLD=$'\e[1m'
  YELLOW=$'\e[33m'
  RESET=$'\e[0m'
else
  GREEN=""; BOLD=""; YELLOW=""; RESET=""
fi

##############################################
# UTILITY FUNCTIONS
##############################################
log() { echo "$1" | tee -a "$LOG_FILE"; }
debug() { [[ $DEBUG -eq 1 ]] && echo "[DEBUG] $*" >&2; }

format_newest() {
  if [[ $COLOR_NEWEST -eq 1 ]]; then printf '%b%s%b' "$GREEN" "$1" "$RESET"; else printf "%s" "$1"; fi
}

##############################################
# USAGE
##############################################
usage() {
cat <<EOF
$BOLD find_latest_flutter_source.sh – Flutter Source Version Finder v$VERSION $RESET

OPTIONS:
  --paths DIR               Base directory to scan recursively
  --pattern PATTERN         Subdirectory name pattern to match
  --group-by MODE           basename | relpath | fullpath
  --include-instances       Show per-instance details
  --diff-vs-latest          Show metadata deltas vs newest
  --color-newest            Highlight newest instance in green
  --csv FILE                CSV export path
  --json FILE               JSON export path
  --log-file FILE           Log output path
  --debug                   Verbose output
  -h, --help                Show help

EXAMPLE:
  ./find_latest_flutter_source_v1.9.sh \\
      --paths "/media/backups" \\
      --pattern "*ir_imagery_tools*" \\
      --group-by relpath \\
      --include-instances \\
      --diff-vs-latest \\
      --json audit.json \\
      --csv audit.csv
EOF
}

##############################################
# ARGUMENT PARSING
##############################################
if [[ $# -eq 0 ]]; then usage; exit 0; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths) BASE_DIR="$2"; shift 2;;
    --pattern) PATTERN="$2"; shift 2;;
    --group-by) GROUP_BY_MODE="$2"; shift 2;;
    --include-instances) INCLUDE_INSTANCES=1; shift;;
    --diff-vs-latest) DIFF_VS_LATEST=1; shift;;
    --color-newest) COLOR_NEWEST=1; shift;;
    --csv) CSV_EXPORT="$2"; shift 2;;
    --json) JSON_EXPORT="$2"; shift 2;;
    --log-file) LOG_FILE="$2"; shift 2;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

[[ -z "$BASE_DIR" ]] && { echo "ERROR: --paths required"; exit 1; }

##############################################
# INITIALIZE EXPORTS
##############################################
if [[ -n "$CSV_EXPORT" ]]; then
  echo "group_key,mtime,sha256,size,path" > "$CSV_EXPORT"
fi

JSON_ROWS=""

##############################################
# FIND DIRECTORIES MATCHING PATTERN
##############################################
log "Scanning: $BASE_DIR"
log "Directory name pattern: $PATTERN"

mapfile -t TARGET_DIRS < <(find "$BASE_DIR" -type d -name "$PATTERN" 2>/dev/null)

[[ ${#TARGET_DIRS[@]} -eq 0 ]] && { log "No matches found"; exit 0; }

##############################################
# INTERNAL DATA STRUCTURES
##############################################
declare -A FILE_GROUPS
declare -A MULTI_INSTANCE

##############################################
# GROUP KEY FUNCTION
##############################################
get_group_key() {
  local full="$1"

  case "$GROUP_BY_MODE" in
    basename)
      basename "$full"
      ;;
    relpath)
      local rel="${full#*/lib/}"
      [[ "$rel" == "$full" ]] && basename "$full" || echo "$rel"
      ;;
    fullpath)
      echo "$full"
      ;;
  esac
}

##############################################
# DIRECTORY SCAN
##############################################
log "Scanning .dart files..."

for dir in "${TARGET_DIRS[@]}"; do
  debug "Searching: $dir"
  while IFS= read -r file; do
    [[ "$file" == *.dart ]] || continue

    ts=$(stat -c %Y "$file")
    size=$(stat -c %s "$file")
    sha=$(sha256sum "$file" | awk '{print $1}')
    key=$(get_group_key "$file")

    FILE_GROUPS["$key"]+="${ts},${file},${sha},${size}"$'\n'
  done < <(find "$dir" -type f -name "*.dart" 2>/dev/null)
done

##############################################
# PROCESS GROUPS
##############################################
log "Processing file groups..."

for key in "${!FILE_GROUPS[@]}"; do
  entries=$(echo -e "${FILE_GROUPS[$key]}" | sed '/^$/d' | sort -t',' -k1,1nr)

  newest=$(echo "$entries" | head -n 1)
  newest_ts=$(echo "$newest" | cut -d',' -f1)
  newest_path=$(echo "$newest" | cut -d',' -f2)

  log "------------------------------------------------------------"
  log "Group: $key"
  log "Newest: $newest_path  ($(date -d @"$newest_ts"))"

  ##############################################
  # PER-INSTANCE REPORTING
  ##############################################
  if [[ $INCLUDE_INSTANCES -eq 1 ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Instances:" | tee -a "$LOG_FILE"

    while IFS=',' read -r ts path sha size; do
      formatted_time=$(date -d @"$ts")

      line="  $formatted_time | $sha | ${size} bytes | $path"

      if [[ "$ts" == "$newest_ts" ]]; then
        format_newest "$line" | tee -a "$LOG_FILE"
      else
        echo "$line" | tee -a "$LOG_FILE"
      fi

      if [[ -n "$CSV_EXPORT" ]]; then
        echo "\"$key\",\"$formatted_time\",\"$sha\",\"$size\",\"$path\"" >> "$CSV_EXPORT"
      fi

      if [[ -n "$JSON_EXPORT" ]]; then
        esc_path=${path//\"/\\\"}
        esc_key=${key//\"/\\\"}
        JSON_ROWS="${JSON_ROWS}{\"group_key\":\"$esc_key\",\"mtime\":\"$formatted_time\",\"sha256\":\"$sha\",\"size\":$size,\"path\":\"$esc_path\"},"
      fi

    done <<< "$entries"
  fi
done

##############################################
# FINALIZE JSON EXPORT
##############################################
if [[ -n "$JSON_EXPORT" ]]; then
  echo "[${JSON_ROWS%,}]" > "$JSON_EXPORT"
  log "JSON export written to $JSON_EXPORT"
fi

log "DONE."

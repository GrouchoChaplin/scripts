#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.9.1
#
# - Search a base root folder for sub-folders matching a pattern (e.g., *ir_imagery_tools*)
# - For each matched folder, gather all .dart files
# - Group .dart files by a chosen key (basename | relpath | fullpath)
# - For each group, find the latest-modified instance
# - Optionally show all instances with:
#       * path
#       * modification time
#       * file size
#       * SHA256
# - Optional CSV and JSON export
# - Optional diff vs latest summary
# - Optional highlighting of newest instance in green
#
set -euo pipefail

VERSION="1.9.1"

##############################################
# GLOBAL DEFAULTS
##############################################
DEBUG=0
DEFAULT_LOG_FILE="find_latest_flutter_source.log"
LOG_FILE="$DEFAULT_LOG_FILE"

BASE_DIR=""
PATTERN="*ir_imagery_too*"

LATEST_PER_FILE=1
GROUP_BY_MODE="basename"
INCLUDE_INSTANCES=0

CSV_EXPORT=""
JSON_EXPORT=""
JSON_ROWS=""

DIFF_VS_LATEST=0
COLOR_NEWEST=0

##############################################
# COLOR SUPPORT
##############################################
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'
  GREEN=$'\e[32m'
  CYAN=$'\e[36m'
  YELLOW=$'\e[33m'
  RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; CYAN=""; YELLOW=""; RESET=""
fi

bold()  { printf '%b%s%b\n' "$BOLD" "$1" "$RESET"; }
green_text() { printf '%b%s%b' "$GREEN" "$1" "$RESET"; }
yellow_text(){ printf '%b%s%b' "$YELLOW" "$1" "$RESET"; }

##############################################
# LOGGING
##############################################
debug() {
  [[ $DEBUG -eq 1 ]] && echo "$(yellow_text "[DEBUG]") $*" >&2
}

log() {
  echo "$1" | tee -a "$LOG_FILE"
}

##############################################
# FORMATTING HELPERS
##############################################
format_newest() {
  local text="$1"
  if [[ $COLOR_NEWEST -eq 1 ]]; then
    printf '\e[32m%s\e[0m' "$text"
  else
    printf '%s' "$text"
  fi
}

show_diff_vs_latest() {
  local newest_ts="$1"
  local newest_sha="$2"
  local newest_size="$3"
  local file_ts="$4"
  local file_sha="$5"
  local file_size="$6"

  local diff=""
  local delta=$(( newest_ts - file_ts ))

  [[ $delta -gt 0 ]] && diff+="    Δ time: ${delta}s older\n"
  [[ "$newest_size" != "$file_size" ]] && diff+="    Δ size: newest=$newest_size vs this=$file_size\n"
  [[ "$newest_sha" != "$file_sha" ]] && diff+="    SHA mismatch\n"

  [[ -n "$diff" ]] && printf "%b" "$diff"
}

write_csv() {
  echo "$2" >> "$CSV_EXPORT"
}

write_json_row() {
  [[ -z "$JSON_ROWS" ]] && JSON_ROWS="$1" || JSON_ROWS="$JSON_ROWS,$1"
}

##############################################
# USAGE
##############################################
usage() {
cat <<EOF
$(bold "find_latest_flutter_source.sh – Flutter Source Version Finder v$VERSION")

Options:
  --paths DIR               Base directory to scan (required)
  --pattern PATTERN         Subdirectory pattern to match
  --group-by MODE           basename | relpath | fullpath
  --include-instances       Include per-instance output
  --csv FILE                CSV export
  --json FILE               JSON export
  --diff-vs-latest          Show diff summary
  --color-newest            Highlight newest instance
  --log-file FILE           Override log file
  --debug                   Debug logging
  -h, --help                Show this help

Instance Output Format (v1.9.1):
  Path | Modification Time | Size | SHA256
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
    --csv) CSV_EXPORT="$2"; shift 2;;
    --json) JSON_EXPORT="$2"; shift 2;;
    --diff-vs-latest) DIFF_VS_LATEST=1; shift;;
    --color-newest) COLOR_NEWEST=1; shift;;
    --log-file) LOG_FILE="$2"; shift 2;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option $1"; exit 1;;
  esac
done

[[ -z "$BASE_DIR" ]] && { echo "ERROR: --paths is required"; exit 1; }

##############################################
# CSV / JSON INITIALIZATION
##############################################
[[ -n "$CSV_EXPORT" && ! -f "$CSV_EXPORT" ]] &&
  echo "group_key,path,mtime,size,sha256" > "$CSV_EXPORT"

JSON_ROWS=""

##############################################
# FIND DIRECTORIES MATCHING PATTERN
##############################################
log "Base directory: $BASE_DIR"
log "Searching for directories matching: $PATTERN"

mapfile -t SCAN_DIRS < <(find "$BASE_DIR" -type d -name "$PATTERN" 2>/dev/null)

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  log "No matching directories."
  [[ -n "$JSON_EXPORT" ]] && echo "[]" > "$JSON_EXPORT"
  exit 0
fi

##############################################
# SCAN .dart FILES
##############################################
declare -A dart_files

get_group_key() {
  local path="$1"
  case "$GROUP_BY_MODE" in
    basename) basename "$path" ;;
    relpath)
      local trimmed="${path#*/lib/}"
      [[ "$trimmed" == "$path" ]] && basename "$path" || echo "$trimmed"
      ;;
    fullpath) echo "$path" ;;
  esac
}

for dir in "${SCAN_DIRS[@]}"; do
  log "Scanning: $dir"
  while IFS= read -r file; do
    [[ "$file" == *.dart ]] || continue
    ts=$(stat -c %Y "$file")
    size=$(stat -c %s "$file")
    sha=$(sha256sum "$file" | awk '{print $1}')
    key=$(get_group_key "$file")
    dart_files["$key"]+="${ts},${file},${sha},${size}"$'\n'
  done < <(find "$dir" -type f -name "*.dart")
done

##############################################
# PROCESS EACH GROUP
##############################################
log "Processing groups..."

for key in "${!dart_files[@]}"; do
  echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
  log "Group: $key"

  sorted=$(echo -e "${dart_files[$key]}" | sed '/^$/d' | sort -t ',' -k1,1nr)

  newest=$(echo "$sorted" | head -n 1)
  newest_ts=$(echo "$newest" | cut -d',' -f1)
  newest_path=$(echo "$newest" | cut -d',' -f2)
  newest_sha=$(echo "$newest" | cut -d',' -f3)
  newest_size=$(echo "$newest" | cut -d',' -f4)

  log "Newest:"
  log "  Path   : $newest_path"
  log "  Time   : $(date -d @"$newest_ts")"
  log "  Size   : $newest_size bytes"
  log "  SHA256 : $newest_sha"

  ############################################################
  # NEW INSTANCE FORMAT for v1.9.1:
  #
  #   Path | Modification Time | Size | SHA256
  ############################################################
  if [[ $INCLUDE_INSTANCES -eq 1 ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Instances of group '$key':" | tee -a "$LOG_FILE"
    echo "  Path | Modification Time | Size | SHA256" | tee -a "$LOG_FILE"

    while IFS=',' read -r ts path sha size; do
      [[ -z "$ts" ]] && continue
      fmt_time=$(date -d @"$ts")
      line="$path | $fmt_time | ${size} bytes | $sha"

      if [[ "$ts" == "$newest_ts" ]]; then
        format_newest "$line" | tee -a "$LOG_FILE"
      else
        echo "$line" | tee -a "$LOG_FILE"
      fi

      # CSV (updated order)
      if [[ -n "$CSV_EXPORT" ]]; then
        echo "\"$key\",\"$path\",\"$fmt_time\",\"$size\",\"$sha\"" >> "$CSV_EXPORT"
      fi

      # JSON (updated order)
      if [[ -n "$JSON_EXPORT" ]]; then
        esc_path=${path//\"/\\\"}
        esc_key=${key//\"/\\\"}
        JSON_ROWS+="$(printf '{"group_key":"%s","path":"%s","mtime":"%s","size":%s,"sha256":"%s"},' \
          "$esc_key" "$esc_path" "$fmt_time" "$size" "$sha")"
      fi

      if [[ $DIFF_VS_LATEST -eq 1 && "$ts" != "$newest_ts" ]]; then
        show_diff_vs_latest "$newest_ts" "$newest_sha" "$newest_size" "$ts" "$sha" "$size" \
          | tee -a "$LOG_FILE"
      fi
    done <<< "$sorted"
  fi
done

##############################################
# FINALIZE JSON
##############################################
if [[ -n "$JSON_EXPORT" ]]; then
  echo "[${JSON_ROWS%,}]" > "$JSON_EXPORT"
  log "JSON written: $JSON_EXPORT"
fi

if [[ -n "$CSV_EXPORT" ]]; then
  log "CSV written: $CSV_EXPORT"
fi

log "Done (v$VERSION)."

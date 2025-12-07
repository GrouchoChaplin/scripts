#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.9.2
#
# - Search a base root folder for sub-folders matching a pattern (e.g., *ir_imagery_tools*)
# - For each matched folder, gather all .dart files
# - Group .dart files by a chosen key (basename | relpath | fullpath)
# - For each group, find the latest-modified instance
# - Optionally show all instances with:
#       * path
#       * modification time
#       * size
#       * SHA256
# - Optional CSV and JSON export of all instances
# - Optional diff vs latest summary
# - Optional highlighting of newest instance in green (stdout)
# - v1.9.2: parallel hashing (when xargs -P available) + path-first instance format
#
set -euo pipefail

VERSION="1.9.2"

##############################
# Global flags / defaults
##############################
DEBUG=0                        # Set to 1 for debug logging
DEFAULT_LOG_FILE="find_latest_flutter_source.log"
LOG_FILE="$DEFAULT_LOG_FILE"

BASE_DIR=""
PATTERN="*ir_imagery_too*"     # Subdirectory name pattern to match

LATEST_PER_FILE=1              # Always doing per-file analysis in this tool
GROUP_BY_MODE="basename"       # basename | relpath | fullpath
INCLUDE_INSTANCES=0            # If 1, show per-instance details

CSV_EXPORT=""                  # If non-empty, path to CSV export file
JSON_EXPORT=""                 # If non-empty, path to JSON export file
JSON_ROWS=""                   # Accumulates JSON rows for final write

DIFF_VS_LATEST=0               # If 1, show diff vs latest for older instances
COLOR_NEWEST=0                 # If 1, highlight newest instance in green (stdout/log will see ANSI)

##############################
# Color helpers
##############################
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'
  GREEN=$'\e[32m'
  CYAN=$'\e[36m'
  YELLOW=$'\e[33m'
  RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; CYAN=""; YELLOW=""; RESET=""
fi

bold()        { printf '%b%s%b\n' "$BOLD" "$1" "$RESET"; }
green_text()  { printf '%b%s%b' "$GREEN" "$1" "$RESET"; }
cyan_text()   { printf '%b%s%b' "$CYAN" "$1" "$RESET"; }
yellow_text() { printf '%b%s%b' "$YELLOW" "$1" "$RESET"; }

##############################
# Logging helpers
##############################
debug() {
  if [[ $DEBUG -eq 1 ]]; then
    echo "$(yellow_text "[DEBUG]") $*" >&2
  fi
}

log() {
  # Always log to stdout AND append to log file
  echo "$1" | tee -a "$LOG_FILE"
}

##############################
# Formatting helpers
##############################
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

  local diff_text=""
  local delta=$(( newest_ts - file_ts ))

  if [[ $delta -gt 0 ]]; then
    diff_text+="    Δ time: ${delta}s older\n"
  fi

  if [[ "$newest_size" != "$file_size" ]]; then
    diff_text+="    Δ size: newest=${newest_size} vs this=${file_size}\n"
  fi

  if [[ "$newest_sha" != "$file_sha" ]]; then
    diff_text+="    SHA mismatch\n"
  fi

  if [[ -n "$diff_text" ]]; then
    printf "%b" "$diff_text"
  fi
}

write_csv() {
  local _group="$1"
  local line="$2"
  echo "$line" >> "$CSV_EXPORT"
}

write_json_row() {
  local json="$1"
  if [[ -z "$JSON_ROWS" ]]; then
    JSON_ROWS="$json"
  else
    JSON_ROWS="$JSON_ROWS,$json"
  fi
}

##############################
# Usage
##############################
usage() {
  cat <<EOF
$(bold "find_latest_flutter_source.sh – Flutter Source Version Finder v$VERSION")

Options:
  --paths DIR               Base directory to scan (required)
  --pattern PATTERN         Subdirectory pattern to match (default: $PATTERN)
  --group-by MODE           Group key for per-file analysis:
                              MODE is one of: basename | relpath | fullpath
  --include-instances       Include per-instance file details (path, mtime, size, SHA256)
  --csv FILE                Export per-instance data as CSV (append if exists)
  --json FILE               Export per-instance data as JSON array
  --diff-vs-latest          Show simple diff summary vs latest instance
  --color-newest            Highlight newest instance in green (stdout + log)
  --log-file FILE           Log output to a specified file (default: $DEFAULT_LOG_FILE)
  --debug                   Enable debug logging
  -h, --help                Show this help

Group-by modes:

  basename   – group by just the filename (e.g. "netcdf_screen.dart").
               All files with the same basename are grouped together.

  relpath    – group by relative path under lib/.
               Example (grouped together):
                 /A/lib/screens/home/home_screen.dart
                 /B/lib/screens/home/home_screen.dart

  fullpath   – no grouping at all; each file is treated as distinct.

Instance format (v1.9.2):

  Path | Modification Time | Size | SHA256

Example:

  find_latest_flutter_source.sh \\
    --paths "/run/media/peddycoartte/MasterBackup/ProjectWorkingCopyBackups" \\
    --pattern "*ir_imagery_tools*" \\
    --group-by basename \\
    --include-instances \\
    --diff-vs-latest \\
    --color-newest \\
    --csv dart_audit.csv \\
    --json dart_audit.json
EOF
}

##############################
# Argument parsing
##############################
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths)
      shift
      BASE_DIR="${1:-}"
      shift
      ;;
    --pattern)
      shift
      PATTERN="${1:-}"
      shift
      ;;
    --group-by)
      shift
      case "${1:-}" in
        basename|relpath|fullpath)
          GROUP_BY_MODE="$1"
          ;;
        *)
          echo "Invalid value for --group-by: ${1:-} (expected basename|relpath|fullpath)" >&2
          exit 1
          ;;
      esac
      shift
      ;;
    --include-instances)
      INCLUDE_INSTANCES=1
      shift
      ;;
    --csv)
      shift
      CSV_EXPORT="${1:-}"
      shift
      ;;
    --json)
      shift
      JSON_EXPORT="${1:-}"
      shift
      ;;
    --diff-vs-latest)
      DIFF_VS_LATEST=1
      shift
      ;;
    --color-newest)
      COLOR_NEWEST=1
      shift
      ;;
    --log-file)
      shift
      LOG_FILE="${1:-$DEFAULT_LOG_FILE}"
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$BASE_DIR" ]]; then
  echo "Error: --paths BASE_DIR is required." >&2
  exit 1
fi

##############################
# CSV / JSON initialization
##############################
if [[ -n "$CSV_EXPORT" ]]; then
  if [[ ! -f "$CSV_EXPORT" ]]; then
    echo "group_key,path,mtime,size,sha256" > "$CSV_EXPORT"
  fi
fi

if [[ -n "$JSON_EXPORT" ]]; then
  JSON_ROWS=""   # Ensure empty at start
fi

##############################
# Find matching subdirectories
##############################
log "Base directory: $BASE_DIR"
log "Searching for directories matching pattern '$PATTERN'..."

mapfile -t SCAN_DIRS < <(find "$BASE_DIR" -type d -name "$PATTERN" 2>/dev/null || true)

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  log "No subdirectories found matching pattern '$PATTERN'."
  if [[ -n "$JSON_EXPORT" ]]; then
    echo "[]" > "$JSON_EXPORT"
  fi
  exit 0
fi

debug "Found subfolders: ${SCAN_DIRS[*]}"

##############################
# Scan .dart files (parallel hashing)
##############################
declare -A dart_files  # key: group key, val: newline-separated "epoch,path,sha,size"

get_group_key() {
  local path="$1"
  case "$GROUP_BY_MODE" in
    basename)
      basename "$path"
      ;;
    relpath)
      # relative path under /lib/
      local trimmed="${path#*/lib/}"
      if [[ "$trimmed" == "$path" ]]; then
        basename "$path"
      else
        echo "$trimmed"
      fi
      ;;
    fullpath)
      echo "$path"
      ;;
    *)
      basename "$path"
      ;;
  esac
}

log "Scanning .dart files in matched directories..."

# Collect all .dart files from all SCAN_DIRS
DART_FILES=()
for dir in "${SCAN_DIRS[@]}"; do
  debug "  Collecting from: $dir"
  while IFS= read -r f; do
    DART_FILES+=("$f")
  done < <(find "$dir" -type f -name "*.dart" 2>/dev/null || true)
done

if [[ ${#DART_FILES[@]} -eq 0 ]]; then
  log "No .dart files found under matched directories."
  if [[ -n "$JSON_EXPORT" ]]; then
    echo "[]" > "$JSON_EXPORT"
  fi
  exit 0
fi

# Detect if xargs -P is available
SUPPORT_XARGS_P=0
if xargs -P 2>/dev/null <<<"" >/dev/null 2>&1; then
  SUPPORT_XARGS_P=1
fi

JOBS=$(( $(command -v nproc >/dev/null 2>&1 && nproc || echo 4) ))

if [[ $SUPPORT_XARGS_P -eq 1 ]]; then
  debug "Using parallel hashing with xargs -P $JOBS"
  # Parallel hashing via xargs
  while IFS=',' read -r ts path sha size; do
    [[ -z "$path" ]] && continue
    group_key=$(get_group_key "$path")
    dart_files["$group_key"]+="${ts},${path},${sha},${size}"$'\n'
  done < <(
    printf '%s\0' "${DART_FILES[@]}" \
      | xargs -0 -n 1 -P "$JOBS" bash -c '
          file="$1"
          ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
          size=$(stat -c %s "$file" 2>/dev/null || echo 0)
          sha=$(sha256sum "$file" 2>/dev/null | awk "{print \$1}")
          printf "%s,%s,%s,%s\n" "$ts" "$file" "$sha" "$size"
        ' _
  )
else
  log "xargs -P not available; falling back to serial hashing."
  for file in "${DART_FILES[@]}"; do
    ts=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    size=$(stat -c %s "$file" 2>/dev/null || echo 0)
    sha=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
    group_key=$(get_group_key "$file")
    dart_files["$group_key"]+="${ts},${file},${sha},${size}"$'\n'
  done
fi

if [[ ${#dart_files[@]} -eq 0 ]]; then
  log "No .dart files grouped successfully."
  if [[ -n "$JSON_EXPORT" ]]; then
    echo "[]" > "$JSON_EXPORT"
  fi
  exit 0
fi

##############################
# Process per group
##############################
log "Processing Dart file groups..."

for group_key in "${!dart_files[@]}"; do
  echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
  log "Processing group key: $group_key"

  # Sort instances newest → oldest by epoch (field 1)
  sorted_files=$(echo -e "${dart_files["$group_key"]}" | sed '/^$/d' | sort -t ',' -k1,1nr)

  # Extract newest instance
  newest_line=$(echo "$sorted_files" | head -n 1)
  newest_ts=$(echo "$newest_line" | cut -d',' -f1)
  newest_path=$(echo "$newest_line" | cut -d',' -f2)
  newest_sha=$(echo "$newest_line" | cut -d',' -f3)
  newest_size=$(echo "$newest_line" | cut -d',' -f4)

  log "Most recent version for group '$group_key':"
  log "    Path    : $newest_path"
  log "    Modified: $(date -d @"$newest_ts")"
  log "    Size    : ${newest_size} bytes"
  log "    SHA256  : $newest_sha"

  ############################################################
  # Per-instance detail (conditional)
  # NEW FORMAT (v1.9.2):
  #   Path | Modification Time | Size | SHA256
  ############################################################
  if [[ $INCLUDE_INSTANCES -eq 1 ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Instances of group '$group_key':" | tee -a "$LOG_FILE"
    echo "  Path | Modification Time | Size | SHA256" | tee -a "$LOG_FILE"

    while IFS=',' read -r ts path sha size; do
      [[ -n "$ts" ]] || continue  # skip empty lines
      formatted_time=$(date -d @"$ts")

      line="$path | $formatted_time | ${size} bytes | $sha"

      if [[ "$ts" == "$newest_ts" && $COLOR_NEWEST -eq 1 ]]; then
        fmt_line=$(format_newest "$line")
      else
        fmt_line="$line"
      fi

      echo "$fmt_line" | tee -a "$LOG_FILE"

      # Diff vs latest (only for non-latest)
      if [[ $DIFF_VS_LATEST -eq 1 && "$ts" != "$newest_ts" ]]; then
        show_diff_vs_latest "$newest_ts" "$newest_sha" "$newest_size" "$ts" "$sha" "$size" \
          | tee -a "$LOG_FILE"
      fi

      # CSV export (updated order)
      if [[ -n "$CSV_EXPORT" ]]; then
        csv_line="\"$group_key\",\"$path\",\"$formatted_time\",\"$size\",\"$sha\""
        write_csv "$group_key" "$csv_line"
      fi

      # JSON export (updated order)
      if [[ -n "$JSON_EXPORT" ]]; then
        esc_path=${path//\"/\\\"}
        esc_group=${group_key//\"/\\\"}
        json_entry="{\"group_key\":\"$esc_group\",\"path\":\"$esc_path\",\"mtime\":\"$formatted_time\",\"size\":$size,\"sha256\":\"$sha\"}"
        write_json_row "$json_entry"
      fi

    done <<< "$sorted_files"

    echo "" | tee -a "$LOG_FILE"
  else
    # Even if we don't show instances, we may still want CSV/JSON
    while IFS=',' read -r ts path sha size; do
      [[ -n "$ts" ]] || continue
      formatted_time=$(date -d @"$ts")

      if [[ -n "$CSV_EXPORT" ]]; then
        csv_line="\"$group_key\",\"$path\",\"$formatted_time\",\"$size\",\"$sha\""
        write_csv "$group_key" "$csv_line"
      fi

      if [[ -n "$JSON_EXPORT" ]]; then
        esc_path=${path//\"/\\\"}
        esc_group=${group_key//\"/\\\"}
        json_entry="{\"group_key\":\"$esc_group\",\"path\":\"$esc_path\",\"mtime\":\"$formatted_time\",\"size\":$size,\"sha256\":\"$sha\"}"
        write_json_row "$json_entry"
      fi

    done <<< "$sorted_files"
  fi
done

##############################
# Finalize JSON (if requested)
##############################
if [[ -n "$JSON_EXPORT" ]]; then
  if [[ -z "$JSON_ROWS" ]]; then
    echo "[]" > "$JSON_EXPORT"
  else
    printf '[%s]\n' "$JSON_ROWS" > "$JSON_EXPORT"
  fi
  log "JSON export written to: $JSON_EXPORT"
fi

if [[ -n "$CSV_EXPORT" ]]; then
  log "CSV export written to: $CSV_EXPORT"
fi

log "Done (v$VERSION)."

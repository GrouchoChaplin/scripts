\
#!/usr/bin/env bash
# find_latest_flutter_source_v1.9.2.sh
# Simplified Analyzer for Dart Backup Toolkit
#
# - Scan one or more backup roots for subdirectories matching a pattern
# - Collect all *.dart files
# - Group them by basename/relpath/fullpath
# - Determine the newest instance per group
# - Optionally print all instances
# - Optionally export CSV / JSON
#
set -euo pipefail

VERSION="1.9.2"

LOG_FILE="find_latest_flutter_source.log"
PATTERN="*"
GROUP_BY_MODE="relpath"
INCLUDE_INSTANCES=0
CSV_EXPORT=""
JSON_EXPORT=""
BASE_DIRS=()

usage() {
  cat <<EOF
find_latest_flutter_source_v${VERSION}.sh – Dart Analyzer

Usage:
  $0 --paths DIR1 [DIR2 ...] [options]

Options:
  --paths DIR1 [DIR2 ...]   One or more base directories to scan (required)
  --pattern PATTERN         Subdirectory name pattern to match (default: "*")
  --group-by MODE           Group key: basename | relpath | fullpath (default: relpath)
  --include-instances       Show all instances per group (not just newest)
  --csv FILE                Export per-instance rows to CSV
  --json FILE               Export per-instance rows to JSON
  --log-file FILE           Log file path (default: ${LOG_FILE})
  -h, --help                Show this help

CSV/JSON schema:
  group_key,mtime,sha256,size,path

EOF
}

log() {
  echo "$*" | tee -a "$LOG_FILE"
}

# Parse args
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths)
      shift
      # consume all non-flag args as paths until next -- or end
      while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
        BASE_DIRS+=("$1")
        shift
      done
      ;;
    --pattern)
      shift
      PATTERN="${1:-*}"
      shift
      ;;
    --group-by)
      shift
      case "${1:-}" in
        basename|relpath|fullpath) GROUP_BY_MODE="$1" ;;
        *) echo "Invalid --group-by value: ${1:-}" >&2; exit 1 ;;
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
    --log-file)
      shift
      LOG_FILE="${1:-$LOG_FILE}"
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

if [[ ${#BASE_DIRS[@]} -eq 0 ]]; then
  echo "Error: at least one --paths DIR is required." >&2
  exit 1
fi

: > "$LOG_FILE"

# CSV/JSON init
if [[ -n "$CSV_EXPORT" && ! -f "$CSV_EXPORT" ]]; then
  echo "group_key,mtime,sha256,size,path" > "$CSV_EXPORT"
fi

JSON_ROWS=""

append_json() {
  local json="$1"
  if [[ -z "$JSON_ROWS" ]]; then
    JSON_ROWS="$json"
  else
    JSON_ROWS="$JSON_ROWS,$json"
  fi
}

get_group_key() {
  local path="$1"
  case "$GROUP_BY_MODE" in
    basename)
      basename "$path"
      ;;
    relpath)
      # attempt to compute relpath under lib/
      local trimmed="${path#*/lib/}"
      if [[ "$trimmed" == "$path" ]]; then
        echo "$(basename "$path")"
      else
        echo "$trimmed"
      fi
      ;;
    fullpath)
      echo "$path"
      ;;
  esac
}

declare -A GROUPS

log "Analyzer v${VERSION}"
log "Log file: $LOG_FILE"
log "Group-by mode: $GROUP_BY_MODE"
log "Subdirectory pattern: $PATTERN"
log "Base dirs: ${BASE_DIRS[*]}"

# Discover candidate dirs
SCAN_DIRS=()
for base in "${BASE_DIRS[@]}"; do
  if [[ ! -d "$base" ]]; then
    log "WARNING: base dir not found: $base"
    continue
  fi
  while IFS= read -r d; do
    SCAN_DIRS+=("$d")
  done < <(find "$base" -type d -name "$PATTERN" 2>/dev/null || true)
done

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  log "No subdirectories found matching '$PATTERN'."
  exit 0
fi

log "Found ${#SCAN_DIRS[@]} matching subdirectories."

# Scan .dart files
for d in "${SCAN_DIRS[@]}"; do
  log "Scanning: $d"
  while IFS= read -r f; do
    [[ "$f" == *.dart ]] || continue
    ts=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    size=$(stat -c %s "$f" 2>/dev/null || echo 0)
    sha=$(sha256sum "$f" 2>/dev/null | awk '{print $1}')
    key=$(get_group_key "$f")
    GROUPS["$key"]+="${ts},${f},${sha},${size}"$'\n'
  done < <(find "$d" -type f -name "*.dart" 2>/dev/null || true)
done

if [[ ${#GROUPS[@]} -eq 0 ]]; then
  log "No .dart files found."
  exit 0
fi

log "Processing groups..."

for key in "${!GROUPS[@]}"; do
  echo "------------------------------------------------------------" | tee -a "$LOG_FILE"
  log "Group: $key"

  entries=$(echo -e "${GROUPS[$key]}" | sed '/^$/d' | sort -t',' -k1,1nr)
  newest_line=$(echo "$entries" | head -n 1)
  newest_ts=$(echo "$newest_line" | cut -d',' -f1)
  newest_path=$(echo "$newest_line" | cut -d',' -f2)
  newest_sha=$(echo "$newest_line" | cut -d',' -f3)
  newest_size=$(echo "$newest_line" | cut -d',' -f4)

  log "Newest:"
  log "  Path   : $newest_path"
  log "  MTime  : $(date -d @"$newest_ts")"
  log "  Size   : ${newest_size} bytes"
  log "  SHA256 : $newest_sha"

  if [[ -n "$CSV_EXPORT" || -n "$JSON_EXPORT" ]]; then
    while IFS=',' read -r ts path sha size; do
      [[ -n "$ts" ]] || continue
      mtime=$(date -d @"$ts" +"%Y-%m-%d %H:%M:%S")
      if [[ -n "$CSV_EXPORT" ]]; then
        printf '"%s","%s","%s","%s","%s"\n' "$key" "$mtime" "$sha" "$size" "$path" >> "$CSV_EXPORT"
      fi
      if [[ -n "$JSON_EXPORT" ]]; then
        esc_path=${path//\"/\\\"}
        esc_key=${key//\"/\\\"}
        esc_mtime=${mtime//\"/\\\"}
        json_entry="{\"group_key\":\"$esc_key\",\"mtime\":\"$esc_mtime\",\"sha256\":\"$sha\",\"size\":$size,\"path\":\"$esc_path\"}"
        append_json "$json_entry"
      fi
    done <<< "$entries"
  fi

  if [[ $INCLUDE_INSTANCES -eq 1 ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Instances of group '$key':" | tee -a "$LOG_FILE"
    echo "  Path | Modification Time | Size | SHA256" | tee -a "$LOG_FILE"
    while IFS=',' read -r ts path sha size; do
      [[ -n "$ts" ]] || continue
      mtime=$(date -d @"$ts")
      printf "  %s | %s | %s bytes | %s\n" "$path" "$mtime" "$size" "$sha" | tee -a "$LOG_FILE"
    done <<< "$entries"
    echo "" | tee -a "$LOG_FILE"
  fi

done

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

log "Done."

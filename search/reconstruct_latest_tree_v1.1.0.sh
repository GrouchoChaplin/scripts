#!/usr/bin/env bash
#
# reconstruct_latest_tree_v1.0.sh
#
# Companion for find_latest_flutter_source_v1.9.2.sh
#
# Reads CSV or JSON export and reconstructs a synthetic "latest" source tree:
#   OUT_DIR/<group_key>  -> copy of latest-version file for that group.
#
# Assumes analyzer CSV header: group_key,path,mtime,size,sha256
# Assumes analyzer JSON objects: { group_key, path, mtime, size, sha256 }
#
set -euo pipefail

JSON_FILE=""
CSV_FILE=""
OUT_DIR=""
DEBUG=0

usage() {
  cat <<EOF
reconstruct_latest_tree_v1.0.sh – Rebuild latest-version Dart tree

Options:
  --json FILE      JSON export from find_latest_flutter_source_v1.9.2.sh
  --csv FILE       CSV export from find_latest_flutter_source_v1.9.2.sh
  --out DIR        Output directory for reconstructed latest tree (required)
  --debug          Enable debug logging
  -h, --help       Show this help

Notes:
  - Exactly one of --json or --csv must be provided.
  - The relative path inside OUT is taken from group_key.
    So for best results, run the analyzer with: --group-by relpath

Example:

  ./reconstruct_latest_tree_v1.0.sh \\
      --json dart_audit.json \\
      --out latest_tree/
EOF
}

log()   { echo "$*"; }
debug() { [[ $DEBUG -eq 1 ]] && echo "[DEBUG] $*" >&2; }

########################################
# Parse arguments
########################################
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_FILE="$2"; shift 2;;
    --csv)  CSV_FILE="$2"; shift 2;;
    --out)  OUT_DIR="$2"; shift 2;;
    --debug) DEBUG=1; shift;;
    -h|--help) usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  echo "Error: --out DIR is required." >&2
  exit 1
fi

if [[ -n "$JSON_FILE" && -n "$CSV_FILE" ]]; then
  echo "Error: Provide only one of --json or --csv, not both." >&2
  exit 1
fi

if [[ -z "$JSON_FILE" && -z "$CSV_FILE" ]]; then
  echo "Error: Must provide either --json or --csv." >&2
  exit 1
fi

if [[ -n "$JSON_FILE" && ! -f "$JSON_FILE" ]]; then
  echo "JSON file not found: $JSON_FILE" >&2
  exit 1
fi

if [[ -n "$CSV_FILE" && ! -f "$CSV_FILE" ]]; then
  echo "CSV file not found: $CSV_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

########################################
# Data structures
########################################
declare -A ALL_FILES   # key -> newline list "epoch,path,sha,size"
declare -A LATEST      # key -> "epoch,path,sha,size"

########################################
# Parsers
########################################
parse_csv() {
  local csv="$1"
  local header=1

  while IFS=',' read -r key path mtime size sha; do
    # skip header
    if [[ $header -eq 1 ]]; then
      header=0
      continue
    fi

    # strip quotes
    key="${key%\"}"; key="${key#\"}"
    path="${path%\"}"; path="${path#\"}"
    mtime="${mtime%\"}"; mtime="${mtime#\"}"
    size="${size%\"}"; size="${size#\"}"
    sha="${sha%\"}"; sha="${sha#\"}"

    [[ -z "$path" ]] && continue

    local epoch
    epoch=$(date -d "$mtime" +%s 2>/dev/null || echo 0)

    ALL_FILES["$key"]+="${epoch},${path},${sha},${size}"$'\n'
  done < "$csv"
}

parse_json() {
  local json="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to parse JSON input." >&2
    exit 1
  fi

  mapfile -t rows < <(jq -c '.[]' "$json")

  for row in "${rows[@]}"; do
    local key path mtime size sha epoch
    key=$(echo "$row"  | jq -r '.group_key')
    path=$(echo "$row" | jq -r '.path')
    mtime=$(echo "$row"| jq -r '.mtime')
    size=$(echo "$row" | jq -r '.size')
    sha=$(echo "$row"  | jq -r '.sha256')

    [[ -z "$path" ]] && continue

    epoch=$(date -d "$mtime" +%s 2>/dev/null || echo 0)

    ALL_FILES["$key"]+="${epoch},${path},${sha},${size}"$'\n'
  done
}

########################################
# Load data
########################################
if [[ -n "$CSV_FILE" ]]; then
  debug "Parsing CSV: $CSV_FILE"
  parse_csv "$CSV_FILE"
fi

if [[ -n "$JSON_FILE" ]]; then
  debug "Parsing JSON: $JSON_FILE"
  parse_json "$JSON_FILE"
fi

if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
  echo "No file groups found in input. Nothing to reconstruct." >&2
  exit 0
fi

########################################
# Determine newest per group
########################################
for key in "${!ALL_FILES[@]}"; do
  # sort newest → oldest by epoch
  local sorted
  sorted=$(echo -e "${ALL_FILES[$key]}" | sed '/^$/d' | sort -t',' -k1,1nr)
  local newest
  newest=$(echo "$sorted" | head -n 1)
  LATEST["$key"]="$newest"
done

########################################
# Reconstruct latest tree
########################################
log "Reconstructing latest tree into: $OUT_DIR"

for key in "${!LATEST[@]}"; do
  local entry="${LATEST[$key]}"
  local epoch path sha size

  epoch=$(echo "$entry" | cut -d',' -f1)
  path=$(echo "$entry"  | cut -d',' -f2)
  sha=$(echo "$entry"   | cut -d',' -f3)
  size=$(echo "$entry"  | cut -d',' -f4)

  # Use group_key as relative path inside OUT_DIR
  local rel="$key"
  local out_path="$OUT_DIR/$rel"

  mkdir -p "$(dirname "$out_path")"

  if [[ -f "$path" ]]; then
    cp "$path" "$out_path"
    debug "Copied: $path -> $out_path"
  else
    log "Warning: source file missing, skipping: $path"
  fi
done

log "Reconstruction complete."

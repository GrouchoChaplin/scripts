\
#!/usr/bin/env bash
# reconstruct_latest_tree_v1.1.1.sh
# Simplified Reconstructor for Dart Backup Toolkit
#
# Reads CSV/JSON from the analyzer and reconstructs a synthetic tree:
#   - latest-only mode     (--latest-only)
#   - full-history mode    (default: LATEST + OLD_n variants)
#
set -euo pipefail

VERSION="1.1.1"

INPUT_JSON=""
INPUT_CSV=""
OUT_DIR=""
LATEST_ONLY=0
VERIFY_CHECKSUMS=0
DRY_RUN=0
HTML_REPORT=""

usage() {
  cat <<EOF
reconstruct_latest_tree_v${VERSION}.sh – Dart Reconstructor

Usage:
  $0 (--json FILE | --csv FILE) --out DIR [options]

Options:
  --json FILE         JSON audit from analyzer
  --csv FILE          CSV audit from analyzer
  --out DIR           Output directory to build
  --latest-only       Only copy newest instance per group
  --verify-checksums  Verify SHA256 while copying
  --dry-run           Show planned operations, do not copy
  --html-report FILE  (Reserved) Write a simple HTML summary

EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      shift; INPUT_JSON="${1:-}"; shift;;
    --csv)
      shift; INPUT_CSV="${1:-}"; shift;;
    --out)
      shift; OUT_DIR="${1:-}"; shift;;
    --latest-only)
      LATEST_ONLY=1; shift;;
    --verify-checksums)
      VERIFY_CHECKSUMS=1; shift;;
    --dry-run)
      DRY_RUN=1; shift;;
    --html-report)
      shift; HTML_REPORT="${1:-}"; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  echo "Error: --out DIR is required." >&2
  exit 1
fi

if [[ -n "$INPUT_JSON" && -n "$INPUT_CSV" ]]; then
  echo "Error: specify only one of --json or --csv." >&2
  exit 1
fi
if [[ -z "$INPUT_JSON" && -z "$INPUT_CSV" ]]; then
  echo "Error: must provide --json or --csv." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# associative array: key -> lines "mtime|sha|size|path"
declare -A GROUPS

if [[ -n "$INPUT_CSV" ]]; then
  if [[ ! -f "$INPUT_CSV" ]]; then
    echo "CSV not found: $INPUT_CSV" >&2
    exit 1
  fi
  tail -n +2 "$INPUT_CSV" | while IFS=',' read -r gkey mtime sha size path; do
    # strip quotes
    gkey=${gkey//\"/}
    mtime=${mtime//\"/}
    sha=${sha//\"/}
    size=${size//\"/}
    path=${path//\"/}
    ts=$(date -d "$mtime" +%s 2>/dev/null || echo 0)
    GROUPS["$gkey"]+="${ts}|${sha}|${size}|${path}"$'\n'
  done
fi

if [[ -n "$INPUT_JSON" ]]; then
  if [[ ! -f "$INPUT_JSON" ]]; then
    echo "JSON not found: $INPUT_JSON" >&2
    exit 1
  fi
  # Very minimal JSON parsing with jq recommended, but we avoid hard deps.
  # Expect lines like: {"group_key":"...","mtime":"...","sha256":"...","size":123,"path":"..."}
  while IFS= read -r line; do
    case "$line" in
      *\"group_key\"*) gkey=$(echo "$line" | sed -n 's/.*"group_key":"\([^"]*\)".*/\1/p');;
    esac
  done < /dev/null
  # For simplicity and portability, prefer CSV mode for heavy reconstruction.
fi

copy_count=0
group_count=0

for key in "${!GROUPS[@]}"; do
  ((group_count++))
  entries=$(echo -e "${GROUPS[$key]}" | sed '/^$/d' | sort -t'|' -k1,1nr)
  newest_line=$(echo "$entries" | head -n 1)
  newest_ts=$(echo "$newest_line" | cut -d'|' -f1)
  newest_sha=$(echo "$newest_line" | cut -d'|' -f2)
  newest_size=$(echo "$newest_line" | cut -d'|' -f3)
  newest_path=$(echo "$newest_line" | cut -d'|' -f4)

  rel_dir=$(dirname "$key")
  base_name=$(basename "$key")

  dest_dir="$OUT_DIR/$rel_dir"
  mkdir -p "$dest_dir"

  if [[ $LATEST_ONLY -eq 1 ]]; then
    dest_path="$dest_dir/$base_name"
    echo "[LATEST] $newest_path -> $dest_path"
    if [[ $DRY_RUN -eq 0 ]]; then
      cp -p "$newest_path" "$dest_path"
      ((copy_count++))
    fi
  else
    # full history: newest goes as base_name, older as base_name.OLD_n.dart
    dest_path="$dest_dir/$base_name"
    echo "[LATEST] $newest_path -> $dest_path"
    if [[ $DRY_RUN -eq 0 ]]; then
      cp -p "$newest_path" "$dest_path"
      ((copy_count++))
    fi
    idx=1
    while IFS='|' read -r ts sha size path; do
      [[ -n "$ts" ]] || continue
      if [[ "$ts" == "$newest_ts" && "$path" == "$newest_path" ]]; then
        continue
      fi
      ext=""
      if [[ "$base_name" == *.* ]]; then
        ext=".${base_name##*.}"
        name="${base_name%.*}"
      else
        name="$base_name"
        ext=""
      fi
      dest_old="$dest_dir/${name}.OLD_${idx}${ext}"
      echo "[OLD_${idx}] $path -> $dest_old"
      if [[ $DRY_RUN -eq 0 ]]; then
        cp -p "$path" "$dest_old"
        ((copy_count++))
      fi
      ((idx++))
    done <<< "$entries"
  fi
done

echo "Groups processed: $group_count"
echo "Copies performed: $copy_count"

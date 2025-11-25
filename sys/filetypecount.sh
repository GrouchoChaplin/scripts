#!/usr/bin/env bash

# DO NOT USE: set -euo pipefail here because Rocky/RHEL Bash breaks read loops
set -uo pipefail

BAR_WIDTH=50
DIR="."
TOP=""
GRAPH=1

declare -A ext_counts=()
declare -a EXCLUDES=()

usage() {
cat <<EOF
Usage: $(basename "$0") [DIR] [OPTIONS]

Options:
  --top N         Only show top N extensions
  --no-graph      Disable the ASCII bar graph
  --exclude PAT   Exclude path (may repeat)
  -h, --help      Help
EOF
exit 0
}

# ----------------------------------
# Parse arguments
# ----------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --top) TOP="$2"; shift 2 ;;
    --no-graph) GRAPH=0; shift ;;
    --exclude) EXCLUDES+=("$2"); shift 2 ;;
    -*)
      echo "Unknown option: $1"
      exit 1 ;;
    *)
      DIR="$1"; shift ;;
  esac
done

[[ ! -d "$DIR" ]] && { echo "Invalid directory: $DIR"; exit 1; }

# ----------------------------------
# Normalize excludes
# ----------------------------------
normalize_pattern() {
  local p="$1"

  case "$p" in
    *.git*|*/.git*)
      echo "*/.git/*" ;;
    *build*|*/build*)
      echo "*/build/*" ;;
    *)
      # prepend */ if missing dir separators
      [[ "$p" != */* ]] && p="*/$p"
      echo "$p" ;;
  esac
}

declare -a FIXED_EXCLUDES=()
for p in "${EXCLUDES[@]}"; do
  FIXED_EXCLUDES+=("$(normalize_pattern "$p")")
done

# ----------------------------------
# Build find command
# ----------------------------------
find_cmd=(find "$DIR" -type f)

for pat in "${FIXED_EXCLUDES[@]}"; do
  find_cmd+=(-not -path "$pat")
done

# ----------------------------------
# DEBUG: print find command
# ----------------------------------
echo "[DEBUG] Running:"
printf "  %q " "${find_cmd[@]}"
echo -e " -print0\n"

# ----------------------------------
# Line-by-line safe reading
# ----------------------------------
file_count=0

# Use a pipe instead of process substitution
"${find_cmd[@]}" -print0 | \
while IFS= read -r -d '' file; do
  ((file_count++))

  base="${file##*/}"

  if [[ "$base" == *.* ]]; then
    ext="${base##*.}"
  else
    ext="NO_EXT"
  fi

  (( ext_counts["$ext"]++ ))
done

# ----------------------------------
# After loop, file_count is local to subshell unless exported
# Fix: recalc file_count from ext_counts
# ----------------------------------
real_total=0
for c in "${ext_counts[@]}"; do
  (( real_total += c ))
done

file_count="$real_total"

# ----------------------------------
# Output diagnostics if no files
# ----------------------------------
if (( file_count == 0 )); then
  echo "No files found."
  echo "Directory: $DIR"
  echo "Raw excludes: ${EXCLUDES[*]:-(none)}"
  echo "Normalized excludes: ${FIXED_EXCLUDES[*]:-(none)}"
  exit 0
fi

# ----------------------------------
# Compute totals
# ----------------------------------
maxcount=0
for v in "${ext_counts[@]}"; do
  (( v > maxcount )) && maxcount=$v
done
(( maxcount == 0 )) && maxcount=1

# ----------------------------------
# Save sorted results
# ----------------------------------
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

for ext in "${!ext_counts[@]}"; do
  printf "%s\t%d\n" "$ext" "${ext_counts[$ext]}" >> "$tmpfile"
done

sort -k2,2nr -k1,1 "$tmpfile" -o "$tmpfile"

if [[ -n "$TOP" ]]; then
  tmp2=$(mktemp)
  head -n "$TOP" "$tmpfile" > "$tmp2"
  mv "$tmp2" "$tmpfile"
fi

# ----------------------------------
# Print header
# ----------------------------------
echo "Directory: $DIR"
echo "Total files: $file_count"
echo "Excludes (raw): ${EXCLUDES[*]:-(none)}"
echo "Excludes (normalized): ${FIXED_EXCLUDES[*]:-(none)}"
echo

printf "%-15s %10s %9s  %s\n" "EXTENSION" "COUNT" "PERCENT" "GRAPH"
printf "%-15s %10s %9s  %s\n" "---------" "-----" "-------" "-----"

# ----------------------------------
# Print rows
# ----------------------------------
while IFS=$'\t' read -r ext count; do
  pct=$(awk -v c="$count" -v t="$file_count" 'BEGIN { printf("%.1f", (c*100)/t) }')

  if (( GRAPH )); then
    bar_len=$(( count * BAR_WIDTH / maxcount ))
    (( bar_len == 0 && count > 0 )) && bar_len=1
    bar=$(printf '%*s' "$bar_len" '' | tr ' ' '#')
  else
    bar=""
  fi

  printf "%-15s %10d %8s%%  %s\n" "$ext" "$count" "$pct" "$bar"
done < "$tmpfile"

#!/usr/bin/env bash
#
# Description: Reads file paths from foundfiles.txt, sorts them by modification
# time, logs results to a timestamped file, and warns about missing files.
#
# Author:      peddycoartte
# Created:     2025-11-08 16:01:27
# Usage:       
#

set -e
set -o pipefail
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sort_files_by_mtime.sh
# Reads file paths from foundfiles.txt, sorts them by modification time,
# logs results to a timestamped file, warns about missing files,
# and optionally includes file sizes in human-readable format.
# ---------------------------------------------------------------------------

INPUT_FILE="foundfiles.txt"
LOG_FILE="sorted_files_$(date '+%Y-%m-%d_%H-%M-%S').log"
TEMP_FILE=$(mktemp)
INCLUDE_SIZE=false
MISSING_COUNT=0

# --- Parse optional flags ---
for arg in "$@"; do
  case "$arg" in
    --size|-s) INCLUDE_SIZE=true ;;
    *) echo "⚠️  Unknown option: $arg" ;;
  esac
done

echo "📂 Reading from: $INPUT_FILE"
echo "🕒 Writing results to: $LOG_FILE"
$INCLUDE_SIZE && echo "📏 Including file sizes"
echo

{
  echo "Sorted file modification times (oldest → newest)"
  echo "Generated on $(date)"
  echo "----------------------------------------------"

  # Collect file metadata
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue  # skip blank lines
    if [[ -f "$file" ]]; then
      if $INCLUDE_SIZE; then
        # Try stat normally
        if stat --format='%Y %s %n' "$file" >> "$TEMP_FILE" 2>/dev/null; then
          :
        # Retry with sudo quietly
        elif sudo -n stat --format='%Y %s %n' "$file" >> "$TEMP_FILE" 2>/dev/null; then
          :
        else
          echo "MISSING: $file"
          ((MISSING_COUNT++))
        fi
      else
        if stat --format='%Y %n' "$file" >> "$TEMP_FILE" 2>/dev/null; then
          :
        elif sudo -n stat --format='%Y %n' "$file" >> "$TEMP_FILE" 2>/dev/null; then
          :
        else
          echo "MISSING: $file"
          ((MISSING_COUNT++))
        fi
      fi
    else
      echo "MISSING: $file"
      ((MISSING_COUNT++))
    fi
  done < "$INPUT_FILE"

  # Format and sort results
  if $INCLUDE_SIZE; then
    sort -n "$TEMP_FILE" | awk '
      function human(x) {
        if (x<1024) return x " B";
        if (x<1048576) return sprintf("%.1f KB", x/1024);
        if (x<1073741824) return sprintf("%.1f MB", x/1048576);
        return sprintf("%.2f GB", x/1073741824);
      }
      /^[0-9]+/ {
        t=$1; size=$2; $1=$2="";
        printf "%s  %-8s  %s\n", strftime("%Y-%m-%d %H:%M:%S", t), human(size), substr($0,3);
      }'
  else
    sort -n "$TEMP_FILE" | awk '
      /^[0-9]+/ {
        $1=strftime("%Y-%m-%d %H:%M:%S",$1);
        print;
      }'
  fi

  rm -f "$TEMP_FILE"

  echo "----------------------------------------------"
  echo "Checked $(wc -l < "$INPUT_FILE") files total."
  echo "Missing or inaccessible: $MISSING_COUNT"
} | tee "$LOG_FILE"

echo
echo "✅ Done. Results saved in: $LOG_FILE"
[[ $MISSING_COUNT -gt 0 ]] && echo "⚠️  $MISSING_COUNT file(s) were missing or inaccessible."

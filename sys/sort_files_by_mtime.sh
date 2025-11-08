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

INPUT_FILE="foundfiles.txt"
LOG_FILE="sorted_files_$(date '+%Y-%m-%d_%H-%M-%S').log"
MISSING_COUNT=0
TEMP_FILE=$(mktemp)

echo "📂 Reading from: $INPUT_FILE"
echo "🕒 Writing results to: $LOG_FILE"
echo

{
  echo "Sorted file modification times (oldest → newest)"
  echo "Generated on $(date)"
  echo "----------------------------------------------"

  # Collect timestamps safely
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue  # skip blank lines

    if [[ -f "$file" ]]; then
      # Try stat normally; if permission denied, retry with sudo
      if ! stat --format='%Y %n' "$file" >> "$TEMP_FILE" 2>/dev/null; then
        sudo -n stat --format='%Y %n' "$file" >> "$TEMP_FILE" 2>/dev/null || {
          echo "MISSING: $file"
          ((MISSING_COUNT++))
        }
      fi
    else
      echo "MISSING: $file"
      ((MISSING_COUNT++))
    fi
  done < "$INPUT_FILE"

  # Sort and pretty-print
  sort -n "$TEMP_FILE" 2>/dev/null | awk '
    /^[0-9]+/ {
      $1 = strftime("%Y-%m-%d %H:%M:%S", $1);
      print;
    }'
  rm -f "$TEMP_FILE"

  echo "----------------------------------------------"
  echo "Checked $(wc -l < "$INPUT_FILE") files total."
  echo "Missing or inaccessible: $MISSING_COUNT"
} | tee "$LOG_FILE"

echo
echo "✅ Done. Results saved in: $LOG_FILE"
[[ $MISSING_COUNT -gt 0 ]] && echo "⚠️  $MISSING_COUNT file(s) were missing or inaccessible."

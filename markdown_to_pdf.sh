#!/usr/bin/env bash
set -e

INPUT="README.md"
OUTPUT="README.pdf"

pandoc "$INPUT" \
  --resource-path=. \
  --toc \
  --highlight-style=tango \
  -V geometry:margin=1in \
  -V fontsize=11pt \
  -o "$OUTPUT"

echo "PDF generated: docs/$OUTPUT"

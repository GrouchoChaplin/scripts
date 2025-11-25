#!/usr/bin/env bash
set -euo pipefail

# Find every .dart file in the current directory tree
find . -type f -name "*.dart" | while IFS= read -r file; do
    filename="$(basename "$file")"

    # Create a temp file
    tmp="$(mktemp)"

    {
        echo "#"
        echo "#=== $filename ==="
        echo "#"
        cat "$file"
    } > "$tmp"

    # Replace original
    mv "$tmp" "$file"

    echo "Updated: $file"
done

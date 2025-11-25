#!/usr/bin/env bash
set -euo pipefail

NEWLINE=$'\n'
BACKUP=true
DRY_RUN=false
COMPACT=false
PARALLEL=0   # 0 = disabled

# -------------------------------------------------------------------
# Generate headers
# -------------------------------------------------------------------
header_for() {
    local filename="$1"

    if $COMPACT; then
        printf "///=== %s ===///${NEWLINE}" "$filename"
    else
        printf "///${NEWLINE}///${NEWLINE}///=== %s ===${NEWLINE}///${NEWLINE}///${NEWLINE}" "$filename"
    fi
}

# -------------------------------------------------------------------
# Detection
# -------------------------------------------------------------------
has_header() {
    local file="$1"
    grep -q "^///=== $(basename "$file") ===" "$file"
}

# -------------------------------------------------------------------
# Strip existing header
# -------------------------------------------------------------------
strip_header() {
    local file="$1"
    local tmp="$(mktemp)"

    awk '
        BEGIN { skipping=1 }
        skipping {
            if ($0 ~ /^\/\/\/=== /) { inblock=1; next }
            if (inblock && $0 ~ /^\/\/\//) next
            if (inblock && $0 !~ /^\/\/\//) {
                skipping=0
                inblock=0
            }
            if (skipping) next
        }
        { print }
    ' "$file" > "$tmp"

    mv "$tmp" "$file"
}

# -------------------------------------------------------------------
# Backups
# -------------------------------------------------------------------
backup_file() {
    local file="$1"
    if $BACKUP && [[ ! -f "$file.bak" ]]; then
        cp "$file" "$file.bak"
    fi
}

# -------------------------------------------------------------------
# Operations
# -------------------------------------------------------------------
add_if_missing() {
    local file="$1"
    local filename=$(basename "$file")

    if ! has_header "$file"; then
        backup_file "$file"
        local tmp="$(mktemp)"

        if $DRY_RUN; then
            echo "[DRY-RUN][ADD] $file"
            return
        fi

        {
            header_for "$filename"
            cat "$file"
        } > "$tmp"

        mv "$tmp" "$file"
        echo "[ADD] $file"
    fi
}

normalize_header() {
    local file="$1"
    local filename=$(basename "$file")
    local tmp="$(mktemp)"

    if $DRY_RUN; then
        echo "[DRY-RUN][NORMALIZE] $file"
        return
    fi

    backup_file "$file"
    strip_header "$file"

    {
        header_for "$filename"
        cat "$file"
    } > "$tmp"

    mv "$tmp" "$file"
    echo "[NORMALIZE] $file"
}

update_if_different() {
    local file="$1"
    local filename=$(basename "$file")
    local desired="$(header_for "$filename")"
    local existing="$(head -n 7 "$file")"

    if [[ "$existing" != "$desired"* ]]; then
        normalize_header "$file"
        echo "[UPDATE] $file"
    fi
}

remove_header() {
    local file="$1"

    if $DRY_RUN; then
        echo "[DRY-RUN][REMOVE] $file"
        return
    fi

    backup_file "$file"
    strip_header "$file"
    echo "[REMOVE] $file"
}

# -------------------------------------------------------------------
# CLI parsing
# -------------------------------------------------------------------
usage() {
    cat <<EOF
Usage:
  headerctl.sh <mode> [file] [options]

Modes:
  add         Add header if missing
  update      Update header if different
  normalize   Strip old + insert proper header
  remove      Remove headers entirely

Options:
  --parallel [N]   Run in parallel (default 16)
  --dry-run        Only show changes, do not modify
  --compact        Use compact header format
  --no-backup      Disable *.bak backup files

Examples:
  headerctl.sh normalize
  headerctl.sh normalize --parallel
  headerctl.sh normalize lib/main.dart
  headerctl.sh remove --dry-run
EOF
    exit 1
}

MODE="${1:-}"
shift || true

FILE_TARGET=""

# Parse options & args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel)
            PARALLEL="${2:-16}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --compact)
            COMPACT=true
            shift
            ;;
        --no-backup)
            BACKUP=false
            shift
            ;;
        *.dart)
            FILE_TARGET="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

[[ -z "$MODE" ]] && usage

process_file() {
    local file="$1"
    case "$MODE" in
        add)       add_if_missing "$file" ;;
        update)    update_if_different "$file" ;;
        normalize) normalize_header "$file" ;;
        remove)    remove_header "$file" ;;
        *)         usage ;;
    esac
}

# -------------------------------------------------------------------
# Run modes
# -------------------------------------------------------------------
if [[ -n "$FILE_TARGET" ]]; then
    process_file "$FILE_TARGET"
else
    FILE_LIST=$(find . -type f -name "*.dart")

    if [[ "$PARALLEL" -gt 0 ]]; then
        echo "$FILE_LIST" | xargs -P "$PARALLEL" -I {} bash -c 'process_file "$@"' _ {}
    else
        echo "$FILE_LIST" | while read -r f; do process_file "$f"; done
    fi
fi

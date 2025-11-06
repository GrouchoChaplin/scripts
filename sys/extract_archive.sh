#!/usr/bin/env bash
#
# Description: 
# Author:      peddycoartte
# Created:     2025-11-06 17:25:46
# Usage:       
#

set -e
set -o pipefail


#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# extract_archive.sh
#
# Smart extractor companion to create_tagged_archive.sh
#   • Auto-detects compression type (.tar.gz, .tar.zst, .tar.xz, .tar.bz2, .zip)
#   • Extracts archives safely with optional verification
#   • Uses multi-threaded decompressors when available
#   • Supports --list (preview), --verify, and --clean (remove after extract)
#
# Author: Groucho
# Version: 1.0.0
# License: MIT
# ---------------------------------------------------------------------------

set -euo pipefail

ARCHIVE=""
DEST_DIR=""
LIST=false
VERIFY=false
CLEAN=false
QUIET=false

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 <archive_file> [--dest DIR] [--list] [--verify] [--clean] [--quiet]"
    echo
    echo "Examples:"
    echo "  $0 mydata.tar.zst"
    echo "  $0 mydata.tar.gz --dest ./output"
    echo "  $0 mydata.zip --list"
    echo
    exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) DEST_DIR="$2"; shift 2 ;;
        --list) LIST=true; shift ;;
        --verify) VERIFY=true; shift ;;
        --clean) CLEAN=true; shift ;;
        --quiet) QUIET=true; shift ;;
        -h|--help) usage ;;
        -*)
            echo "❌ Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$ARCHIVE" ]]; then
                ARCHIVE="$1"
            else
                echo "❌ Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate input
# ---------------------------------------------------------------------------
if [[ -z "$ARCHIVE" ]]; then
    echo "❌ No archive file specified."
    usage
fi
if [[ ! -f "$ARCHIVE" ]]; then
    echo "❌ Archive not found: $ARCHIVE"
    exit 1
fi

# ---------------------------------------------------------------------------
# Detect archive type
# ---------------------------------------------------------------------------
FILENAME=$(basename "$ARCHIVE")
EXT="${FILENAME##*.}"
TYPE=""

case "$ARCHIVE" in
    *.tar) TYPE="tar" ;;
    *.tar.gz|*.tgz) TYPE="targz" ;;
    *.tar.xz|*.txz) TYPE="tarxz" ;;
    *.tar.zst|*.tzst) TYPE="tarzst" ;;
    *.tar.bz2|*.tbz2) TYPE="tarbz2" ;;
    *.zip) TYPE="zip" ;;
    *)
        echo "❌ Unknown archive type for: $ARCHIVE"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Determine destination folder
# ---------------------------------------------------------------------------
if [[ -z "$DEST_DIR" ]]; then
    BASE=$(basename "$ARCHIVE")
    DEST_DIR="${BASE%.*}"
    DEST_DIR="${DEST_DIR%.tar}"
fi

mkdir -p "$DEST_DIR"

if ! $QUIET; then
    echo "📦 Extracting:"
    echo "   File:   $ARCHIVE"
    echo "   Type:   $TYPE"
    echo "   Output: $DEST_DIR"
    echo
fi

# ---------------------------------------------------------------------------
# Extraction logic
# ---------------------------------------------------------------------------
case "$TYPE" in
    tar)
        if $LIST; then tar -tf "$ARCHIVE"; exit 0; fi
        tar -xf "$ARCHIVE" -C "$DEST_DIR"
        ;;
    targz)
        if $LIST; then tar -tzf "$ARCHIVE"; exit 0; fi
        tar -xzf "$ARCHIVE" -C "$DEST_DIR"
        ;;
    tarbz2)
        if $LIST; then tar -tjf "$ARCHIVE"; exit 0; fi
        tar -xjf "$ARCHIVE" -C "$DEST_DIR"
        ;;
    tarxz)
        if $LIST; then tar -tJf "$ARCHIVE"; exit 0; fi
        if command -v xz >/dev/null 2>&1; then
            THREADS=$(nproc 2>/dev/null || echo 1)
            tar --use-compress-program="xz -T$THREADS -d" -xf "$ARCHIVE" -C "$DEST_DIR"
        else
            tar -xJf "$ARCHIVE" -C "$DEST_DIR"
        fi
        ;;
    tarzst)
        if $LIST; then tar -I zstd -tf "$ARCHIVE"; exit 0; fi
        if command -v zstd >/dev/null 2>&1; then
            THREADS=$(nproc 2>/dev/null || echo 1)
            tar --use-compress-program="zstd -T$THREADS -d" -xf "$ARCHIVE" -C "$DEST_DIR"
        else
            tar --zstd -xf "$ARCHIVE" -C "$DEST_DIR"
        fi
        ;;
    zip)
        if $LIST; then unzip -l "$ARCHIVE"; exit 0; fi
        unzip -q "$ARCHIVE" -d "$DEST_DIR"
        ;;
esac

if ! $QUIET; then
    echo "✅ Extraction complete."
fi

# ---------------------------------------------------------------------------
# Verify extracted contents
# ---------------------------------------------------------------------------
if $VERIFY; then
    if [[ -d "$DEST_DIR" ]]; then
        FILE_COUNT=$(find "$DEST_DIR" -type f | wc -l)
        if [[ "$FILE_COUNT" -gt 0 ]]; then
            echo "🔍 Verification: $FILE_COUNT files extracted successfully."
        else
            echo "⚠️ Verification failed: no files found in $DEST_DIR."
        fi
    else
        echo "⚠️ Verification failed: $DEST_DIR not found."
    fi
fi

# ---------------------------------------------------------------------------
# Optionally delete archive
# ---------------------------------------------------------------------------
if $CLEAN; then
    rm -f "$ARCHIVE"
    echo "🧹 Removed archive: $ARCHIVE"
fi

if ! $QUIET; then
    SIZE=$(du -sh "$DEST_DIR" | awk '{print $1}')
    echo "📁 Extracted folder size: $SIZE"
    echo "🎉 Done!"
fi

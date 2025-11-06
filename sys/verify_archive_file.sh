#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify_archive_file.sh
# Verify integrity of common tar-based archives:
#   .tar, .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Usage check ---
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <archive-file>"
    exit 1
fi

ARCHIVE="$1"

if [[ ! -f "$ARCHIVE" ]]; then
    echo "❌ File not found: $ARCHIVE"
    exit 1
fi

# --- Detect archive type based on extension ---
case "$ARCHIVE" in
    *.tar)        TYPE="tar" ;;
    *.tar.gz|*.tgz)   TYPE="tar.gz" ;;
    *.tar.bz2|*.tbz2) TYPE="tar.bz2" ;;
    *.tar.xz|*.txz)   TYPE="tar.xz" ;;
    *) echo "⚠️ Unsupported or unknown archive type: $ARCHIVE"; exit 2 ;;
esac

echo "🔍 Verifying archive: $ARCHIVE"
echo "   Detected type: $TYPE"
echo

# --- Function for gzip integrity test ---
check_gzip() {
    gzip -t "$ARCHIVE" >/dev/null 2>&1
}

# --- Function for bzip2 integrity test ---
check_bzip2() {
    bzip2 -t "$ARCHIVE" >/dev/null 2>&1
}

# --- Function for xz integrity test ---
check_xz() {
    xz -t "$ARCHIVE" >/dev/null 2>&1
}

# --- Main verification logic ---
status=0

case "$TYPE" in
    tar)
        echo "🧩 Checking tar structure..."
        if tar -tf "$ARCHIVE" >/dev/null 2>&1; then
            echo "✅ tar structure OK"
        else
            echo "❌ tar structure corrupted"
            status=1
        fi
        ;;
    tar.gz)
        echo "🧩 Checking gzip compression..."
        if check_gzip; then
            echo "✅ gzip layer OK"
            echo "🧩 Checking tar structure..."
            if tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
                echo "✅ tar structure OK"
            else
                echo "❌ tar structure corrupted"
                status=1
            fi
        else
            echo "❌ gzip layer corrupted"
            status=1
        fi
        ;;
    tar.bz2)
        echo "🧩 Checking bzip2 compression..."
        if check_bzip2; then
            echo "✅ bzip2 layer OK"
            echo "🧩 Checking tar structure..."
            if tar -tjf "$ARCHIVE" >/dev/null 2>&1; then
                echo "✅ tar structure OK"
            else
                echo "❌ tar structure corrupted"
                status=1
            fi
        else
            echo "❌ bzip2 layer corrupted"
            status=1
        fi
        ;;
    tar.xz)
        echo "🧩 Checking xz compression..."
        if check_xz; then
            echo "✅ xz layer OK"
            echo "🧩 Checking tar structure..."
            if tar -tJf "$ARCHIVE" >/dev/null 2>&1; then
                echo "✅ tar structure OK"
            else
                echo "❌ tar structure corrupted"
                status=1
            fi
        else
            echo "❌ xz layer corrupted"
            status=1
        fi
        ;;
esac

echo
if [[ $status -eq 0 ]]; then
    echo "🎉 Archive integrity verified successfully!"
else
    echo "⚠️  Archive failed verification. See errors above."
fi

exit $status

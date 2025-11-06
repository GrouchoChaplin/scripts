#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create_tagged_archive.sh
#
# Smart, portable archiver with:
#   • Flexible flag order (options can appear anywhere)
#   • --desc <text> appends descriptive text to archive filenames
#   • Auto-detects best compression available (zstd → xz → gzip)
#   • Multi-threaded compression, CPU-aware ($UNUSED_PROCS respected)
#   • Built-in version management + changelog
#
# Author: Groucho
# Version: 1.3.0
# License: MIT
# ---------------------------------------------------------------------------

set -euo pipefail

TYPE=""
ADD_DATE=true
VERIFY=false
SHOW_TYPES=false
SHOW_VERSION=false
UPDATE_VERSION=""
DESC=""
TAG=""

ADD_ENTRIES=()
CHANGE_ENTRIES=()
FIX_ENTRIES=()

POSITIONAL=()

# ---------------------------------------------------------------------------
# Argument parsing (order-independent)
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) TYPE="$2"; shift 2 ;;
        --desc) DESC="$2"; shift 2 ;;
        --no-date) ADD_DATE=false; shift ;;
        --verify) VERIFY=true; shift ;;
        --show-types) SHOW_TYPES=true; shift ;;
        --version) SHOW_VERSION=true; shift ;;
        --update-version) UPDATE_VERSION="${2:-patch}"; shift 2 ;;
        --add) ADD_ENTRIES+=("$2"); shift 2 ;;
        --change) CHANGE_ENTRIES+=("$2"); shift 2 ;;
        --fix) FIX_ENTRIES+=("$2"); shift 2 ;;
        -*) echo "❌ Unknown option: $1"; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

# Restore positional arguments (dest, src, [tag])
set -- "${POSITIONAL[@]:-}"

DEST_DIR="${1:-}"
SRC_DIR="${2:-}"
TAG="${3:-}"

SCRIPT_NAME="$(basename "$0")"
SCRIPT_PATH="$(realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
AUTHOR="Groucho"

# ---------------------------------------------------------------------------
# Function: check_tar_support
# ---------------------------------------------------------------------------
check_tar_support() {
    local flag="$1"
    if tar "$flag" --version >/dev/null 2>&1; then echo "✅"; else echo "❌"; fi
}

# ---------------------------------------------------------------------------
# --version
# ---------------------------------------------------------------------------
if $SHOW_VERSION; then
    VERSION=$(grep -m1 "^# Version:" "$SCRIPT_PATH" | awk '{print $3}')
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        LAST_COMMIT_HASH=$(git -C "$SCRIPT_DIR" log -1 --pretty=format:"%h")
        LAST_COMMIT_DATE=$(git -C "$SCRIPT_DIR" log -1 --pretty=format:"%cd" --date=short)
        SOURCE_INFO="Git commit $LAST_COMMIT_HASH ($LAST_COMMIT_DATE)"
    else
        MOD_DATE=$(stat -c %y "$SCRIPT_PATH" 2>/dev/null | cut -d'.' -f1)
        SOURCE_INFO="Last modified: $MOD_DATE"
    fi
    echo "📦 $SCRIPT_NAME"
    echo "──────────────────────────────────────"
    echo "Author:   $AUTHOR"
    echo "Version:  $VERSION"
    echo "$SOURCE_INFO"
    echo "Path:     $SCRIPT_PATH"
    echo
    echo "Usage: $SCRIPT_NAME [options]"
    echo "  --show-types            List compressor availability and tar integration"
    echo "  --version               Show script metadata"
    echo "  --update-version [part] Bump version (major|minor|patch)"
    echo "  --desc <text>           Add descriptive string to filename"
    echo
    exit 0
fi

# ---------------------------------------------------------------------------
# --update-version (auto-changelog)
# ---------------------------------------------------------------------------
if [[ -n "$UPDATE_VERSION" ]]; then
    VERSION_LINE=$(grep -m1 "^# Version:" "$SCRIPT_PATH")
    CURRENT_VERSION=$(echo "$VERSION_LINE" | awk '{print $3}')
    IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_VERSION"

    case "$UPDATE_VERSION" in
        major) ((MAJOR++)); MINOR=0; PATCH=0 ;;
        minor) ((MINOR++)); PATCH=0 ;;
        patch) ((PATCH++)) ;;
        *) echo "❌ Invalid version part: $UPDATE_VERSION (use major|minor|patch)"; exit 1 ;;
    esac

    NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
    DATE=$(date "+%Y-%m-%d %H:%M:%S")
    echo "🔧 Updating version: $CURRENT_VERSION → $NEW_VERSION"

    sed -i "s/^# Version:.*/# Version: $NEW_VERSION/" "$SCRIPT_PATH"

    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$SCRIPT_DIR" add "$SCRIPT_PATH"
        git -C "$SCRIPT_DIR" commit -m "Bump version to $NEW_VERSION" >/dev/null 2>&1 || true
        git -C "$SCRIPT_DIR" tag -a "v$NEW_VERSION" -m "Version $NEW_VERSION" >/dev/null 2>&1 || true
        COMMIT_HASH=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
        echo "✅ Git commit + tag created: v$NEW_VERSION ($COMMIT_HASH)"
    else
        echo "✅ Version updated (no Git repo detected)."
    fi

    CHANGELOG="$SCRIPT_DIR/CHANGELOG.md"
    {
        echo ""
        echo "## v$NEW_VERSION — $DATE"
        echo ""
        if [[ ${#ADD_ENTRIES[@]} -gt 0 ]]; then
            echo "### 🟢 Added"
            for e in "${ADD_ENTRIES[@]}"; do echo "- $e"; done
            echo ""
        fi
        if [[ ${#CHANGE_ENTRIES[@]} -gt 0 ]]; then
            echo "### 🔧 Changed"
            for e in "${CHANGE_ENTRIES[@]}"; do echo "- $e"; done
            echo ""
        fi
        if [[ ${#FIX_ENTRIES[@]} -gt 0 ]]; then
            echo "### 🐞 Fixed"
            for e in "${FIX_ENTRIES[@]}"; do echo "- $e"; done
            echo ""
        fi
        if [[ ${#ADD_ENTRIES[@]} -eq 0 && ${#CHANGE_ENTRIES[@]} -eq 0 && ${#FIX_ENTRIES[@]} -eq 0 ]]; then
            echo "- No changelog entries provided."
        fi
    } >> "$CHANGELOG"

    echo "📝 Updated changelog: $CHANGELOG"
    echo "🎉 Version bump complete!"
    exit 0
fi

# ---------------------------------------------------------------------------
# SHOW AVAILABLE COMPRESSORS
# ---------------------------------------------------------------------------
if $SHOW_TYPES; then
    echo "🔍 Checking available compressors and tar integration..."
    printf "%-10s %-10s %-12s %-10s\n" "Compressor" "Installed" "Tar Support" "Command"
    printf "%-10s %-10s %-12s %-10s\n" "----------" "----------" "------------" "--------"

    declare -A tar_flags=(
        ["gzip"]="--gzip"
        ["bzip2"]="--bzip2"
        ["xz"]="--xz"
        ["zstd"]="--zstd"
    )

    for c in gzip bzip2 xz zstd zip; do
        if command -v "$c" >/dev/null 2>&1; then
            installed="✅"; cmdpath=$(command -v "$c")
        else
            installed="❌"; cmdpath="-"
        fi
        if [[ -n "${tar_flags[$c]:-}" ]]; then
            support=$(check_tar_support "${tar_flags[$c]}")
        else
            support="N/A"
        fi
        printf "%-10s %-10s %-12s %-10s\n" "$c" "$installed" "$support" "$cmdpath"
    done

    echo
    if command -v zstd >/dev/null 2>&1; then DEFAULT="tarzst"
    elif command -v xz >/dev/null 2>&1; then DEFAULT="tarxz"
    else DEFAULT="targz"; fi
    echo "🤖 Default auto-selected type would be: $DEFAULT"
    echo
    exit 0
fi

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
if [[ -z "${DEST_DIR:-}" || -z "${SRC_DIR:-}" ]]; then
    echo "Usage: $0 <dest_dir> <source_dir> [tag] [--type TYPE] [--desc TEXT] [--no-date] [--verify]"
    exit 1
fi
if [[ ! -d "$SRC_DIR" ]]; then echo "❌ Source directory not found: $SRC_DIR"; exit 1; fi
mkdir -p "$DEST_DIR"

# ---------------------------------------------------------------------------
# AUTO-DETECT BEST TYPE
# ---------------------------------------------------------------------------
if [[ -z "$TYPE" || "$TYPE" == "auto" ]]; then
    if command -v zstd >/dev/null 2>&1; then TYPE="tarzst"
    elif command -v xz >/dev/null 2>&1; then TYPE="tarxz"
    else TYPE="targz"; fi
    echo "🤖 Auto-selected best archive type: $TYPE"
fi

# ---------------------------------------------------------------------------
# Filename setup
# ---------------------------------------------------------------------------
BASENAME=$(basename "$SRC_DIR")

DATE_TAG=""
$ADD_DATE && DATE_TAG=".$(date '+%Y-%m-%d_T%H-%M-%S')"

TAG_PART=""
[[ -n "$TAG" ]] && TAG_PART=".$TAG"

DESC_PART=""
[[ -n "$DESC" ]] && DESC_PART=".$DESC"

case "$TYPE" in
    tar) EXT=".tar" ;;
    targz|tgz) EXT=".tar.gz" ;;
    tarbz2|tbz2) EXT=".tar.bz2" ;;
    tarxz|txz) EXT=".tar.xz" ;;
    tarzst|tzst) EXT=".tar.zst" ;;
    zip) EXT=".zip" ;;
    ""|auto)
        if command -v zstd >/dev/null 2>&1; then TYPE="tarzst"; EXT=".tar.zst"
        elif command -v xz >/dev/null 2>&1; then TYPE="tarxz"; EXT=".tar.xz"
        else TYPE="targz"; EXT=".tar.gz"; fi
        ;;
    *) echo "❌ Unsupported type: $TYPE"; exit 1 ;;
esac

OUTFILE="${DEST_DIR}/${BASENAME}${DATE_TAG}${TAG_PART}${DESC_PART}${EXT}"

# ---------------------------------------------------------------------------
# Thread config
# ---------------------------------------------------------------------------
TOTAL_CORES=$(nproc 2>/dev/null || echo 1)
UNUSED_CORES=${UNUSED_PROCS:-1}
THREADS=$(( TOTAL_CORES - UNUSED_CORES )); (( THREADS < 1 )) && THREADS=1

echo "📦 Creating archive:"
echo "   Source:      $SRC_DIR"
echo "   Destination: $OUTFILE"
echo "   Type:        $TYPE"
echo "   Threads:     $THREADS"
echo

# ---------------------------------------------------------------------------
# Archive creation
# ---------------------------------------------------------------------------
case "$TYPE" in
    tar) tar -cf "$OUTFILE" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" ;;
    targz|tgz) tar --gzip -cf "$OUTFILE" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" ;;
    tarbz2|tbz2) tar --bzip2 -cf "$OUTFILE" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" ;;
    tarxz|txz)
        if tar --xz --version >/dev/null 2>&1; then
            tar --xz -cf "$OUTFILE" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"
        else
            tar -cf - -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" | xz -T"$THREADS" -9 -c > "$OUTFILE"
        fi ;;
    tarzst|tzst)
        if tar --zstd --version >/dev/null 2>&1; then
            tar --zstd -cf "$OUTFILE" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")"
        else
            tar -cf - -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" | zstd -T"$THREADS" -10 -o "$OUTFILE"
        fi ;;
    zip)
        (cd "$(dirname "$SRC_DIR")" && zip -r -q "$OUTFILE" "$(basename "$SRC_DIR")") ;;
esac

echo "✅ Archive created successfully."

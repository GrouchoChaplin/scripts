#!/usr/bin/env bash
#
# update_tree_readme.sh
#
# Generate a clean Markdown-rendered directory tree into README.md.
# Fully configurable via --root and --output.
#
# Version: 1.0.0
# Build:   2025-11-18
# Git:     $(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
# Path:    ~/projects/peddycoartte/scripts/sys/update_tree_readme.sh

set -euo pipefail

# -------------------------------
# Defaults
# -------------------------------

ROOT="data"
OUT=""
VERBOSE=0
EXCLUDES=()

# -------------------------------
# Functions
# -------------------------------

log() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "[*] $*"
    fi
}

show_help() {
cat <<EOF
update_tree_readme.sh — auto-generate Markdown README trees

Usage:
  update_tree_readme.sh [options]

Options:
  --root <dir>        Root folder to scan (default: data)
  --output <file>     Output README.md (default: <root>/README.md)
  --exclude <pattern> Exclude pattern (repeatable)
  --verbose           Verbose logging
  --version           Show version info
  --help              Show this help

Examples:
  update_tree_readme.sh
  update_tree_readme.sh --root data --output data/README.md
  update_tree_readme.sh --root src --exclude "*.o" --exclude build/
EOF
}

show_version() {
cat <<EOF
update_tree_readme.sh version 1.0.0
Build:   2025-11-18
Git:     $(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
EOF
}

# -------------------------------
# Argument Parsing
# -------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            ROOT="$2"
            shift 2
            ;;
        --output)
            OUT="$2"
            shift 2
            ;;
        --exclude)
            EXCLUDES+=("$2")
            shift 2
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        --version)
            show_version
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If output not specified → default to ROOT/README.md
if [[ -z "$OUT" ]]; then
    OUT="$ROOT/README.md"
fi

if [[ ! -d "$ROOT" ]]; then
    echo "ERROR: root directory not found: $ROOT"
    exit 1
fi

log "Root: $ROOT"
log "Output: $OUT"
log "Excludes: ${EXCLUDES[*]:-(none)}"

mkdir -p "$(dirname "$OUT")"

# -------------------------------
# Write heading
# -------------------------------

{
    echo "# Directory Tree for \`$ROOT\`"
    echo ""
    echo "Updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    echo '```'
} > "$OUT"

# -------------------------------
# Build exclude args for tree
# -------------------------------

TREE_EXCLUDES=()
for ex in "${EXCLUDES[@]}"; do
    TREE_EXCLUDES+=( -I "$ex" )
done

# -------------------------------
# Generate tree
# -------------------------------

if command -v tree >/dev/null 2>&1; then
    log "Using 'tree'"
    tree -a --noreport "${TREE_EXCLUDES[@]}" "$ROOT" >> "$OUT"
else
    log "tree not installed — using fallback"
    find "$ROOT" \
        $(printf ' -not -path "%s"' "${EXCLUDES[@]}") |
    sed 's|[^/]*/|   |g' |
    sed 's|   \(.*\)$|├── \1|g' >> "$OUT"
fi

echo '```' >> "$OUT"

log "Done"
echo "Generated: $OUT"

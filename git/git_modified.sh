#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# git_modified.sh
# Shows a colorized, timestamped summary of all local modifications in a Git repo.
#
# Features:
#   • Works from any subdirectory (auto-detects repo root)
#   • Displays unstaged, staged, and untracked files
#   • Includes modification time and file size
#   • Shows per-extension breakdowns
#   • Optional:
#       --show-diff  → show inline color diffs
#       --compact    → show single-line summary (for prompts/hooks)
# ---------------------------------------------------------------------------

set -euo pipefail
SHOW_DIFF=false
COMPACT_MODE=false

# --- Parse options ---
for arg in "$@"; do
    case "$arg" in
        --show-diff) SHOW_DIFF=true ;;
        --compact) COMPACT_MODE=true ;;
    esac
done

# --- Verify inside a Git repository ---
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ Not inside a Git repository."
    exit 1
fi

# --- Detect repo root and current relative path ---
REPO_ROOT=$(git rev-parse --show-toplevel)
START_DIR=$(pwd)
REL_PATH=$(realpath --relative-to="$REPO_ROOT" "$START_DIR" 2>/dev/null || echo ".")

cd "$REPO_ROOT"

# --- Helper to count file extensions ---
count_extensions() {
    local -a FILES=("$@")
    declare -A EXT_COUNT=()
    for f in "${FILES[@]}"; do
        [[ ! -f "$f" ]] && continue
        ext="${f##*.}"
        [[ "$ext" == "$f" ]] && ext="(noext)"
        ((EXT_COUNT["$ext"]++))
    done
    local summary=""
    for k in "${!EXT_COUNT[@]}"; do
        summary+="${EXT_COUNT[$k]} ${k}, "
    done
    echo "${summary%, }"
}

# --- Gather file lists ---
MODIFIED_FILES=($(git diff --name-only))
STAGED_FILES=($(git diff --cached --name-only))
UNTRACKED_FILES=($(git ls-files --others --exclude-standard))

COUNT_MOD=${#MODIFIED_FILES[@]}
COUNT_STG=${#STAGED_FILES[@]}
COUNT_UNT=${#UNTRACKED_FILES[@]}

SUMMARY_MOD=$(count_extensions "${MODIFIED_FILES[@]}" || true)
SUMMARY_STG=$(count_extensions "${STAGED_FILES[@]}" || true)
SUMMARY_UNT=$(count_extensions "${UNTRACKED_FILES[@]}" || true)

# ---------------------------------------------------------------------------
# COMPACT MODE
# ---------------------------------------------------------------------------
if $COMPACT_MODE; then
    printf "🟡 %d mod" "$COUNT_MOD"
    [[ -n "$SUMMARY_MOD" ]] && printf " (%s)" "$SUMMARY_MOD"
    printf " | 🟢 %d staged" "$COUNT_STG"
    [[ -n "$SUMMARY_STG" ]] && printf " (%s)" "$SUMMARY_STG"
    printf " | 🔵 %d untracked" "$COUNT_UNT"
    [[ -n "$SUMMARY_UNT" ]] && printf " (%s)" "$SUMMARY_UNT"
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# FULL DETAILED MODE
# ---------------------------------------------------------------------------
echo ""
echo "📘 Repository: $(basename "$REPO_ROOT")"
echo "📂 Started from: $REL_PATH"
echo "🌿 Branch: $(git rev-parse --abbrev-ref HEAD)"
echo ""
echo -e "\033[1;37mSummary:\033[0m"
printf "  🟡 Modified:   %3d" "$COUNT_MOD"; [[ -n "$SUMMARY_MOD" ]] && echo "  ($SUMMARY_MOD)" || echo ""
printf "  🟢 Staged:     %3d" "$COUNT_STG"; [[ -n "$SUMMARY_STG" ]] && echo "  ($SUMMARY_STG)" || echo ""
printf "  🔵 Untracked:  %3d" "$COUNT_UNT"; [[ -n "$SUMMARY_UNT" ]] && echo "  ($SUMMARY_UNT)" || echo ""
echo ""

# --- Helper: print file info with timestamp and size ---
print_file_info() {
    local FILE="$1"
    if [[ -f "$FILE" ]]; then
        local MTIME SIZE
        MTIME=$(stat -c "%y" "$FILE" | cut -d'.' -f1)
        SIZE=$(stat -c "%s" "$FILE" | numfmt --to=iec 2>/dev/null || stat -c "%s" "$FILE")
        printf "  %-60s  %10s  %s\n" "$FILE" "$SIZE" "$MTIME"
    else
        printf "  %-60s  %10s  %s\n" "$FILE" "—" "missing"
    fi
}

# --- Section header ---
section() {
    echo ""
    echo -e "$1"
    echo "------------------------------------------------------------"
}

# --- Modified (unstaged) ---
section "\033[1;33m=== Modified (Unstaged) ===\033[0m"
if (( COUNT_MOD > 0 )); then
    for f in "${MODIFIED_FILES[@]}"; do print_file_info "$f"; done
else
    echo "  (none)"
fi

# --- Staged (ready to commit) ---
section "\033[1;32m=== Staged (Ready to Commit) ===\033[0m"
if (( COUNT_STG > 0 )); then
    for f in "${STAGED_FILES[@]}"; do print_file_info "$f"; done
else
    echo "  (none)"
fi

# --- Untracked files ---
section "\033[1;34m=== Untracked (Not in Git) ===\033[0m"
if (( COUNT_UNT > 0 )); then
    for f in "${UNTRACKED_FILES[@]}"; do print_file_info "$f"; done
else
    echo "  (none)"
fi

# --- Optional inline diff ---
if $SHOW_DIFF; then
    section "\033[1;35m=== Inline Diffs (Unstaged) ===\033[0m"
    git diff | less -R
fi

echo ""
echo -e "\033[1;36m✅ Done.\033[0m"

#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# init_all.sh  —  Silent modular environment loader
#
# Loads custom environment scripts from ~/projects/peddycoartte/scripts in a clean order:
#   1. Environment and alias files (env/*.sh)
#   2. All other module directories (git/, sys/, net/, etc.)
#
# Automatically ignores hidden folders like .cache, .git, .vscode, tmp, etc.
#
# Add to your ~/.bashrc:
#     source "$HOME/projects/peddycoartte/scripts/init_all.sh"
#
# Optional reload alias:
#     reloadEnv
# ---------------------------------------------------------------------------

# --- Guard: prevent accidental direct execution ----------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "⚠️  This file should be sourced, not executed."
    echo "   Add this line to your ~/.bashrc instead:"
    echo "     source \$HOME/projects/peddycoartte/scripts/init_all.sh"
    exit 1
fi

SCRIPT_ROOT="$HOME/projects/peddycoartte/scripts"
[[ -d "$SCRIPT_ROOT" ]] || return 0 2>/dev/null || exit 0

[[ -n "${INIT_VERBOSE:-}" ]] && echo "[init] Loading from $SCRIPT_ROOT..."

# --- Helper: safe source with silent error capture -------------------------
safe_source() {
    local file="$1"
    [[ -f "$file" && -r "$file" ]] || return 0
    # shellcheck disable=SC1090
    source "$file" 2>/dev/null || echo "⚠️  Error loading: $file" >&2
}

# --- 1️⃣ Load environment and aliases first ---------------------------------
if [[ -d "$SCRIPT_ROOT/env" ]]; then
    for file in "$SCRIPT_ROOT"/env/*.sh; do
        [[ -f "$file" ]] || continue
        safe_source "$file"
    done
fi

# --- 2️⃣ Load all other categorized scripts --------------------------------
for dir in "$SCRIPT_ROOT"/*/; do
    [[ -d "$dir" ]] || continue
    local dname
    dname="$(basename "$dir")"

    # Skip special or hidden directories
    case "$dname" in
        env|.git|.cache|.vscode|tmp|temp|__pycache__) continue ;;
    esac

    for file in "$dir"*.sh; do
        [[ -f "$file" ]] || continue
        safe_source "$file"
    done
done

# --- 3️⃣ Define a quick reload alias ---------------------------------------
alias reloadEnv="source $HOME/projects/peddycoartte/scripts/init_all.sh >/dev/null 2>&1 && echo '🔁 Environment reloaded.'"

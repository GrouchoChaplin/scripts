#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# init_all.sh  —  Silent modular environment loader
#
# Loads your environment and scripts from ~/projects/scripts in this order:
#   1. Environment files (env/*.sh)     → PATH, LANG, aliases, prompt, etc.
#   2. Other modules (git/, sys/, net/) → functions, utilities, tools
#
# Hidden directories (.cache, .git, .vscode, etc.) are ignored.
#
# Add this to your ~/.bashrc:
#     source "$HOME/projects/scripts/init_all.sh"
#
# Reload anytime with:
#     reloadEnv
# ---------------------------------------------------------------------------

# --- Guard: prevent direct execution ---------------------------------------
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "⚠️  This file must be sourced, not executed."
    echo "   Add this line to your ~/.bashrc:"
    echo "     source \$HOME/projects/scripts/init_all.sh"
    exit 1
fi

SCRIPT_ROOT="$HOME/projects/scripts"
[[ -d "$SCRIPT_ROOT" ]] || return 0 2>/dev/null || exit 0

# --- Helper: safe source ----------------------------------------------------
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

    # Skip environment & hidden/system folders
    case "$dname" in
        env|.git|.cache|.vscode|tmp|temp|__pycache__) continue ;;
    esac

    for file in "$dir"*.sh; do
        [[ -f "$file" ]] || continue
        safe_source "$file"
    done
done

# --- 3️⃣ Define reload alias ------------------------------------------------
alias reloadEnv="source $HOME/projects/scripts/init_all.sh >/dev/null 2>&1 && echo '🔁 Environment reloaded.'"

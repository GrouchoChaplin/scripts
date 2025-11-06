# shellcheck shell=bash
# Prevent accidental execution
[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
    echo "❌ This script is meant to be sourced, not executed."
    exit 1
}

# ---------------------------------------------------------------------------
# _gbs_completion : tab-completion for git_branch_search / gbs
# Provides:
#   • Flag descriptions (--long, --refresh, etc.)
#   • Cached branch name suggestions
#   • Remote name completions with branch counts
# ---------------------------------------------------------------------------

_gbs_completion() {
    local cur prev words cword
    _init_completion || return

    local remotes cachedir branches
    local -A desc

    # Descriptive help text for flags
    desc=(
        [--long]="show commit hashes"
        [--no-color]="disable color highlighting"
        [--cache-min]="set cache lifetime in minutes"
        [--refresh]="force refresh of cached data"
    )

    # Gather Git remotes
    remotes=$(git remote 2>/dev/null)

    # Cached branch database
    cachedir="${HOME}/.cache/git_branch_search"
    branches=$(grep -h 'refs/heads/' "$cachedir"/* 2>/dev/null | sed 's#.*refs/heads/##' | sort -u)

    # Full completion candidates
    local opts="--long --no-color --cache-min --refresh $remotes $branches"

    # If user typed "--cache-min", suggest time values
    if [[ "$prev" == "--cache-min" ]]; then
        COMPREPLY=( $(compgen -W "1 2 5 10 15 30 60" -- "$cur") )
        return 0
    fi

    # Regular completions
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )

    # On double-Tab, show descriptions and remote branch counts
    if [[ $COMP_TYPE == 63 && -n $COMPREPLY ]]; then
        echo
        printf "Available options:\n"
        printf "  %-15s %s\n" "--long"       "${desc[--long]}"
        printf "  %-15s %s\n" "--no-color"   "${desc[--no-color]}"
        printf "  %-15s %s\n" "--cache-min"  "${desc[--cache-min]}"
        printf "  %-15s %s\n" "--refresh"    "${desc[--refresh]}"
        echo

        if [[ -n "$remotes" ]]; then
            printf "Remotes and cached branch counts:\n"
            for r in $remotes; do
                local f="$cachedir/${r}.heads"
                if [[ -f "$f" ]]; then
                    local n
                    n=$(grep -c '^' "$f" 2>/dev/null)
                    printf "  %-15s (%s branches cached)\n" "$r" "$n"
                else
                    printf "  %-15s (no cache yet)\n" "$r"
                fi
            done
            echo
        fi
    fi
}

# Register completion for gbs and git_branch_search
complete -F _gbs_completion gbs
complete -F _gbs_completion git_branch_search

# Enable for Zsh if needed
if [[ -n "$ZSH_VERSION" && -z "$(declare -f _init_completion)" ]]; then
    autoload -U +X bashcompinit && bashcompinit
fi

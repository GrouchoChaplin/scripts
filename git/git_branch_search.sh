# shellcheck shell=bash
# ---------------------------------------------------------------------------
# git_branch_search : search remote branches using regex, color highlighting,
# caching, multi-remote, remote-prefixed output, and summary.
# ---------------------------------------------------------------------------

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || {
    echo "❌ This script is meant to be sourced, not executed directly."
    exit 1
}

git_branch_search() {
    local long_output=false
    local use_color=true
    local cache_minutes=5
    local refresh_cache=false
    local -a remotes=()
    local -a patterns=()
    local total_matches=0
    local total_remotes=0

    # --- Parse flags ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --long) long_output=true ;;
            --no-color) use_color=false ;;
            --cache-min) shift; cache_minutes="$1" ;;
            --refresh) refresh_cache=true ;;
            *)
                if git remote | grep -qx "$1"; then
                    remotes+=("$1")
                else
                    patterns+=("$1")
                fi
                ;;
        esac
        shift
    done

    # Defaults
    if [ ${#remotes[@]} -eq 0 ]; then
        remotes=("origin")
    fi
    if [ ${#patterns[@]} -eq 0 ]; then
        echo "Usage: git_branch_search [--long] [--no-color] [--cache-min N] [--refresh] [remote1 remote2 ...] <pattern1> [pattern2] ..."
        echo "Example: git_branch_search --long origin '^release-' '-dev$' feature"
        return 1
    fi

    local pattern
    pattern=$(printf "%s|" "${patterns[@]}")
    pattern=${pattern%|}

    echo "🔍 Searching remotes [${remotes[*]}] for branches matching regex: $pattern"
    echo

    local color_flag=""
    $use_color && color_flag="--color=always"

    local cache_dir="${HOME}/.cache/git_branch_search"
    mkdir -p "$cache_dir"

    local cache_age_limit=$((cache_minutes * 60))
    local multi_remote=false
    (( ${#remotes[@]} > 1 )) && multi_remote=true

    for remote in "${remotes[@]}"; do
        ((total_remotes++))
        local cache_file="$cache_dir/${remote}.heads"
        local now=$(date +%s)
        local refresh=$refresh_cache
        local match_count=0

        # Cache freshness check
        if [ -f "$cache_file" ] && ! $refresh; then
            local modified=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
            local age=$((now - modified))
            if [ "$age" -lt "$cache_age_limit" ]; then
                echo "✅ Using cached branch list for $remote (age < ${cache_minutes}m)"
                refresh=false
            else
                refresh=true
            fi
        fi

        # Refresh cache if needed
        if $refresh; then
            echo "⏳ Fetching branch list from $remote ..."
            git ls-remote --heads "$remote" >"$cache_file" 2>/dev/null

            # --- Graceful fetch failure handling ---
            if [ ! -s "$cache_file" ]; then
                echo "⚠️  Unable to fetch branches for remote '$remote'."
                echo "    Check your network connection, SSH keys, or remote access."
                echo
                continue
            fi
        fi

        # --- Guard: ensure cache file exists and has data ---
        if [ ! -s "$cache_file" ]; then
            echo "⚠️  No branch data available for remote '$remote'."
            echo "    Try running: gbs --refresh $remote"
            echo
            continue
        fi

        echo
        # Output formatting
        if $long_output; then
            if $multi_remote; then
                grep -E $color_flag "$pattern" "$cache_file" \
                    | sed "s#^#${remote}/#" | sed 's#refs/heads/##'
            else
                grep -E $color_flag "$pattern" "$cache_file" \
                    | sed 's#refs/heads/##'
            fi
            match_count=$(grep -E "$pattern" "$cache_file" | wc -l)
        else
            if $multi_remote; then
                grep -E $color_flag "$pattern" "$cache_file" \
                    | awk '{print $2}' | sed "s#refs/heads#${remote}#" | sed 's#//#/#g'
            else
                grep -E $color_flag "$pattern" "$cache_file" \
                    | awk '{print $2}' | sed 's#refs/heads/##'
            fi
            match_count=$(grep -E "$pattern" "$cache_file" | wc -l)
        fi

        total_matches=$((total_matches + match_count))
        echo
    done

    # --- Summary Footer ---
    local summary_color="\033[0;32m"  # green
    local reset_color="\033[0m"
    if (( total_matches == 0 )); then
        summary_color="\033[1;33m"    # yellow if none found
    fi

    echo -e "──────────────────────────────────────────────"
    echo -e "${summary_color}✅ Found $total_matches matching branch(es) across $total_remotes remote(s).${reset_color}"
    echo -e "──────────────────────────────────────────────"
}

# Short alias for convenience
alias gbs='git_branch_search'

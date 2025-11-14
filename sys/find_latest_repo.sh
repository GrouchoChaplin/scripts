#!/usr/bin/env bash

# GLOBALS
ROOT_DIR="${1:-$HOME}"
TARGET_REPO_NAME="${2:-my-repo}"
MAX_DEPTH="${3:-5}"

# FUNCTIONS

sanitize_path() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        printf "Error: Provided path '%s' is not a directory.\n" "$path" >&2
        return 1
    fi
    ROOT_DIR="$(cd "$path" && pwd -P)"
}

find_git_repos() {
    local base="$1"
    find "$base" -maxdepth "$MAX_DEPTH" -type d -name ".git" -exec dirname {} \;
}

get_repo_status() {
    local repo="$1"
    local status branch last_commit
    cd "$repo" || return 1

    if ! branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
        printf "Error: Could not determine branch for repo '%s'\n" "$repo" >&2
        return 1
    fi

    if ! last_commit=$(git log -1 --format="%ct" 2>/dev/null); then
        printf "Error: Could not get last commit timestamp for repo '%s'\n" "$repo" >&2
        return 1
    fi

    if ! status=$(git status --porcelain); then
        printf "Error: Could not determine git status for repo '%s'\n" "$repo" >&2
        return 1
    fi

    local unstaged="no"
    local uncommitted="no"

    if grep -q '^[ MARC][ MD]' <<< "$status"; then
        unstaged="yes"
    fi

    if grep -q '^??' <<< "$status"; then
        uncommitted="yes"
    fi

    printf "%s|%s|%s|%s|%s\n" "$repo" "$branch" "$last_commit" "$unstaged" "$uncommitted"
}

analyze_repos() {
    local repos=()
    local repo; local result
    if ! mapfile -t repos < <(find_git_repos "$ROOT_DIR"); then
        printf "Error: Failed to find Git repositories.\n" >&2
        return 1
    fi

    if [[ "${#repos[@]}" -eq 0 ]]; then
        printf "No Git repositories found under '%s'\n" "$ROOT_DIR" >&2
        return 1
    fi

    for repo in "${repos[@]}"; do
        if ! result=$(get_repo_status "$repo"); then
            continue
        fi
        printf "%s\n" "$result"
    done
}

print_best_repo() {
    local data=()
    local repo branch commit unstaged uncommitted
    local latest_commit=0
    local best_repo=""

    while IFS= read -r line; do
        data+=("$line")
    done < <(analyze_repos)

    for entry in "${data[@]}"; do
        IFS='|' read -r repo branch commit unstaged uncommitted <<< "$entry"

        if [[ "$unstaged" == "yes" || "$uncommitted" == "yes" ]]; then
            printf "Uncommitted changes found in: %s (Branch: %s)\n" "$repo" "$branch"
            continue
        fi

        if (( commit > latest_commit )); then
            latest_commit="$commit"
            best_repo="$repo"
        fi
    done

    if [[ -n "$best_repo" ]]; then
        printf "\nMost recently committed clean repo: %s\n" "$best_repo"
    fi
}

main() {
    if ! sanitize_path "$ROOT_DIR"; then
        return 1
    fi

    print_best_repo
}

main "$@"

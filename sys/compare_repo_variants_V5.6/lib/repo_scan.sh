#!/usr/bin/env bash
#
# repo_scan.sh — module for compare_repo_variants_V5.6
# Handles:
#   - locating repo folders
#   - reading repo metadata
#   - scanning dirty/staged/untracked
#   - determining latest file modification

###############################################
#  find_repos
#  Locate all repo directories matching pattern
###############################################
find_repos() {
    local root="$1"
    local pattern="$2"

    [[ ! -d "$root" ]] && {
        echo "ERROR: root folder does not exist: $root" >&2
        return 1
    }

    find "$root" \
        -maxdepth 8 \
        -type d \
        -name "${pattern}*" \
        | while read -r path; do
            # Accept repo if `.git` is a directory OR file (worktrees/backups)
            if [[ -e "$path/.git" ]]; then
                echo "$path"
            fi
        done
}


###############################################
# scan_repo
###############################################
scan_repo() {
    local repo="$1"

    [[ ! -d "$repo/.git" ]] && return 1

    # Branch name
    local branch
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")

    # Commit timestamps
    local commit_epoch commit_human
    commit_epoch=$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)
    commit_human=$(git -C "$repo" log -1 --format="%Y-%m-%d %H:%M:%S %z" 2>/dev/null || echo "NO COMMITS")

    # Dirty flag
    local dirty_flag="clean"
    if ! git -C "$repo" diff --quiet --ignore-submodules -- 2>/dev/null; then
        dirty_flag="dirty"
    fi

    # Staged / unstaged / untracked
    local staged_count unstaged_count untracked_count
    staged_count=$(git -C "$repo" diff --cached --name-only | wc -l)
    unstaged_count=$(git -C "$repo" diff --name-only | wc -l)
    untracked_count=$(git -C "$repo" ls-files --others --exclude-standard | wc -l)

    # Newest file modification (epoch)
    local newest_file_epoch
    newest_file_epoch=$(find "$repo" \
        -type f \
        ! -path "*/.git/*" \
        ! -path "*/build/*" \
        ! -path "*/.dart_tool/*" \
        -printf "%T@\n" 2>/dev/null \
        | sort -nr | head -1)

    [[ -z "$newest_file_epoch" ]] && newest_file_epoch=0

    # Output (TAB-delimited)
    echo -e "${repo}\t${branch}\t${commit_epoch}\t${commit_human}\t${dirty_flag}\t${staged_count}\t${unstaged_count}\t${untracked_count}\t${newest_file_epoch}"
}

###############################################
# scan_all_repos
###############################################
scan_all_repos() {
    local root="$1"
    local pattern="$2"

    find_repos "$root" "$pattern" | while read -r repo; do
        scan_repo "$repo"
    done
}

#!/usr/bin/env bash
#
# repo_scan.sh — scanner module for compare_repo_variants_V5.6
#
# Responsibilities:
#   - Locate repo directories matching a given prefix
#   - Extract basic git metadata (branch, dirty, last commit, ahead/behind)
#   - Extract forensic details (staged/unstaged/untracked, latest file change)
#
# Requires:
#   - common.sh (for fmt_ts, git_ahead, git_behind, error, etc.)

###############################################
# find_repos ROOT PREFIX OUTFILE
#
# - ROOT:   directory to search under
# - PREFIX: repo folder name prefix (e.g., jsigconversiontools)
# - OUTFILE: path to write list of repo dirs (one per line)
###############################################
find_repos() {
    local root="$1"
    local prefix="$2"
    local outfile="$3"

    : > "$outfile"

    if [[ ! -d "$root" ]]; then
        error "Root folder does not exist: $root"
        return 1
    fi

    # Find directories whose name starts with PREFIX and that contain a .git
    # (file or directory, to support worktrees / backups with pointer .git files).
    while IFS= read -r -d '' path; do
        if [[ -e "$path/.git" ]]; then
            echo "$path" >> "$outfile"
        fi
    done < <(find "$root" -maxdepth 8 -type d -name "${prefix}*" -print0 2>/dev/null)
}

###############################################
# _count_status_classes REPO
#
# Internal helper:
#   Reads git status --porcelain and computes:
#     staged_count, unstaged_count, untracked_count
###############################################
_count_status_classes() {
    local repo="$1"
    local staged=0
    local unstaged=0
    local untracked=0

    # Each line: XY <path>
    # X = index (staged), Y = work tree (unstaged)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local x="${line:0:1}"
        local y="${line:1:1}"

        if [[ "$x$y" == "??" ]]; then
            ((untracked++))
            continue
        fi

        # Staged changes: X not blank or '?'
        if [[ "$x" != " " && "$x" != "?" ]]; then
            ((staged++))
        fi

        # Unstaged changes: Y not blank or '?'
        if [[ "$y" != " " && "$y" != "?" ]]; then
            ((unstaged++))
        fi
    done < <(git -C "$repo" status --porcelain 2>/dev/null || true)

    echo "${staged} ${unstaged} ${untracked}"
}

###############################################
# _latest_file_change REPO
#
# Internal helper:
#   Returns "epoch path" of the most recently modified file.
#   Excludes .git, build, .dart_tool and a few other noisy dirs.
###############################################
_latest_file_change() {
    local repo="$1"

    local line
    line=$(find "$repo" \
        -type f \
        ! -path "$repo/.git/*" \
        ! -path "$repo/build/*" \
        ! -path "$repo/.dart_tool/*" \
        ! -path "$repo/.idea/*" \
        ! -path "$repo/.vscode/*" \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -1)

    if [[ -z "$line" ]]; then
        echo "0"
        echo ""
        return
    fi

    local epoch_f="${line%% *}"
    local path="${line#* }"
    # Trim fractional seconds
    local epoch="${epoch_f%.*}"

    echo "$epoch"
    echo "$path"
}

###############################################
# scan_repo_basic REPO
#
# Output TSV columns:
#   1: commit_epoch
#   2: repo_path
#   3: branch
#   4: commit_human
#   5: dirty_flag
#   6: ahead
#   7: behind
#
# This is optimized for "standard" mode table output.
###############################################
scan_repo_basic() {
    local repo="$1"

    [[ ! -e "$repo/.git" ]] && return 1

    # Branch
    local branch
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

    # Last commit epoch
    local commit_epoch
    commit_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)

    # Human-readable timestamp
    local commit_human
    commit_human=$(fmt_ts "$commit_epoch")

    # Dirty?
    local dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi

    # Ahead/behind (may be empty if no upstream)
    local ahead behind
    ahead=$(git_ahead "$repo");   [[ -z "$ahead" ]] && ahead=0
    behind=$(git_behind "$repo"); [[ -z "$behind" ]] && behind=0

    echo -e "${commit_epoch}\t${repo}\t${branch}\t${commit_human}\t${dirty}\t${ahead}\t${behind}"
}

###############################################
# scan_repo_forensic REPO
#
# Output TSV columns:
#   1: repo_path
#   2: branch
#   3: last_commit_epoch
#   4: last_commit_human
#   5: dirty_flag
#   6: ahead
#   7: behind
#   8: staged_count
#   9: unstaged_count
#  10: untracked_count
#  11: latest_file_epoch
#  12: latest_file_human
#  13: latest_file_path
###############################################
scan_repo_forensic() {
    local repo="$1"

    [[ ! -e "$repo/.git" ]] && return 1

    # Branch
    local branch
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

    # Last commit epoch
    local commit_epoch
    commit_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)

    # Human-readable commit time
    local commit_human
    commit_human=$(fmt_ts "$commit_epoch")

    # Dirty flag
    local dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi

    # Ahead/behind
    local ahead behind
    ahead=$(git_ahead "$repo");   [[ -z "$ahead" ]] && ahead=0
    behind=$(git_behind "$repo"); [[ -z "$behind" ]] && behind=0

    # Status classification
    local staged unstaged untracked
    read -r staged unstaged untracked < <(_count_status_classes "$repo")

    # Latest file change
    local latest_epoch latest_path
    latest_epoch=$(_latest_file_change "$repo" | sed -n '1p')
    latest_path=$(_latest_file_change "$repo" | sed -n '2p')

    local latest_human
    latest_human=$(fmt_ts "$latest_epoch")

    echo -e "${repo}\t${branch}\t${commit_epoch}\t${commit_human}\t${dirty}\t${ahead}\t${behind}\t${staged}\t${unstaged}\t${untracked}\t${latest_epoch}\t${latest_human}\t${latest_path}"
}

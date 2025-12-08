#!/usr/bin/env bash
#
# compare_repo_variants_V5.6_Patch6.sh
#
# Deep forensic comparison of multiple backups/copies of the same Git repo.
#
# Features:
#   - Find all repo copies whose directory name *contains* a given prefix
#   - Standard mode:
#       * Branch, last commit time, dirty flag, ahead/behind
#   - Forensic mode:
#       * last commit time
#       * staged / unstaged / untracked counts
#       * latest file modification (epoch + path)
#       * "likely last active repo" based on latest activity
#   - Deep search (any depth) under the given root folder
#   - Optional --debug-find to show every candidate as found
#
# Example:
#   ./compare_repo_variants_V5.6_Patch6.sh \
#      --root-folder /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10 \
#      --repo-name jsigconversiontools \
#      --mode forensic \
#      --debug-find
#
set -euo pipefail

########################################
# Colors
########################################
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

color() {
    local c="$1"; shift
    echo -e "${c}$*${RESET}"
}

info()    { echo -e "🔍 $*"; }
warn()    { echo -e "⚠️  $*"; }
error()   { echo -e "❌ $*" >&2; }
success() { echo -e "✅ $*"; }

########################################
# Time helpers
########################################
fmt_ts() {
    local epoch="${1:-0}"
    if [[ -z "$epoch" || "$epoch" == "0" ]]; then
        echo "N/A"
        return
    fi
    date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S"
}

now_ts() {
    date "+%Y-%m-%d_%H-%M-%S"
}

########################################
# Git helpers
########################################
git_ahead() {
    local repo="$1"
    if git -C "$repo" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
        git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $2}'
    else
        echo 0
    fi
}

git_behind() {
    local repo="$1"
    if git -C "$repo" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
        git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $1}'
    else
        echo 0
    fi
}

########################################
# Repo discovery (Option A + 2)
#
#   Deep recursive search under ROOT
#   Match: directory name containing REPO_NAME
#   Require: .git directory inside
#   Optional debug output: --debug-find
########################################
DEBUG_FIND=0

find_repos() {
    local root="$1"
    local prefix="$2"
    local outfile="$3"

    : > "$outfile"

    if [[ ! -d "$root" ]]; then
        error "Root folder does not exist: $root"
        return 1
    fi

    # Deep search: any depth, names that contain prefix
    # Example prefix: jsigconversiontools
    # Matches: jsigconversiontools, jsigconversiontools.oops, TEMP/jsigconversiontools, etc.
    while IFS= read -r -d '' d; do
        if [[ -d "$d/.git" ]]; then
            (( DEBUG_FIND )) && echo "   [debug-find] candidate repo: $d"
            echo "$d" >> "$outfile"
        else
            (( DEBUG_FIND )) && echo "   [debug-find] has name match but no .git: $d"
        fi
    done < <(find "$root" -type d -name "*${prefix}*" -print0 2>/dev/null)
}

########################################
# Status classification
########################################
count_status_classes() {
    local repo="$1"
    local staged=0
    local unstaged=0
    local untracked=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local x="${line:0:1}"
        local y="${line:1:1}"

        # Untracked
        if [[ "$x$y" == "??" ]]; then
            ((untracked++))
            continue
        fi
        # Staged changes (index)
        if [[ "$x" != " " && "$x" != "?" ]]; then
            ((staged++))
        fi
        # Unstaged changes (worktree)
        if [[ "$y" != " " && "$y" != "?" ]]; then
            ((unstaged++))
        fi
    done < <(git -C "$repo" status --porcelain 2>/dev/null || true)

    echo "${staged} ${unstaged} ${untracked}"
}

########################################
# Latest file change in repo
# Excludes heavy / irrelevant dirs
########################################
latest_file_change() {
    local repo="$1"
    local line

    line=$(find "$repo" \
        -type f \
        ! -path "*/.git/*" \
        ! -path "*/build/*" \
        ! -path "*/.dart_tool/*" \
        ! -path "*/.idea/*" \
        ! -path "*/.vscode/*" \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -1)

    if [[ -z "$line" ]]; then
        echo -e "0\t"
        return
    fi

    local epoch_f="${line%% *}"
    local path="${line#* }"
    local epoch="${epoch_f%.*}"

    echo -e "${epoch}\t${path}"
}

########################################
# Scan repo (standard)
########################################
scan_repo_standard() {
    local repo="$1"

    [[ ! -e "$repo/.git" ]] && return 1

    local branch commit_epoch commit_human dirty ahead behind

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    commit_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)
    commit_human=$(fmt_ts "$commit_epoch")

    dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi

    ahead=$(git_ahead "$repo")
    behind=$(git_behind "$repo")

    echo -e "${commit_epoch}\t${repo}\t${branch}\t${commit_human}\t${dirty}\t${ahead}\t${behind}"
}

########################################
# Scan repo (forensic)
########################################
scan_repo_forensic() {
    local repo="$1"

    [[ ! -e "$repo/.git" ]] && return 1

    local branch last_epoch last_human dirty ahead behind
    local staged unstaged untracked
    local latest_epoch latest_path latest_human
    local activity_epoch

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    last_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)
    last_human=$(fmt_ts "$last_epoch")

    dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi

    ahead=$(git_ahead "$repo")
    behind=$(git_behind "$repo")

    read -r staged unstaged untracked < <(count_status_classes "$repo")
    IFS=$'\t' read -r latest_epoch latest_path <<< "$(latest_file_change "$repo")"
    latest_human=$(fmt_ts "$latest_epoch")

    # "Activity epoch" = max(last commit, latest file touch)
    if [[ "$latest_epoch" -gt "$last_epoch" ]]; then
        activity_epoch="$latest_epoch"
    else
        activity_epoch="$last_epoch"
    fi

    echo -e "${activity_epoch}\t${repo}\t${branch}\t${last_epoch}\t${last_human}\t${dirty}\t${ahead}\t${behind}\t${staged}\t${unstaged}\t${untracked}\t${latest_epoch}\t${latest_human}\t${latest_path}"
}

########################################
# Printing helpers
########################################
print_standard_header() {
    printf "%-70s | %-25s | %-19s | %-7s | %-5s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%0.s—" {1..150}
    echo
}

print_forensic_header() {
    printf "%-70s | %-10s | %-19s | %-19s | %-6s | %-6s | %-6s | %-6s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "LAST FILE" "DIRTY" "STAGE" "UNSTG" "UNTRK" "ACT.EPOCH"
    printf "%0.s—" {1..170}
    echo
}

########################################
# Modes
########################################
run_mode_standard() {
    local root="$1"
    local name="$2"

    info "Running STANDARD comparison mode…"
    info "Searching: $root"
    info "Looking for repos with names containing: $name"

    local repo_list
    repo_list="$(mktemp)"
    local scan_file
    scan_file="$(mktemp)"
    local sorted
    sorted="$(mktemp)"

    find_repos "$root" "$name" "$repo_list"

    if [[ ! -s "$repo_list" ]]; then
        error "No repos found matching *${name}* under: $root"
        rm -f "$repo_list" "$scan_file" "$sorted"
        return 1
    fi

    info "Found $(wc -l < "$repo_list") repo(s). Collecting metadata…"

    while IFS= read -r repo; do
        scan_repo_standard "$repo" >> "$scan_file"
    done < "$repo_list"

    sort -nr -k1,1 "$scan_file" > "$sorted"

    echo
    print_standard_header

    while IFS=$'\t' read -r commit_epoch repo branch commit_human dirty ahead behind; do
        local dirty_colored="$dirty"
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored="$(color "$RED" "$dirty")"
        else
            dirty_colored="$(color "$GREEN" "$dirty")"
        fi
        printf "%-70s | %-25s | %-19s | %-7s | %-5s | %-6s\n" \
            "$repo" "$branch" "$commit_human" "$dirty_colored" "$ahead" "$behind"
    done < "$sorted"

    if [[ "$DEBUG_TEMP" -eq 1 ]]; then
        echo
        echo "[debug-temp] Keeping temp files for inspection:"
        echo "  repo_list = $repo_list"
        echo "  scan_file = $scan_file"
        echo "  sorted    = $sorted"
    else
        rm -f "$repo_list" "$scan_file" "$sorted"
    fi

}

run_mode_forensic() {
    local root="$1"
    local name="$2"

    info "Running FORENSIC mode…"
    info "Searching: $root"
    info "Looking for repos with names containing: $name"

    local repo_list
    repo_list="$(mktemp)"
    local scan_file
    scan_file="$(mktemp)"
    local sorted
    sorted="$(mktemp)"

    find_repos "$root" "$name" "$repo_list"

    if [[ ! -s "$repo_list" ]]; then
        error "No repos found matching *${name}* under: $root"
        rm -f "$repo_list" "$scan_file" "$sorted"
        return 1
    fi

    info "Found $(wc -l < "$repo_list") repo(s). Collecting forensic data…"

    while IFS= read -r repo; do
        scan_repo_forensic "$repo" >> "$scan_file"
    done < "$repo_list"

    # Sort by activity_epoch descending (field 1)
    sort -nr -k1,1 "$scan_file" > "$sorted"

    echo
    print_forensic_header

    local best_repo=""
    local best_epoch=0
    local first=1

    while IFS=$'\t' read -r activity_epoch repo branch last_epoch last_human dirty ahead behind \
                             staged unstaged untracked latest_epoch latest_human latest_path; do
        # Mark first row as "likely last active"
        if [[ $first -eq 1 ]]; then
            best_repo="$repo"
            best_epoch="$activity_epoch"
            first=0
        fi

        local dirty_colored="$dirty"
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored="$(color "$RED" "$dirty")"
        else
            dirty_colored="$(color "$GREEN" "$dirty")"
        fi

        printf "%-70s | %-10s | %-19s | %-19s | %-6s | %-6s | %-6s | %-6s | %-6s\n" \
            "$repo" "$branch" "$last_human" "$latest_human" \
            "$dirty_colored" "$staged" "$unstaged" "$untracked" "$activity_epoch"
    done < "$sorted"

    echo
    success "Likely LAST ACTIVE repo (by activity):"
    echo "   Path : $best_repo"
    echo "   Epoch: $best_epoch"
    echo "   Time : $(fmt_ts "$best_epoch")"

    if [[ "$DEBUG_TEMP" -eq 1 ]]; then
        echo
        echo "[debug-temp] Keeping temp files for inspection:"
        echo "  repo_list = $repo_list"
        echo "  scan_file = $scan_file"
        echo "  sorted    = $sorted"
    else
        rm -f "$repo_list" "$scan_file" "$sorted"
    fi

}

########################################
# CLI parsing
########################################

ROOT_FOLDER=""
REPO_NAME=""
MODE="standard"
DEBUG_FIND=0
DEBUG_TEMP=0 

usage() {
    cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [--mode standard|forensic] [--debug-find]

Options:
  --root-folder PATH    Root of backup tree to search
  --repo-name NAME      Repo name substring (e.g. jsigconversiontools)
  --mode MODE           'standard' (default) or 'forensic'
  --debug-find          Print each candidate directory found during search
  -h, --help            Show this help

Examples:
  Standard:
    $0 --root-folder /run/media/.../2025-10-10 \\
       --repo-name jsigconversiontools \\
       --mode standard

  Forensic:
    $0 --root-folder /run/media/.../2025-10-10 \\
       --repo-name jsigconversiontools \\
       --mode forensic --debug-find
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root-folder)
            ROOT_FOLDER="$2"; shift 2 ;;
        --repo-name)
            REPO_NAME="$2"; shift 2 ;;
        --mode)
            MODE="$2"; shift 2 ;;
        --debug-find)
            DEBUG_FIND=1; shift ;;
        --debug-temp)
            DEBUG_TEMP=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            error "Unknown argument: $1"
            usage
            exit 1 ;;
    esac
done

if [[ -z "$ROOT_FOLDER" ]]; then
    error "--root-folder is required"
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    error "--repo-name is required"
    exit 1
fi

if [[ ! -d "$ROOT_FOLDER" ]]; then
    error "Root folder does not exist: $ROOT_FOLDER"
    exit 1
fi

case "$MODE" in
    standard|forensic) ;;
    *)
        error "Invalid --mode: $MODE (must be 'standard' or 'forensic')"
        exit 1 ;;
esac

########################################
# Dispatch
########################################
case "$MODE" in
    standard) run_mode_standard "$ROOT_FOLDER" "$REPO_NAME" ;;
    forensic) run_mode_forensic "$ROOT_FOLDER" "$REPO_NAME" ;;
esac

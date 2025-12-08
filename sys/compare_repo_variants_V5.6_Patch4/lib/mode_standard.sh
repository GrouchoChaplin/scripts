#!/usr/bin/env bash
#
# mode_standard.sh — “standard” comparison mode for V5.6_Patch4
#
# Responsibilities:
#   - Read repo list
#   - Scan each repo using scan_repo_basic
#   - Sort by last commit
#   - Print colorized table

run_mode_standard() {
    local root="$1"
    local prefix="$2"

    local repo_list_file
    repo_list_file="$(mktemp)"
    local scan_results
    scan_results="$(mktemp)"
    local sorted
    sorted="$(mktemp)"

    info "Searching: $root"
    info "Looking for repos matching prefix: ${prefix}*"

    find_repos "$root" "$prefix" "$repo_list_file"

    if [[ ! -s "$repo_list_file" ]]; then
        error "No repositories found matching: ${prefix}*"
        rm -f "$repo_list_file" "$scan_results" "$sorted"
        return 1
    fi

    # Scan
    while IFS= read -r repo; do
        scan_repo_basic "$repo" >> "$scan_results"
    done < "$repo_list_file"

    # Sort by commit epoch descending
    sort -nr -k1,1 "$scan_results" > "$sorted"

    print_header

    while IFS=$'\t' read -r commit_epoch repo branch commit_human dirty ahead behind; do
        local dirty_colored="$dirty"
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored=$(colorize "$RED" "dirty")
        else
            dirty_colored=$(colorize "$GREEN" "clean")
        fi

        local ahead_colored="$ahead"
        local behind_colored="$behind"

        [[ "$ahead"  -gt 0 ]] && ahead_colored=$(colorize "$GREEN" "$ahead")
        [[ "$behind" -gt 0 ]] && behind_colored=$(colorize "$YELLOW" "$behind")

        printf "%-65s | %-22s | %-19s | %-7s | %-6s | %-6s\n" \
            "$repo" "$branch" "$commit_human" "$dirty_colored" "$ahead_colored" "$behind_colored"
    done < "$sorted"

    rm -f "$repo_list_file" "$scan_results" "$sorted"
}

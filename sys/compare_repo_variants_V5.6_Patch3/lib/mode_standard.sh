#!/usr/bin/env bash
#
# mode_standard.sh — “standard” comparison mode for V5.6-Patch3
#
# Responsibilities:
#   - Read repo list from temp file
#   - Scan each repo using scan_repo_basic
#   - Sort by last commit
#   - Print colorized table using common.sh helpers

###############################################
# run_mode_standard ROOT PREFIX
###############################################
run_mode_standard() {
    local root="$1"
    local prefix="$2"

    # Temp file containing repo list (one per line)
    local repo_list_file=$(mktemp)

    info "Searching: $root"
    info "Looking for repos matching prefix: ${prefix}*"

    # Populate list
    find_repos "$root" "$prefix" "$repo_list_file"

    if [[ ! -s "$repo_list_file" ]]; then
        error "No repositories found matching: ${prefix}*"
        rm -f "$repo_list_file"
        return 1
    fi

    ###########################################################################
    # Scan all repos — produce TSV rows:
    #   commit_epoch <TAB> repo_path <TAB> branch <TAB> commit_human <TAB> dirty <TAB> ahead <TAB> behind
    ###########################################################################

    local scan_results="$(mktemp)"

    while IFS= read -r repo; do
        scan_repo_basic "$repo" >> "$scan_results"
    done < "$repo_list_file"

    ###########################################################################
    # Sort by commit epoch (largest first)
    ###########################################################################
    local sorted="$(mktemp)"
    sort -nr -k1,1 "$scan_results" > "$sorted"

    ###########################################################################
    # Print table header
    ###########################################################################
    print_header

    ###########################################################################
    # Print each repo entry with colors
    ###########################################################################
    while IFS=$'\t' read -r commit_epoch repo branch commit_human dirty ahead behind; do

        # colorize DIRTY state
        local dirty_colored
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored=$(colorize "$RED" "dirty")
        else
            dirty_colored=$(colorize "$GREEN" "clean")
        fi

        # ahead/behind highlighting
        local ahead_colored="$ahead"
        local behind_colored="$behind"

        [[ $ahead  -gt 0 ]] && ahead_colored=$(colorize "$GREEN" "$ahead")
        [[ $behind -gt 0 ]] && behind_colored=$(colorize "$YELLOW" "$behind")

        # final output
        printf "%-65s | %-22s | %-19s | %-7s | %-6s | %-6s\n" \
            "$repo" "$branch" "$commit_human" "$dirty_colored" "$ahead_colored" "$behind_colored"

    done < "$sorted"

    ###########################################################################
    # Cleanup
    ###########################################################################
    rm -f "$repo_list_file" "$scan_results" "$sorted"
}

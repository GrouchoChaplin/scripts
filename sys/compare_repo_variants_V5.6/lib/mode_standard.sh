# lib/mode_standard.sh — classic simple mode

run_mode_standard() {
    local tmp_repos="$1"
    local tmp_meta
    tmp_meta=$(mktemp)

    log_info ""
    log_info "Collecting basic repo metadata (standard mode)…"

    while IFS= read -r repo; do
        scan_repo_basic "$repo"
    done < "$tmp_repos" > "$tmp_meta"

    log_info ""
    printf "%-70s | %-20s | %-6s | %-19s\n" "REPO PATH" "BRANCH" "DIRTY" "LAST COMMIT"
    printf "%-70s-+-%-20s-+-%-6s-+-%-19s\n" "$(printf '%.0s-' {1..70})" "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..6})" "$(printf '%.0s-' {1..19})"

    while IFS=$'\t' read -r epoch path branch dirty; do
        local ts
        ts=$(human_time "$epoch")
        printf "%-70s | %-20s | %-6s | %-19s\n" "$path" "$branch" "$dirty" "$ts"
    done < <(sort -nrk1,1 "$tmp_meta")

    rm -f "$tmp_meta" 2>/dev/null || true
}

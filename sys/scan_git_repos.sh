#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${1:-.}"

echo "🔍 Scanning for Git repos under: $BASE_DIR"
echo

# Find every .git folder and get its parent directory (the repo)
mapfile -t REPOS < <(find "$BASE_DIR" -type d -name ".git" -prune 2>/dev/null | sed 's/\/.git$//')

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "❌ No git repos found."
    exit 1
fi

printf "%-50s | %-30s | %-20s | %-8s | %s\n" "REPO PATH" "BRANCH" "LAST COMMIT TIME" "DIRTY" "HASH"
printf "%s\n" "$(printf '—%.0s' {1..120})"

for repo in "${REPOS[@]}"; do
    pushd "$repo" >/dev/null

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
    commit_hash=$(git rev-parse --short HEAD)
    commit_time=$(git log -1 --format="%ci")
    
    # Check for modifications
    dirty="clean"
    if [[ -n $(git status --porcelain) ]]; then
        dirty="DIRTY"
    fi

    printf "%-50s | %-30s | %-20s | %-8s | %s\n" \
        "$repo" "$branch" "$commit_time" "$dirty" "$commit_hash"

    # Detailed status if dirty
    if [[ "$dirty" == "DIRTY" ]]; then
        echo "   🔸 Changes:"
        git status --porcelain | sed 's/^/      /'
    fi

    echo
    popd >/dev/null
done

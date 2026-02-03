#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Scanning forks for unique commits..."

gh repo list --fork --json nameWithOwner,parent \
| jq -r '.[] | select(.parent != null) | [.nameWithOwner, .parent.nameWithOwner] | @tsv' \
| while IFS=$'\t' read -r fork upstream; do
    echo
    echo "▶ $fork (upstream: $upstream)"

    tmpdir=$(mktemp -d)
    git clone --quiet https://github.com/$fork.git "$tmpdir/fork"
    cd "$tmpdir/fork"

    git remote add upstream https://github.com/$upstream.git
    git fetch --quiet upstream

    unique_commits=$(git rev-list --count HEAD ^upstream/HEAD || echo 0)

    if [[ "$unique_commits" -eq 0 ]]; then
        echo "🗑 No unique commits — deleting $fork"
        # gh repo delete "$fork" --yes
echo "[DRY RUN] Would delete $fork"
        
    else
        echo "✅ $unique_commits unique commit(s) — keeping"
    fi

    cd /
    rm -rf "$tmpdir"
done

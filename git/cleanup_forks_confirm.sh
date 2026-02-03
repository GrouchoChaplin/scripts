#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"

usage() {
    cat <<EOF
Usage: $0 [--dry-run | --apply]

Options:
  --dry-run   Analyze and show what would be deleted (default)
  --apply     Actually delete repositories after confirmation
  --help      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo "🔍 Scanning forks for unique commits..."
echo "Mode: $MODE"

DELETE_LIST=()
KEEP_LIST=()

while IFS=$'\t' read -r fork upstream branch; do
    echo
    echo "▶ $fork (upstream: $upstream, branch: $branch)"

    tmpdir=$(mktemp -d)
    (
        set +e
        git clone --quiet https://github.com/$fork.git "$tmpdir/fork" || exit 0
        cd "$tmpdir/fork" || exit 0

        git remote add upstream https://github.com/$upstream.git
        git fetch --quiet upstream

        unique_commits=$(git rev-list --count "$branch" "^upstream/$branch" 2>/dev/null || echo 0)

        if [[ "$unique_commits" -eq 0 ]]; then
            echo "🗑 No unique commits — candidate for deletion"
            DELETE_LIST+=("$fork")
        else
            echo "✅ $unique_commits unique commit(s) — keeping"
            KEEP_LIST+=("$fork")
        fi
    )
    rm -rf "$tmpdir"
done < <(
  gh repo list --fork --json nameWithOwner,parent,defaultBranchRef \
  | jq -r '.[] 
    | select(.parent != null) 
    | [.nameWithOwner, .parent.nameWithOwner, .defaultBranchRef.name] 
    | @tsv'
)

echo
echo "======================"
echo "📊 SUMMARY"
echo "======================"

printf "\n%-10s | %-50s\n" "ACTION" "REPOSITORY"
printf "%-10s-+-%-50s\n" "----------" "--------------------------------------------------"

for r in "${DELETE_LIST[@]:-}"; do
    printf "%-10s | %-50s\n" "DELETE" "$r"
done

for r in "${KEEP_LIST[@]:-}"; do
    printf "%-10s | %-50s\n" "KEEP" "$r"
done

echo
echo "Delete candidates: ${#DELETE_LIST[@]}"
echo "Kept repos:        ${#KEEP_LIST[@]}"

if [[ "${#DELETE_LIST[@]}" -eq 0 ]]; then
    echo "🎉 Nothing to delete."
    exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
    echo
    echo "🧪 DRY RUN — no repositories will be deleted."
    exit 0
fi

echo
read -rp "❓ Type DELETE to confirm permanent deletion: " CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "🚫 Aborted. No repositories were deleted."
    exit 0
fi

echo
echo "🔥 Deleting repositories..."

for r in "${DELETE_LIST[@]}"; do
    echo "Deleting $r"
    gh repo delete "$r" --yes
done

echo
echo "✅ Cleanup complete."

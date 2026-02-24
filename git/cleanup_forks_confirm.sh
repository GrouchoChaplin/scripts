#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"
KEEP_STARRED=false
KEEP_PATTERN=""

usage() {
cat <<EOF
Usage: $0 [options]

Options:
  --dry-run               Analyze only (default)
  --apply                 Delete confirmed candidates
  --keep-starred          Never delete starred repos
  --keep-pattern REGEX    Never delete repos matching REGEX (name only)
  --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --keep-starred) KEEP_STARRED=true; shift ;;
    --keep-pattern) KEEP_PATTERN="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "❌ Unknown option: $1"; usage; exit 1 ;;
  esac
done

echo "🔍 Scanning forks for unique commits..."
echo "Mode:          $MODE"
echo "Keep starred:  $KEEP_STARRED"
echo "Keep pattern:  ${KEEP_PATTERN:-<none>}"

DELETE_LIST=()
KEEP_LIST=()

while IFS=$'\t' read -r fork upstream fork_branch upstream_branch starred; do
  repo_name="${fork##*/}"

  echo
  echo "▶ $fork"
  echo "   upstream: $upstream"
  echo "   branch:   $fork_branch"

  # ---- Keep rules (pre-check, no cloning needed) ----
  if [[ "$KEEP_STARRED" == true && "$starred" == "true" ]]; then
    echo "⭐ Starred repo — keeping"
    KEEP_LIST+=("$fork")
    continue
  fi

  if [[ -n "$KEEP_PATTERN" && "$repo_name" =~ $KEEP_PATTERN ]]; then
    echo "🔒 Name matches keep pattern ($KEEP_PATTERN) — keeping"
    KEEP_LIST+=("$fork")
    continue
  fi

  # ---- Clone + compare ----
  tmpdir=$(mktemp -d)

  set +e
  git clone --quiet https://github.com/$fork.git "$tmpdir/fork"
  clone_status=$?
  set -e

  if [[ $clone_status -ne 0 ]]; then
    echo "⚠️ Clone failed — keeping repo for safety"
    KEEP_LIST+=("$fork")
    rm -rf "$tmpdir"
    continue
  fi

  cd "$tmpdir/fork"

  git remote add upstream https://github.com/$upstream.git
  git fetch --quiet upstream || true

  unique_commits=$(git rev-list --count \
      "$fork_branch" "^upstream/$upstream_branch" 2>/dev/null || echo 0)

  if [[ "$unique_commits" -eq 0 ]]; then
    echo "🗑 No unique commits — candidate for deletion"
    DELETE_LIST+=("$fork")
  else
    echo "✅ $unique_commits unique commit(s) — keeping"
    KEEP_LIST+=("$fork")
  fi

  cd /
  rm -rf "$tmpdir"

done < <(
  gh repo list --fork --json nameWithOwner,defaultBranchRef,parent,viewerHasStarred \
  | jq -r '
      .[]
      | select(.parent != null)
      | [
          .nameWithOwner,
          .parent.nameWithOwner,
          .defaultBranchRef.name,
          .parent.defaultBranchRef.name,
          .viewerHasStarred
        ]
      | @tsv
    '
)

echo
echo "======================"
echo "📊 SUMMARY"
echo "======================"

printf "\n%-10s | %-50s\n" "ACTION" "REPOSITORY"
printf "%-10s-+-%-50s\n" "----------" "--------------------------------------------------"

for r in "${DELETE_LIST[@]}"; do
  printf "%-10s | %-50s\n" "DELETE" "$r"
done

for r in "${KEEP_LIST[@]}"; do
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
  echo "🧪 DRY RUN — no repositories deleted."
  exit 0
fi

echo
read -rp "Type DELETE to confirm permanent deletion: " CONFIRM
[[ "$CONFIRM" != "DELETE" ]] && { echo "Aborted."; exit 0; }

echo
echo "🔥 Deleting repositories..."

for r in "${DELETE_LIST[@]}"; do
  echo "Deleting $r"
  gh repo delete "$r" --yes
done

echo
echo "✅ Cleanup complete."

#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# git-branches-recent.sh
#
# List git branches ordered by most recent commit.
# Shows:
#   - Commit date (short)
#   - Author
#   - Branch name
#   - Last commit subject
#
# Works for:
#   - Local branches (default)
#   - Remote branches (--remote)
#   - All branches (--all)
#
# Usage:
#   git-branches-recent.sh
#   git-branches-recent.sh --remote
#   git-branches-recent.sh --all
# ------------------------------------------------------------------------------

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: git-branches-recent.sh [OPTIONS]

Options:
  --local        Show local branches only (default)
  --remote       Show remote branches only
  --all          Show local + remote branches
  -h, --help     Show this help message

Examples:
  git-branches-recent.sh
  git-branches-recent.sh --remote
  git-branches-recent.sh --all
EOF
}

# Default scope
scope="refs/heads/"

case "${1:-}" in
  --local|"")
    scope="refs/heads/"
    ;;
  --remote)
    scope="refs/remotes/"
    ;;
  --all)
    scope=""
    ;;
  -h|--help)
    show_help
    exit 0
    ;;
  *)
    echo "❌ Unknown option: $1" >&2
    show_help
    exit 1
    ;;
esac

# Ensure we're inside a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Not inside a git repository" >&2
  exit 1
fi

git for-each-ref \
  ${scope:+$scope} \
  --sort=-committerdate \
  --format='%(committerdate:iso) %(authorname) %(refname:short) — %(contents:subject)'

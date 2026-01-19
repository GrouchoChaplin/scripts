#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME --url <git-repo-url> --branch <branch-name> [--dir <target-dir>]

Options:
  --url      Git repository URL (HTTPS or SSH)   [required]
  --branch   Branch name to clone                [required]
  --dir      Target directory (default: repo name)
  --help     Show this help and exit

Examples:
  $SCRIPT_NAME --url https://gitlab.com/org/project.git --branch develop
  $SCRIPT_NAME --url git@gitlab.com:org/project.git --branch feature-x --dir mydir
EOF
  exit 0
}

# Defaults
REPO_URL=""
BRANCH=""
TARGET_DIR=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "❌ Unknown option: $1"
      usage
      ;;
  esac
done

# Validate required args
if [[ -z "$REPO_URL" || -z "$BRANCH" ]]; then
  echo "❌ Error: --url and --branch are required"
  usage
fi

# Default target dir
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(basename "$REPO_URL" .git)"
fi

echo "Cloning repository:"
echo "  URL    : $REPO_URL"
echo "  Branch : $BRANCH"
echo "  Target : $TARGET_DIR"
echo

git clone \
  --single-branch \
  --branch "$BRANCH" \
  --depth 1 \
  "$REPO_URL" \
  "$TARGET_DIR"

echo
echo "✅ Clone complete."

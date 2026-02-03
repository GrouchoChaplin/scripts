#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:"
  echo "  $0 --url <repo-url> --branch <branch-name> [--dir <target-dir>]"
  echo
  echo "Example:"
  echo "  $0 --url https://github.com/user/repo.git --branch my-branch"
  exit 1
}

URL=""
BRANCH=""
DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --dir)
      DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "❌ Unknown argument: $1"
      usage
      ;;
  esac
done

if [[ -z "$URL" || -z "$BRANCH" ]]; then
  echo "❌ --url and --branch are required"
  usage
fi

CMD=(git clone --single-branch --branch "$BRANCH" "$URL")

if [[ -n "$DIR" ]]; then
  CMD+=("$DIR")
fi

echo "📦 Cloning branch '$BRANCH' from $URL"
"${CMD[@]}"

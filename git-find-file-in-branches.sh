#!/usr/bin/env bash
# git-find-file.sh
# Search all remote branches for a file and sort results by modification date.
#
# Usage:
#   ./git-find-file.sh <file_path> [options]
#
# Options:
#   -r, --remote <name>   Remote name to search (default: origin)
#   -a, --asc             Sort ascending (oldest first); default is newest first
#   -i, --ignore-case     Case-insensitive file path matching
#   -h, --help            Show this help message
#
#
# chmod +x git-find-file.sh
#
# # Basic usage
# ./git-find-file.sh src/config.js
#
# # Case-insensitive match, oldest first
# ./git-find-file.sh config.js --ignore-case --asc
#
# # Search a different remote
# ./git-find-file.sh package.json --remote upstream
#

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
REMOTE="origin"
SORT_ORDER="-r"   # newest first
GREP_OPTS="-q"
FILE_PATH=""

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Help ─────────────────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage ;;
    -r|--remote)      REMOTE="$2"; shift 2 ;;
    -a|--asc)         SORT_ORDER=""; shift ;;
    -i|--ignore-case) GREP_OPTS="-qi"; shift ;;
    -*)               echo -e "${RED}Unknown option: $1${RESET}" >&2; exit 1 ;;
    *)                FILE_PATH="$1"; shift ;;
  esac
done

if [[ -z "$FILE_PATH" ]]; then
  echo -e "${RED}Error:${RESET} No file path specified."
  echo "Usage: $0 <file_path> [options]"
  exit 1
fi

# ── Sanity checks ─────────────────────────────────────────────────────────────
if ! git rev-parse --git-dir &>/dev/null; then
  echo -e "${RED}Error:${RESET} Not inside a Git repository."
  exit 1
fi

# ── Fetch latest remote refs ──────────────────────────────────────────────────
echo -e "${CYAN}Fetching remote '${REMOTE}'...${RESET}"
if ! git fetch "$REMOTE" --quiet 2>/dev/null; then
  echo -e "${YELLOW}Warning:${RESET} Could not fetch from '${REMOTE}'. Proceeding with cached refs."
fi

# ── Search branches ───────────────────────────────────────────────────────────
echo -e "${CYAN}Searching branches for:${RESET} ${BOLD}${FILE_PATH}${RESET}\n"

results=()

while IFS= read -r remote_branch; do
  branch="${remote_branch#"${REMOTE}/"}"

  # Check if file exists in this branch
  if git ls-tree -r "$remote_branch" --name-only 2>/dev/null | grep $GREP_OPTS "$FILE_PATH"; then
    # Get the last commit date for this file on this branch
    date=$(git log -1 --format="%ai" "$remote_branch" -- "$FILE_PATH" 2>/dev/null)
    if [[ -n "$date" ]]; then
      results+=("$date $branch")
    fi
  fi
done < <(git branch -r | grep "^[[:space:]]*${REMOTE}/" | sed 's/[[:space:]]*//' | grep -v 'HEAD')

# ── Output ────────────────────────────────────────────────────────────────────
if [[ ${#results[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No branches found containing:${RESET} ${FILE_PATH}"
  exit 0
fi

# Sort and print
echo -e "${BOLD}$(printf '%-35s %s' 'Last Modified' 'Branch')${RESET}"
echo "$(printf '%0.s─' {1..60})"

echo "${results[@]}" | tr ' ' '\n' | paste - - - - | \
  sort ${SORT_ORDER} | \
  while IFS=$'\t' read -r date tz branch; do
    printf "${GREEN}%-25s${RESET}  %s\n" "$date $tz" "$branch"
  done

echo ""
echo -e "  ${BOLD}${#results[@]}${RESET} branch(es) found."
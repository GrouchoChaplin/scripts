#!/usr/bin/env bash
#
# git_latest_info.sh
#
# Author:      peddycoartte
# Created:     2025-11-09 15:40:50
#
# Description: 
#
# Displays detailed information about the latest commit in the current Git repo.
# Can be run standalone or sourced to use the git_latest_info() function.
#
# Usage:
#   ./git_latest_info.sh [--short|--summary|--json|--full]
#   source ./git_latest_info.sh   # to load git_latest_info() into your scripts
#   git_latest_info [options]
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Function: git_latest_info ---------------------------------------------
git_latest_info() {
    local mode="${1:-summary}"

    # Verify inside a git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "❌ Not inside a Git repository." >&2
        return 1
    fi

    local branch status_clean

    branch="$(git rev-parse --abbrev-ref HEAD)"
    if git diff --quiet && git diff --cached --quiet; then
        status_clean="✅ Clean"
    else
        status_clean="⚠️  Dirty (uncommitted changes)"
    fi

    case "$mode" in
        --short)
            git log -1 --pretty=format:"[%h] %s (%ad) by %an on branch ${branch}" --date=short
            ;;
        --summary)
            echo "📘 Latest Commit Summary"
            echo "Branch: ${branch}   Status: ${status_clean}"
            echo "------------------------------------------"
            git log -1 --pretty=format:"Commit: %H%nAuthor: %an <%ae>%nDate: %ad%n%nMessage:%n%s%n%b" --date=iso
            ;;
        --full)
            echo "📘 Latest Commit Details"
            echo "Branch: ${branch}   Status: ${status_clean}"
            echo "------------------------------------------"
            git log -1 --pretty=format:"Commit: %H%nAuthor: %an <%ae>%nDate: %ad%n%nMessage:%n%s%n%b" --date=iso
            echo
            echo "🧾 File Changes:"
            git show -1 --stat
            ;;
        --json)
            # Output structured JSON for automation
            echo "{"
            echo "  \"branch\": \"${branch}\","
            echo "  \"status\": \"${status_clean}\","
            git log -1 --pretty=format:'  "hash": "%H",
  "short_hash": "%h",
  "author_name": "%an",
  "author_email": "%ae",
  "date": "%ad",
  "subject": "%s",
  "body": "%b"' --date=iso
            echo
            echo "}"
            ;;
        *)
            echo "Usage: git_latest_info [--short|--summary|--json|--full]" >&2
            return 1
            ;;
    esac
}

# --- If run directly, execute with arguments ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    git_latest_info "${@:-summary}"
fi

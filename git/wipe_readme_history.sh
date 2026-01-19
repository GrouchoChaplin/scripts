#!/usr/bin/env bash
#
# wipe_readme_history.sh
# Completely removes README.md (and all README* variants) from ALL branches.
# Safe, automated, and produces a verification report.
#
# Usage:
#   ./wipe_readme_history.sh <repo-url>
#
# Example:
#   ./wipe_readme_history.sh git@gitlab.com:mygroup/myrepo.git
#

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <repo-url>"
    exit 1
fi

REPO_URL="$1"
WORK_DIR="repo-clean-wipe"
TARGET_PATTERN="README*"

echo "--------------------------------------------------"
echo "  Wipe README History Script"
echo "  Repo: $REPO_URL"
echo "  Pattern: $TARGET_PATTERN"
echo "--------------------------------------------------"
echo

# Step 1 — Fresh clone
echo "[1/6] Cloning clean repo..."
rm -rf "$WORK_DIR"
git clone "$REPO_URL" "$WORK_DIR"
cd "$WORK_DIR"

# Step 2 — Identify all branches that contain README historically
echo "[2/6] Detecting branches containing README*..."
AFFECTED_BRANCHES=()
for BR in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
    if git log "$BR" --name-only --pretty=format: | grep -qi '^README'; then
        echo "  -> Affected: $BR"
        AFFECTED_BRANCHES+=("$BR")
    fi
done

if [[ ${#AFFECTED_BRANCHES[@]} -eq 0 ]]; then
    echo "No branches contain README*. Nothing to do."
    exit 0
fi

echo
echo "Branches to rewrite:"
printf '  %s\n' "${AFFECTED_BRANCHES[@]}"
echo

# Step 3 — Run filter-repo across ALL branches
echo "[3/6] Rewriting history using git filter-repo..."
git filter-repo --path-glob "$TARGET_PATTERN" --invert-paths --force

# Step 4 — Verification before push
echo "[4/6] Verifying wipe..."
if git log --all --name-only --pretty=format: | grep -qi '^README'; then
    echo "ERROR: README still appears in history!"
    exit 1
fi
echo "Verification passed. README* fully removed from history."
echo

# Step 5 — Force-push rewritten branches
echo "[5/6] Force-pushing rewritten branches..."
for BR in "${AFFECTED_BRANCHES[@]}"; do
    echo "  -> Pushing $BR"
    git push origin "$BR" --force
done

echo
echo "[6/6] Wipe complete!"
echo "README.md and all README* variants removed from all history."
echo
echo "You may now recreate a new README.md safely."

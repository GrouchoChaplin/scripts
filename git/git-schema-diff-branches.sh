git_schema_diff_branches() {
  local BASE_BRANCH="${1:-main}"

  # Make sure we have up-to-date refs
  git fetch --all --quiet

  git for-each-ref --format='%(refname)' refs/heads refs/remotes | while read ref; do
    # Skip the base branch itself
    if [[ "$ref" == "refs/heads/$BASE_BRANCH" || "$ref" == "refs/remotes/origin/$BASE_BRANCH" ]]; then
      continue
    fi

    # Check if any schema JSON files differ vs base
    if git diff --quiet "$BASE_BRANCH...$ref" -- docs/schema/*.json 2>/dev/null; then
      : # no diff → ignore
    else
      echo "=== ${ref#refs/*/} differs from $BASE_BRANCH ==="
      git diff --name-only "$BASE_BRANCH...$ref" -- docs/schema/*.json
      echo
    fi
  done
}

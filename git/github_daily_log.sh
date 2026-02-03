#!/usr/bin/env bash
set -euo pipefail

DATE=$(date +"%Y-%m-%d")
OUT="github-log-$DATE.md"

echo "# GitHub Activity — $DATE" > "$OUT"
echo >> "$OUT"

echo "## Commits" >> "$OUT"
gh search commits \
  --author "@me" \
  --committer-date "$(date +%Y-%m-%d)" \
  --json repository,commit \
| jq -r '.[] | "- \(.repository.nameWithOwner): \(.commit.messageHeadline)"' \
>> "$OUT" || echo "- None" >> "$OUT"

echo >> "$OUT"
echo "## Pull Requests Opened" >> "$OUT"
gh pr list --author "@me" --state all --json title,url \
| jq -r '.[] | "- [\(.title)](\(.url))"' \
>> "$OUT" || echo "- None" >> "$OUT"

echo >> "$OUT"
echo "## Issues Commented On" >> "$OUT"
gh issue list --author "@me" --state all --json title,url \
| jq -r '.[] | "- [\(.title)](\(.url))"' \
>> "$OUT" || echo "- None" >> "$OUT"

echo
echo "📝 Wrote $OUT"

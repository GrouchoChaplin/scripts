#!/usr/bin/env bash
set -euo pipefail

# Docs live in docs/
# You generate docs before release
# Semantic versioning (vX.Y.Z)

VERSION="$1"
[[ -z "$VERSION" ]] && { echo "Usage: $0 vX.Y.Z"; exit 1; }

echo "📦 Preparing release $VERSION"

# 1. Regenerate docs
echo "📚 Generating docs..."
./scripts/generate_docs.sh

# 2. Commit docs
git add docs/
git commit -m "docs: update for release $VERSION"

# 3. Tag
git tag -a "$VERSION" -m "Release $VERSION"

# 4. Push
git push origin main
git push origin "$VERSION"

# 5. GitHub release
gh release create "$VERSION" \
  --title "Release $VERSION" \
  --notes-file docs/RELEASE_NOTES.md \
  --verify-tag

echo "🚀 Release $VERSION published"

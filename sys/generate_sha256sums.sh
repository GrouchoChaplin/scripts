#!/usr/bin/env bash
set -euo pipefail

OUTPUT="sha256sum.info"
EXCLUDES=(".git")
VERIFY=false

show_help() {
  cat <<EOF
Usage: generate_sha256sums.sh [OPTIONS]

Options:
  -o, --output FILE        Output file (default: sha256sum.info)
  -e, --exclude DIR        Exclude directory (repeatable)
  -v, --verify             Verify checksums instead of generating
  -h, --help               Show this help

Examples:
  generate_sha256sums.sh
  generate_sha256sums.sh -e build -e .dart_tool
  generate_sha256sums.sh --verify
  generate_sha256sums.sh --verify -o release.sha256
EOF
}

# -----------------------
# Parse args
# -----------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUTPUT="$2"
      shift 2
      ;;
    -e|--exclude)
      EXCLUDES+=("$2")
      shift 2
      ;;
    -v|--verify)
      VERIFY=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      exit 1
      ;;
  esac
done

# -----------------------
# Verify mode
# -----------------------
if $VERIFY; then
  if [[ ! -f "$OUTPUT" ]]; then
    echo "❌ Checksum file not found: $OUTPUT"
    exit 1
  fi

  echo "🔍 Verifying checksums in $OUTPUT"
  sha256sum -c "$OUTPUT"
  echo "✅ Verification successful"
  exit 0
fi

# -----------------------
# Build find expression
# -----------------------
FIND_EXPR=()

for dir in "${EXCLUDES[@]}"; do
  FIND_EXPR+=( -type d -name "$dir" -prune -o )
done

FIND_EXPR+=( -type f -print )

# -----------------------
# Generate checksums
# -----------------------
find . "${FIND_EXPR[@]}" \
| sort \
| xargs sha256sum > "$OUTPUT"

echo "✅ SHA-256 checksums written to $OUTPUT"

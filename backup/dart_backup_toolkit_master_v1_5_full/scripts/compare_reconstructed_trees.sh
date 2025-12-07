\
#!/usr/bin/env bash
# compare_reconstructed_trees.sh
# Compare two reconstructed trees using a diff tool.
set -euo pipefail

TOOL="diff"

usage() {
  cat <<EOF
compare_reconstructed_trees.sh TREE_A TREE_B [--tool meld|code|vimdiff|diff]

Examples:
  compare_reconstructed_trees.sh latest_tree/ full_history_tree/ --tool meld
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

A="$1"; B="$2"; shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      shift
      TOOL="${1:-diff}"
      shift
      ;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

if [[ ! -d "$A" || ! -d "$B" ]]; then
  echo "Both TREE_A and TREE_B must be directories." >&2
  exit 1
fi

case "$TOOL" in
  meld)
    exec meld "$A" "$B"
    ;;
  code)
    exec code --diff "$A" "$B"
    ;;
  vimdiff)
    exec vimdiff <(cd "$A" && find . | sort) <(cd "$B" && find . | sort)
    ;;
  diff|*)
    diff -qr "$A" "$B"
    ;;
esac

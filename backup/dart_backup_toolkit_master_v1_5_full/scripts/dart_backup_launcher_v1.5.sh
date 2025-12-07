\
#!/usr/bin/env bash
# dart_backup_launcher_v1.5.sh
# Minimal launcher stub for Dart Backup Toolkit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Dart Backup Toolkit Launcher v1.5"
echo
echo "This minimal stub is provided as an integration point."
echo "Run the core tools directly, for example:"
echo
echo "  ${SCRIPT_DIR}/find_latest_flutter_source_v1.9.2.sh --help"
echo "  ${SCRIPT_DIR}/reconstruct_latest_tree_v1.1.1.sh --help"
echo "  ${SCRIPT_DIR}/compare_reconstructed_trees.sh TREE_A TREE_B --tool meld"
echo
echo "You can later replace this stub with the full interactive TUI launcher script."

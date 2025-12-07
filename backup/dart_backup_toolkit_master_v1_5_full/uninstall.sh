\
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/dart_backup_toolkit"
BIN_DIR="${HOME}/.local/bin"
LAUNCHER_PATH="${BIN_DIR}/dart_backup_launcher"

echo "This will remove:"
echo "  $INSTALL_DIR"
echo "  $LAUNCHER_PATH"
read -rp "Proceed? [y/N] " ans
case "$ans" in
  y|Y)
    rm -rf "$INSTALL_DIR"
    rm -f "$LAUNCHER_PATH"
    echo "Uninstalled."
    ;;
  *)
    echo "Cancelled."
    ;;
esac

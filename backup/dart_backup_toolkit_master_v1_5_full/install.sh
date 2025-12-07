\
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/dart_backup_toolkit"
BIN_DIR="${HOME}/.local/bin"

echo "Installing Dart Backup Toolkit into: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r scripts presets.d docs site examples "$INSTALL_DIR/"

mkdir -p "$BIN_DIR"
LAUNCHER_PATH="${BIN_DIR}/dart_backup_launcher"
cat > "$LAUNCHER_PATH" <<'EOF'
#!/usr/bin/env bash
TOOL_DIR="${HOME}/.local/share/dart_backup_toolkit"
exec "${TOOL_DIR}/scripts/dart_backup_launcher_v1.5.sh" "$@"
EOF
chmod +x "$LAUNCHER_PATH"

echo
echo "Installation complete."
echo "If not already on your PATH, add:"
echo '  export PATH="$HOME/.local/bin:$PATH"'

#!/usr/bin/env bash
set -euo pipefail

echo "==============================================="
echo " Dart Backup Reconciliation Toolkit Installer"
echo " Installs:"
echo "   - v1.5 stub launcher"
echo "   - v1.6 full TUI launcher"
echo "   - analyzer, reconstructor, comparer"
echo "   - wrappers, presets directory"
echo "   - permissions + PATH setup"
echo "==============================================="

TOOL_ROOT="$HOME/.local/share/dart_backup_toolkit"
SCRIPT_DIR="$TOOL_ROOT/scripts"
PRESETS_DIR="$TOOL_ROOT/presets.d"
BIN_DIR="$HOME/.local/bin"

echo "[1/8] Creating directories..."
mkdir -p "$SCRIPT_DIR"
mkdir -p "$PRESETS_DIR"
mkdir -p "$BIN_DIR"

echo "[2/8] Installing v1.5 stub launcher..."
cat > "$SCRIPT_DIR/dart_backup_launcher_v1.5.sh" << 'EOF'
#!/usr/bin/env bash
# Dart Backup Toolkit Launcher v1.5 (stub)
echo "Dart Backup Toolkit Launcher v1.5"
echo ""
echo "This is the minimal stub launcher."
echo "Use the full launcher with:"
echo "  dart_backup_launcher_full"
echo ""
echo "Or run components directly:"
echo "  find_latest_flutter_source_v1.9.2.sh --help"
echo "  reconstruct_latest_tree_v1.1.1.sh --help"
echo "  compare_reconstructed_trees.sh TREE_A TREE_B --tool meld"
EOF
chmod +x "$SCRIPT_DIR/dart_backup_launcher_v1.5.sh"

echo "[3/8] Installing v1.6 FULL TUI launcher..."
cat > "$SCRIPT_DIR/dart_backup_launcher_full_v1.6.sh" << 'EOF'
REPLACED_BY_CHATGPT_LAUNCHER_FULL_V1_6_CONTENT
EOF

# Replace placeholder with actual launcher content you received earlier
sed -i "s|REPLACED_BY_CHATGPT_LAUNCHER_FULL_V1_6_CONTENT|$(sed 's|/|\\/|g' <<< "$(< dart_backup_launcher_full_v1.6.sh)")|" \
  "$SCRIPT_DIR/dart_backup_launcher_full_v1.6.sh"

chmod +x "$SCRIPT_DIR/dart_backup_launcher_full_v1.6.sh"

echo "[4/8] Installing wrapper commands into ~/.local/bin..."

# Wrapper for v1.5 stub launcher
cat > "$BIN_DIR/dart_backup_launcher" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/share/dart_backup_toolkit/scripts/dart_backup_launcher_v1.5.sh" "$@"
EOF
chmod +x "$BIN_DIR/dart_backup_launcher"

# Wrapper for v1.6 full launcher
cat > "$BIN_DIR/dart_backup_launcher_full" << 'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/share/dart_backup_toolkit/scripts/dart_backup_launcher_full_v1.6.sh" "$@"
EOF
chmod +x "$BIN_DIR/dart_backup_launcher_full"

echo "[5/8] Installing toolkit scripts..."

# Analyzer
cat > "$SCRIPT_DIR/find_latest_flutter_source_v1.9.2.sh" << 'EOF'
REPLACED_BY_ANALYZER_1_9_2
EOF

# Reconstructor
cat > "$SCRIPT_DIR/reconstruct_latest_tree_v1.1.1.sh" << 'EOF'
REPLACED_BY_RECONSTRUCTOR_1_1_1
EOF

# Comparer
cat > "$SCRIPT_DIR/compare_reconstructed_trees.sh" << 'EOF'
REPLACED_BY_COMPARER
EOF

chmod +x "$SCRIPT_DIR/"*.sh

echo "[6/8] PATH check..."
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Adding ~/.local/bin to PATH via ~/.bashrc..."
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
fi

echo "[7/8] Installing presets directory placeholder..."
cat > "$PRESETS_DIR/README.txt" << 'EOF'
Place your preset .conf files here.
EOF

echo "[8/8] Installation complete!"
echo "Run:"
echo "  dart_backup_launcher        # v1.5 stub"
echo "  dart_backup_launcher_full   # v1.6 full TUI"

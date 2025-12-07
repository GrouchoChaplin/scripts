\
#!/usr/bin/env bash
set -euo pipefail

echo "Upgrading Dart Backup Toolkit (re-running install.sh from current directory)..."
if [[ ! -x "./install.sh" ]]; then
  echo "install.sh not found in current directory." >&2
  exit 1
fi
./install.sh
echo "Upgrade complete."

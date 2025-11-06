#!/usr/bin/env bash
#
# create_script_file.sh
# ---------------------
# Usage:
#   create_script_file.sh [options] <script_name>
#
# Options:
#   --dir <path>     Destination folder (default: ~/projects/scripts)
#   --desc <string>  Description text for the header
#   --no-edit        Do not open file in editor after creation
#
# Example:
#   create_script_file.sh --desc "Backup utility" my_backup
#   create_script_file.sh --dir ~/bin --no-edit sys_info

set -e
set -o pipefail

# --- Defaults ---
DEFAULT_DIR="$HOME/projects/scripts"
OPEN_IN_EDITOR=true
DESCRIPTION=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ -z "$2" ]]; then
        echo "❌ Error: --dir requires a path argument."
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --desc)
      if [[ -z "$2" ]]; then
        echo "❌ Error: --desc requires a description string."
        exit 1
      fi
      DESCRIPTION="$2"
      shift 2
      ;;
    --no-edit)
      OPEN_IN_EDITOR=false
      shift
      ;;
    -*)
      echo "❌ Unknown option: $1"
      exit 1
      ;;
    *)
      SCRIPT_NAME="$1"
      shift
      ;;
  esac
done

# --- Validate script name ---
if [[ -z "$SCRIPT_NAME" ]]; then
  echo "Usage: $0 [--dir path] [--desc text] [--no-edit] <script_name>"
  exit 1
fi

# --- Determine destination directory ---
DEST_DIR="${TARGET_DIR:-$DEFAULT_DIR}"
mkdir -p "$DEST_DIR"

# --- Construct full path ---
if [[ "$SCRIPT_NAME" != *.sh ]]; then
  SCRIPT_NAME="${SCRIPT_NAME}.sh"
fi
SCRIPT_PATH="$DEST_DIR/$SCRIPT_NAME"

# --- Prevent overwrite ---
if [[ -e "$SCRIPT_PATH" ]]; then
  echo "❌ Error: '$SCRIPT_PATH' already exists."
  exit 1
fi

# --- Generate boilerplate ---
cat << EOF > "$SCRIPT_PATH"
#!/usr/bin/env bash
#
# Description: ${DESCRIPTION}
# Author:      $(whoami)
# Created:     $(date "+%Y-%m-%d %H:%M:%S")
# Usage:       
#

set -e
set -o pipefail

EOF

# --- Make executable ---
chmod +x "$SCRIPT_PATH"

# --- Confirmation ---
echo "✅ Created executable script: $SCRIPT_PATH"

# --- Optionally open in editor ---
if $OPEN_IN_EDITOR; then
  if [[ -n "$EDITOR" ]]; then
    "$EDITOR" "$SCRIPT_PATH"
  else
    echo "💡 Tip: Set \$EDITOR to auto-open new scripts (e.g., export EDITOR=nano)"
  fi
fi

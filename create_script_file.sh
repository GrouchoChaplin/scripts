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

# --- Detect light vs dark terminal theme ---
# If the terminal background is dark, use bright colors.
# If light, use darker toned colors for contrast.
detect_theme() {
  # Default: dark theme
  local bg_color
  if command -v tput &>/dev/null; then
    bg_color=$(tput colors 2>/dev/null || echo 0)
  else
    bg_color=0
  fi

  if [[ "$bg_color" -ge 8 ]]; then
    # Assume dark terminal by default
    DARK_MODE=true
  else
    DARK_MODE=false
  fi
}

# --- Initialize color palette ---
set_colors() {
  if [[ "$DARK_MODE" == true ]]; then
    RED="\033[1;31m"
    GREEN="\033[1;32m"
    YELLOW="\033[1;33m"
    BLUE="\033[1;36m"
  else
    # Softer tones for light backgrounds
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    BLUE="\033[0;34m"
  fi
  RESET="\033[0m"
}

detect_theme
set_colors

# --- Defaults ---
DEFAULT_DIR="$HOME/projects/scripts"
OPEN_IN_EDITOR=true
DESCRIPTION=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ -z "$2" ]]; then
        echo -e "${RED}❌ Error:${RESET} --dir requires a path argument."
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --desc)
      if [[ -z "$2" ]]; then
        echo -e "${RED}❌ Error:${RESET} --desc requires a description string."
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
      echo -e "${RED}❌ Unknown option:${RESET} $1"
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
  echo -e "${YELLOW}Usage:${RESET} $0 [--dir path] [--desc text] [--no-edit] <script_name>"
  exit 1
fi

# --- Destination setup ---
DEST_DIR="${TARGET_DIR:-$DEFAULT_DIR}"
mkdir -p "$DEST_DIR"

# --- Script path ---
[[ "$SCRIPT_NAME" != *.sh ]] && SCRIPT_NAME="${SCRIPT_NAME}.sh"
SCRIPT_PATH="$DEST_DIR/$SCRIPT_NAME"

if [[ -e "$SCRIPT_PATH" ]]; then
  echo -e "${RED}❌ Error:${RESET} '$SCRIPT_PATH' already exists."
  exit 1
fi

# --- File boilerplate ---
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

chmod +x "$SCRIPT_PATH"

echo -e "${GREEN}✅ Created executable script:${RESET} $SCRIPT_PATH"

if $OPEN_IN_EDITOR; then
  if [[ -n "$EDITOR" ]]; then
    echo -e "${BLUE}📝 Opening in editor:${RESET} $EDITOR"
    "$EDITOR" "$SCRIPT_PATH"
  else
    echo -e "${YELLOW}💡 Tip:${RESET} Set \$EDITOR to auto-open new scripts (e.g., export EDITOR=nano)"
  fi
fi

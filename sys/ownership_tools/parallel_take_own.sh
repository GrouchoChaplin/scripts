#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# parallel_take_own.sh
#
# Safely change ownership (to the current user) and harden permissions
# (remove "other" access) for all files/folders inside a specified directory.
#
# Uses GNU Parallel for speed and runs everything inside one sudo session,
# prompting for your password only once.
#
# Usage:
#   ./parallel_take_own.sh <top_folder> [--parallel <N>] [--verbose]
#
# Example:
#   ./parallel_take_own.sh /run/media/peddycoartte/MasterBackup/Projects --parallel 16 --verbose
#
# Requirements:
#   • GNU parallel installed
#   • sudo privileges
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Color setup ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- Defaults ---
PARALLEL_JOBS="$(nproc)"
VERBOSE=false
TARGET_DIR=""
LOG_FILE="/tmp/parallel_take_own_$(date +'%Y-%m-%d_%H-%M-%S').log"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel) PARALLEL_JOBS="$2"; shift ;;
        --verbose|-v) VERBOSE=true ;;
        --help|-h)
            grep '^#' "$0" | sed -E 's/^# ?//' | head -n 30
            exit 0 ;;
        *)
            if [[ -z "$TARGET_DIR" ]]; then
                TARGET_DIR="$1"
            else
                echo -e "${RED}❌ Unknown argument:${RESET} $1"
                exit 1
            fi ;;
    esac
    shift
done

# --- Validation ---
if [[ -z "$TARGET_DIR" ]]; then
    echo -e "${RED}❌ Error:${RESET} No target directory specified."
    exit 1
fi
if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}❌ Error:${RESET} Target is not a directory: $TARGET_DIR"
    exit 1
fi

# --- Check for GNU parallel ---
if ! command -v parallel &>/dev/null; then
    echo -e "${RED}❌ GNU parallel not found.${RESET}"
    echo "Install it via: sudo dnf install parallel"
    exit 1
fi

# --- Gather current user/group before sudo ---
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"

# --- Warm up sudo (single prompt) ---
if ! sudo -v 2>/dev/null; then
    echo -e "${YELLOW}🔐 Sudo password required...${RESET}"
    sudo -v || { echo -e "${RED}❌ Unable to gain sudo privileges.${RESET}"; exit 1; }
fi

# --- Silence GNU Parallel citation notice ---
parallel --citation >/dev/null 2>&1 || true

# --- Banner ---
echo
echo "------------------------------------------------------------"
echo " PARALLEL OWNERSHIP + PERMISSION HARDENING"
echo "------------------------------------------------------------"
echo "Target:   $TARGET_DIR"
echo "User:     $USER_NAME"
echo "Group:    $GROUP_NAME"
echo "Jobs:     $PARALLEL_JOBS"
echo "Log:      $LOG_FILE"
[[ "$VERBOSE" == "true" ]] && echo "Verbose:  enabled"
echo "------------------------------------------------------------"
echo

# --- Main logic ---
if [[ "$VERBOSE" == "true" ]]; then
    sudo bash -c "
        parallel -j\"$PARALLEL_JOBS\" chown -vR \"$USER_NAME:$GROUP_NAME\" ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
        parallel -j\"$PARALLEL_JOBS\" chmod -vR o-rwx ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
    "
else
    sudo bash -c "
        parallel -j\"$PARALLEL_JOBS\" chown -vR \"$USER_NAME:$GROUP_NAME\" ::: \"$TARGET_DIR\"/* >> \"$LOG_FILE\" 2>&1
        parallel -j\"$PARALLEL_JOBS\" chmod -vR o-rwx ::: \"$TARGET_DIR\"/* >> \"$LOG_FILE\" 2>&1
    "
fi

echo -e "${GREEN}✅ Completed successfully.${RESET}"
echo "See log: $LOG_FILE"

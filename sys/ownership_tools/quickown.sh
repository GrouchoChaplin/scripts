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
PARALLEL_JOBS=28 # "$(nproc)"
TARGET_DIR="/run/media/peddycoartte/Development/"
LOG_FILE="/tmp/parallel_take_own_$(date +'%Y-%m-%d_%H-%M-%S').log"

# --- Gather current user/group before sudo ---
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"


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

# --- Main logic ---
sudo bash -c "
    parallel -j\"$PARALLEL_JOBS\" chown -vR \"$USER_NAME:$GROUP_NAME\" ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
"

# sudo bash -c "
#     parallel -j\"$PARALLEL_JOBS\" chmod -vR o-rwx ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
# "

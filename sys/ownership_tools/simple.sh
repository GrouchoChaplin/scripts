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



PARALLEL_JOBS=28
TARGET_DIR="/run/media/peddycoartte/MasterBackup/Nightly/"
USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"
LOG_FILE=""
echo
echo "------------------------------------------------------------"
echo " PARALLEL OWNERSHIP + PERMISSION HARDENING"
echo "------------------------------------------------------------"
echo "Target:   $TARGET_DIR"
echo "User:     $USER_NAME"
echo "Group:    $GROUP_NAME"
echo "Jobs:     $PARALLEL_JOBS"
echo "------------------------------------------------------------"
echo


    echo  "
        parallel -j\"$PARALLEL_JOBS\" chown -vR \"$USER_NAME:$GROUP_NAME\" ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
        parallel -j\"$PARALLEL_JOBS\" chmod -vR o-rwx ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
    "


    # sudo bash -c "
    #     parallel -j\"$PARALLEL_JOBS\" chown -vR \"$USER_NAME:$GROUP_NAME\" ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
    #     parallel -j\"$PARALLEL_JOBS\" chmod -vR o-rwx ::: \"$TARGET_DIR\"/* 2>&1 | tee -a \"$LOG_FILE\"
    # "

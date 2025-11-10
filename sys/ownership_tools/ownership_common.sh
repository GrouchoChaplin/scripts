#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ownership_common.sh
# Common helpers for ownership scripts
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Colors ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# --- Logging setup ---
LOG_DIR="${SCRIPT_LOGS:-/tmp}"
mkdir -p "$LOG_DIR"
TODAY="$(date +'%Y-%m-%d')"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/ownership_${TODAY}.log}"

# --- Timestamp helper ---
ts() { date +'%Y-%m-%d %H:%M:%S'; }

# --- Banner ---
banner() {
    echo
    echo "------------------------------------------------------------"
    echo " $1"
    echo "------------------------------------------------------------"
    echo
}

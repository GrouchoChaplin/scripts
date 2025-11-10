# ============================================================================
#!/usr/bin/env bash
#
# Description: 
# Author:      peddycoartte
# Author: Groucho
# Purpose: Provide standardized safety, logging, and error handling for Bash scripts
# Platform: RHEL 8 / compatible
# ============================================================================


set -e
set -o pipefail


# --- Safety Settings --------------------------------------------------------
# Exit on error (-e), undefined variable (-u), or pipeline failure (pipefail)
set -euo pipefail

# --- Variables --------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

LOG_DIR="${LOG_DIR:-$HOME/script_logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME%.*}_$TIMESTAMP.log"

# --- Trap Handling ----------------------------------------------------------
# Print a friendly message if the script exits with error
trap 'on_error $LINENO $?' ERR

on_error() {
  local line=$1
  local code=$2
  echo "❌ ERROR in ${SCRIPT_NAME} at line ${line} (exit code ${code})"
  echo "🔍 Check log: $LOG_FILE"
  exit $code
}

# --- Logging ---------------------------------------------------------------
{
  echo "==============================================================="
  echo "🕒 Script:    $SCRIPT_NAME"
  echo "📂 Directory: $SCRIPT_DIR"
  echo "📅 Started:   $TIMESTAMP"
  echo "==============================================================="
} | tee -a "$LOG_FILE"

# --- Utility Functions ------------------------------------------------------
log()   { echo "[$(date +"%H:%M:%S")] $*" | tee -a "$LOG_FILE"; }
warn()  { echo "⚠️  [$(date +"%H:%M:%S")] WARNING: $*" | tee -a "$LOG_FILE" >&2; }
error() { echo "❌ [$(date +"%H:%M:%S")] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

# --- Example Usage ----------------------------------------------------------
# log "Starting operation..."
# warn "This step may take a while..."
# error "Something went wrong!"
# (your main script logic continues below)

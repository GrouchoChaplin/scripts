#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# update_anaconda.sh  —  Safely update Anaconda/conda on RHEL 8
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
LOG_DIR="$HOME/anaconda_logs"
RUN_FULL_UPDATE=${1:-false}   # pass "true" to also run 'conda update --all'
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/update_anaconda_$TIMESTAMP.log"

echo "🧠 Starting Anaconda update..."
echo "📜 Log file: $LOG_FILE"
echo "----------------------------------------------------"

# --- Check for conda ---
if ! command -v conda >/dev/null 2>&1; then
    echo "❌ conda not found. Please install Anaconda or add it to PATH."
    exit 1
fi

# --- Log system and conda info ---
{
  echo "===== SYSTEM INFO ====="
  uname -a
  echo
  echo "===== CONDA INFO (before update) ====="
  conda info
  echo
  echo "===== CONDA VERSION (before) ====="
  conda --version
  echo
} >> "$LOG_FILE"

# --- Update conda itself ---
echo "🔄 Updating conda..."
conda update -y conda | tee -a "$LOG_FILE"

# --- Update Anaconda metapackage ---
echo "🔄 Updating Anaconda distribution..."
conda update -y anaconda | tee -a "$LOG_FILE"

# --- Optional: Update all packages ---
if [[ "$RUN_FULL_UPDATE" == "true" ]]; then
  echo "⚙️  Performing full package update (--all)..."
  conda update -y --all | tee -a "$LOG_FILE"
else
  echo "⚙️  Skipping full package update (--all)."
fi

# --- Clean cache ---
echo "🧹 Cleaning up conda cache..."
conda clean -y --all | tee -a "$LOG_FILE"

# --- Verify and summarize ---
{
  echo
  echo "===== CONDA INFO (after update) ====="
  conda info
  echo
  echo "===== PACKAGE CHECK ====="
  conda list | head -n 10
} >> "$LOG_FILE"

echo "✅ Anaconda update complete."
echo "📄 Detailed log saved to: $LOG_FILE"

# --- Optional summary to terminal ---
conda --version
python --version
conda list anaconda | head -n 3

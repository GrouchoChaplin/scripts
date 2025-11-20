#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------
# Configuration
# ---------------------------------------------------------
TODAY=$(date +%F)
NOW=$(date +%F-%H%M%S)
START_TS=$(date +%s)

BASE="/run/media/peddycoartte/MasterBackup"
SRC_HOME="/home/peddycoartte/projects"
SRC_DEV="/home/peddycoartte/projects"
DEST_HOME="$BASE/Nightly"
DEST_DEV="$BASE/DevelopmentBackups"
RETENTION_DAYS=30
LOG_DIR="${HOME}/logs"
LOCKFILE="${HOME}/.lock_nightly_backup.lock"

mkdir -p "$DEST_HOME" "$DEST_DEV" "$LOG_DIR"

LOGFILE="${LOG_DIR}/nightly_backup-${NOW}.log"
exec > >(tee -a "$LOGFILE") 2>&1

# ---------------------------------------------------------
# Lock handling (prevents overlap)
# ---------------------------------------------------------
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "[$NOW] Another backup process is already running. Exiting."
    exit 0
fi

# ---------------------------------------------------------
# Start logging
# ---------------------------------------------------------
echo "=========================================================="
echo "[$NOW] Starting nightly backup"
echo "Backup log: $LOGFILE"
echo "Source: $SRC_HOME"
echo "Destination: $DEST_HOME"
echo "----------------------------------------------------------"

# ---------------------------------------------------------
# Home directory backup
# ---------------------------------------------------------
echo "[$NOW] Backing up HOME..."
rsync -aHAXv --delete \
  --link-dest="$DEST_HOME/latest" \
  "$SRC_HOME"/ "$DEST_HOME/$TODAY/"

ln -sfn "$DEST_HOME/$TODAY" "$DEST_HOME/latest"
echo "[$(date +%F-%H%M%S)] HOME backup complete."

# ---------------------------------------------------------
# Development folder backup (uncomment if desired)
# ---------------------------------------------------------
# echo "[$(date +%F-%H%M%S)] Backing up DEVELOPMENT..."
# rsync -aHAXv --delete \
#   --link-dest="$DEST_DEV/latest" \
#   "$SRC_DEV"/ "$DEST_DEV/$TODAY/"
# ln -sfn "$DEST_DEV/$TODAY" "$DEST_DEV/latest"
# echo "[$(date +%F-%H%M%S)] DEVELOPMENT backup complete."

# ---------------------------------------------------------
# Cleanup old backups
# ---------------------------------------------------------
echo "[$(date +%F-%H%M%S)] Cleaning up backups older than $RETENTION_DAYS days..."
find "$DEST_HOME" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS ! -name "latest" -exec rm -rf {} \; -exec echo "Deleted {}" \;
find "$DEST_DEV" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS ! -name "latest" -exec rm -rf {} \; -exec echo "Deleted {}" \;

# ---------------------------------------------------------
# Log rotation (delete old logs)
# ---------------------------------------------------------
find "$LOG_DIR" -type f -name "nightly_backup-*.log" -mtime +$RETENTION_DAYS -exec rm -f {} \;

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
echo "[$(date +%F-%H%M%S)] Backup completed successfully in ${ELAPSED}s"
echo "=========================================================="

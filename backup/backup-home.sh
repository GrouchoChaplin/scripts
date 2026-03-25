

#!/usr/bin/env bash
# Mirror backup of /home with detailed logging

set -euo pipefail

SOURCE="/home/"
DEST="/run/media/peddycoartte/Development/Backups/"
LOG="/var/log/backup-home.log"
MAX_LOG_SIZE_MB=10

# ── Log rotation ─────────────────────────────────────────────────────────────
rotate_log() {
    if [[ -f "$LOG" ]]; then
        local size_mb
        size_mb=$(du -m "$LOG" | cut -f1)
        if (( size_mb >= MAX_LOG_SIZE_MB )); then
            mv "$LOG" "${LOG}.1"
            echo "[$(ts)] Log rotated (was ${size_mb}MB)." > "$LOG"
        fi
    fi
}

# ── Timestamp helper ──────────────────────────────────────────────────────────
ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    local level="$1"
    shift
    echo "[$(ts)] [$level] $*" | tee -a "$LOG"
}

# ── Start ─────────────────────────────────────────────────────────────────────
rotate_log
log INFO  "======================================================"
log INFO  "Backup started"
log INFO  "  Source : $SOURCE"
log INFO  "  Dest   : $DEST"
log INFO  "  User   : $(whoami)  Host: $(hostname)"

START_EPOCH=$(date +%s)

# ── Mount check ───────────────────────────────────────────────────────────────
MOUNT_POINT=$(df --output=target "$DEST" 2>/dev/null | tail -1 || true)
if [[ -z "$MOUNT_POINT" ]] || ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    log WARN "Destination may not be on a separate mount — proceeding anyway"
else
    log INFO "Destination mount point: $MOUNT_POINT"
fi

# ── Run rsync ─────────────────────────────────────────────────────────────────
RSYNC_EXIT=0
rsync -aAXHv --delete \
    --stats \
    --exclude='*/.cache/' \
    --exclude='*/.Trash/' \
    --exclude='*/tmp/' \
    --log-file="$LOG" \
    "$SOURCE" "$DEST" || RSYNC_EXIT=$?

# ── Finish ────────────────────────────────────────────────────────────────────
END_EPOCH=$(date +%s)
DURATION=$(( END_EPOCH - START_EPOCH ))
DURATION_FMT=$(printf '%02dh %02dm %02ds' \
    $(( DURATION/3600 )) $(( (DURATION%3600)/60 )) $(( DURATION%60 )))

if [[ $RSYNC_EXIT -eq 0 ]]; then
    log INFO  "Backup completed successfully in $DURATION_FMT"
elif [[ $RSYNC_EXIT -eq 24 ]]; then
    # Exit 24 = some files vanished during transfer (harmless race condition)
    log WARN  "Backup finished with warnings (exit $RSYNC_EXIT — some files vanished mid-transfer) in $DURATION_FMT"
else
    log ERROR "Backup FAILED (rsync exit code $RSYNC_EXIT) after $DURATION_FMT"
    exit $RSYNC_EXIT
fi



# log INFO  "======================================================"
# ```

# ---

# **What's new vs the original:**

# | Addition | What it does |
# |---|---|
# | `log()` function | Every entry has `[timestamp] [LEVEL]` — easy to `grep ERROR` or `grep WARN` |
# | Duration tracking | Logs elapsed time in `HH MM SS` format |
# | `--stats` flag | rsync appends a transfer summary (files sent, bytes transferred, speed) to the log automatically |
# | Exit code handling | Distinguishes a clean exit, the harmless "files vanished" code 24, and real failures |
# | Log rotation | Rotates to `.log.1` when the log hits 10MB — keeps it from growing unbounded |
# | Mount/source info | Logs hostname, user, source, dest, and mount point at the top of every run |

# ---

# **Sample log output:**
# ```
# [2026-03-20 02:00:01] [INFO] ======================================================
# [2026-03-20 02:00:01] [INFO] Backup started
# [2026-03-20 02:00:01] [INFO]   Source : /home/
# [2026-03-20 02:00:01] [INFO]   Dest   : /mnt/backup/home-mirror/
# [2026-03-20 02:00:01] [INFO]   User   : root  Host: myserver
# [2026-03-20 02:00:01] [INFO] Destination mount point: /mnt/backup
# [2026-03-20 02:03:47] [INFO] Backup completed successfully in 00h 03m 46s
# [2026-03-20 02:03:47] [INFO] ======================================================
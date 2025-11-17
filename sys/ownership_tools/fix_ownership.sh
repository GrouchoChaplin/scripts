#!/usr/bin/env bash
#
# fix_ownership.sh  v1.0
# Parallel, safe ownership repair tool.
# Author: Groucho (peddycoartte)
# Date: 2025-11-17
#

set -euo pipefail

###############
# Defaults
###############
USER_GROUP=""
TARGET_PATH=""
PARALLEL=8
DRYRUN=false
LOGFILE="/tmp/fix_ownership_$(date +%Y%m%d_%H%M%S).log"

###############
# Helpers
###############
usage() {
    cat <<EOF
Usage:
  fix_ownership.sh --path <dir> --user <user> --group <group> [--parallel N] [--dry-run]

Examples:
  fix_ownership.sh --path /run/media/... --user peddycoartte --group peddycoartte --parallel 16
  fix_ownership.sh --path ~/projects --user $(whoami) --group $(whoami)

Options:
  --path <dir>       Directory whose ownership will be fixed
  --user <name>      Username
  --group <name>     Group name
  --parallel <N>     Number of parallel workers (default: 8)
  --dry-run          Print the actions but do not modify anything
EOF
}

fail() { echo "[ERROR] $*" >&2; exit 1; }
log()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOGFILE"; }

###############
# Parse args
###############
while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)    TARGET_PATH="$2"; shift 2 ;;
        --user)    USER_GROUP="$2"; shift 2 ;;
        --group)   USER_GROUP="${USER_GROUP}:$2"; shift 2 ;;
        --parallel) PARALLEL="$2"; shift 2 ;;
        --dry-run) DRYRUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done

[[ -z "$TARGET_PATH" ]]      && fail "--path is required"
[[ -z "$USER_GROUP" ]]       && fail "--user/--group required"
[[ -d "$TARGET_PATH" ]]      || fail "Path does not exist: $TARGET_PATH"
[[ "$PARALLEL" =~ ^[0-9]+$ ]] || fail "--parallel must be an integer"

###############
# Safety checks
###############
case "$TARGET_PATH" in
    "/"|"/root"|"/boot"|"/etc" )
        fail "Refusing to operate on high-risk paths"
        ;;
esac

###############
# FS type check
###############
FSTYPE=$(df -T "$TARGET_PATH" | awk 'NR==2{print $2}')

log "Target path: $TARGET_PATH"
log "Filesystem:  $FSTYPE"
log "User:Group:  $USER_GROUP"
log "Parallel:    $PARALLEL"
log "Dry run:     $DRYRUN"
log "Log file:    $LOGFILE"
log "-----------------------------------------"

if [[ "$FSTYPE" =~ ^(ntfs|exfat|vfat|fat32)$ ]]; then
    log "⚠ WARNING: Filesystem '$FSTYPE' does not support Unix permissions."
    log "  chown will appear to run but will have no persistent effect."
fi

###############
# Execution
###############
start_ts=$(date +%s)

log "Fixing ownership for DIRECTORIES..."
find "$TARGET_PATH" -type d -print0 \
  | parallel -0 -P "$PARALLEL" ${DRYRUN:+echo} chown "$USER_GROUP" "{}" \
  2>&1 | tee -a "$LOGFILE"

log "Fixing ownership for FILES..."
find "$TARGET_PATH" -type f -print0 \
  | parallel -0 -P "$PARALLEL" ${DRYRUN:+echo} chown "$USER_GROUP" "{}" \
  2>&1 | tee -a "$LOGFILE"

end_ts=$(date +%s)
elapsed=$(( end_ts - start_ts ))

log "-----------------------------------------"
log "Completed in ${elapsed}s"
log "Ownership successfully updated (or simulated)."
log "Log saved to $LOGFILE"

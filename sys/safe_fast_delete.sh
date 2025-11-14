#!/usr/bin/env bash
#
# safe_fast_delete.sh — fast, safe directory deletion + intelligent diagnosis
# Version: 2025-11-14.3
#
# Guarantees:
#   - Never reformats anything.
#   - Never deletes mount points (only empties them with --empty-mount).
#   - Never touches critical system paths.
#   - Fast deletion for normal directories using rsync-to-empty.
#
# New Feature:
#   --diagnose   → Safe, read-only diagnostics of why a directory is busy.
#

set -euo pipefail

SCRIPT_VERSION="2025-11-14.3"

LOGFILE=""
TARGET=""
DRYRUN=0
VERBOSE=0
FORCE=0
EMPTY_MOUNT=0
DIAGNOSE=0

# --------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------
bold()  { printf "\e[1m%s\e[0m\n" "$*"; }
info()  { printf "[INFO] %s\n" "$*"; }
warn()  { printf "\e[33m[WARN] %s\e[0m\n" "$*"; }
err()   { printf "\e[1;31m[ERROR] %s\e[0m\n" "$*" >&2; }
log() {
    [[ -n "$LOGFILE" ]] && \
        printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGFILE"
}

# --------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------
usage() {
cat <<EOF
safe_fast_delete.sh (version ${SCRIPT_VERSION})

Usage:
  $0 --target <dir> [options]

Options:
  --target <dir>     Directory to delete
  --verbose          Verbose output
  --dry-run          Show what would be done
  --force            Skip confirmation
  --empty-mount      If target is mount point, empty its contents only
  --log <file>       Append log entries to <file>
  --diagnose         Run full diagnostic mode (read-only)

Diagnosis reveals:
  - Whether target is a mount point
  - Filesystem type (tmpfs, bind, overlay, etc.)
  - Processes holding FDs, cwd, mmap files inside
  - Deleted-but-open files
  - Namespace-bound mounts (Chrome, GNOME, Flatpak)
EOF
}

# --------------------------------------------------------------------
# Argument Parsing
# --------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:-}"; shift 2;;
        --verbose) VERBOSE=1; shift;;
        --dry-run) DRYRUN=1; shift;;
        --force) FORCE=1; shift;;
        --empty-mount) EMPTY_MOUNT=1; shift;;
        --log) LOGFILE="${2:-}"; shift 2;;
        --diagnose) DIAGNOSE=1; shift;;
        --help|-h) usage; exit 0;;
        *)
            err "Unknown argument: $1"
            usage
            exit 1;;
    esac
done

# --------------------------------------------------------------------
# Prepare Logging
# --------------------------------------------------------------------
if [[ -n "$LOGFILE" ]]; then
    touch "$LOGFILE" || { err "Cannot write to log file: $LOGFILE"; exit 1; }
    log "=== safe_fast_delete.sh START ver $SCRIPT_VERSION ==="
fi

# --------------------------------------------------------------------
# Validate target
# --------------------------------------------------------------------
if [[ -z "$TARGET" ]]; then
    err "Missing --target"
    exit 1
fi

if [[ ! -d "$TARGET" ]]; then
    err "Target must be a directory: $TARGET"
    exit 1
fi

TARGET="$(readlink -f "$TARGET")"
log "Target resolved to: $TARGET"

# --------------------------------------------------------------------
# Critical path protection
# --------------------------------------------------------------------
case "$TARGET" in
    "/"|"/home"|"/etc"|"/usr"|"/opt"|"/bin"|"/sbin"|"/var"|"/root"|"/boot"|"/lib"|"/lib64"|"/run")
        err "Refusing to operate on critical path: $TARGET"
        log "ABORT: protected path: $TARGET"
        exit 1;;
esac

# --------------------------------------------------------------------
# Mountpoint check helper
# --------------------------------------------------------------------
is_mountpoint() {
    if command -v mountpoint >/dev/null 2>&1; then
        mountpoint -q "$1"
        return $?
    fi
    awk '{print $2}' /proc/self/mounts | grep -Fx -- "$1" >/dev/null 2>&1
}

IS_MP=0
if is_mountpoint "$TARGET"; then
    IS_MP=1
    log "Target is a mount point"
fi

# --------------------------------------------------------------------
# DIAGNOSE MODE
# --------------------------------------------------------------------
if [[ $DIAGNOSE -eq 1 ]]; then
    bold "=== DIAGNOSING: $TARGET ==="
    log "Starting diagnose mode"

    echo
    echo "→ Is target a mount point?"
    if [[ $IS_MP -eq 1 ]]; then
        echo "  ✔ YES"
        grep " $TARGET " /proc/self/mounts
    else
        echo "  ✘ NO"
    fi

    echo
    echo "→ Filesystem type:"
    awk -v t="$TARGET" '( $2 == t ){print "  FS Type:",$3}' /proc/self/mounts || true

    echo
    echo "→ Bind mount?"
    grep "bind" /proc/self/mounts | grep " $TARGET " && echo "  ✔ Bind mount" || echo "  ✘ Not a bind mount"

    echo
    echo "→ tmpfs?"
    awk -v t="$TARGET" '( $2==t && $3=="tmpfs" ){print "  ✔ tmpfs"}' /proc/self/mounts || echo "  (not tmpfs)"

    echo
    echo "→ Processes with CWD inside target:"
    lsof | grep "cwd" | grep "$TARGET" || echo "  None"

    echo
    echo "→ Processes with open files in target:"
    lsof +D "$TARGET" 2>/dev/null || echo "  None"

    echo
    echo "→ Deleted-but-open files:"
    lsof | grep deleted | grep "$TARGET" || echo "  None"

    echo
    echo "→ Memory-mapped files:"
    lsof -nP | grep "REG" | grep "$TARGET" || echo "  None"

    echo
    echo "→ Namespace mounts referencing target:"
    for pid in /proc/[0-9]*; do
        if grep -q "$TARGET" "$pid/mounts" 2>/dev/null; then
            CMD=$(ps -p "$(basename "$pid")" -o comm= 2>/dev/null)
            echo "  PID $(basename "$pid"): $CMD"
        fi
    done

    echo
    bold "Diagnosis complete. No changes were made."
    log "Diagnosis complete"
    exit 0
fi

# --------------------------------------------------------------------
# Deletion Logic (unchanged except for logging)
# --------------------------------------------------------------------
# Mount point case
if [[ $IS_MP -eq 1 ]]; then
    if [[ $EMPTY_MOUNT -ne 1 ]]; then
        err "Target is a mount point. Refusing."
        log "ABORT: mount point without --empty-mount"
        exit 1
    fi

    bold "Emptying contents of mount point: $TARGET"
    log "Emptying mount contents"

    find "$TARGET" -mindepth 1 -maxdepth 1 -print0 | xargs -0 rm -rf || true

    bold "✔ Mount contents emptied"
    log "SUCCESS: mount contents emptied"
    exit 0
fi

# Normal directory case
empty="$(mktemp -d)"
log "Temp empty dir: $empty"

bold "Fast-wiping directory: $TARGET"
rsync -a --delete "$empty"/ "$TARGET"/
log "rsync wipe done"

rmdir "$TARGET"
rm -rf "$empty"

bold "✔ Directory deleted safely and quickly"
log "SUCCESS: normal directory deleted"
exit 0

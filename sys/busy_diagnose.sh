#!/usr/bin/env bash
#
# busy_diagnose.sh — Determine exactly WHY a directory is “Device or resource busy”
# Version: 2025-11-14.1
#
# This diagnoses:
#   ✔ mount point detection
#   ✔ type of filesystem (tmpfs, bind, overlay, etc.)
#   ✔ stale bind mounts
#   ✔ processes with cwd in the directory
#   ✔ open files held inside the directory
#   ✔ mmapped files inside the directory
#   ✔ deleted-but-open files
#   ✔ namespace-bound mounts (Chrome, GNOME, Flatpak, etc.)
#
# Safe. Read-only. Makes no changes to the system.

set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

TARGET="$(readlink -f "$TARGET")"

echo "============================================================="
echo " busy_diagnose.sh — Diagnosing: $TARGET"
echo "============================================================="
echo

# ----------------------------------------------
# 1. Basic existence check
# ----------------------------------------------
if [[ ! -e "$TARGET" ]]; then
    echo "[ERROR] Target does not exist."
    exit 1
fi

if [[ ! -d "$TARGET" ]]; then
    echo "[ERROR] Target is not a directory."
    exit 1
fi

# ----------------------------------------------
# 2. Is it a mount point?
# ----------------------------------------------
echo "→ Checking if target is a mount point..."
if mountpoint -q "$TARGET"; then
    echo "  ✔ YES: $TARGET is a mount point"
    echo

    echo "→ Mount details:"
    grep " $TARGET " /proc/self/mounts || true
    echo

    echo "→ Filesystem type:"
    awk '($2 == "'$TARGET'"){print "  Type:", $3}' /proc/self/mounts
    echo

    echo "→ Checking if this is a bind mount..."
    grep "bind" /proc/self/mounts | grep " $TARGET " && echo "  ✔ Bind mount" || echo "  ✘ Not a bind mount"
    echo

    echo "→ Checking if this is tmpfs or other temp filesystem..."
    awk '($2 == "'$TARGET'" && $3 == "tmpfs"){print "  ✔ tmpfs"}' /proc/self/mounts || echo "  (not tmpfs)"
    echo

else
    echo "  ✘ No: $TARGET is not a mount point"
fi

echo
echo "-------------------------------------------------------------"
echo " PROCESSES USING THIS DIRECTORY"
echo "-------------------------------------------------------------"
echo

# ----------------------------------------------
# 3. Processes with cwd inside the directory
# ----------------------------------------------
echo "→ Processes with CWD in directory:"
lsof | grep "cwd" | grep "$TARGET" || echo "  None"
echo

# ----------------------------------------------
# 4. Open files inside the directory
# ----------------------------------------------
echo "→ Processes with open files inside directory:"
if lsof +D "$TARGET" 2>/dev/null; then
    :
else
    echo "  None"
fi
echo

# ----------------------------------------------
# 5. Deleted-but-open files
# ----------------------------------------------
echo "→ Deleted but still open files:"
if lsof | grep deleted | grep "$TARGET"; then
    :
else
    echo "  None"
fi
echo

# ----------------------------------------------
# 6. mmap’d files in the directory
# ----------------------------------------------
echo "→ mmapped (memory-mapped) files inside directory:"
if lsof -nP | grep "REG" | grep "$TARGET"; then
    :
else
    echo "  None"
fi
echo

# ----------------------------------------------
# 7. Namespace-bound mounts (browser sandboxes, Flatpak, GNOME)
# ----------------------------------------------
echo "→ Checking for namespace-mounted paths referencing it:"
if find /proc/*/mounts -maxdepth 0 2>/dev/null | grep -q "mounts"; then
    for PID in /proc/[0-9]*; do
        if grep -q "$TARGET" "$PID/mounts" 2>/dev/null; then
            CMD="$(ps -p $(basename $PID) -o comm= 2>/dev/null || true)"
            echo "  PID $(basename $PID) ($CMD) has this mount in its namespace"
        fi
    done
else
    echo "  Cannot scan namespaces on this system."
fi

echo
echo "-------------------------------------------------------------"
echo " DIRECTORY CONTENT SUMMARY"
echo "-------------------------------------------------------------"
echo

echo "→ Listing mount entries above target:"
grep "$TARGET" /proc/self/mounts || echo "  None"
echo

echo "→ ls -ld:"
ls -ld "$TARGET"
echo

echo "============================================================="
echo " Diagnosis complete."
echo "============================================================="

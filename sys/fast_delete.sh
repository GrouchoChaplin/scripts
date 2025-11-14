#!/usr/bin/env bash
#
# fast_delete.sh — fastest safe directory deletion on Linux
# Version: 2025-11-14.1
# Author: Groucho Scripts Toolkit
#
# Uses the bind-mount masking trick, then unmounts cleanly before deletion
# to avoid "Device or resource busy".
#
# Supports:
#   --target <dir>    (required)
#   --verbose
#   --dry-run
#   --force
#   --auto-unmount   (auto-fix stale bind mounts)
#

set -euo pipefail

bold()  { printf "\e[1m%s\e[0m\n" "$*"; }
info()  { printf "[INFO] %s\n" "$*"; }
err()   { printf "\e[1;31m[ERROR] %s\e[0m\n" "$*" >&2; }

TARGET=""
DRYRUN=0
VERBOSE=0
FORCE=0
AUTO=0

usage() {
cat <<EOF
Usage: $0 --target <dir> [--verbose] [--dry-run] [--force] [--auto-unmount]

Options:
  --target <dir>   Directory to delete
  --verbose        Print each action
  --dry-run        Show what would happen, but don't execute
  --force          Skip safety confirmation
  --auto-unmount   Automatically unmount stale bind mounts on target

This uses:
  1. mount --bind empty_dir -> target      # masks large dir instantly
  2. umount target                         # prevents EBUSY
  3. rm -rf target                         # instant delete
EOF
}

# -----------------------------
# Parse arguments
# -----------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2;;
        --verbose) VERBOSE=1; shift;;
        --dry-run) DRYRUN=1; shift;;
        --force) FORCE=1; shift;;
        --auto-unmount) AUTO=1; shift;;
        --help|-h) usage; exit 0;;
        *) err "Unknown option: $1"; usage; exit 1;;
    esac
done

[[ -z "$TARGET" ]] && { err "Missing --target"; exit 1; }

TARGET=$(readlink -f "$TARGET")

# -----------------------------
# Safety checks
# -----------------------------
case "$TARGET" in
    "/"|"/home"|"/root"|"/etc"|"/usr"|"/opt"|"/bin"|"/sbin"|"/var")
        err "Refusing to operate on critical system directory: $TARGET"
        exit 1
        ;;
esac

[[ ! -d "$TARGET" ]] && { err "Target is not a directory: $TARGET"; exit 1; }

if [[ $FORCE -eq 0 ]]; then
    bold "About to delete: $TARGET"
    read -rp "Continue? (yes/no): " ans
    [[ "$ans" == "yes" ]] || { err "Aborted."; exit 1; }
fi

# -----------------------------
# Detect stale mount
# -----------------------------
if mount | grep -q " on ${TARGET} "; then
    if [[ $AUTO -eq 1 ]]; then
        info "Stale mount detected on $TARGET — auto-unmounting..."
        umount "$TARGET" || { err "Failed to unmount stale mount"; exit 1; }
    else
        err "Target is already a mount point. Use --auto-unmount to fix."
        mount | grep " on ${TARGET} "
        exit 1
    fi
fi

# -----------------------------
# Dry run mode
# -----------------------------
if [[ $DRYRUN -eq 1 ]]; then
    bold "*** DRY RUN ***"
    cat <<EOF
Would run:
  empty=\$(mktemp -d)
  mount --make-rprivate /
  mount --bind "\$empty" "$TARGET"
  umount "$TARGET"
  rm -rf "$TARGET"
  rm -rf "\$empty"
EOF
    exit 0
fi

# -----------------------------
# Actual deletion
# -----------------------------
empty=$(mktemp -d)
[[ $VERBOSE -eq 1 ]] && info "Created empty temp dir $empty"

# Private namespace ensures mount ops are isolated
mount --make-rprivate /
[[ $VERBOSE -eq 1 ]] && info "Set mount namespace private"

# Mask directory
mount --bind "$empty" "$TARGET"
[[ $VERBOSE -eq 1 ]] && info "Bind-mounted empty dir to $TARGET"

# Unmount so rm -rf won't hit a busy mount
umount "$TARGET"
[[ $VERBOSE -eq 1 ]] && info "Unmounted $TARGET"

# Directory is now empty — instant delete
rm -rf "$TARGET"
[[ $VERBOSE -eq 1 ]] && info "Deleted $TARGET"

# Cleanup temp
rm -rf "$empty"
[[ $VERBOSE -eq 1 ]] && info "Deleted temp $empty"

bold "✔ Fast delete complete: $TARGET"
exit 0

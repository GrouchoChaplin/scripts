#!/usr/bin/env bash
#
# fix_ownership.sh  v3.0
# Parallel ownership repair with ordered include/exclude filters,
# Timeshift exclusion preset, and fzf TUI preview.
#
# Semantics:
#   1. Collect ALL paths under --path
#   2. Apply filters in the order specified on the command line:
#      - include: keep only items whose basename matches pattern
#      - exclude: drop items whose basename matches pattern
#      - exclude-dir: drop items whose path contains that directory
#   3. Run chown (or echo in --dry-run) in parallel with a progress bar.
#

set -euo pipefail

#########################
# Defaults
#########################
USER_GROUP=""
TARGET_PATH=""
PARALLEL=8
DRYRUN=false
TUI=false
LOGFILE="/tmp/fix_ownership_$(date +%Y%m%d_%H%M%S).log"

# Filter pipeline: types and patterns in CLI order
FILTER_TYPES=()
FILTER_PATS=()

#########################
usage() {
    cat <<EOF
Usage:
  fix_ownership.sh --path <dir> --user <u> --group <g>
                   [--parallel N]
                   [--dry-run]
                   [--tui]
                   [--include PAT]...
                   [--exclude PAT]...
                   [--exclude-dir NAME]...
                   [--exclude-timeshift]

Examples:
  # Basic:
  fix_ownership.sh --path /run/media/USER/OldMasterBackup \\
                   --user USER --group USER --parallel 16

  # Exclude build + node_modules everywhere:
  fix_ownership.sh --path ~/projects --user USER --group USER \\
                   --exclude-dir build --exclude-dir node_modules

  # Timeshift-aware:
  fix_ownership.sh --path /run/media/USER/OldMasterBackup \\
                   --user USER --group USER \\
                   --exclude-timeshift --parallel 16

Options:
  --path <dir>          Target directory
  --user <name>         Username
  --group <name>        Group
  --parallel <N>        Parallel workers (default: 8)
  --dry-run             Show what would be done; do not modify
  --tui                 fzf preview of filtered paths (implies --dry-run)
  --include PAT         Keep only items whose basename matches PAT (can repeat)
  --exclude PAT         Drop items whose basename matches PAT (can repeat)
  --exclude-dir NAME    Drop items whose path contains /NAME/ or ends with /NAME (can repeat)
  --exclude-timeshift   Convenience preset: excludes Timeshift-related dirs
EOF
}

fail() { echo "[ERROR] $*" >&2; exit 1; }
log()  { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOGFILE"; }

#########################
# Arg parsing
#########################
while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)
            TARGET_PATH="$2"; shift 2 ;;
        --user)
            USER_GROUP="$2"; shift 2 ;;
        --group)
            USER_GROUP="${USER_GROUP}:$2"; shift 2 ;;
        --parallel)
            PARALLEL="$2"; shift 2 ;;
        --dry-run)
            DRYRUN=true; shift ;;
        --tui)
            TUI=true; DRYRUN=true; shift ;;
        --include)
            FILTER_TYPES+=("include")
            FILTER_PATS+=("$2")
            shift 2 ;;
        --exclude)
            FILTER_TYPES+=("exclude")
            FILTER_PATS+=("$2")
            shift 2 ;;
        --exclude-dir)
            FILTER_TYPES+=("exclude_dir")
            FILTER_PATS+=("$2")
            shift 2 ;;
        --exclude-timeshift)
            # Preset: Timeshift common dirs
            FILTER_TYPES+=("exclude_dir" "exclude_dir" "exclude_dir")
            FILTER_PATS+=("timeshift" "timeshift-btrfs" ".snapshots")
            shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            fail "Unknown option: $1" ;;
    esac
done

#########################
# Basic validation
#########################
[[ -z "${TARGET_PATH:-}" ]] && fail "--path is required"
[[ -z "${USER_GROUP:-}"  ]] && fail "--user/--group required"
[[ -d "$TARGET_PATH"    ]] || fail "Path does not exist: $TARGET_PATH"
[[ "$PARALLEL" =~ ^[0-9]+$ ]] || fail "--parallel must be an integer"

case "$TARGET_PATH" in
    "/"|"/root"|"/boot"|"/etc")
        fail "Refusing to operate on high-risk system paths."
        ;;
esac

if ! command -v parallel >/dev/null 2>&1; then
    fail "GNU parallel is required but not found. Install with: sudo dnf install parallel"
fi

if $TUI && ! command -v fzf >/dev/null 2>&1; then
    fail "--tui requires fzf. Install with: sudo dnf install fzf"
fi

#########################
# Filesystem check
#########################
FSTYPE=$(df -T "$TARGET_PATH" | awk 'NR==2{print $2}')
log "Target path : $TARGET_PATH"
log "Filesystem  : $FSTYPE"
log "User:Group  : $USER_GROUP"
log "Parallel    : $PARALLEL"
log "Dry run     : $DRYRUN"
log "Log file    : $LOGFILE"
log "----------------------------------------"

if [[ "$FSTYPE" =~ ^(ntfs|exfat|vfat|fat32)$ ]]; then
    log "⚠ NOTE: Filesystem '$FSTYPE' does not truly support Unix ownership."
    log "  chown will not persist in the same way as on ext4/btrfs/xfs."
fi

#########################
# Temp files + cleanup
#########################
BASE_LIST=""
FILTERED_LIST=""

cleanup() {
    [[ -n "$BASE_LIST"     && -f "$BASE_LIST"     ]] && rm -f "$BASE_LIST"
    [[ -n "$FILTERED_LIST" && -f "$FILTERED_LIST" ]] && rm -f "$FILTERED_LIST"
}
trap cleanup EXIT

#########################
# Build initial file list
#########################
log "Scanning filesystem under: $TARGET_PATH"

BASE_LIST=$(mktemp)
FILTERED_LIST=$(mktemp)

# All paths (files + dirs), NUL-separated
find "$TARGET_PATH" -mindepth 1 -print0 > "$BASE_LIST"

TOTAL_RAW=$(tr -cd '\0' < "$BASE_LIST" | wc -c)
if [[ "$TOTAL_RAW" -eq 0 ]]; then
    fail "No items found under $TARGET_PATH"
fi
log "Initial items found: $TOTAL_RAW"

# Copy base → filtered initially
cp "$BASE_LIST" "$FILTERED_LIST"

#########################
# Apply filters in order
#########################
if ((${#FILTER_TYPES[@]} > 0)); then
    log "Applying ${#FILTER_TYPES[@]} filter(s) in order..."
fi

for idx in "${!FILTER_TYPES[@]}"; do
    type="${FILTER_TYPES[$idx]}"
    pat="${FILTER_PATS[$idx]}"
    log "  Filter $((idx+1)): $type '$pat'"

    NEXT_LIST=$(mktemp)

    case "$type" in
        include)
            # keep only paths whose basename matches pattern
            while IFS= read -r -d '' path; do
                base=${path##*/}
                if [[ "$base" == $pat ]]; then
                    printf '%s\0' "$path" >> "$NEXT_LIST"
                fi
            done < "$FILTERED_LIST"
            ;;
        exclude)
            # drop paths whose basename matches pattern
            while IFS= read -r -d '' path; do
                base=${path##*/}
                if [[ "$base" == $pat ]]; then
                    continue
                fi
                printf '%s\0' "$path" >> "$NEXT_LIST"
            done < "$FILTERED_LIST"
            ;;
        exclude_dir)
            # drop anything that contains /DIR/ or ends with /DIR
            while IFS= read -r -d '' path; do
                case "$path" in
                    */"$pat"/*|*/"$pat")
                        # skip
                        ;;
                    *)
                        printf '%s\0' "$path" >> "$NEXT_LIST"
                        ;;
                esac
            done < "$FILTERED_LIST"
            ;;
        *)
            fail "Internal error: unknown filter type '$type'"
            ;;
    esac

    rm -f "$FILTERED_LIST"
    FILTERED_LIST="$NEXT_LIST"
done

TOTAL_FILTERED=$(tr -cd '\0' < "$FILTERED_LIST" | wc -c)
log "Items after filtering: $TOTAL_FILTERED"

if [[ "$TOTAL_FILTERED" -eq 0 ]]; then
    fail "No items remain after filters. Nothing to do."
fi

#########################
# TUI preview mode
#########################
if $TUI; then
    log "Launching fzf preview of filtered paths (no changes made)..."
    tr '\0' '\n' < "$FILTERED_LIST" | fzf --multi --preview 'ls -ld -- "{}"'
    log "TUI preview complete. Exiting due to --tui."
    exit 0
fi

#########################
# Run chown in parallel
#########################
log "Starting parallel chown with GNU parallel..."

start_ts=$(date +%s)

# Use parallel's built-in progress bar (--bar)
# DRYRUN: echo chown USER:GROUP PATH instead of executing
if $DRYRUN; then
    tr '\0' '\n' < "$FILTERED_LIST" \
      | parallel --bar -P "$PARALLEL" echo chown "$USER_GROUP" '{}'
else
    tr '\0' '\n' < "$FILTERED_LIST" \
      | parallel --bar -P "$PARALLEL" chown "$USER_GROUP" '{}'#  2>&1 | tee -a "$LOGFILE"
fi

end_ts=$(date +%s)
elapsed=$(( end_ts - start_ts ))

log "----------------------------------------"
if $DRYRUN; then
    log "Dry-run completed for $TOTAL_FILTERED item(s) in ${elapsed}s."
    log "No ownership changes were made."
else
    log "Ownership updated for $TOTAL_FILTERED item(s) in ${elapsed}s."
fi
log "Log saved to: $LOGFILE"

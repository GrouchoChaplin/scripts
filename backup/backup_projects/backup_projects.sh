#!/usr/bin/env bash
#
# backup_projects.sh
#
# Dual-mode backup script for:
#   SRC:        $HOME/projects
#   MIRROR:     $HOME/project_backups/mirror/projects
#   SNAPSHOTS:  $HOME/project_backups/snapshots/<timestamp>/
#
# Modes:
#   --mirror      → keep a single up-to-date mirror
#   --snapshot    → create a timestamped snapshot (Time-Machine style)
#
# Features:
#   - rsync -aHAX with optional --delete, --progress, --dry-run, --verbose
#   - retention (keep newest N snapshots)
#   - disk space threshold check
#   - logging with timestamps
#   - atomic snapshot creation (.incomplete → final)
#   - latest symlink for snapshots
#   - basic doctor/health check mode
#

set -o errexit
set -o pipefail
set -o nounset

#############################
# CONFIGURATION DEFAULTS
#############################

SRC="${HOME}/projects"
BACKUP_ROOT="${HOME}/project_backups"

MIRROR_ROOT="${BACKUP_ROOT}/mirror"
MIRROR_DEST="${MIRROR_ROOT}/projects"

SNAPSHOT_ROOT="${BACKUP_ROOT}/snapshots"
LATEST_LINK="${SNAPSHOT_ROOT}/latest"

LOG_DIR="${BACKUP_ROOT}/logs"

# Exclusion lists (relative to $SRC); can also be overridden via config
EXCLUDE_DIRS=()   # e.g. ("${HOME}/projects/3rdParty" "${HOME}/projects/JSIG")
EXCLUDE_FILE=""   # path to file with one pattern per line

# Retention: keep the newest N snapshots
KEEP_SNAPSHOTS=30

# Disk usage threshold (percent used) above which we abort backups
# e.g. 95 → abort if filesystem is 95% or more full (<=5% free)
MAX_USED_PERCENT=95

# Optional config file to override defaults
CONFIG_FILE="${BACKUP_ROOT}/backup.conf"

#############################
# RUNTIME STATE
#############################
MODE=""          # "mirror" or "snapshot"
DRY_RUN=0
VERBOSE=0
SHOW_PROGRESS=0
NO_DELETE=0
DOCTOR=0

TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

# Colors
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

#############################
# UTILS
#############################

log() {
    # log LEVEL MESSAGE...
    local level="$1"; shift
    local now
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    local line="[$now] [$level] $*"
    echo -e "$line" | tee -a "$LOG_FILE" >/dev/null
}

info()  { log "INFO"  "$@"; }
warn()  { log "WARN"  "$@"; }
error() { log "ERROR" "$@"; }

die() {
    error "$*"
    echo -e "${RED}✖ $*${RESET}"
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [MODE] [options]

MODE (exactly one required):
  --mirror        Run in mirror mode (single up-to-date copy)
  --snapshot      Run in snapshot mode (timestamped, Time-Machine style)
  --doctor        Run health checks only (no rsync)

Options:
  --dry-run       Perform a trial run without making changes
  --verbose       Increase rsync verbosity
  --progress      Show rsync per-file progress
  --no-delete     Do NOT delete files removed from source
  --exclude-dir D Exclude a directory (or pattern) under the source
  --exclude-file F
                   Read exclude patterns (one per line) relative to the source root
  --keep N        Keep only the newest N snapshots (default: ${KEEP_SNAPSHOTS})
  --help          Show this help

Examples:
  # Mirror current projects to project_backups (with delete)
  $0 --mirror

  # Create a new snapshot with progress display
  $0 --snapshot --progress

  # Dry-run snapshot, show what *would* happen
  $0 --snapshot --dry-run --verbose

  # Doctor mode: check paths, structure, snapshots
  $0 --doctor
EOF
}

#############################
# ARGUMENT PARSING
#############################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mirror)
                MODE="mirror"
                ;;
            --snapshot)
                MODE="snapshot"
                ;;
            --doctor)
                MODE="doctor"
                DOCTOR=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --verbose)
                VERBOSE=1
                ;;
            --progress)
                SHOW_PROGRESS=1
                ;;
            --no-delete)
                NO_DELETE=1
                ;;
            --exclude-dir)
                # directory or pattern to exclude (usually under $SRC)
                shift
                [[ $# -eq 0 ]] && die "--exclude-dir requires a value"
                EXCLUDE_DIRS+=("$1")
                ;;
            --exclude-file)
                # file containing one exclude pattern per line (relative to $SRC)
                shift
                [[ $# -eq 0 ]] && die "--exclude-file requires a value"
                EXCLUDE_FILE="$1"
                ;;
            --keep)
                shift
                [[ $# -eq 0 ]] && die "--keep requires a value"
                KEEP_SNAPSHOTS="$1"
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done

    if [[ -z "${MODE}" ]]; then
        die "You must specify exactly one of: --mirror, --snapshot, or --doctor"
    fi

    if [[ "${MODE}" != "mirror" && "${MODE}" != "snapshot" && "${MODE}" != "doctor" ]]; then
        die "Internal error: invalid MODE=${MODE}"
    fi
}

#############################
# CONFIG FILE LOADING
#############################

load_config_if_present() {
    mkdir -p "${BACKUP_ROOT}" "${LOG_DIR}"
    # create log file early so doctor mode has it
    touch "${LOG_FILE}"

    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Loading config file: ${CONFIG_FILE}"
        # shellcheck source=/dev/null
        . "${CONFIG_FILE}"
    fi
}

#############################
# SAFETY CHECKS
#############################

assert_safe_paths() {
    [[ "${SRC}" == "/" ]] && die "SRC must not be /"
    [[ "${BACKUP_ROOT}" == "/" ]] && die "BACKUP_ROOT must not be /"

    [[ -d "${SRC}" ]] || die "Source directory does not exist: ${SRC}"

    mkdir -p "${BACKUP_ROOT}" "${MIRROR_ROOT}" "${SNAPSHOT_ROOT}" "${LOG_DIR}"

    [[ -w "${BACKUP_ROOT}" ]] || die "Backup root is not writable: ${BACKUP_ROOT}"

    # Basic sanity: don't allow mirror target to be inside source
    case "${MIRROR_ROOT}" in
        "${SRC}"* )
            die "Mirror root (${MIRROR_ROOT}) must not be inside source (${SRC})"
            ;;
    esac
}

check_disk_space() {
    # Skip disk check on doctor-only mode
    if [[ "${MODE}" == "doctor" ]]; then
        return
    fi

    # Use df -P for portable parseable output (POSIX format)
    local df_out used
    df_out="$(df -P "${BACKUP_ROOT}" | awk 'NR==2 {print $5}')"
    used="${df_out%%%}"  # strip trailing %

    if [[ -z "${used}" ]]; then
        warn "Could not determine disk usage; continuing cautiously."
        return
    fi

    info "Disk usage on backup filesystem: ${used}% used"

    if (( used >= MAX_USED_PERCENT )); then
        die "Filesystem is ${used}% used (>= ${MAX_USED_PERCENT}%). Aborting backup to avoid filling disk."
    fi
}

#############################
# DOCTOR MODE
#############################

doctor_mode() {
    echo -e "${CYAN}🔍 Doctor mode: checking backup setup...${RESET}"
    info "Doctor mode started."

    echo "Configuration:"
    echo "  SRC          = ${SRC}"
    echo "  BACKUP_ROOT  = ${BACKUP_ROOT}"
    echo "  MIRROR_DEST  = ${MIRROR_DEST}"
    echo "  SNAPSHOT_ROOT= ${SNAPSHOT_ROOT}"
    echo "  KEEP_SNAPSHOTS = ${KEEP_SNAPSHOTS}"
    echo "  MAX_USED_PERCENT = ${MAX_USED_PERCENT}"
    echo "  CONFIG_FILE  = ${CONFIG_FILE}"
    echo "  LOG_DIR      = ${LOG_DIR}"

    [[ -d "${SRC}" ]] && echo -e "${GREEN}✔ Source directory exists.${RESET}" || echo -e "${RED}✖ Source directory missing: ${SRC}${RESET}"
    [[ -d "${BACKUP_ROOT}" ]] && echo -e "${GREEN}✔ Backup root exists.${RESET}" || echo -e "${YELLOW}⚠ Backup root will be created: ${BACKUP_ROOT}${RESET}"
    [[ -d "${SNAPSHOT_ROOT}" ]] && echo -e "${GREEN}✔ Snapshot root exists.${RESET}" || echo -e "${YELLOW}⚠ Snapshot root not yet created: ${SNAPSHOT_ROOT}${RESET}"

    if [[ -L "${LATEST_LINK}" ]]; then
        local target
        target="$(readlink "${LATEST_LINK}")"
        echo -e "${GREEN}✔ latest symlink exists → ${target}${RESET}"
    else
        echo -e "${YELLOW}⚠ latest symlink does not exist yet.${RESET}"
    fi

    check_disk_space

    info "Doctor mode completed."
    echo -e "${GREEN}Doctor check complete. See log: ${LOG_FILE}${RESET}"
}

#############################
# SNAPSHOT HELPERS
#############################

list_snapshots_sorted() {
    # List snapshot directories sorted lexicographically (oldest first)
    if [[ -d "${SNAPSHOT_ROOT}" ]]; then
        find "${SNAPSHOT_ROOT}" -mindepth 1 -maxdepth 1 -type d \
            ! -name "latest" \
            ! -name ".*" \
            -printf '%f\n' | sort
    fi
}

prune_snapshots() {
    # Skip pruning in dry-run
    if (( DRY_RUN == 1 )); then
        info "Dry-run: skipping snapshot pruning."
        return
    fi

    local snapshots count_to_delete
    mapfile -t snapshots < <(list_snapshots_sorted)

    local total="${#snapshots[@]}"
    if (( total <= KEEP_SNAPSHOTS )); then
        info "No pruning needed: ${total} snapshots <= KEEP_SNAPSHOTS (${KEEP_SNAPSHOTS})"
        return
    fi

    count_to_delete=$(( total - KEEP_SNAPSHOTS ))
    info "Pruning ${count_to_delete} old snapshot(s); keeping newest ${KEEP_SNAPSHOTS} of ${total}."

    local i
    for (( i = 0; i < count_to_delete; i++ )); do
        local snap="${snapshots[$i]}"
        local full="${SNAPSHOT_ROOT}/${snap}"
        info "Deleting old snapshot: ${full}"
        rm -rf --one-file-system -- "${full}"
    done
}

#############################
# RSYNC INVOCATION
#############################

build_rsync_opts() {
    local opts="-aHAX"

    if (( VERBOSE == 1 )); then
        opts="${opts} -v"
    fi
    if (( DRY_RUN == 1 )); then
        opts="${opts} --dry-run"
    fi
    if (( SHOW_PROGRESS == 1 )); then
        opts="${opts} --progress"
    fi
    if (( NO_DELETE == 0 )); then
        opts="${opts} --delete"
    else
        warn "--no-delete: destination may accumulate files that no longer exist in source."
    fi

    echo "${opts}"
}

# Build --exclude arguments for rsync from EXCLUDE_DIRS/EXCLUDE_FILE.
# Directories may be absolute (e.g. "$HOME/projects/JSIG") or relative
# to $SRC (e.g. "JSIG" or "old/JSIG").
build_rsync_excludes() {
    local args=()

    # Normalize source path
    local src_abs
    src_abs="$(realpath -m "${SRC}")"

    # From explicit --exclude-dir arguments
    for d in "${EXCLUDE_DIRS[@]}"; do
        [[ -z "${d}" ]] && continue

        # Expand leading ~ if present
        local raw="${d/#\~/$HOME}"
        local abs
        abs="$(realpath -m "${raw}")" || abs="${raw}"

        local rel=""
        if [[ "${abs}" == "${src_abs}"* ]]; then
            # Strip the $SRC prefix so rsync sees a path relative to the root
            rel="${abs#${src_abs}/}"
        else
            # Not under $SRC; fall back to basename/pattern
            rel="${raw}"
        fi

        args+=( "--exclude=${rel}" )
    done

    # From --exclude-file (one pattern per line, "#" comments allowed)
    if [[ -n "${EXCLUDE_FILE}" ]]; then
        if [[ ! -f "${EXCLUDE_FILE}" ]]; then
            die "--exclude-file specified but file not found: ${EXCLUDE_FILE}"
        fi
        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "${line}" ]] && continue
            [[ "${line}" =~ ^[[:space:]]*# ]] && continue
            args+=( "--exclude=${line}" )
        done < "${EXCLUDE_FILE}"
    fi

    echo "${args[*]}"
}

run_rsync_mirror() {
    local rsync_opts
    local exclude_opts
    rsync_opts="$(build_rsync_opts)"
    exclude_opts="$(build_rsync_excludes)"

    info "Starting MIRROR mode backup."
    info "Source:      ${SRC}"
    info "Mirror dest: ${MIRROR_DEST}"
    info "Rsync opts:  ${rsync_opts}"
    [[ -n "${exclude_opts}" ]] && info "Rsync excl:  ${exclude_opts}"

    mkdir -p "${MIRROR_ROOT}"

    echo -e "${CYAN}▶️  MIRROR: ${SRC} → ${MIRROR_DEST}${RESET}"
    echo -e "${CYAN}    Options: ${rsync_opts}${RESET}"
    if [[ -n "${exclude_opts}" ]]; then
        echo -e "${CYAN}    Exclude: ${exclude_opts}${RESET}"
    fi
    (( DRY_RUN == 1 )) && echo -e "${YELLOW}    DRY-RUN — no changes will be made.${RESET}"

    # No trailing slash on SRC so the directory itself is mirrored under MIRROR_ROOT
    rsync ${rsync_opts} ${exclude_opts} "${SRC}" "${MIRROR_ROOT}/" | tee -a "${LOG_FILE}"

    local status=$?
    if (( status == 0 )); then
        info "Mirror backup completed successfully."
        echo -e "${GREEN}✔ MIRROR backup completed successfully.${RESET}"
    else
        error "Mirror backup failed with exit code ${status}."
        echo -e "${RED}✖ MIRROR backup failed (exit ${status}).${RESET}"
    fi
    return "${status}"
}

run_rsync_snapshot() {
    local rsync_opts link_dest_arg="" exclude_opts
    rsync_opts="$(build_rsync_opts)"
    exclude_opts="$(build_rsync_excludes)"

    info "Starting SNAPSHOT mode backup."
    info "Source:        ${SRC}"
    info "Snapshot root: ${SNAPSHOT_ROOT}"
    info "Rsync opts:    ${rsync_opts}"
    [[ -n "${exclude_opts}" ]] && info "Rsync excl:    ${exclude_opts}"

    mkdir -p "${SNAPSHOT_ROOT}"

    local snap_name="${TIMESTAMP}"
    local tmp_dir="${SNAPSHOT_ROOT}/.incomplete-${snap_name}"
    local final_dir="${SNAPSHOT_ROOT}/${snap_name}"

    # Determine link-dest (previous latest snapshot)
    if [[ -L "${LATEST_LINK}" ]]; then
        local latest_target
        latest_target="$(readlink "${LATEST_LINK}")"
        if [[ -n "${latest_target}" && -d "${SNAPSHOT_ROOT}/${latest_target}" ]]; then
            link_dest_arg="--link-dest=${SNAPSHOT_ROOT}/${latest_target}"
            info "Using link-dest = ${SNAPSHOT_ROOT}/${latest_target}"
        else
            warn "LATEST symlink invalid or target missing; snapshot will be full copy."
        fi
    fi

    echo -e "${CYAN}▶️  SNAPSHOT: ${SRC} → ${final_dir}${RESET}"
    echo -e "${CYAN}    Options: ${rsync_opts} ${link_dest_arg}${RESET}"
    if [[ -n "${exclude_opts}" ]]; then
        echo -e "${CYAN}    Exclude: ${exclude_opts}${RESET}"
    fi
    (( DRY_RUN == 1 )) && echo -e "${YELLOW}    DRY-RUN — no changes will be made.${RESET}"

    mkdir -p "${tmp_dir}"

    # No trailing slash on SRC so we snapshot the directory itself
    rsync ${rsync_opts} ${exclude_opts} ${link_dest_arg} "${SRC}" "${tmp_dir}/" | tee -a "${LOG_FILE}"

    local status=$?
    if (( status != 0 )); then
        error "Snapshot rsync failed with exit code ${status}."
        echo -e "${RED}✖ SNAPSHOT backup failed (exit ${status}).${RESET}"
        # In non-dry-run, clean up incomplete dir
        if (( DRY_RUN == 0 )); then
            rm -rf --one-file-system -- "${tmp_dir}"
        fi
        return "${status}"
    fi

    # Promote from temporary to final name (atomic-ish)
    if (( DRY_RUN == 0 )); then
        mv "${tmp_dir}" "${final_dir}"
        info "Promoted snapshot to ${final_dir}"

        # Update latest symlink
        ln -sfn "${snap_name}" "${LATEST_LINK}"
        info "Updated latest symlink → ${snap_name}"
    else
        info "Dry-run: not promoting ${tmp_dir} to final snapshot."
    fi

    echo -e "${GREEN}✔ SNAPSHOT backup completed successfully.${RESET}"
    return 0
}

#############################
# MAIN
#############################

main() {
    parse_args "$@"
    load_config_if_present
    assert_safe_paths

    # Doctor mode doesn't actually run rsync
    if (( DOCTOR == 1 )); then
        doctor_mode
        exit 0
    fi

    check_disk_space

    info "Backup run starting: MODE=${MODE}, DRY_RUN=${DRY_RUN}, KEEP_SNAPSHOTS=${KEEP_SNAPSHOTS}"

    local status=0

    case "${MODE}" in
        mirror)
            run_rsync_mirror || status=$?
            ;;
        snapshot)
            run_rsync_snapshot || status=$?
            if (( status == 0 )); then
                prune_snapshots
            fi
            ;;
        *)
            die "Unexpected MODE: ${MODE}"
            ;;
    esac

    if (( status == 0 )); then
        info "Backup run completed successfully."
    else
        error "Backup run completed with errors (exit ${status})."
    fi

    echo
    echo -e "${CYAN}📄 Log file: ${LOG_FILE}${RESET}"
    exit "${status}"
}

main "$@"

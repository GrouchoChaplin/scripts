#!/usr/bin/env bash
#
# compare_repo_variants_V5.6_Patch4.sh
# Main driver for repo comparison + forensic analysis

set -euo pipefail

###############################################
# Resolve script directory
###############################################
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

###############################################
# Source modules
###############################################
source "$LIB_DIR/common.sh"
source "$LIB_DIR/repo_scan.sh"
source "$LIB_DIR/mode_standard.sh"
source "$LIB_DIR/mode_forensic.sh"

###############################################
# Default values
###############################################
ROOT_FOLDER=""
REPO_NAME=""
MODE="standard"   # default run-mode

###############################################
# Usage Banner
###############################################
usage() {
    cat <<EOF

compare_repo_variants_V5.6_Patch4.sh
────────────────────────────────────
Compare multiple backups of a Git repo and determine:
  • latest commit per backup
  • most recent modified file per backup
  • untracked / unstaged / staged changes
  • which backup is likely the "last active" snapshot
  • HTML forensic report with sortable table

Usage:
  $0 --root-folder <path> --repo-name <prefix> [--mode standard|forensic]

Examples:
  Standard comparison:
    $0 --root-folder /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs \
       --repo-name jsigconversiontools \
       --mode standard

  Forensic investigation:
    $0 --root-folder /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs \
       --repo-name jsigconversiontools \
       --mode forensic

EOF
}

###############################################
# Option Parser
###############################################
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root-folder)
            ROOT_FOLDER="$2"; shift 2 ;;
        --repo-name)
            REPO_NAME="$2"; shift 2 ;;
        --mode)
            MODE="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            error "Unknown argument: $1"
            usage
            exit 1 ;;
    esac
done

###############################################
# Validate args
###############################################
if [[ -z "$ROOT_FOLDER" ]]; then
    error "--root-folder is required"
    exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
    error "--repo-name is required"
    exit 1
fi

if [[ ! -d "$ROOT_FOLDER" ]]; then
    error "Root folder does not exist: $ROOT_FOLDER"
    exit 1
fi

case "$MODE" in
    standard|forensic)
        ;;
    *)
        error "Invalid mode: $MODE   (must be: standard or forensic)"
        exit 1 ;;
esac

###############################################
# Dispatch to mode
###############################################
case "$MODE" in
    standard)
        info "Running STANDARD comparison mode…"
        run_mode_standard "$ROOT_FOLDER" "$REPO_NAME"
        ;;
    forensic)
        info "Running FORENSIC mode…"
        run_mode_forensic "$ROOT_FOLDER" "$REPO_NAME"
        ;;
esac

#!/usr/bin/env bash
set -euo pipefail

##############################################
# parallel_chown_safe.sh
# Safe, resume-friendly, dry-run parallel chown tool
##############################################

TARGET_USER="peddycoartte"
TARGET_GROUP="peddycoartte"
LOGFILE="parallel_chown.log"

JOBS="$(nproc)"  # auto-detect cores
DRY_RUN=0
NO_REDIRECT=0
VERBOSE=0
DEBUG=0

color() { printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
ok()    { color "32" "[OK] $1"; }
info()  { color "36" "[INFO] $1"; }
warn()  { color "33" "[WARN] $1"; }
fail()  { color "31" "[FAIL] $1"; }
ts()    { date +"%Y-%m-%d %H:%M:%S"; }

begin_section() {
  echo "===== BEGIN: $1 @ $(ts) =====" | tee -a "$LOGFILE"
}

end_section() {
  echo "===== END: $1 @ $(ts) =====" | tee -a "$LOGFILE"
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] DIRECTORY

Options:
  --dry-run         Show what would be changed, but don't change anything
  --jobs N          Use N parallel jobs (default: all cores)
  --no-redirect     Do not redirect stdout/stderr to log
  --verbose         Print all activity
  --debug           Extra debugging output
  --help            Show this help

Example:
  $0 --jobs 28 /run/media/peddycoartte/MasterBackup/Nightly
EOF
}

##############################################
# Parse args
##############################################
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --jobs)    JOBS="$2"; shift ;;
    --no-redirect) NO_REDIRECT=1 ;;
    --verbose) VERBOSE=1 ;;
    --debug)   DEBUG=1; VERBOSE=1 ;;
    --help)    usage; exit 0 ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

if [[ ${#ARGS[@]} -ne 1 ]]; then
  usage
  exit 1
fi

TARGET_DIR="${ARGS[0]}"

##############################################
# Redirect output unless disabled
##############################################
cleanup_redirect() {
  exec 1>&3 2>&4
  exec 3>&- 4>&-
}
if [[ "$NO_REDIRECT" -eq 0 ]]; then
  exec 3>&1 4>&2
  exec 1>"$LOGFILE" 2>&1
  trap cleanup_redirect EXIT
  ok "Logging redirected to $LOGFILE (use --no-redirect to disable)"
fi

##############################################
# Validate input
##############################################
begin_section "VALIDATION"

if [[ ! -d "$TARGET_DIR" ]]; then
  fail "Directory does not exist: $TARGET_DIR"
  exit 1
fi

ok "Target directory: $TARGET_DIR"
ok "Parallel jobs: $JOBS"
[[ $DRY_RUN -eq 1 ]] && warn "Dry-run mode enabled — NO CHANGES will be made"

end_section "VALIDATION"

##############################################
# Generate file list
##############################################
begin_section "FILE SCAN"

info "Scanning target directory..."
FILELIST=$(mktemp)

find "$TARGET_DIR" -mindepth 1 > "$FILELIST"

COUNT=$(wc -l < "$FILELIST")

ok "Found $COUNT items"

end_section "FILE SCAN"


##############################################
# Define the worker command
##############################################
run_chown() {
  local f="$1"

  # Skip if already correct owner
  current="$(stat -c '%U:%G' "$f")"
  if [[ "$current" == "$TARGET_USER:$TARGET_GROUP" ]]; then
    [[ $DEBUG -eq 1 ]] && info "SKIP $f"
    return
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: chown $TARGET_USER:$TARGET_GROUP \"$f\""
    return
  fi

  chown "$TARGET_USER:$TARGET_GROUP" "$f"
  [[ $VERBOSE -eq 1 ]] && ok "CHOWN: $f"
}

export -f run_chown
export TARGET_USER TARGET_GROUP DRY_RUN VERBOSE DEBUG

##############################################
# Execute in parallel
##############################################
begin_section "PARALLEL CHOWN"

info "Starting parallel ownership fix..."

parallel \
  --jobs "$JOBS" \
  --halt now,fail=1 \
  run_chown :::: "$FILELIST"

ok "Parallel ownership update completed"

end_section "PARALLEL CHOWN"

##############################################
# Summary
##############################################
begin_section "SUMMARY"
echo "Run complete @ $(ts)"
[[ $DRY_RUN -eq 1 ]] && echo "Mode: DRY-RUN (no changes made)"
echo "Items processed: $COUNT"
end_section "SUMMARY"

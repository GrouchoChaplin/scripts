#!/usr/bin/env bash
#
# setup_rpmbuild_env.sh
#
# One-time RPM build environment setup for Rocky/RHEL.
#
# Features:
#   - Creates TOPDIR/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
#   - Ensures ~/.rpmmacros sets %_topdir to TOPDIR
#   - Optional: install build dependencies via --install-deps
#   - Optional: custom TOPDIR via --topdir PATH
#
# Safe to run multiple times.
#
# Examples:
#   setup_rpmbuild_env.sh
#   setup_rpmbuild_env.sh --install-deps
#   setup_rpmbuild_env.sh --topdir ~/projects/rpmbuild --install-deps
#

set -euo pipefail

###############################################################################
# Defaults / Config
###############################################################################

TOPDIR_DEFAULT="${HOME}/rpmbuild"
TOPDIR="${TOPDIR_DEFAULT}"
RPMMACROS="${HOME}/.rpmmacros"
INSTALL_DEPS=0

###############################################################################
# Colors / logging
###############################################################################

if [[ -t 1 ]]; then
  C_GREEN="\033[1;32m"
  C_YELLOW="\033[1;33m"
  C_RED="\033[1;31m"
  C_BLUE="\033[1;34m"
  C_RESET="\033[0m"
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_RESET=""
fi

log()    { printf "%b[%s]%b %s\n" "${C_BLUE}"  "rpm-setup" "${C_RESET}" "$*"; }
ok()     { printf "%b[%s]%b %s\n" "${C_GREEN}" "OK"        "${C_RESET}" "$*"; }
warn()   { printf "%b[%s]%b %s\n" "${C_YELLOW}" "WARN"     "${C_RESET}" "$*"; }
err()    { printf "%b[%s]%b %s\n" "${C_RED}"   "ERROR"     "${C_RESET}" "$*"; }

###############################################################################
# Usage
###############################################################################

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Set up a non-root RPM build environment for Rocky/RHEL.

Options:
  --topdir PATH       Set custom RPM topdir (default: ${TOPDIR_DEFAULT})
                      Example: --topdir ~/projects/rpmbuild
  --install-deps      Install RPM build dependencies via dnf:
                        rpm-build gcc make ncurses-devel curl
  -h, --help          Show this help and exit

Behavior:
  - Ensures TOPDIR has BUILD, RPMS, SOURCES, SPECS, SRPMS subdirs
  - Ensures ~/.rpmmacros defines %_topdir appropriately:
      * If TOPDIR == ${TOPDIR_DEFAULT}:
            %_topdir %(echo \$HOME)/rpmbuild
        (home-relative for portability)
      * Else:
            %_topdir /full/path/to/custom/topdir
        (absolute path)
  - If ~/.rpmmacros exists and already has %_topdir, it will NOT be modified
    (only reported).
EOF
}

###############################################################################
# Argument parsing
###############################################################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --topdir)
      if [[ $# -lt 2 ]]; then
        err "--topdir requires a PATH argument"
        exit 1
      fi
      TOPDIR="$2"
      shift 2
      ;;
    --install-deps)
      INSTALL_DEPS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      echo
      usage
      exit 1
      ;;
  esac
done

# Expand leading ~ in TOPDIR (e.g. ~/projects/rpmbuild)
case "${TOPDIR}" in
  "~"|"~/"*)
    TOPDIR="${TOPDIR/#\~/$HOME}"
    ;;
esac

###############################################################################
# Functions
###############################################################################

install_deps() {
  if [[ "${INSTALL_DEPS}" -ne 1 ]]; then
    return
  fi

  log "Installing RPM build dependencies via dnf (requires sudo)..."
  # You can add/edit packages here if you need more later.
  sudo dnf install -y rpm-build gcc make ncurses-devel curl
  ok "Build dependencies installed (or already present)."
}

ensure_topdir_tree() {
  log "Ensuring RPM build tree under: ${TOPDIR}"

  mkdir -p "${TOPDIR}/BUILD" \
           "${TOPDIR}/RPMS" \
           "${TOPDIR}/SOURCES" \
           "${TOPDIR}/SPECS" \
           "${TOPDIR}/SRPMS"

  ok "Created/verified directory tree:
  ${TOPDIR}/BUILD
  ${TOPDIR}/RPMS
  ${TOPDIR}/SOURCES
  ${TOPDIR}/SPECS
  ${TOPDIR}/SRPMS"
}

ensure_rpmmacros() {
  local desired_line

  # If using the standard ~/rpmbuild, keep home-relative form.
  if [[ "${TOPDIR}" == "${TOPDIR_DEFAULT}" ]]; then
    desired_line='%_topdir %(echo $HOME)/rpmbuild'
  else
    desired_line="%_topdir ${TOPDIR}"
  fi

  log "Configuring ${RPMMACROS} for TOPDIR=${TOPDIR}"

  if [[ ! -f "${RPMMACROS}" ]]; then
    log "No existing ${RPMMACROS}; creating a new one."
    {
      echo "${desired_line}"
    } > "${RPMMACROS}"
    ok "Created ${RPMMACROS} with:"
    echo "    ${desired_line}"
    return
  fi

  # File exists; check if %_topdir is already present
  if grep -q '^%_topdir' "${RPMMACROS}"; then
    local current
    current="$(grep '^%_topdir' "${RPMMACROS}" | head -n1 || true)"
    ok "Existing %_topdir found in ${RPMMACROS}:"
    echo "    ${current}"
    if [[ "${current}" != "${desired_line}" ]]; then
      warn "Current %_topdir differs from desired:"
      echo "    desired: ${desired_line}"
      echo "    current: ${current}"
      warn "Leaving existing setting untouched."
      warn "If you want to switch to TOPDIR=${TOPDIR}, edit ${RPMMACROS}"
      warn "manually or remove the existing %_topdir and re-run this script."
    fi
    return
  fi

  # No %_topdir line: append ours, with backup
  local backup="${RPMMACROS}.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "${RPMMACROS}" "${backup}"
  warn "Existing ${RPMMACROS} had no %_topdir; backed up as:"
  echo "    ${backup}"

  {
    echo
    echo "# Added by $(basename "$0") on $(date)"
    echo "${desired_line}"
  } >> "${RPMMACROS}"

  ok "Appended %_topdir to ${RPMMACROS}:"
  echo "    ${desired_line}"
}

###############################################################################
# Main
###############################################################################

main() {
  log "Starting RPM build environment setup"
  log "Using TOPDIR: ${TOPDIR}"

  install_deps
  ensure_topdir_tree
  ensure_rpmmacros

  ok "RPM build environment is ready."
  echo
  echo "Next steps example:"
  echo "  cd \"${TOPDIR}/SPECS\""
  echo "  rpmbuild -ba your-package.spec"
}

main "$@"

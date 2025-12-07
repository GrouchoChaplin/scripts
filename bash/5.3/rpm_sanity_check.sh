#!/usr/bin/env bash
#
# rpm_sanity_check.sh
#
# Comprehensive sanity check for the RPM build environment.
# Validates:
#   ✓ ~/.rpmmacros exists and contains %_topdir
#   ✓ $TOPDIR exists (from ~/.rpmmacros)
#   ✓ BUILD / RPMS / SOURCES / SPECS / SRPMS subdirs exist
#   ✓ spec file exists (bash53.spec)
#   ✓ source tarball exists (bash-5.3.tar.gz)
#   ✓ dependencies installed (rpm-build, gcc, make, ncurses-devel, curl)
#
# Works on Rocky/RHEL 8 and 9.
#

set -euo pipefail

# ------------------------ Colors ------------------------
if [[ -t 1 ]]; then
  G="\033[1;32m"
  Y="\033[1;33m"
  R="\033[1;31m"
  B="\033[1;34m"
  X="\033[0m"
else
  G=""; Y=""; R=""; B=""; X=""
fi

good()  { printf "%b[GOOD]%b %s\n"   "$G" "$X" "$*"; }
warn()  { printf "%b[WARN]%b %s\n"   "$Y" "$X" "$*"; }
bad()   { printf "%b[FAIL]%b %s\n"   "$R" "$X" "$*"; }
info()  { printf "%b[INFO]%b %s\n"   "$B" "$X" "$*"; }

fail() {
  bad "$1"
  exit 1
}

# ------------------------ Step 1: ~/.rpmmacros ------------------------
info "Checking ~/.rpmmacros..."

RPMMACROS="$HOME/.rpmmacros"

if [[ ! -f "$RPMMACROS" ]]; then
  fail "~/.rpmmacros is missing. Run setup_rpmbuild_env.sh first."
fi

if ! grep -q "%_topdir" "$RPMMACROS"; then
  fail "~/.rpmmacros exists but does NOT define %_topdir."
fi

TOPDIR=$(grep "^%_topdir" "$RPMMACROS" | awk '{print $2}')
TOPDIR="${TOPDIR/#\~/$HOME}"

good "~/.rpmmacros OK (TOPDIR=$TOPDIR)"

# ------------------------ Step 2: Topdir exists ------------------------
info "Checking TOPDIR structure..."

[[ -d "$TOPDIR" ]] || fail "TOPDIR directory '$TOPDIR' does not exist."

for d in BUILD RPMS SOURCES SPECS SRPMS; do
  if [[ ! -d "$TOPDIR/$d" ]]; then
    fail "Missing directory: $TOPDIR/$d"
  fi
done

good "RPM directory tree exists."

# ------------------------ Step 3: Spec file ------------------------
SPECFILE="$TOPDIR/SPECS/bash53.spec"

info "Checking for spec file: $SPECFILE"

if [[ ! -f "$SPECFILE" ]]; then
  fail "Spec file not found. Copy it with:
    cp path/to/bash53.spec $TOPDIR/SPECS/"
fi

good "Spec file exists."

# ------------------------ Step 4: Source tarball ------------------------
SRCFILE="$TOPDIR/SOURCES/bash-5.3.tar.gz"

info "Checking for source tarball: $SRCFILE"

if [[ ! -f "$SRCFILE" ]]; then
  warn "Source tarball missing."
  warn "Downloading it now..."
  (
    cd "$TOPDIR/SOURCES" &&
    curl -LO https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz
  ) || fail "Curl failed to download bash-5.3.tar.gz"
  
  good "Downloaded bash-5.3.tar.gz"
else
  good "Source tarball exists."
fi

# ------------------------ Step 5: Dependencies ------------------------
info "Checking for required build dependencies..."

MISSING=0

check_dep() {
  if ! rpm -q "$1" >/dev/null 2>&1; then
    warn "Missing package: $1"
    MISSING=1
  else
    good "Package installed: $1"
  fi
}

check_dep rpm-build
check_dep gcc
check_dep make
check_dep ncurses-devel
check_dep curl

if [[ $MISSING -eq 1 ]]; then
  warn "Some dependencies are missing."
  warn "Install them with:"
  echo
  echo "    sudo dnf install -y rpm-build gcc make ncurses-devel curl"
  echo
  fail "Environment not fully ready."
fi

good "All required build dependencies installed."

# ------------------------ Step 6: Final summary ------------------------
echo
good "RPM build environment sanity check PASSED."
echo
info "You may now run:"
echo
echo "  rpmbuild -ba $SPECFILE"
echo

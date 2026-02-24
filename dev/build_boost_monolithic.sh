#!/usr/bin/env bash
set -euo pipefail

########################################
# Defaults
########################################

SOURCE=""
TARBALL_URL=""
TARBALL_SHA256=""
PREFIX="$(pwd)/myboost"
JOBS="$(nproc)"
LIBNAME="BoostMono"

########################################
# Helpers
########################################

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  build_boost_monolithic.sh \\
    --source tarball \\
    --tarball-url <url> \\
    --tarball-sha256 <sha256> \\
    [--prefix <dir>] \\
    [--jobs <n>] \\
    [--libname <name>]

Required:
  --source tarball
  --tarball-url
  --tarball-sha256

Optional:
  --prefix   Install prefix (default: ./myboost)
  --jobs     Parallel jobs (default: nproc)
  --libname  Output archive base name (default: BoostMono)
EOF
}

########################################
# Argument parsing
########################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --tarball-url) TARBALL_URL="$2"; shift 2 ;;
    --tarball-sha256) TARBALL_SHA256="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --libname) LIBNAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

########################################
# Validation
########################################

[[ "$SOURCE" == "tarball" ]] || die "--source tarball is required"
[[ -n "$TARBALL_URL" ]] || die "--tarball-url is required"
[[ -n "$TARBALL_SHA256" ]] || die "--tarball-sha256 is required"

########################################
# Setup
########################################

WORKDIR="$(pwd)/_boost_build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Workdir: $WORKDIR"
echo "==> Prefix:  $PREFIX"
echo "==> Jobs:    $JOBS"

########################################
# Download tarball
########################################

echo "==> Downloading Boost tarball"
curl -L --fail -o boost.tar.gz "$TARBALL_URL"

########################################
# Verify SHA-256
########################################

echo "==> Verifying SHA-256"
echo "$TARBALL_SHA256  boost.tar.gz" | sha256sum -c -

########################################
# Extract tarball
########################################

echo "==> Extracting tarball"
tar -xzf boost.tar.gz

BOOST_SRC_DIR="$(tar -tzf boost.tar.gz | head -1 | cut -d/ -f1)"
[[ -d "$BOOST_SRC_DIR" ]] || die "Failed to locate extracted Boost directory"

BOOST_SRC_DIR="$WORKDIR/$BOOST_SRC_DIR"
echo "==> Boost source dir: $BOOST_SRC_DIR"

########################################
# Bootstrap Boost.Build
########################################

cd "$BOOST_SRC_DIR"

echo "==> Bootstrapping Boost.Build"
./bootstrap.sh

########################################
# Stage Boost headers (REQUIRED)
########################################

echo "==> Staging Boost headers"
./b2 headers

########################################
# Build and install static Boost libraries
########################################

echo "==> Building and installing static Boost libraries"
./b2 \
  -j"$JOBS" \
  link=static \
  runtime-link=static \
  threading=multi \
  variant=release \
  cxxflags="-fPIC" \
  --prefix="$PREFIX" \
  install

########################################
# Merge all static libs
########################################

echo "==> Merging static libraries"

LIBDIR="$PREFIX/lib"
OUTLIB="$LIBDIR/lib${LIBNAME}.a"

mkdir -p "$LIBDIR"
rm -f "$OUTLIB"

ARFILES=$(find "$LIBDIR" -name "libboost_*.a")
[[ -n "$ARFILES" ]] || die "No Boost static libraries found to merge"

ar -M <<EOF
CREATE $OUTLIB
$(for f in $ARFILES; do echo "ADDLIB $f"; done)
SAVE
END
EOF

echo "==> Created monolithic archive:"
echo "    $OUTLIB"

########################################
# Sanity check
########################################

echo "==> Verifying archive contents"
ar t "$OUTLIB" | head -n 10

echo "==> SUCCESS"

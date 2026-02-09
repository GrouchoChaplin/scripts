#!/usr/bin/env bash
set -euo pipefail

# ================== Defaults ==================
REMOTE=""
TAG=""
EXPECTED_COMMIT=""
PREFIX=""
JOBS=6
CXXSTD=17
BUILD_LOCALE=1
WORKDIR="$(pwd)/_boost_build"

DRY_RUN=0

DEFAULT_LIB_BASENAME="libBoostMono"
MONO_NAME=""

# ==============================================

usage() {
cat <<EOF
Usage:
  $0 --remote <git-url> --tag <ref> [options]

Required:
  --remote <url>          Boost git repository
  --tag <ref>             Branch or tag to build

Options:
  --expect-commit <sha>   Require exact commit SHA
  --prefix <dir>          Install prefix
  --jobs <n>              Parallel jobs (default: 6)
  --cxxstd <nn>           C++ standard (default: 17)
  --no-locale             Disable boost_locale
  --libname <name>        Override output archive name
  --workdir <dir>         Build working directory
  --dry-run               Print actions only; do not build
  -h, --help              Show this help
EOF
}

log() { printf "==> %s\n" "$*" >&2; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

# ================= Arg parsing =================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --expect-commit) EXPECTED_COMMIT="$2"; shift 2 ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --cxxstd) CXXSTD="$2"; shift 2 ;;
    --no-locale) BUILD_LOCALE=0; shift ;;
    --libname) MONO_NAME="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$REMOTE" ]] || die "--remote required"
[[ -n "$TAG" ]] || die "--tag required"

PREFIX="${PREFIX:-$WORKDIR/myboost}"

# ================= Preflight =================
require git
require g++
require ar
require ranlib
require nm
require sha256sum

verify_remote_and_ref() {
  log "Preflight: verifying remote and ref"
  git ls-remote --exit-code "$REMOTE" >/dev/null \
    || die "Remote not reachable: $REMOTE"
  git ls-remote --exit-code "$REMOTE" \
    "refs/tags/$TAG" "refs/heads/$TAG" >/dev/null \
    || die "Ref '$TAG' not found in $REMOTE"
}

# detect_compiler_tag() {
#   local v
#   v="$(g++ --version | head -n1)"
#   if [[ "$v" =~ gcc ]]; then
#     echo "gcc$(g++ -dumpversion | cut -d. -f1)"
#   elif [[ "$v" =~ clang ]]; then
#     echo "clang$(g++ --version | sed -n 's/.*clang version \([0-9]\+\).*/\1/p')"
#   else
#     echo "cxxunknown"
#   fi
# }

detect_compiler_tag() {
  local cxx="${CXX:-g++}"
  local line

  line="$("$cxx" --version | head -n 1 || true)"

  # Normalize to lowercase for matching
  local lower
  lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lower" =~ gcc ]]; then
    # gcc/g++ major version
    local maj
    maj="$("$cxx" -dumpversion | cut -d. -f1)"
    echo "gcc${maj}"
  elif [[ "$lower" =~ clang ]]; then
    # clang++ major version
    local maj
    maj="$("$cxx" --version | sed -n 's/.*clang version \([0-9]\+\).*/\1/p')"
    echo "clang${maj:-unknown}"
  else
    echo "cxxunknown"
  fi
}


infer_boost_version_from_ref() {
  if [[ "$1" =~ boost-([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "unknown"
  fi
}

verify_remote_and_ref

# ================= Resolve commit (no clone) =================
GIT_COMMIT="$(git ls-remote "$REMOTE" "refs/tags/$TAG" "refs/heads/$TAG" \
  | head -n1 | awk '{print $1}')"

[[ -n "$GIT_COMMIT" ]] || die "Failed to resolve commit for ref $TAG"

if [[ -n "$EXPECTED_COMMIT" && "$EXPECTED_COMMIT" != "$GIT_COMMIT" ]]; then
  die "Commit mismatch: expected $EXPECTED_COMMIT, got $GIT_COMMIT"
fi

COMPILER_TAG="$(detect_compiler_tag)"
STD_TAG="cxx${CXXSTD}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  BOOST_VERSION="$(infer_boost_version_from_ref "$TAG")"
else
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  git clone --depth 1 --branch "$TAG" "$REMOTE" "$TMP_DIR/src" >/dev/null
  BOOST_VERSION="$(grep -E '^#define BOOST_LIB_VERSION' "$TMP_DIR/src/boost/version.hpp" \
    | awk '{print $3}' | tr -d '"' | sed 's/_/./')"
fi

CANONICAL_NAME="${DEFAULT_LIB_BASENAME}-${BOOST_VERSION}-${COMPILER_TAG}-${STD_TAG}.a"
[[ -z "$MONO_NAME" ]] && MONO_NAME="$CANONICAL_NAME"

ABI_ID="boost=${BOOST_VERSION};compiler=${COMPILER_TAG};cxxstd=${CXXSTD};locale=${BUILD_LOCALE}"

# ================= Dry-run =================
if [[ "$DRY_RUN" -eq 1 ]]; then
  log "DRY RUN MODE — no build will occur"
  cat <<EOF

Resolved configuration:
  Remote:        $REMOTE
  Ref:           $TAG
  Commit:        $GIT_COMMIT
  Boost version: $BOOST_VERSION (inferred)
  Compiler:      $COMPILER_TAG
  C++ standard:  c++$CXXSTD
  Locale:        $BUILD_LOCALE
  Jobs:          $JOBS

Outputs:
  Prefix:        $PREFIX
  Archive:       $PREFIX/lib/$MONO_NAME
  ABI identity:  $ABI_ID

Actions skipped:
  - git clone
  - bootstrap
  - b2 build
  - archive merge
  - manifest writes

EOF
  exit 0
fi

# ================= Real build =================
log "Starting real build"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
git clone --branch "$TAG" "$REMOTE" "$WORKDIR/boost-src"
cd "$WORKDIR/boost-src"

./bootstrap.sh >/dev/null

WITH_LOCALE=()
[[ "$BUILD_LOCALE" -eq 1 ]] && WITH_LOCALE+=(--with-locale)

./b2 \
  -j"$JOBS" \
  link=static runtime-link=static threading=multi variant=release \
  cxxflags="-std=c++$CXXSTD -fPIC" \
  --with-system --with-filesystem --with-thread --with-chrono \
  --with-regex --with-date_time --with-atomic --with-serialization \
  --with-program_options --with-iostreams --with-random \
  --with-timer --with-wave --with-context --with-coroutine --with-fiber \
  "${WITH_LOCALE[@]}" \
  stage

mkdir -p "$PREFIX/include" "$PREFIX/lib" "$PREFIX/manifest"
cp -r boost "$PREFIX/include/"
cp stage/lib/libboost_*.a "$PREFIX/lib/"

cd "$PREFIX/lib"
ar -M <<EOF
CREATE $MONO_NAME
ADDLIB libboost_*.a
SAVE
END
EOF
ranlib "$MONO_NAME"

ln -sf "$MONO_NAME" "${DEFAULT_LIB_BASENAME}-${BOOST_VERSION}.a"
ln -sf "$MONO_NAME" "${DEFAULT_LIB_BASENAME}.a"

# ================= Manifests =================
TEXT_MANIFEST="$PREFIX/manifest/BoostMono-manifest.txt"
JSON_MANIFEST="$PREFIX/manifest/BoostMono-manifest.json"

cat > "$TEXT_MANIFEST" <<EOF
timestamp_utc: $(date -u +%FT%TZ)
remote: $REMOTE
ref: $TAG
commit: $GIT_COMMIT
boost_version: $BOOST_VERSION
compiler: $COMPILER_TAG
cxxstd: c++$CXXSTD
archive: $MONO_NAME
archive_sha256: $(sha256sum "$PREFIX/lib/$MONO_NAME" | awk '{print $1}')
abi_identity: $ABI_ID
EOF

cat > "$JSON_MANIFEST" <<EOF
{
  "timestamp_utc": "$(date -u +%FT%TZ)",
  "remote": "$REMOTE",
  "ref": "$TAG",
  "commit": "$GIT_COMMIT",
  "boost_version": "$BOOST_VERSION",
  "compiler": "$COMPILER_TAG",
  "cxx_standard": "c++$CXXSTD",
  "archive": "$MONO_NAME",
  "archive_sha256": "$(sha256sum "$PREFIX/lib/$MONO_NAME" | awk '{print $1}')",
  "abi_identity": "$ABI_ID"
}
EOF

log "DONE"
log "Library:  $PREFIX/lib/$MONO_NAME"
log "Manifest: $TEXT_MANIFEST"
log "JSON:     $JSON_MANIFEST"

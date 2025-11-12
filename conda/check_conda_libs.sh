#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# check_conda_libs.sh
#
# Checks for missing shared library dependencies (".so" files) in a Conda environment.
# By default, it scans GDAL's osgeo modules for broken .so links (e.g., missing libnsl.so.1).
#
# Usage:
#   ./check_conda_libs.sh [--env <env_name>] [--package <subdir>] [--verbose]
#
# Examples:
#   ./check_conda_libs.sh
#   ./check_conda_libs.sh --env nc2geotiff
#   ./check_conda_libs.sh --env nc2geotiff --package osgeo
#   ./check_conda_libs.sh --env myenv --package numpy --verbose
#
# Notes:
#   - The script locates .so files in the given package directory under <env>/lib/python*/site-packages.
#   - Uses 'ldd' to list shared object dependencies and flags missing ones.
#   - Exit code 0 = all good; nonzero = at least one missing dependency.
# --------------------------------------------------------------------------------------------------

set -euo pipefail
ENV_NAME=""
PACKAGE="osgeo"
VERBOSE=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV_NAME="$2"; shift ;;
        --package) PACKAGE="$2"; shift ;;
        --verbose) VERBOSE=true ;;
        -h|--help)
            grep '^#' "$0" | cut -c 4-
            exit 0 ;;
        *)
            echo "❌ Unknown option: $1"
            echo "Run with --help for usage."
            exit 1 ;;
    esac
    shift
done

# --- Resolve environment path ---
if [[ -z "$ENV_NAME" ]]; then
    if [[ -n "${CONDA_PREFIX:-}" ]]; then
        ENV_PATH="$CONDA_PREFIX"
    else
        echo "❌ No Conda environment active and no --env specified."
        exit 1
    fi
else
    ENV_PATH="$(conda env list | awk -v env="$ENV_NAME" '$1==env {print $2}')"
    if [[ -z "$ENV_PATH" ]]; then
        echo "❌ Conda environment '$ENV_NAME' not found."
        exit 1
    fi
fi

echo "🔍 Checking shared library dependencies in: $ENV_PATH"
echo "📦 Package directory: $PACKAGE"
echo

SITE_PACKAGES_DIR="$(find "$ENV_PATH/lib" -type d -path "*/site-packages" | head -n1)"
if [[ -z "$SITE_PACKAGES_DIR" ]]; then
    echo "❌ Could not locate site-packages directory."
    exit 1
fi

TARGET_DIR="$SITE_PACKAGES_DIR/$PACKAGE"
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "❌ Package directory not found: $TARGET_DIR"
    exit 1
fi

FOUND_MISSING=false
for sofile in "$TARGET_DIR"/_*.so; do
    [[ -e "$sofile" ]] || continue
    echo "🧩 Checking $(basename "$sofile")"
    MISSING=$(ldd "$sofile" | grep "not found" || true)
    if [[ -n "$MISSING" ]]; then
        echo "❌ Missing dependencies:"
        echo "$MISSING" | sed 's/^/   /'
        FOUND_MISSING=true
    elif $VERBOSE; then
        echo "✅ All dependencies satisfied."
    fi
    echo
done

if $FOUND_MISSING; then
    echo "⚠️  Some dependencies are missing!"
    exit 2
else
    echo "✅ All libraries verified — no missing dependencies."
    exit 0
fi

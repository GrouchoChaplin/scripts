#!/usr/bin/env bash
set -euo pipefail

# Defaults
ROOT="."
REPO=""

usage() {
    echo "Usage:"
    echo "  $0 --root-folder <path> --repo-name <repo>"
    echo
    echo "Example:"
    echo "  $0 --root-folder /run/media/peddycoartte/MasterBackup --repo-name jsig.optimized_shader"
    exit 1
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in

        --root-folder)
            ROOT="$2"
            shift 2
            ;;

        --repo-name)
            REPO="$2"
            shift 2
            ;;

        -h|--help)
            usage
            ;;

        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# --- Validate ---
if [[ -z "$REPO" ]]; then
    echo "❌ Missing required argument: --repo-name"
    usage
fi

if [[ ! -d "$ROOT" ]]; then
    echo "❌ Root folder does not exist: $ROOT"
    exit 1
fi

echo "🔍 Scanning under: $ROOT"
echo "🔎 Looking for repo dirs matching: ${REPO}*"
echo

# --- Find matching repo directories ---
mapfile -t CANDIDATES < <(
    find "$ROOT" -maxdepth 8 -type d -name "${REPO}*" -not -path "*/.git/*"
)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "❌ No matching directories found."
    exit 1
fi

printf "%-60s | %-25s | %-20s | %-7s | %s\n" \
       "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "HASH"
printf "%s\n" "$(printf '—%.0s' {1..150})"

# --- Process each candidate directory ---
for dir in "${CANDIDATES[@]}"; do
    if [[ ! -d "$dir/.git" ]]; then
        continue
    fi

    pushd "$dir" >/dev/null

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
    hash=$(git rev-parse --short HEAD)
    last_commit=$(git log -1 --format="%ci" 2>/dev/null || echo "NO COMMITS")
    dirty="clean"

    # Detect modified/untracked files
    if [[ -n "$(git status --porcelain)" ]]; then
        dirty="DIRTY"
    fi

    printf "%-60s | %-25s | %-20s | %-7s | %s\n" \
        "$dir" "$branch" "$last_commit" "$dirty" "$hash"

    if [[ "$dirty" == "DIRTY" ]]; then
        echo "   🔸 Uncommitted changes:"
        git status --porcelain | sed 's/^/      /'
    fi

    echo
    popd >/dev/null
done

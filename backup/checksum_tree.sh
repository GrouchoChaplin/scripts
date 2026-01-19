#!/usr/bin/env bash
# checksum_tree.sh
#
# Deterministic, Merkle-tree-style SHA256 integrity for directory trees.
# - Per-directory leaf file: sha256sum.dir  (hashes of regular files in that directory)
# - Per-directory node file: sha256sum.tree (hash of sha256sum.dir + child sha256sum.tree files)
# - Root file: ROOT_HASH.txt (hash of root sha256sum.tree for archival)
#
# Modes:
#   --update : (default) generate/update checksum files
#   --verify : verify all sha256sum.dir and sha256sum.tree and ROOT_HASH.txt
#
# Excludes:
#   --exclude PATTERN  (repeatable) patterns match paths relative to root, e.g. ".git" "build" "node_modules"
#
# Optional rsync integration:
#   --rsync SRC DST [--rsync-opts "<opts>"] [--verify-after]
#
# Requirements: bash, find, sort, sha256sum, xargs
set -euo pipefail

# Make behavior deterministic across machines/locales
export LC_ALL=C
export LANG=C

PROG="$(basename "$0")"

MODE="update"
ROOT="."
EXCLUDES=()
DO_RSYNC=0
RSYNC_SRC=""
RSYNC_DST=""
RSYNC_OPTS="-aHAX --numeric-ids --delete --info=progress2"
VERIFY_AFTER=0

LEAF_FILE="sha256sum.dir"
TREE_FILE="sha256sum.tree"
ROOT_HASH_FILE="ROOT_HASH.txt"

usage() {
  cat <<EOF
Usage:
  $PROG [--root DIR] [--exclude PATTERN ...] [--update|--verify]

  $PROG --rsync SRC DST [--rsync-opts "<opts>"] [--exclude PATTERN ...] [--verify-after]

Examples:
  # Update checksums for current tree, excluding common junk
  $PROG --exclude .git --exclude build --exclude node_modules --update

  # Verify
  $PROG --root /mnt/backup_drive --verify

  # Rsync then update (and optionally verify) on destination
  $PROG --rsync /data/ /mnt/backup_drive/data/ --exclude .git --verify-after

Notes on --exclude:
  Patterns are matched as paths relative to --root.
  Use directory names like ".git" or glob-ish paths like "build" or "tmp/cache".
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        [[ $# -ge 2 ]] || die "--root requires an argument"
        ROOT="$2"; shift 2
        ;;
      --exclude)
        [[ $# -ge 2 ]] || die "--exclude requires an argument"
        EXCLUDES+=("$2"); shift 2
        ;;
      --update)
        MODE="update"; shift
        ;;
      --verify)
        MODE="verify"; shift
        ;;
      --rsync)
        [[ $# -ge 3 ]] || die "--rsync requires SRC and DST"
        DO_RSYNC=1
        RSYNC_SRC="$2"
        RSYNC_DST="$3"
        shift 3
        ;;
      --rsync-opts)
        [[ $# -ge 2 ]] || die "--rsync-opts requires an argument"
        RSYNC_OPTS="$2"
        shift 2
        ;;
      --verify-after)
        VERIFY_AFTER=1
        shift
        ;;
      -h|--help)
        usage; exit 0
        ;;
      *)
        die "Unknown argument: $1 (use --help)"
        ;;
    esac
  done
}

# Build a safe find pruning expression from EXCLUDES.
# We prune both the exact path and everything under it:
#   -path "./PAT" -o -path "./PAT/*"
build_find_prune_args() {
  local -a args=()
  if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
    args+=( \( )
    local first=1
    local pat
    for pat in "${EXCLUDES[@]}"; do
      # Normalize: strip leading "./" if user provided it
      pat="${pat#./}"
      if [[ $first -eq 0 ]]; then
        args+=( -o )
      fi
      args+=( -path "./$pat" -o -path "./$pat/*" )
      first=0
    done
    args+=( \) -prune -o )
  fi
  printf '%s\0' "${args[@]}"
}

# List directories to process, deepest-first, excluding pruned paths.
# Output is NUL-delimited to be safe with weird names.
list_dirs_deep_first() {
  local root="$1"
  local -a prune_args=()
  # Rehydrate prune args (NUL-delimited)
  while IFS= read -r -d '' tok; do prune_args+=("$tok"); done < <(build_find_prune_args)

  ( cd "$root"
    # -print0 ensures safe names
    find . "${prune_args[@]}" -type d -print0 | sort -z -r
  )
}

# List directories to verify, any order (we use find), excluding pruned paths.
list_dirs_any() {
  local root="$1"
  local -a prune_args=()
  while IFS= read -r -d '' tok; do prune_args+=("$tok"); done < <(build_find_prune_args)

  ( cd "$root"
    find . "${prune_args[@]}" -type d -print0
  )
}

# Generate sha256sum.dir in a single directory (only regular files in that dir).
write_leaf_for_dir() {
  local root="$1"
  local d_rel="$2"

  ( cd "$root/$d_rel"

    # Hash files at maxdepth=1, excluding our own checksum files.
    # Deterministic ordering: sort by filename (NUL-safe).
    # Format: "<hash><two spaces><filename>"
    if find . -maxdepth 1 -type f \
        ! -name "$LEAF_FILE" \
        ! -name "$TREE_FILE" \
        ! -name "$ROOT_HASH_FILE" \
        -print0 | sort -z | xargs -0 -r sha256sum > "$LEAF_FILE".tmp 2>/dev/null
    then
      :
    else
      # If sha256sum had issues, preserve stderr for caller
      rm -f "$LEAF_FILE".tmp
      return 1
    fi

    mv -f "$LEAF_FILE".tmp "$LEAF_FILE"
  )
}

# Generate sha256sum.tree in a directory based on:
#   - its sha256sum.dir (if present; empty is okay)
#   - each immediate child directory's sha256sum.tree
write_tree_for_dir() {
  local root="$1"
  local d_rel="$2"

  ( cd "$root/$d_rel"

    # Ensure leaf exists (even if empty)
    [[ -f "$LEAF_FILE" ]] || : > "$LEAF_FILE"

    # Collect entries: hash of LEAF_FILE and hashes of child TREE_FILEs.
    # Store as: "<hash><two spaces><name>"
    # where name is "$LEAF_FILE" or "childdir/$TREE_FILE"
    {
      # hash of leaf file contents
      sha256sum "$LEAF_FILE" | awk '{print $1 "  '"$LEAF_FILE"'"}'

      # hash each immediate child tree file
      local child
      while IFS= read -r -d '' child; do
        local rel="${child#./}"
        # child is like "./subdir/sha256sum.tree"
        local h
        h="$(sha256sum "$child" | awk '{print $1}')"
        echo "$h  $rel"
      done < <(find . -mindepth 2 -maxdepth 2 -type f -name "$TREE_FILE" -print0 2>/dev/null || true)
    } | sort > "$TREE_FILE".tmp

    mv -f "$TREE_FILE".tmp "$TREE_FILE"
  )
}

# Write ROOT_HASH.txt at root as "<hash>  sha256sum.tree"
write_root_hash() {
  local root="$1"
  ( cd "$root"
    [[ -f "./$TREE_FILE" ]] || die "Missing root $TREE_FILE; run --update first"
    sha256sum "./$TREE_FILE" | awk '{print $1 "  '"$TREE_FILE"'"}' > "./$ROOT_HASH_FILE".tmp
    mv -f "./$ROOT_HASH_FILE".tmp "./$ROOT_HASH_FILE"
  )
}

do_update() {
  local root="$1"

  # sanity
  [[ -d "$root" ]] || die "Root is not a directory: $root"

  # Process deepest-first so child sha256sum.tree exists before parent.
  # list_dirs_deep_first outputs NUL-delimited "./path"
  while IFS= read -r -d '' d; do
    # Normalize "./" to "." handling
    local d_rel="${d#./}"
    [[ -z "$d_rel" ]] && d_rel="."
    write_leaf_for_dir "$root" "$d_rel"
    # Tree will be written after leaf, but needs children -> deepest-first ensures children already processed
    write_tree_for_dir "$root" "$d_rel"
  done < <(list_dirs_deep_first "$root")

  # Finally, root hash
  write_root_hash "$root"
}

verify_leaf_in_dir() {
  local root="$1"
  local d_rel="$2"
  ( cd "$root/$d_rel"
    [[ -f "$LEAF_FILE" ]] || return 0  # nothing to verify
    sha256sum -c "$LEAF_FILE" >/dev/null
  )
}

verify_tree_in_dir() {
  local root="$1"
  local d_rel="$2"
  ( cd "$root/$d_rel"
    [[ -f "$TREE_FILE" ]] || return 0
    # Recompute expected TREE_FILE content and compare hash of content? We verify by recomputing file exactly:
    # To avoid rewriting, we compute a temp, diff it.
    local tmp
    tmp="$(mktemp -t checksum_tree.XXXXXX)"
    trap 'rm -f "$tmp"' RETURN

    [[ -f "$LEAF_FILE" ]] || : > "$LEAF_FILE"

    {
      sha256sum "$LEAF_FILE" | awk '{print $1 "  '"$LEAF_FILE"'"}'
      local child
      while IFS= read -r -d '' child; do
        local rel="${child#./}"
        local h
        h="$(sha256sum "$child" | awk '{print $1}')"
        echo "$h  $rel"
      done < <(find . -mindepth 2 -maxdepth 2 -type f -name "$TREE_FILE" -print0 2>/dev/null || true)
    } | sort > "$tmp"

    diff -q "$tmp" "$TREE_FILE" >/dev/null
  )
}

do_verify() {
  local root="$1"

  [[ -d "$root" ]] || die "Root is not a directory: $root"

  # Verify leaf files and tree structure deterministically.
  # If anything is missing or mismatched, we fail.
  local failures=0

  while IFS= read -r -d '' d; do
    local d_rel="${d#./}"
    [[ -z "$d_rel" ]] && d_rel="."
    if ! verify_leaf_in_dir "$root" "$d_rel"; then
      echo "FAIL leaf: $root/$d_rel/$LEAF_FILE" >&2
      failures=$((failures+1))
    fi
    if ! verify_tree_in_dir "$root" "$d_rel"; then
      echo "FAIL tree: $root/$d_rel/$TREE_FILE" >&2
      failures=$((failures+1))
    fi
  done < <(list_dirs_any "$root")

  # Verify root hash file
  if [[ -f "$root/$ROOT_HASH_FILE" ]]; then
    ( cd "$root" && sha256sum -c "$ROOT_HASH_FILE" >/dev/null ) || {
      echo "FAIL root: $root/$ROOT_HASH_FILE" >&2
      failures=$((failures+1))
    }
  else
    echo "FAIL root: missing $root/$ROOT_HASH_FILE" >&2
    failures=$((failures+1))
  fi

  if [[ $failures -ne 0 ]]; then
    die "Verification failed: $failures issue(s)"
  fi
}

do_rsync_then_update() {
  local src="$1"
  local dst="$2"

  need_cmd rsync

  # Run rsync (user can override RSYNC_OPTS)
  # shellcheck disable=SC2086
  rsync $RSYNC_OPTS "$src" "$dst"

  # After rsync, update checksums on destination root
  ROOT="$dst"
  do_update "$ROOT"

  if [[ $VERIFY_AFTER -eq 1 ]]; then
    do_verify "$ROOT"
  fi
}

main() {
  parse_args "$@"

  need_cmd find
  need_cmd sort
  need_cmd sha256sum
  need_cmd xargs
  need_cmd awk
  need_cmd diff

  if [[ $DO_RSYNC -eq 1 ]]; then
    do_rsync_then_update "$RSYNC_SRC" "$RSYNC_DST"
    exit 0
  fi

  case "$MODE" in
    update) do_update "$ROOT" ;;
    verify) do_verify "$ROOT" ;;
    *) die "Unknown mode: $MODE" ;;
  esac
}

main "$@"

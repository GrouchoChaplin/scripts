#!/usr/bin/env bash
#
# rpmmacros_sanitize.sh
#
# Automatically fix incorrect %_topdir definitions inside ~/.rpmmacros,
# including malformed macro expressions (e.g., "%_topdir %(echo $HOME)/rpmbuild")
# by rewriting them into absolute paths.
#
# - Creates a timestamped backup before modifying anything
# - Preserves all other macros unchanged
# - Ensures the target directory exists (and offers to create it)
# - Rocky/RHEL safe

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

good()  { printf "%b[GOOD]%b %s\n" "$G" "$X" "$*"; }
warn()  { printf "%b[WARN]%b %s\n" "$Y" "$X" "$*"; }
bad()   { printf "%b[FAIL]%b %s\n" "$R" "$X" "$*"; }
info()  { printf "%b[INFO]%b %s\n" "$B" "$X" "$*"; }

fail() {
  bad "$1"
  exit 1
}

# ------------------------ Paths ------------------------
RPMMACROS="$HOME/.rpmmacros"

info "Checking $RPMMACROS ..."

if [[ ! -f "$RPMMACROS" ]]; then
  fail "$RPMMACROS does not exist. Run setup_rpmbuild_env.sh first."
fi

# Extract raw %_topdir line
TOPLINE=$(grep '^%_topdir' "$RPMMACROS" || true)

if [[ -z "$TOPLINE" ]]; then
  fail "%_topdir not found in $RPMMACROS. Nothing to sanitize."
fi

info "Found line: $TOPLINE"


# ------------------------ Function: normalize path ------------------------
normalize_topdir() {
  local raw="$1"

  # CASE 1: Already an absolute path
  if [[ "$raw" == /* ]]; then
    echo "$raw"
    return
  fi

  # CASE 2: Broken macro pattern: "%_topdir %(echo $HOME)/whatever"
  # Extract "$HOME)/whatever", strip macro
  if [[ "$raw" =~ %\_topdir\ %\((echo\ \$HOME)\)(.*) ]]; then
    local tail="${BASH_REMATCH[2]}"
    echo "$HOME$tail"
    return
  fi

  # CASE 3: Full macro inside parentheses:
  # Example: "%_topdir %(echo $HOME/projects/foo)"
  if [[ "$raw" =~ %\_topdir\ %\((echo\ (.*))\) ]]; then
    local inside="${BASH_REMATCH[2]}"
    # inside = $HOME/projects/foo  → expand it
    eval echo "$inside"
    return
  fi

  # CASE 4: Something else weird → fallback to absolute path guess
  warn "Unexpected %_topdir syntax. Attempting automatic cleanup..."
  # Remove "%_topdir" and trim whitespace
  local cleaned=$(echo "$raw" | sed 's/^%_topdir //')
  # Replace leading ~ if present
  cleaned="${cleaned/#\~/$HOME}"
  echo "$cleaned"
}

# ------------------------ Normalize the line ------------------------
NEW_TOPDIR=$(normalize_topdir "$TOPLINE")
info "Resolved TOPDIR → $NEW_TOPDIR"

if [[ -z "$NEW_TOPDIR" ]]; then
  fail "Sanitizer produced an empty TOPDIR. Aborting."
fi

# ------------------------ Confirm directory exists ------------------------
if [[ ! -d "$NEW_TOPDIR" ]]; then
  warn "Directory does not exist: $NEW_TOPDIR"
  read -r -p "Create it? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    mkdir -p "$NEW_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    good "Created $NEW_TOPDIR and standard RPM subdirs."
  else
    fail "User declined directory creation."
  fi
else
  good "TOPDIR directory exists."
fi

# ------------------------ Rewrite ~/.rpmmacros ------------------------
BACKUP="$RPMMACROS.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$RPMMACROS" "$BACKUP"
good "Created backup: $BACKUP"

info "Rewriting %_topdir in $RPMMACROS..."

# Rebuild file:
{
  while IFS='' read -r line; do
    if [[ "$line" =~ ^%_topdir ]]; then
      echo "%_topdir $NEW_TOPDIR"
    else
      echo "$line"
    fi
  done < "$BACKUP"
} > "$RPMMACROS"

good "%_topdir successfully sanitized:"
echo "    %_topdir $NEW_TOPDIR"

info "Sanity check:"

grep '^%_topdir' "$RPMMACROS"

good "Rewrite complete."

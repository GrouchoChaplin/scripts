#!/usr/bin/env bash
#
# manage_locate_paths.sh
# -------------------------------------------------------------
# Cross-compatible locate manager for mlocate/plocate.
# Adds/removes directories, lists databases, searches, and refreshes all.
# Automatically detects which updatedb flavor is installed.
#
# Usage:
#   sudo ./manage_locate_paths.sh --add /path/to/include
#   sudo ./manage_locate_paths.sh --remove /path/to/remove
#   ./manage_locate_paths.sh --list
#   ./manage_locate_paths.sh --search <pattern>
#   sudo ./manage_locate_paths.sh --refresh-all
#
# Log file:
#   ~/projects/scripts/sys/manage_locate_paths.log
# -------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$SCRIPT_DIR/manage_locate_paths.log"
DB_DIR="/var/lib/manage_locate_paths"

timestamp() { date "+%F %T"; }
log() { echo "[$(timestamp)] $*" | tee -a "$LOGFILE"; }

sudo mkdir -p "$DB_DIR" 2>/dev/null || true
sudo chmod 755 "$DB_DIR" 2>/dev/null || true

ACTION=""
TARGET_PATH=""
SEARCH_PATTERN=""

# --- Parse args ---
case "${1:-}" in
  --add)         ACTION="add";         TARGET_PATH="${2:-}";;
  --remove)      ACTION="remove";      TARGET_PATH="${2:-}";;
  --list)        ACTION="list";;
  --search)      ACTION="search";      SEARCH_PATTERN="${2:-}";;
  --refresh-all) ACTION="refresh-all";;
  *)
    echo "Usage:"
    echo "  sudo $0 --add /path/to/include"
    echo "  sudo $0 --remove /path/to/remove"
    echo "  $0 --list"
    echo "  $0 --search <pattern>"
    echo "  sudo $0 --refresh-all"
    exit 1
    ;;
esac

# --- Root check ---
if [[ "$ACTION" =~ ^(add|remove|refresh-all)$ && "$EUID" -ne 0 ]]; then
  log "⚠️  Must be run as root (sudo) for $ACTION action."
  exit 1
fi

# --- Detect updatedb flavor ---
if updatedb --help 2>&1 | grep -q -- '--localpaths'; then
  UPDATEDB_MODE="plocate"
else
  UPDATEDB_MODE="mlocate"
fi
log "🔎 Detected updatedb mode: $UPDATEDB_MODE"

# --- LIST ---
if [[ "$ACTION" == "list" ]]; then
  log "📋 Listing tracked locate paths:"
  if compgen -G "$DB_DIR/*.db" > /dev/null; then
    for db in "$DB_DIR"/*.db; do
      echo "  - $(basename "${db%.db}" | sed 's#_#/#g')"
    done
  else
    echo "  (no tracked custom paths)"
  fi
  exit 0
fi

# --- SEARCH ---
if [[ "$ACTION" == "search" ]]; then
  if [[ -z "$SEARCH_PATTERN" ]]; then
    log "❌ Missing search pattern."
    exit 1
  fi
  if ! compgen -G "$DB_DIR/*.db" > /dev/null; then
    log "ℹ️  No custom databases found. Add one first with --add."
    exit 0
  fi
  log "🔍 Searching for '$SEARCH_PATTERN' across all custom databases..."
  RESULTS=$(locate -d "$DB_DIR"/*.db "$SEARCH_PATTERN" 2>/dev/null || true)
  if [[ -z "$RESULTS" ]]; then
    log "ℹ️  No matches found."
    exit 0
  fi
  echo "$RESULTS" | GREP_COLOR='1;32' grep --color=always -E "$SEARCH_PATTERN|$"
  exit 0
fi

# --- REFRESH ALL ---
if [[ "$ACTION" == "refresh-all" ]]; then
  if ! compgen -G "$DB_DIR/*.db" > /dev/null; then
    log "ℹ️  No databases to refresh."
    exit 0
  fi
  log "🔁 Refreshing all locate databases..."
  for db in "$DB_DIR"/*.db; do
    BASE_NAME="$(basename "$db" .db)"
    TARGET_PATH="$(echo "$BASE_NAME" | sed 's#_#/#g')"
    log "↻ Refreshing '$TARGET_PATH'..."
    if [[ -d "$TARGET_PATH" ]]; then
      TMP_CONF="$(mktemp)"
      echo "PRUNEFS =" > "$TMP_CONF"
      echo "PRUNEPATHS =" >> "$TMP_CONF"
      if [[ "$UPDATEDB_MODE" == "plocate" ]]; then
        updatedb --localpaths="$TARGET_PATH" --prunepaths="" --output="$db"
      else
        SEARCH_PATHS="$TARGET_PATH" updatedb -f "$TMP_CONF" -o "$db"
      fi
      rm -f "$TMP_CONF"
      log "✅ Refreshed: $db"
    else
      log "⚠️  Skipped missing path: $TARGET_PATH"
    fi
  done
  log "🪶 Refresh complete."
  exit 0
fi

# --- ADD ---
if [[ "$ACTION" == "add" ]]; then
  if [[ -z "$TARGET_PATH" ]]; then
    log "❌ Missing path argument."
    exit 1
  fi
  if [[ ! -d "$TARGET_PATH" ]]; then
    log "❌ '$TARGET_PATH' is not a valid directory."
    exit 1
  fi
  DB_NAME="$(echo "$TARGET_PATH" | sed 's#/#_#g' | sed 's/^_//')"
  DB_PATH="$DB_DIR/${DB_NAME}.db"

  log "🔧 Indexing '$TARGET_PATH' into its own locate database..."
  TMP_CONF="$(mktemp)"
  echo "PRUNEFS =" > "$TMP_CONF"
  echo "PRUNEPATHS =" >> "$TMP_CONF"

  if [[ "$UPDATEDB_MODE" == "plocate" ]]; then
    updatedb --localpaths="$TARGET_PATH" --prunepaths="" --output="$DB_PATH"
  else
    SEARCH_PATHS="$TARGET_PATH" updatedb -f "$TMP_CONF" -o "$DB_PATH"
  fi
  rm -f "$TMP_CONF"
  log "✅ Created database: $DB_PATH"

  SAMPLE_FILE=$(find "$TARGET_PATH" -type f | head -n 1 || true)
  if [[ -n "$SAMPLE_FILE" ]]; then
    if locate -d "$DB_PATH" "$(basename "$SAMPLE_FILE")" | grep -q "$TARGET_PATH"; then
      log "✅ Verified: '$TARGET_PATH' indexed successfully."
    else
      log "⚠️  Verification failed — may require re-run."
    fi
  else
    log "ℹ️  Directory empty; nothing to index yet."
  fi
  exit 0
fi

# --- REMOVE ---
if [[ "$ACTION" == "remove" ]]; then
  if [[ -z "$TARGET_PATH" ]]; then
    log "❌ Missing path argument."
    exit 1
  fi
  DB_NAME="$(echo "$TARGET_PATH" | sed 's#/#_#g' | sed 's/^_//')"
  DB_PATH="$DB_DIR/${DB_NAME}.db"

  if [[ -f "$DB_PATH" ]]; then
    log "🧹 Removing database for '$TARGET_PATH'..."
    rm -f "$DB_PATH"
    log "✅ Removed $DB_PATH"
  else
    log "ℹ️  No database found for '$TARGET_PATH'"
  fi
  exit 0
fi

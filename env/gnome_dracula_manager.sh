#!/usr/bin/env bash
# GNOME Terminal Dracula Manager + Profile Manager
# Works on Rocky/RHEL 8 (GNOME Terminal 3.28) and similar

set -euo pipefail

SCHEMA_BASE="org.gnome.Terminal.Legacy.Profile"
PROFILES_BASE="/org/gnome/terminal/legacy/profiles:/"

# ---------- Helpers ----------

die() {
    echo "ERROR: $*" >&2
    exit 1
}

profiles_list_raw() {
    gsettings get org.gnome.Terminal.ProfilesList list
}

profiles_array() {
    profiles_list_raw | tr -d "[],'" | tr ' ' '\n' | sed '/^$/d'
}

get_profile_name() {
    local uuid="$1"
    dconf read "${PROFILES_BASE}:$uuid/visible-name" 2>/dev/null || echo "''"
}

set_profile_name() {
    local uuid="$1" name="$2"
    # dconf is the reliable way on Rocky/RHEL 8
    dconf write "${PROFILES_BASE}:$uuid/visible-name" "'$name'"
}

set_profile_key() {
    local uuid="$1" key="$2" value="$3"
    local instance="${SCHEMA_BASE}:${PROFILES_BASE}:$uuid/"
    gsettings set "$instance" "$key" "$value"
}

get_default_uuid() {
    gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'"
}

set_default_uuid() {
    local uuid="$1"
    gsettings set org.gnome.Terminal.ProfilesList default "'$uuid'"
}

find_uuid_by_name() {
    local target="$1"
    for uuid in $(profiles_array); do
        local name
        name=$(get_profile_name "$uuid" | tr -d "'")
        if [[ "$name" == "$target" ]]; then
            echo "$uuid"
            return 0
        fi
    done
    return 1
}

# ---------- Commands ----------

cmd_list() {
    echo "Profiles:"
    for uuid in $(profiles_array); do
        local name
        name=$(get_profile_name "$uuid")
        echo "  $uuid → ${name:-''}"
    done

    local def
    def=$(get_default_uuid)
    echo
    echo "Default profile UUID: $def"
}

cmd_set_default() {
    local id="${1:-}"
    [[ -z "$id" ]] && die "Usage: $0 set-default <name-or-uuid>"

    local uuid="$id"

    # If it doesn't look like a UUID, treat as name
    if ! [[ "$uuid" =~ - ]]; then
        uuid=$(find_uuid_by_name "$id" || true)
        [[ -z "$uuid" ]] && die "No profile found with name '$id'"
    fi

    set_default_uuid "$uuid"
    echo "✅ Default profile set to: $uuid"
}

cmd_rename() {
    local old="${1:-}"
    local new="${2:-}"
    [[ -z "$old" || -z "$new" ]] && die "Usage: $0 rename <old-name> <new-name>"

    local uuid
    uuid=$(find_uuid_by_name "$old" || true)
    [[ -z "$uuid" ]] && die "No profile found with name '$old'"

    set_profile_name "$uuid" "$new"
    echo "✅ Renamed '$old' → '$new' (UUID: $uuid)"
}

cmd_install_dracula() {
    # Don’t duplicate
    if uuid=$(find_uuid_by_name "Dracula" 2>/dev/null); then
        echo "ℹ️ Dracula already exists (UUID: $uuid)"
        return 0
    fi

    echo "🎨 Creating Dracula profile…"

    local list uuid new_list
    list=$(profiles_list_raw)
    uuid=$(uuidgen)

    # Add to list
    new_list=$(echo "$list" | sed "s/]$/, '$uuid']/")
    gsettings set org.gnome.Terminal.ProfilesList list "$new_list"

    # Name
    set_profile_name "$uuid" "Dracula"

    # Colors (Rocky 8 safe)
    local inst="${SCHEMA_BASE}:${PROFILES_BASE}:$uuid/"
    gsettings set "$inst" background-color "'#282A36'"
    gsettings set "$inst" foreground-color "'#F8F8F2'"
    gsettings set "$inst" use-theme-colors false

    gsettings set "$inst" palette \
"['#000000', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#BBBBBB', \
'#44475A', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#FFFFFF']"

    # Cursor colors (keys available on Rocky)
    gsettings set "$inst" cursor-background-color "'#FF79C6'"
    gsettings set "$inst" cursor-foreground-color "'#282A36'"

    # Set as default
    set_default_uuid "$uuid"

    echo "✅ Dracula installed with UUID: $uuid"
    echo "   Dracula is now the default profile."
}

cmd_fix_dracula() {
    local uuid
    uuid=$(find_uuid_by_name "Dracula" || true)
    [[ -z "$uuid" ]] && die "No 'Dracula' profile found to fix."

    echo "🩹 Fixing Dracula profile (UUID: $uuid)…"

    set_profile_name "$uuid" "Dracula"

    local inst="${SCHEMA_BASE}:${PROFILES_BASE}:$uuid/"
    gsettings set "$inst" background-color "'#282A36'"
    gsettings set "$inst" foreground-color "'#F8F8F2'"
    gsettings set "$inst" use-theme-colors false

    gsettings set "$inst" palette \
"['#000000', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#BBBBBB', \
'#44475A', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#FFFFFF']"

    gsettings set "$inst" cursor-background-color "'#FF79C6'"
    gsettings set "$inst" cursor-foreground-color "'#282A36'"

    echo "✅ Dracula profile repaired."
}

cmd_remove_dracula() {
    local uuid
    uuid=$(find_uuid_by_name "Dracula" || true)
    [[ -z "$uuid" ]] && die "No 'Dracula' profile found to remove."

    echo "⚠️ Removing Dracula profile (UUID: $uuid)…"

    # Remove from profile list
    local list new_list
    list=$(profiles_list_raw)
    new_list=$(echo "$list" | sed "s/'$uuid',\? //;s/, '$uuid'//;s/'$uuid'//")
    gsettings set org.gnome.Terminal.ProfilesList list "$new_list"

    # If Dracula was default, switch to first remaining profile
    local def
    def=$(get_default_uuid)
    if [[ "$def" == "$uuid" ]]; then
        local first
        first=$(profiles_array | head -n1)
        [[ -n "$first" ]] && set_default_uuid "$first"
        echo "ℹ️ Dracula was default. Switched default to: $first"
    fi

    echo "✅ Dracula profile removed (settings remain in dconf, but profile is deregistered)."
}

cmd_backup() {
    local file="${1:-}"
    [[ -z "$file" ]] && die "Usage: $0 backup <file>"

    dconf dump /org/gnome/terminal/legacy/ > "$file"
    echo "✅ GNOME Terminal profiles backed up to $file"
}

cmd_restore() {
    local file="${1:-}"
    [[ -z "$file" ]] && die "Usage: $0 restore <file>"

    [[ ! -f "$file" ]] && die "File not found: $file"

    echo "⚠️ This will overwrite GNOME Terminal profile settings under /org/gnome/terminal/legacy/."
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."

    dconf load /org/gnome/terminal/legacy/ < "$file"
    echo "✅ GNOME Terminal profiles restored from $file"
}

cmd_doctor() {
    echo "🔎 GNOME Terminal Doctor"
    echo

    echo "Profiles:"
    for uuid in $(profiles_array); do
        local name
        name=$(get_profile_name "$uuid" | tr -d "'")
        [[ -z "$name" ]] && name="(no name)"
        echo "  $uuid → $name"
    done

    local def
    def=$(get_default_uuid)
    echo
    echo "Default profile UUID: $def"

    if uuid=$(find_uuid_by_name "Dracula" 2>/dev/null); then
        echo "Dracula profile found: $uuid"
    else
        echo "No Dracula profile found."
    fi
}

cmd_help() {
    cat <<EOF
GNOME Terminal Dracula Manager

Usage:
  $0 help                 Show this help
  $0 list                 List profiles and default
  $0 set-default <id>     Set default profile by name or UUID
  $0 rename <old> <new>   Rename profile by name
  $0 install-dracula      Create Dracula profile and set it as default
  $0 fix-dracula          Repair Dracula colors & name
  $0 remove-dracula       Remove Dracula profile
  $0 backup <file>        Backup GNOME Terminal profiles to <file>
  $0 restore <file>       Restore GNOME Terminal profiles from <file>
  $0 doctor               Diagnose profile configuration
EOF
}

# ---------- Main dispatch ----------

cmd="${1:-help}"
shift || true

case "$cmd" in
    help)            cmd_help "$@" ;;
    list)            cmd_list "$@" ;;
    set-default)     cmd_set_default "$@" ;;
    rename)          cmd_rename "$@" ;;
    install-dracula) cmd_install_dracula "$@" ;;
    fix-dracula)     cmd_fix_dracula "$@" ;;
    remove-dracula)  cmd_remove_dracula "$@" ;;
    backup)          cmd_backup "$@" ;;
    restore)         cmd_restore "$@" ;;
    doctor)          cmd_doctor "$@" ;;
    *)               die "Unknown command: $cmd (try: $0 help)" ;;
esac

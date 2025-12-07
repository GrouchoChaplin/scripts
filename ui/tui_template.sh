#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Reusable ncurses-style TUI for Bash using dialog/whiptail
# ---------------------------------------------------------------------------

set -euo pipefail

# Pick dialog or whiptail (auto-detect)
if command -v dialog >/dev/null 2>&1; then
    TUI="dialog"
elif command -v whiptail >/dev/null 2>&1; then
    TUI="whiptail"
else
    echo "ERROR: dialog or whiptail is required." >&2
    exit 1
fi

# Cleanup temp files on exit
TMP=$(mktemp)
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

# ------------------------------
#  TUI FUNCTIONS
# ------------------------------

msg_box() {
    $TUI --title "$1" --msgbox "$2" 10 60
}

yesno() {
    $TUI --title "$1" --yesno "$2" 10 60
}

input_box() {
    $TUI --title "$1" --inputbox "$2" 10 60 2> "$TMP"
    cat "$TMP"
}

menu_box() {
    # Usage: menu_box "Title" "Prompt text" "tag1" "desc1" "tag2" "desc2" ...
    $TUI --title "$1" --menu "$2" 15 60 8 \
        "${@:3}" 2> "$TMP"
    cat "$TMP"
}

checklist_box() {
    # Usage: checklist_box "Title" "Prompt text"  "tag" "desc" "on/off"  ...
    $TUI --title "$1" --checklist "$2" 20 60 12 \
        "${@:3}" 2> "$TMP"
    cat "$TMP"
}

progress_bar() {
    # Usage: progress_bar <percentage> <text>
    {
        for i in $(seq 0 "$1"); do
            echo "$i"
            sleep 0.02
        done
    } | $TUI --gauge "$2" 10 60 0
}

# ------------------------------
#  DEMO (you can delete this)
# ------------------------------
if [[ "${1:-}" == "--demo" ]]; then
    choice=$(menu_box "Main Menu" "Choose an option:" \
        1 "Show Message" \
        2 "Input Box" \
        3 "Show Checklist" \
        4 "Progress Bar" \
        0 "Exit")

    case $choice in
        1) msg_box "Hello" "This is a message box." ;;
        2) name=$(input_box "Name" "Enter your name:"); msg_box "You entered" "$name" ;;
        3)
            selected=$(checklist_box "Pick features" "Choose options:" \
                a "Feature A" on \
                b "Feature B" off \
                c "Feature C" on)
            msg_box "Selected" "$selected"
            ;;
        4) progress_bar 100 "Working..." ;;
    esac
fi

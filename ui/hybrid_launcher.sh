#!/usr/bin/env bash
# ============================================================================
# HYBRID TUI LAUNCHER (dialog + fzf)
# Fast fuzzy navigation + structured ncurses UI for actions
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# COLOR HELPERS FOR PREVIEW PANES
# ---------------------------------------------------------------------------
CY="\033[1;36m"
GR="\033[1;32m"
RD="\033[1;31m"
YL="\033[1;33m"
NC="\033[0m"

# ---------------------------------------------------------------------------
# DIALOG / WHIPTAIL FALLBACK
# ---------------------------------------------------------------------------
if command -v dialog >/dev/null 2>&1; then
    TUI=dialog
elif command -v whiptail >/dev/null 2>&1; then
    TUI=whiptail
else
    echo "ERROR: dialog or whiptail is required." >&2
    exit 1
fi

TMP=$(mktemp)
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

# ========================= TUI FORM/WIZARD HELPERS ===========================
msgbox()     { $TUI --title "$1" --msgbox "$2" 12 60; }
yesno()      { $TUI --title "$1" --yesno "$2" 10 60; }
inputbox()   { $TUI --title "$1" --inputbox "$2" 10 60 2>"$TMP"; cat "$TMP"; }
menu_box()   { $TUI --title "$1" --menu "$2" 22 70 14 "${@:3}" 2>"$TMP"; cat "$TMP"; }

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPTS_DIR="tools/scripts"
PRESETS_DIR="presets"
ARTIFACTS_DIR="artifacts"
LOGS_DIR="logs"

# ============================================================================
# SAFETY CONFIRMATION FOR DESTRUCTIVE OPS
# ============================================================================
safety_lock() {
    yesno "Safety Check" \
"⚠️  This action can modify files or directories.

Are you ABSOLUTELY sure you want to continue?"

}

# ============================================================================
# ACTION EXECUTION HANDLERS
# ============================================================================
run_script() {
    local script="$1"
    if [[ ! -x "$script" ]]; then
        msgbox "Error" "Script '$script' is not executable."
        return
    fi

    yesno "Run Script" "Run '$script' now?" || return
    "$script"
    msgbox "Completed" "'$script' has finished execution."
}

browse_artifacts() {
    find "$ARTIFACTS_DIR" -type f 2>/dev/null |
        fzf --prompt="Artifacts > " \
            --preview 'head -100 {}' \
            --preview-window=down:60%
}

browse_logs() {
    find "$LOGS_DIR" -type f 2>/dev/null |
        fzf --prompt="Logs > " \
            --preview 'sed -n "1,200p" {}'
}

run_preset() {
    local preset="$1"
    msgbox "Preset" "Running preset: $preset"

    # Load preset (JSON or key=value)
    # Here you can customize logic matching your JSIG tools

    if [[ "$preset" == *.sh ]]; then
        run_script "$preset"
        return
    fi

    msgbox "WIP" "Preset handler not implemented yet."
}

# ============================================================================
# PREVIEW ENGINE FOR FZF
# ============================================================================
preview_item() {
    local line="$1"
    local target="${line##*::}"

    case "$target" in
        scripts)
            echo -e "${CY}Scripts:${NC}"
            ls -lt "$SCRIPTS_DIR"
            ;;
        presets)
            echo -e "${CY}Presets:${NC}"
            ls -lt "$PRESETS_DIR"
            ;;
        artifacts)
            echo -e "${CY}Artifacts:${NC}"
            ls -lt "$ARTIFACTS_DIR" | head
            ;;
        logs)
            echo -e "${CY}Logs:${NC}"
            ls -lt "$LOGS_DIR" | head
            ;;
        *)
            if [[ -f "$target" ]]; then
                echo -e "${CY}File Preview:${NC}"
                sed -n '1,120p' "$target"
            else
                echo "No preview available"
            fi
            ;;
    esac
}

# ============================================================================
# TOP-LEVEL MENU ITEMS
# ============================================================================
MAIN_MENU=(
  "Run Script                ::scripts"
  "Run Preset                ::presets"
  "Browse Artifacts          ::artifacts"
  "Browse Logs               ::logs"
  "Safety Lock Test          ::destructive"
  "Exit                      ::exit"
)

# ============================================================================
# MAIN FZF LAUNCHER
# ============================================================================
main_selector() {
    printf "%s\n" "${MAIN_MENU[@]}" |
        fzf --ansi \
            --prompt="Launcher > " \
            --header="Hybrid TUI Launcher — fzf + dialog" \
            --preview='bash -c "preview_item \"{}\""'
}

# ============================================================================
# MAIN LOOP
# ============================================================================
while true; do
    choice=$(main_selector)
    [[ -z "$choice" ]] && exit 0

    action="${choice##*::}"

    case "$action" in

        scripts)
            sel=$(find "$SCRIPTS_DIR" -maxdepth 1 -type f |
                  fzf --prompt="Scripts > " --preview 'sed -n "1,200p" {}')
            [[ -n "$sel" ]] && run_script "$sel"
            ;;

        presets)
            sel=$(find "$PRESETS_DIR" -maxdepth 1 -type f |
                  fzf --prompt="Presets > " --preview 'sed -n "1,200p" {}')
            [[ -n "$sel" ]] && run_preset "$sel"
            ;;

        artifacts)
            browse_artifacts
            ;;

        logs)
            browse_logs
            ;;

        destructive)
            safety_lock && msgbox "Confirmed" "Destructive action allowed (simulation)."
            ;;

        exit)
            exit 0
            ;;
    esac
done

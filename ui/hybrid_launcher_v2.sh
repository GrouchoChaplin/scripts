#!/usr/bin/env bash
# =============================================================================
# Hybrid Launcher v2.0 (dialog + fzf)
#
# Features:
#   - fzf-based top-level launcher with previews
#   - dialog/whiptail ncurses-style prompts (yes/no, menus, etc.)
#   - Auto-discovery of tools from tools/scripts (with optional @tool metadata)
#   - Preset runner with placeholder expansion (${TODAY}, ${LATEST_JSON}, etc.)
#   - Artifact & log browser with previews and HTML open via xdg-open
#   - Recent-runs history viewer (stored in ~/.hybrid_launcher_runs.log)
#   - Project Doctor (basic environment diagnostics)
#   - Auto-Fix hook (optional external script)
#   - Plugin-style design: dropping new scripts into tools/scripts makes them available
#   - Status bar with time, hostname, git branch, disk usage
#   - Light theming support via HL_THEME env var
#
# Requirements:
#   - bash, fzf, dialog or whiptail, sed, awk, find, date, df, git (optional)
#
# Intended layout (but configurable below):
#   tools/scripts/    -> tool shell scripts
#   presets/          -> preset .conf/.sh files
#   artifacts/        -> generated outputs (JSON, HTML, etc.)
#   logs/             -> log files
#
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# BASIC CONFIG
# -----------------------------------------------------------------------------
LAUNCHER_NAME="Hybrid Launcher v2.0"

# Base directory: try git root, fallback to current directory
if ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null); then
    :
else
    ROOT_DIR="$(pwd)"
fi

SCRIPTS_DIR="$ROOT_DIR/tools/scripts"
PRESETS_DIR="$ROOT_DIR/presets"
ARTIFACTS_DIR="$ROOT_DIR/artifacts"
LOGS_DIR="$ROOT_DIR/logs"

RUN_LOG="${HOME}/.hybrid_launcher_runs.log"

# Optional external scripts (if they exist, they’re used)
AUTO_FIX_SCRIPT="$SCRIPTS_DIR/auto_fix.sh"
DOCTOR_EXTRA_SCRIPT="$SCRIPTS_DIR/doctor_extra.sh"

# Ensure core directories exist (don’t fail if missing; just create)
mkdir -p "$SCRIPTS_DIR" "$PRESETS_DIR" "$ARTIFACTS_DIR" "$LOGS_DIR"

# -----------------------------------------------------------------------------
# THEME (colors for previews / status line)
#   HL_THEME can be: default | mono | retro
# -----------------------------------------------------------------------------
HL_THEME="${HL_THEME:-default}"

case "$HL_THEME" in
    retro)
        C_PRIMARY="\033[0;32m"   # dim green
        C_ACCENT="\033[1;32m"
        C_WARN="\033[1;33m"
        C_ERROR="\033[1;31m"
        C_RESET="\033[0m"
        ;;
    mono)
        C_PRIMARY=""
        C_ACCENT=""
        C_WARN=""
        C_ERROR=""
        C_RESET=""
        ;;
    *)
        # default
        C_PRIMARY="\033[1;36m"
        C_ACCENT="\033[1;32m"
        C_WARN="\033[1;33m"
        C_ERROR="\033[1;31m"
        C_RESET="\033[0m"
        ;;
esac

# -----------------------------------------------------------------------------
# REQUIREMENTS CHECK
# -----------------------------------------------------------------------------
command -v fzf    >/dev/null 2>&1 || { echo "ERROR: fzf is required."; exit 1; }

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

# -----------------------------------------------------------------------------
# DIALOG HELPERS
# -----------------------------------------------------------------------------
msgbox() {
    $TUI --title "$1" --msgbox "$2" 12 70
}

yesno() {
    $TUI --title "$1" --yesno "$2" 10 70
}

inputbox() {
    $TUI --title "$1" --inputbox "$2" 10 70 2>"$TMP" || return 1
    cat "$TMP"
}

menu_box() {
    # Usage: menu_box "Title" "Prompt" "tag1" "item1" "tag2" "item2" ...
    $TUI --title "$1" --menu "$2" 22 70 14 "${@:3}" 2>"$TMP" || return 1
    cat "$TMP"
}

# -----------------------------------------------------------------------------
# STATUS LINE (for fzf header)
# -----------------------------------------------------------------------------
status_line() {
    local now host branch disk
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    host="$(hostname -s 2>/dev/null || echo 'host')"

    if branch=$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null); then
        :
    else
        branch="no-git"
    fi

    disk=$(df -h "$ROOT_DIR" 2>/dev/null | awk 'NR==2 {print $4 " free"}')

    printf "%s[%s]%s %s | %s | %s\n" \
        "$C_PRIMARY" "$LAUNCHER_NAME" "$C_RESET" "$now@$host" "$branch" "$disk"
}

# -----------------------------------------------------------------------------
# SAFETY LOCK
# -----------------------------------------------------------------------------
safety_lock() {
    yesno "Safety Check" \
"⚠ This action may modify or delete files.

Are you absolutely sure you want to continue?"
}

# -----------------------------------------------------------------------------
# RUN LOGGING
# -----------------------------------------------------------------------------
log_run() {
    local type="$1" name="$2" status="$3"
    local ts
    ts="$(date --iso-8601=seconds)"
    printf "%s | %-8s | %-10s | %s\n" "$ts" "$type" "$status" "$name" >> "$RUN_LOG"
}

view_recent_runs() {
    if [[ ! -f "$RUN_LOG" ]]; then
        msgbox "Recent Runs" "No runs logged yet."
        return
    fi

    # fzf viewer over recent runs
    tac "$RUN_LOG" | fzf --prompt="Recent Runs > " \
        --header="$(status_line)" \
        --preview "echo {}" \
        --preview-window=down:3:wrap
}

# -----------------------------------------------------------------------------
# PLACEHOLDER / PRESET SUPPORT
#   Supported placeholders in preset values:
#     ${TODAY}        -> YYYY-MM-DD
#     ${NOW}          -> YYYYMMDD_HHMMSS
#     ${LATEST_JSON}  -> newest *.json in artifacts/
#     ${LATEST_HTML}  -> newest *.html in artifacts/
#     ${ROOT_DIR}     -> root of project
# -----------------------------------------------------------------------------
compute_placeholders() {
    TODAY="$(date '+%Y-%m-%d')"
    NOW="$(date '+%Y%m%d_%H%M%S')"

    LATEST_JSON="$(find "$ARTIFACTS_DIR" -type f -name '*.json' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | awk '{print $2}')"
    LATEST_HTML="$(find "$ARTIFACTS_DIR" -type f -name '*.htm*' -printf '%T@ %p\n' 2>/dev/null \
        | sort -nr | head -1 | awk '{print $2}')"

    export TODAY NOW LATEST_JSON LATEST_HTML ROOT_DIR
}

apply_placeholders() {
    # Expand environment variables in a string
    local input="$1"
    eval "printf '%s' \"$input\""
}

# -----------------------------------------------------------------------------
# TOOL DISCOVERY
#   Uses optional metadata in first lines of script:
#     # @tool: Friendly Name
#     # @category: build / analyze / misc / etc.
# -----------------------------------------------------------------------------
discover_tools() {
    find "$SCRIPTS_DIR" -maxdepth 1 -type f -perm -u+x 2>/dev/null | sort
}

tool_label_from_file() {
    local file="$1"
    local label
    label=$(sed -n '1,10p' "$file" | awk -F': ' '/^# @tool:/ {print $2; exit}')
    if [[ -z "${label:-}" ]]; then
        label="$(basename "$file")"
    fi
    printf "%s\n" "$label"
}

tool_category_from_file() {
    local file="$1"
    local cat
    cat=$(sed -n '1,10p' "$file" | awk -F': ' '/^# @category:/ {print $2; exit}')
    [[ -z "${cat:-}" ]] && cat="misc"
    printf "%s\n" "$cat"
}

run_tool() {
    local script="$1"
    if [[ ! -x "$script" ]]; then
        msgbox "Error" "Script '$script' is not executable."
        log_run "tool" "$script" "NOEXEC"
        return
    fi

    yesno "Run Tool" "Run tool: $(basename "$script") ?" || { log_run "tool" "$script" "CANCEL"; return; }

    if "$script"; then
        msgbox "Tool Completed" "Tool '$(basename "$script")' finished successfully."
        log_run "tool" "$script" "OK"
    else
        msgbox "Tool Failed" "Tool '$(basename "$script")' returned an error."
        log_run "tool" "$script" "FAIL"
    fi
}

select_and_run_tool() {
    local tools tool label cat selection
    tools=$(discover_tools)
    [[ -z "$tools" ]] && { msgbox "Tools" "No executable scripts found in $SCRIPTS_DIR"; return; }

    # Build annotated list: "Label [category] :: /full/path"
    selection=$(while IFS= read -r t; do
        label=$(tool_label_from_file "$t")
        cat=$(tool_category_from_file "$t")
        printf "%s [%s] :: %s\n" "$label" "$cat" "$t"
    done <<< "$tools" | \
        fzf --ansi \
            --with-nth=1,2 \
            --delimiter='::' \
            --prompt="Tools > " \
            --header="$(status_line)" \
            --preview 'sed -n "1,120p" "$(echo {} | sed "s/.*:: //")"' \
            --preview-window=right:60%)

    [[ -z "${selection:-}" ]] && return

    tool="${selection##*:: }"
    run_tool "$tool"
}

# -----------------------------------------------------------------------------
# PRESET HANDLING
#   Presets are shell-style config files in $PRESETS_DIR.
#   A preset MAY define:
#     PRESET_NAME="Friendly name"
#     PRESET_DESC="Description"
#     PRESET_CMD="tools/scripts/some_tool.sh --input ${LATEST_JSON} --date ${TODAY}"
# -----------------------------------------------------------------------------
discover_presets() {
    find "$PRESETS_DIR" -maxdepth 1 -type f \( -name '*.conf' -o -name '*.sh' -o -name '*.preset' \) 2>/dev/null | sort
}

preset_label() {
    local file="$1" name
    name=$(awk -F'=' '/^PRESET_NAME=/{sub(/^PRESET_NAME=/,""); gsub(/^"|\"$/,""); print; exit}' "$file" 2>/dev/null || true)
    [[ -z "${name:-}" ]] && name="$(basename "$file")"
    printf "%s\n" "$name"
}

preset_desc() {
    local file="$1" desc
    desc=$(awk -F'=' '/^PRESET_DESC=/{sub(/^PRESET_DESC=/,""); gsub(/^"|\"$/,""); print; exit}' "$file" 2>/dev/null || true)
    printf "%s\n" "${desc:-""}"
}

run_preset_file() {
    local file="$1"
    compute_placeholders

    # shell-style: source it in a subshell to avoid polluting caller environment too much
    (
        set -a
        # shellcheck disable=SC1090
        source "$file"
        set +a

        if [[ -z "${PRESET_CMD:-}" ]]; then
            echo "Preset '$file' has no PRESET_CMD defined." >&2
            exit 1
        fi

        # Apply placeholder expansion
        CMD_EXPANDED=$(apply_placeholders "$PRESET_CMD")
        echo "Running preset command:"
        echo "  $CMD_EXPANDED"
        echo

        if eval "$CMD_EXPANDED"; then
            exit 0
        else
            exit 1
        fi
    )
}

select_and_run_preset() {
    local presets selection file label desc
    presets=$(discover_presets)
    [[ -z "$presets" ]] && { msgbox "Presets" "No presets found in $PRESETS_DIR"; return; }

    selection=$(while IFS= read -r p; do
        label=$(preset_label "$p")
        desc=$(preset_desc "$p")
        printf "%s :: %s :: %s\n" "$label" "$desc" "$p"
    done <<< "$presets" | \
        fzf --ansi \
            --with-nth=1,2 \
            --delimiter='::' \
            --prompt="Presets > " \
            --header="$(status_line)" \
            --preview 'sed -n "1,120p" "$(echo {} | awk -F"::" "{gsub(/^ /,\"\"); print \$3}")"' \
            --preview-window=right:60%)

    [[ -z "${selection:-}" ]] && return

    file="$(echo "$selection" | awk -F'::' '{gsub(/^ /,"",$3); print $3}')"

    yesno "Run Preset" "Run preset: $(preset_label "$file") ?" || { log_run "preset" "$file" "CANCEL"; return; }

    if run_preset_file "$file"; then
        msgbox "Preset Completed" "Preset '$(preset_label "$file")' ran successfully."
        log_run "preset" "$file" "OK"
    else
        msgbox "Preset Failed" "Preset '$(preset_label "$file")' failed."
        log_run "preset" "$file" "FAIL"
    fi
}

# -----------------------------------------------------------------------------
# ARTIFACT & LOG BROWSERS
# -----------------------------------------------------------------------------
browse_artifacts() {
    local sel
    sel=$(find "$ARTIFACTS_DIR" -type f 2>/dev/null | sort \
        | fzf --prompt="Artifacts > " \
              --header="$(status_line)" \
              --preview 'file="{}"; case "$file" in *.json) jq -C . "$file" 2>/dev/null || head -100 "$file";; *.htm*|*.md) head -100 "$file";; *) head -100 "$file";; esac' \
              --preview-window=right:60%)

    [[ -z "${sel:-}" ]] && return

    case "$sel" in
        *.html|*.htm)
            if command -v xdg-open >/dev/null 2>&1; then
                yesno "Open HTML" "Open '$sel' in browser using xdg-open?" && xdg-open "$sel" >/dev/null 2>&1 &
            else
                msgbox "Open HTML" "xdg-open not found; cannot auto-open."
            fi
            ;;
        *)
            msgbox "Artifact Selected" "$sel"
            ;;
    esac
}

browse_logs() {
    local sel
    sel=$(find "$LOGS_DIR" -type f 2>/dev/null | sort \
        | fzf --prompt="Logs > " \
              --header="$(status_line)" \
              --preview 'sed -n "1,200p" "{}"' \
              --preview-window=right:60%)

    [[ -z "${sel:-}" ]] && return
    msgbox "Log Selected" "$sel"
}

# -----------------------------------------------------------------------------
# PROJECT DOCTOR
#   Basic checks; extended checks delegated to DOCTOR_EXTRA_SCRIPT if present.
# -----------------------------------------------------------------------------
run_doctor() {
    local report
    report="$(mktemp)"

    {
        echo "=== PROJECT DOCTOR REPORT ==="
        echo "Timestamp: $(date --iso-8601=seconds)"
        echo "Root Dir: $ROOT_DIR"
        echo

        echo "1) Git status"
        if command -v git >/dev/null 2>&1; then
            git -C "$ROOT_DIR" status --short || echo "git status failed."
        else
            echo "git not installed."
        fi
        echo

        echo "2) Disk space (root dir device)"
        df -h "$ROOT_DIR" || echo "df failed."
        echo

        echo "3) Required tools"
        for c in fzf "$TUI" sed awk find; do
            if command -v "$c" >/dev/null 2>&1; then
                echo "OK: $c"
            else
                echo "MISSING: $c"
            fi
        done
        echo

        echo "4) Scripts/Presets/Artifacts/Logs structure"
        for d in "$SCRIPTS_DIR" "$PRESETS_DIR" "$ARTIFACTS_DIR" "$LOGS_DIR"; do
            if [[ -d "$d" ]]; then
                echo "OK: $d"
            else
                echo "MISSING: $d"
            fi
        done
        echo

        if [[ -x "$DOCTOR_EXTRA_SCRIPT" ]]; then
            echo "5) Extra doctor script: $DOCTOR_EXTRA_SCRIPT"
            "$DOCTOR_EXTRA_SCRIPT" || echo "Extra doctor script returned non-zero."
            echo
        fi
    } > "$report"

    # Show via fzf or pager-style preview
    fzf --preview "sed -n '1,200p' '$report'" --header="Project Doctor (press ESC to exit)" <<< "Close" >/dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# AUTO-FIX
#   Calls external script if present and confirmed via safety_lock.
# -----------------------------------------------------------------------------
run_auto_fix() {
    if [[ ! -x "$AUTO_FIX_SCRIPT" ]]; then
        msgbox "Auto-Fix" "No auto-fix script found at $AUTO_FIX_SCRIPT"
        return
    fi

    safety_lock || return

    if "$AUTO_FIX_SCRIPT"; then
        msgbox "Auto-Fix" "Auto-Fix completed successfully."
    else
        msgbox "Auto-Fix" "Auto-Fix encountered errors."
    fi
}

# -----------------------------------------------------------------------------
# SETTINGS / INFO
# -----------------------------------------------------------------------------
settings_panel() {
    local choice
    choice=$(menu_box "Settings" "Launcher settings / info:" \
        1 "View configuration paths" \
        2 "View recent runs log path" \
        3 "Show theme info" \
        0 "Back to main menu") || return

    case "$choice" in
        1)
            msgbox "Config Paths" "ROOT_DIR:      $ROOT_DIR
SCRIPTS_DIR:   $SCRIPTS_DIR
PRESETS_DIR:   $PRESETS_DIR
ARTIFACTS_DIR: $ARTIFACTS_DIR
LOGS_DIR:      $LOGS_DIR"
            ;;
        2)
            msgbox "Run Log Path" "$RUN_LOG"
            ;;
        3)
            msgbox "Theme" "Current theme: $HL_THEME

Set HL_THEME to one of:
  - default
  - mono
  - retro

Example:
  HL_THEME=retro ./hybrid_launcher_v2.sh"
            ;;
        *)
            ;;
    esac
}

# -----------------------------------------------------------------------------
# MAIN MENU (via fzf)
# -----------------------------------------------------------------------------
main_menu_fzf() {
    cat <<EOF
Run Tool                 :: tools
Run Preset               :: presets
Browse Artifacts         :: artifacts
Browse Logs              :: logs
Recent Runs              :: recent
Project Doctor           :: doctor
Auto-Fix (if available)  :: autofix
Settings / Info          :: settings
Exit                     :: exit
EOF
}

main_loop() {
    while true; do
        selection=$(main_menu_fzf | \
            fzf --ansi \
                --prompt="Launcher > " \
                --with-nth=1 \
                --delimiter='::' \
                --header="$(status_line)" \
                --preview 'echo -e "'"$C_ACCENT"'Action: $(echo {} | cut -d"::" -f1)'"$C_RESET"'\n\nRoot: '"$ROOT_DIR"'\nScripts: '"$SCRIPTS_DIR"'\nPresets: '"$PRESETS_DIR"'\nArtifacts: '"$ARTIFACTS_DIR"'\nLogs: '"$LOGS_DIR" \
                --preview-window=down:8:wrap)

        [[ -z "${selection:-}" ]] && exit 0

        action="$(echo "$selection" | awk -F'::' '{gsub(/^ /,"",$2); print $2}')"

        case "$action" in
            tools)
                select_and_run_tool
                ;;
            presets)
                select_and_run_preset
                ;;
            artifacts)
                browse_artifacts
                ;;
            logs)
                browse_logs
                ;;
            recent)
                view_recent_runs
                ;;
            doctor)
                run_doctor
                ;;
            autofix)
                run_auto_fix
                ;;
            settings)
                settings_panel
                ;;
            exit)
                exit 0
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# ENTRY POINT
# -----------------------------------------------------------------------------
main_loop

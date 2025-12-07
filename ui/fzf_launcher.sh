#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fzf-powered launcher panel
# Reusable interactive selector with dynamic actions
# ---------------------------------------------------------------------------

set -euo pipefail

# Colors for headers inside the preview pane
CYAN="\033[1;36m"
RESET="\033[0m"

# Main launcher menu entries
MENU_ITEMS=(
  "Run RPM Sanity Check    ::tools/scripts/rpm_sanity_check.sh"
  "Run Build & Verify      ::tools/scripts/build_verify.sh"
  "Run Diagnostics         ::tools/scripts/diagnostics.sh"
  "Browse Recent Artifacts ::browse_artifacts"
  "Browse Logs             ::browse_logs"
  "Exit                    ::exit"
)

# Preview function
preview_cmd() {
    local entry="$1"
    local command="${entry##*::}"

    case "$command" in
        browse_artifacts)
            echo -e "${CYAN}Browsing recent artifacts...${RESET}"
            ls -lt artifacts/ | head
            ;;
        browse_logs)
            echo -e "${CYAN}Latest logs:${RESET}"
            ls -lt logs/ | head
            ;;
        *)
            echo -e "${CYAN}Script contents:${RESET}"
            sed -n '1,200p' "$command" 2>/dev/null || echo "No preview available."
            ;;
    esac
}

# Main selector
selection=$(printf "%s\n" "${MENU_ITEMS[@]}" |
    fzf --ansi --prompt="Launcher > " \
        --header="Select a command to run" \
        --preview='bash -c "preview_cmd \"{}\""')

[[ -z "$selection" ]] && exit 0

COMMAND="${selection##*::}"

case "$COMMAND" in
    browse_artifacts)
        find artifacts/ -type f | fzf --preview 'head -50 {}'
        ;;
    browse_logs)
        find logs/ -type f | fzf --preview 'sed -n "1,200p" {}'
        ;;
    exit)
        exit 0
        ;;
    *)
        bash "$COMMAND"
        ;;
esac

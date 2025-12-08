\
#!/usr/bin/env bash
# dart_backup_launcher_full_v1.6.sh
# Full TUI-style launcher for Dart Backup Reconciliation Toolkit
#
# Features:
#   - Preset browser (from presets.d/*.conf)
#   - Analyzer / Reconstructor / Comparer runners
#   - Automatic per-preset log naming (logs/)
#   - Run history (~/.dart_backup_history + .dart_backup_history in CWD)
#   - Recent artifacts browser (JSON/CSV/HTML)
#   - Analyzer stats viewer (from logs)
#   - Dashboard summary export to Markdown (Obsidian-friendly)
#   - Safety lock for reconstructor runs that target non-empty --out dirs
#   - Optional fzf menus (fallback to numbered)
#
set -euo pipefail

VERSION="1.6"

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="${SCRIPT_PATH%/scripts}"
PRESETS_DIR_DEFAULT="${TOOL_ROOT}/presets.d"
PRESETS_DIR="${DART_BACKUP_PRESETS_DIR:-$PRESETS_DIR_DEFAULT}"

CWD="$(pwd)"
LOG_DIR="${CWD}/logs"
LOCAL_HISTORY="${CWD}/.dart_backup_history"
GLOBAL_HISTORY="${HOME}/.dart_backup_history"

mkdir -p "$LOG_DIR"

now_iso() { date +"%Y-%m-%d %H:%M:%S"; }
today_ymd() { date +"%Y%m%d"; }
now_stamp() { date +"%Y%m%d_%H%M%S"; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

log_history() {
  local line="$1"
  echo "$line" >> "$LOCAL_HISTORY"
  echo "$line" >> "$GLOBAL_HISTORY"
}

info() { printf "\e[36m[INFO]\e[0m %s\n" "$*"; }
warn() { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
err()  { printf "\e[31m[ERR]\e[0m %s\n" "$*"; }

press_enter() { read -rp "Press ENTER to continue..." _; }

pick_from_list() {
  local items=("$@")
  local n="${#items[@]}"
  if (( n == 0 )); then
    echo ""
    return 1
  fi

  if has_cmd fzf; then
    local choice
    choice=$(printf '%s\n' "${items[@]}" | fzf --prompt="Select: " --height=20) || {
      echo ""
      return 1
    }
    echo "$choice"
    return 0
  fi

  local i
  for ((i=0; i<n; i++)); do
    printf "%2d) %s\n" $((i+1)) "${items[$i]}"
  done
  printf " q) Cancel\n"
  read -rp "Select: " ans
  if [[ "$ans" == "q" || "$ans" == "Q" ]]; then
    echo ""
    return 1
  fi
  if ! [[ "$ans" =~ ^[0-9]+$ ]]; then
    echo ""
    return 1
  fi
  if (( ans < 1 || ans > n )); then
    echo ""
    return 1
  fi
  echo "${items[$((ans-1))]}"
}

list_preset_files() {
  [[ -d "$PRESETS_DIR" ]] || return 1
  find "$PRESETS_DIR" -maxdepth 1 -type f -name "*.conf" | sort
}

describe_preset() {
  local file="$1"
  (
    unset PRESET_NAME PRESET_DESC ANALYZER_CMD RECON_LATEST_CMD RECON_FULL_CMD
    # shellcheck source=/dev/null
    source "$file"
    local name="${PRESET_NAME:-$(basename "$file")}"
    local desc="${PRESET_DESC:-"(no description)"}"

    local last_run=""
    if [[ -f "$GLOBAL_HISTORY" ]]; then
      last_run=$(grep -F "PRESET=${name}:" "$GLOBAL_HISTORY" 2>/dev/null | tail -n1 | cut -d'|' -f1 | xargs || true)
    fi
    if [[ -z "$last_run" && -f "$LOCAL_HISTORY" ]]; then
      last_run=$(grep -F "PRESET=${name}:" "$LOCAL_HISTORY" 2>/dev/null | tail -n1 | cut -d'|' -f1 | xargs || true)
    fi
    printf '%s|%s|%s|%s\n' "$name" "$desc" "$last_run" "$file"
  )
}

expand_dynamic_vars() {
  TODAY=$(today_ymd)
  NOW=$(now_stamp)
  LATEST_JSON=""
  LATEST_CSV=""

  local j c
  j=$(find . -maxdepth 5 -type f -name "*.json" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | awk '{ $1=""; sub(/^ /,""); print }' || true)
  c=$(find . -maxdepth 5 -type f -name "*.csv"  -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | awk '{ $1=""; sub(/^ /,""); print }' || true)
  [[ -n "$j" ]] && LATEST_JSON="$j"
  [[ -n "$c" ]] && LATEST_CSV="$c"
}

parse_out_dir_from_cmd() {
  local cmd="$1"
  local prev="" token
  for token in $cmd; do
    if [[ "$prev" == "--out" ]]; then
      token="${token%\"}"
      token="${token#\"}"
      echo "$token"
      return 0
    fi
    prev="$token"
  done
  echo ""
}

safety_lock_for_out_dir() {
  local out="$1"
  if [[ -z "$out" ]]; then
    return 0
  fi
  if [[ -d "$out" ]]; then
    if [[ -n "$(ls -A "$out" 2>/dev/null || true)" ]]; then
      echo
      warn "SAFETY LOCK: Output directory '$out' exists and is NOT empty."
      echo "This could overwrite or mix files."
      read -rp "Type EXACTLY 'YES' to proceed anyway: " ans
      if [[ "$ans" != "YES" ]]; then
        warn "Aborted by user."
        return 1
      fi
    fi
  fi
  return 0
}

run_with_logging() {
  local preset_name="$1"
  local mode="$2"
  local cmd="$3"

  expand_dynamic_vars

  local ts start end dur
  ts=$(now_iso)
  start=$(date +%s)
  local safe_preset="${preset_name// /_}"
  local stamp
  stamp=$(now_stamp)
  local logfile="${LOG_DIR}/${safe_preset}_${mode}_${stamp}.log"

  info "Running preset '${preset_name}' mode=${mode}"
  info "Logging to: $logfile"
  echo "Command:"
  echo "  $cmd"
  echo

  TODAY="$TODAY" NOW="$NOW" LATEST_JSON="$LATEST_JSON" LATEST_CSV="$LATEST_CSV" \
  PRESET_NAME="$preset_name" MODE="$mode" \
  bash -c "$cmd" 2>&1 | tee "$logfile"
  local rc=${PIPESTATUS[0]}
  end=$(date +%s)
  dur=$(( end - start ))

  local hist_line
  hist_line="$(now_iso) | DUR=${dur}s | PRESET=${preset_name}:${mode} | RC=${rc} | CMD=$cmd"
  log_history "$hist_line"

  if [[ $rc -ne 0 ]]; then
    err "Command exited with code $rc"
  else
    info "Completed in ${dur}s"
  fi
  echo
  return $rc
}

preset_menu() {
  local name="$1"
  local desc="$2"
  local conf="$3"

  unset PRESET_NAME PRESET_DESC ANALYZER_CMD RECON_LATEST_CMD RECON_FULL_CMD
  # shellcheck source=/dev/null
  source "$conf"
  local pname="${PRESET_NAME:-$name}"
  local pdesc="${PRESET_DESC:-$desc}"

  while true; do
    clear
    echo "Preset: $pname"
    echo "$pdesc"
    echo "Config: $conf"
    echo
    echo "1) Run Analyzer"
    echo "2) Run Reconstructor (latest-only)"
    echo "3) Run Reconstructor (full history)"
    echo "4) Show preset commands"
    echo "q) Back"
    echo
    read -rp "Select: " ans
    case "$ans" in
      1)
        if [[ -z "${ANALYZER_CMD:-}" ]]; then
          err "ANALYZER_CMD not defined in preset."
          press_enter
        else
          run_with_logging "$pname" "ANALYZER" "$ANALYZER_CMD"
          press_enter
        fi
        ;;
      2)
        if [[ -z "${RECON_LATEST_CMD:-}" ]]; then
          err "RECON_LATEST_CMD not defined in preset."
          press_enter
        else
          local outdir
          outdir=$(parse_out_dir_from_cmd "$RECON_LATEST_CMD")
          if ! safety_lock_for_out_dir "$outdir"; then
            press_enter
          else
            run_with_logging "$pname" "RECON_LATEST" "$RECON_LATEST_CMD"
            press_enter
          fi
        fi
        ;;
      3)
        if [[ -z "${RECON_FULL_CMD:-}" ]]; then
          err "RECON_FULL_CMD not defined in preset."
          press_enter
        else
          local outdir
          outdir=$(parse_out_dir_from_cmd "$RECON_FULL_CMD")
          if ! safety_lock_for_out_dir "$outdir"; then
            press_enter
          else
            run_with_logging "$pname" "RECON_FULL" "$RECON_FULL_CMD"
            press_enter
          fi
        fi
        ;;
      4)
        clear
        echo "ANALYZER_CMD:"
        echo "  ${ANALYZER_CMD:-<not set>}"
        echo
        echo "RECON_LATEST_CMD:"
        echo "  ${RECON_LATEST_CMD:-<not set>}"
        echo
        echo "RECON_FULL_CMD:"
        echo "  ${RECON_FULL_CMD:-<not set>}"
        echo
        press_enter
        ;;
      q|Q)
        return
        ;;
      *)
        ;;
    esac
  done
}

browse_presets() {
  local files
  IFS=$'\n' read -r -d '' -a files < <(list_preset_files && printf '\0') || true
  if (( ${#files[@]} == 0 )); then
    err "No presets found in $PRESETS_DIR"
    press_enter
    return
  fi

  local display_items=()
  local map_lines=()
  local line name desc last_run conf path rest
  for path in "${files[@]}"; do
    line=$(describe_preset "$path")
    name=${line%%|*}
    rest=${line#*|}
    desc=${rest%%|*}
    rest=${rest#*|}
    last_run=${rest%%|*}
    conf=${rest#*|}
    [[ -z "$last_run" ]] && last_run="(never run)"
    display_items+=("${name} :: ${desc} :: last: ${last_run}")
    map_lines+=("$line")
  done

  clear
  echo "Preset Browser (v$VERSION)"
  echo "Presets directory: $PRESETS_DIR"
  echo

  local choice
  choice=$(pick_from_list "${display_items[@]}") || return
  [[ -z "$choice" ]] && return

  local idx=-1 i
  for ((i=0; i<${#display_items[@]}; i++)); do
    if [[ "${display_items[$i]}" == "$choice" ]]; then
      idx=$i; break
    fi
  done
  (( idx < 0 )) && return

  line="${map_lines[$idx]}"
  name=${line%%|*}
  rest=${line#*|}
  desc=${rest%%|*}
  rest=${rest#*|}
  last_run=${rest%%|*}
  conf=${rest#*|}

  preset_menu "$name" "$desc" "$conf"
}

artifacts_browser() {
  clear
  echo "Recent Artifacts Browser (JSON/CSV/HTML)"
  echo

  local lines
  IFS=$'\n' read -r -d '' -a lines < <(find . -maxdepth 5 -type f \( -name "*.json" -o -name "*.csv" -o -name "*.html" \) -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n 100 | awk '{ $1=""; sub(/^ /,""); print }' && printf '\0') || true
  if (( ${#lines[@]} == 0 )); then
    warn "No artifacts found."
    press_enter
    return
  fi

  local choice
  choice=$(pick_from_list "${lines[@]}") || return
  [[ -z "$choice" ]] && return
  local path="$choice"
  path="${path#./}"

  echo
  info "Selected: $path"
  if [[ "$path" == *.html ]]; then
    if has_cmd xdg-open; then
      info "Opening in browser..."
      xdg-open "$path" >/dev/null 2>&1 || true
    else
      warn "xdg-open not found; cannot auto-open."
    fi
  else
    echo
    echo "Preview (head -n 40):"
    echo "------------------------------------------------------------"
    head -n 40 "$path" || true
    echo "------------------------------------------------------------"
  fi
  press_enter
}

pick_log_file() {
  local logs
  IFS=$'\n' read -r -d '' -a logs < <(find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" 2>/dev/null | sort && printf '\0') || true
  if (( ${#logs[@]} == 0 )); then
    warn "No logs found in $LOG_DIR"
    return 1
  fi
  pick_from_list "${logs[@]}"
}

analyzer_stats_from_log() {
  clear
  echo "Analyzer Stats from Log"
  echo "Log dir: $LOG_DIR"
  echo

  local log
  log=$(pick_log_file) || { press_enter; return; }
  [[ -z "$log" ]] && { press_enter; return; }

  echo
  info "Analyzing: $log"
  local groups instances csv json
  groups=$(grep -c "^Group:" "$log" 2>/dev/null || echo 0)
  instances=$(grep -c "^Instances of group" "$log" 2>/dev/null || echo 0)
  csv=$(grep -F "CSV export written to:" "$log" 2>/dev/null | tail -n1 | sed 's/.*: //')
  json=$(grep -F "JSON export written to:" "$log" 2>/dev/null | tail -n1 | sed 's/.*: //')

  echo "Groups processed : ${groups}"
  echo "Instance blocks  : ${instances}"
  echo "CSV export       : ${csv:-<none>}"
  echo "JSON export      : ${json:-<none>}"
  echo
  echo "Last 10 log lines:"
  echo "------------------------------------------------------------"
  tail -n 10 "$log" || true
  echo "------------------------------------------------------------"
  press_enter
}

show_recent_history() {
  clear
  echo "Recent Runs (local + global)"
  echo

  echo "Local history: $LOCAL_HISTORY"
  [[ -f "$LOCAL_HISTORY" ]] && tail -n 20 "$LOCAL_HISTORY" || echo "  (none)"

  echo
  echo "Global history: $GLOBAL_HISTORY"
  [[ -f "$GLOBAL_HISTORY" ]] && tail -n 20 "$GLOBAL_HISTORY" || echo "  (none)"

  echo
  press_enter
}

export_dashboard_markdown() {
  clear
  echo "Export Dashboard Summary to Markdown"
  echo

  local ts today out
  today=$(today_ymd)
  ts=$(now_stamp)
  out="${CWD}/dashboard_summary_${today}.md"

  local latest_json latest_csv latest_html
  latest_json=$(find . -maxdepth 5 -type f -name "*.json" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | awk '{ $1=""; sub(/^ /,""); print }' || true)
  latest_csv=$(find . -maxdepth 5 -type f -name "*.csv"  -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | awk '{ $1=""; sub(/^ /,""); print }' || true)
  latest_html=$(find . -maxdepth 5 -type f -name "*.html" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -n1 | awk '{ $1=""; sub(/^ /,""); print }' || true)

  {
    echo "# Dart Backup Toolkit – Dashboard Summary ($(now_iso))"
    echo
    echo "## Recent Runs"
    echo
    if [[ -f "$LOCAL_HISTORY" ]]; then
      tail -n 20 "$LOCAL_HISTORY" | sed 's/^/- /'
    else
      echo "- (no local history yet)"
    fi
    echo
    echo "## Latest Artifacts"
    echo
    echo "- Latest JSON: ${latest_json:-none}"
    echo "- Latest CSV : ${latest_csv:-none}"
    echo "- Latest HTML: ${latest_html:-none}"
    echo
    echo "## Notes"
    echo
    echo "- Working directory: \`$CWD\`"
    echo "- Log directory    : \`$LOG_DIR\`"
  } > "$out"

  info "Dashboard written to: $out"
  press_enter
}

logs_dashboard_menu() {
  while true; do
    clear
    echo "Logs & Dashboard"
    echo "Working dir: $CWD"
    echo "Log dir    : $LOG_DIR"
    echo
    echo "1) Show recent history"
    echo "2) List log files"
    echo "3) Analyzer stats from a log"
    echo "4) Export dashboard summary to Markdown"
    echo "q) Back"
    echo
    read -rp "Select: " ans
    case "$ans" in
      1) show_recent_history ;;
      2)
        clear
        echo "Log files in: $LOG_DIR"
        echo
        ls -1 "$LOG_DIR" 2>/dev/null || echo "(none)"
        echo
        press_enter
        ;;
      3) analyzer_stats_from_log ;;
      4) export_dashboard_markdown ;;
      q|Q) return ;;
      *) ;;
    esac
  done
}

main_menu() {
  while true; do
    clear
    echo "Dart Backup Toolkit Launcher (FULL) v$VERSION"
    echo "Tool root : $TOOL_ROOT"
    echo "Presets   : $PRESETS_DIR"
    echo "CWD       : $CWD"
    echo "Logs      : $LOG_DIR"
    echo
    echo "1) Run Analyzer/Reconstructor via preset browser"
    echo "2) Recent Artifacts Browser (JSON/CSV/HTML)"
    echo "3) Logs & Dashboard"
    echo "4) Quick compare trees (manual)"
    echo "q) Quit"
    echo
    read -rp "Select: " ans
    case "$ans" in
      1) browse_presets ;;
      2) artifacts_browser ;;
      3) logs_dashboard_menu ;;
      4)
        clear
        echo "Quick Compare Trees"
        echo
        read -rp "Path to TREE A: " TA
        read -rp "Path to TREE B: " TB
        read -rp "Diff tool [meld|code|vimdiff|diff] (default: diff): " TOOL
        TOOL=${TOOL:-diff}
        echo
        info "Running compare_reconstructed_trees.sh '$TA' '$TB' --tool $TOOL"
        "${SCRIPT_PATH}/compare_reconstructed_trees.sh" "$TA" "$TB" --tool "$TOOL" || true
        press_enter
        ;;
      q|Q) break ;;
      *) ;;
    esac
  done
}

main_menu

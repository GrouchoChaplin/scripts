#
# lib/core.sh — core logic for compare_repo_variants_V5.6_Patch8_modular.sh
#
set -euo pipefail

# (Everything from the monolithic script **after** the shebang,
#  but with a small tweak: wrap the CLI+dispatch section into main().
#  I’ll inline it fully here.)

########################################
# Colors
########################################
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

color() {
    local c="$1"; shift
    echo -e "${c}$*${RESET}"
}

info()    { echo -e "🔍 $*"; }
warn()    { echo -e "⚠️  $*"; }
error()   { echo -e "❌ $*" >&2; }
success() { echo -e "✅ $*"; }

########################################
# Time helpers
########################################
fmt_ts() {
    local epoch="${1:-0}"
    if [[ -z "$epoch" || "$epoch" == "0" ]]; then
        echo "N/A"
        return
    fi
    date -d "@${epoch}" "+%Y-%m-%d %H:%M:%S"
}

now_ts() {
    date "+%Y-%m-%d_%H-%M-%S"
}

########################################
# Debug + feature flags (globals)
########################################
DEBUG_FIND=0
DEBUG_TEMP=0
DEBUG_SCAN=0
DEEP_COMPARE=0
HTML_ENABLED=0
HTML_FILE=""
LOG_ENABLED=0
LOG_FILE=""

debug_scan() {
    if [[ "$DEBUG_SCAN" -eq 1 ]]; then
        echo "[debug-scan] $*" >&2
    fi
}

########################################
# Git helpers
########################################
git_ahead() {
    local repo="$1"
    if git -C "$repo" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
        git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $2}'
    else
        echo 0
    fi
}

git_behind() {
    local repo="$1"
    if git -C "$repo" rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
        git -C "$repo" rev-list --left-right --count @{u}...HEAD 2>/dev/null | awk '{print $1}'
    else
        echo 0
    fi
}

########################################
# Repo discovery
########################################
find_repos() {
    local root="$1"
    local prefix="$2"
    local outfile="$3"

    : > "$outfile"

    if [[ ! -d "$root" ]]; then
        error "Root folder does not exist: $root"
        return 1
    fi

    while IFS= read -r -d '' d; do
        if [[ -d "$d/.git" ]]; then
            (( DEBUG_FIND )) && echo "   [debug-find] candidate repo: $d"
            echo "$d" >> "$outfile"
        else
            (( DEBUG_FIND )) && echo "   [debug-find] has name match but no .git: $d"
        fi
    done < <(find "$root" -type d -name "*${prefix}*" -print0 2>/dev/null)
}

########################################
# Status classification
########################################
count_status_classes() {
    local repo="$1"
    local staged=0
    local unstaged=0
    local untracked=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local x="${line:0:1}"
        local y="${line:1:1}"

        if [[ "$x$y" == "??" ]]; then
            ((untracked++))
            continue
        fi
        if [[ "$x" != " " && "$x" != "?" ]]; then
            ((staged++))
        fi
        if [[ "$y" != " " && "$y" != "?" ]]; then
            ((unstaged++))
        fi
    done < <(git -C "$repo" status --porcelain 2>/dev/null || true)

    echo "${staged} ${unstaged} ${untracked}"
}

########################################
# Latest file change in repo
########################################
latest_file_change() {
    local repo="$1"
    local line

    line=$(find "$repo" \
        -type f \
        ! -path "*/.git/*" \
        ! -path "*/build/*" \
        ! -path "*/.dart_tool/*" \
        ! -path "*/.idea/*" \
        ! -path "*/.vscode/*" \
        -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -1)

    if [[ -z "$line" ]]; then
        echo -e "0\t"
        return
    fi

    local epoch_f="${line%% *}"
    local path="${line#* }"
    local epoch="${epoch_f%.*}"

    echo -e "${epoch}\t${path}"
}

########################################
# Scan repo (standard)
########################################
scan_repo_standard() {
    local repo="$1"

    [[ ! -e "$repo/.git" ]] && return 0

    local branch commit_epoch commit_human dirty ahead behind

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    commit_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)
    commit_human=$(fmt_ts "$commit_epoch")

    dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi

    ahead=$(git_ahead "$repo")
    behind=$(git_behind "$repo")

    echo -e "${commit_epoch}\t${repo}\t${branch}\t${commit_human}\t${dirty}\t${ahead}\t${behind}"
}

########################################
# Scan repo (forensic)
########################################
scan_repo_forensic() {
    local repo="$1"

    debug_scan "scan_repo_forensic: START repo=$repo"

    if [[ ! -e "$repo/.git" ]]; then
        debug_scan "  repo has no .git, skipping"
        return 0
    fi

    local branch last_epoch last_human dirty ahead behind
    local staged unstaged untracked
    local latest_epoch latest_path latest_human
    local activity_epoch

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    debug_scan "  branch=$branch"

    last_epoch=$(git -C "$repo" log -1 --format='%ct' 2>/dev/null || echo 0)
    last_human=$(fmt_ts "$last_epoch")
    debug_scan "  last_epoch=$last_epoch last_human='$last_human'"

    dirty="clean"
    if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
        dirty="dirty"
    fi
    debug_scan "  dirty=$dirty"

    ahead=$(git_ahead "$repo")
    behind=$(git_behind "$repo")
    debug_scan "  ahead=$ahead behind=$behind"

    read -r staged unstaged untracked < <(count_status_classes "$repo")
    debug_scan "  staged=$staged unstaged=$unstaged untracked=$untracked"

    IFS=$'\t' read -r latest_epoch latest_path <<< "$(latest_file_change "$repo")"
    latest_human=$(fmt_ts "$latest_epoch")
    debug_scan "  latest_epoch=$latest_epoch latest_path='$latest_path' latest_human='$latest_human'"

    if [[ "$latest_epoch" -gt "$last_epoch" ]]; then
        activity_epoch="$latest_epoch"
    else
        activity_epoch="$last_epoch"
    fi
    debug_scan "  activity_epoch=$activity_epoch"

    echo -e "${activity_epoch}\t${repo}\t${branch}\t${last_epoch}\t${last_human}\t${dirty}\t${ahead}\t${behind}\t${staged}\t${unstaged}\t${untracked}\t${latest_epoch}\t${latest_human}\t${latest_path}"

    debug_scan "scan_repo_forensic: END repo=$repo"
}

########################################
# Printing helpers
########################################
print_standard_header() {
    printf "%-70s | %-25s | %-19s | %-7s | %-5s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%0.s—" {1..150}
    echo
}

print_forensic_header() {
    printf "%-70s | %-20s | %-19s | %-19s | %-6s | %-6s | %-6s | %-6s | %-10s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "LAST FILE" "DIRTY" "STAGE" "UNSTG" "UNTRK" "ACT.EPOCH"
    printf "%0.s—" {1..180}
    echo
}

########################################
# HTML helpers
########################################
html_init() {
    local title="$1"
    HTML_FILE="$2"
    cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${title}</title>
<style>
body { font-family: sans-serif; background: #111; color: #eee; }
h1, h2, h3 { color: #8be9fd; }
table { border-collapse: collapse; width: 100%; margin-bottom: 1.5em; }
th, td { border: 1px solid #444; padding: 4px 6px; font-size: 0.85rem; }
th { background: #282a36; }
tr:nth-child(even) { background: #222; }
tr:nth-child(odd) { background: #181818; }
.bad { color: #ff5555; }
.good { color: #50fa7b; }
.warn { color: #f1fa8c; }
pre { background: #1e1e1e; padding: 6px; overflow-x: auto; }
details { margin-bottom: 1em; }
summary { cursor: pointer; color: #bd93f9; }
</style>
</head>
<body>
<h1>Repo Forensic Report</h1>
<p>Generated: $(fmt_ts "$(date +%s)")</p>
EOF
}

html_close() {
    [[ -z "$HTML_FILE" ]] && return 0
    cat >> "$HTML_FILE" <<EOF
</body>
</html>
EOF
}

html_append_forensic_table() {
    local sorted="$1"
    [[ -z "$HTML_FILE" ]] && return 0

    cat >> "$HTML_FILE" <<EOF
<h2>Forensic Summary</h2>
<table>
<thead>
<tr>
  <th>Repo Path</th>
  <th>Branch</th>
  <th>Last Commit</th>
  <th>Last File Change</th>
  <th>Dirty</th>
  <th>Staged</th>
  <th>Unstaged</th>
  <th>Untracked</th>
  <th>Activity Epoch</th>
</tr>
</thead>
<tbody>
EOF

    while IFS=$'\t' read -r activity_epoch repo branch last_epoch last_human dirty ahead behind \
                                 staged unstaged untracked latest_epoch latest_human latest_path; do
        local dirty_class="good"
        [[ "$dirty" == "dirty" ]] && dirty_class="bad"
        cat >> "$HTML_FILE" <<EOF
<tr>
  <td>${repo}</td>
  <td>${branch}</td>
  <td>${last_human}</td>
  <td>${latest_human}</td>
  <td class="${dirty_class}">${dirty}</td>
  <td>${staged}</td>
  <td>${unstaged}</td>
  <td>${untracked}</td>
  <td>${activity_epoch}</td>
</tr>
EOF
    done < "$sorted"

    cat >> "$HTML_FILE" <<EOF
</tbody>
</table>
EOF
}

html_append_deep_compare_block() {
    local base="$1"
    local other="$2"
    local diff_output_file="$3"

    [[ -z "$HTML_FILE" ]] && return 0

    local base_esc="${base//&/&amp;}"
    base_esc="${base_esc//</&lt;}"
    base_esc="${base_esc//>/&gt;}"
    local other_esc="${other//&/&amp;}"
    other_esc="${other_esc//</&lt;}"
    other_esc="${other_esc//>/&gt;}"

    cat >> "$HTML_FILE" <<EOF
<details>
  <summary>Deep compare: <code>${base_esc}</code> vs <code>${other_esc}</code></summary>
  <pre>
EOF

    if [[ -f "$diff_output_file" ]]; then
        sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$diff_output_file" >> "$HTML_FILE"
    else
        echo "(no diff output file found: $diff_output_file)" >> "$HTML_FILE"
    fi

    cat >> "$HTML_FILE" <<EOF
  </pre>
</details>
EOF
}

########################################
# Deep compare helpers
########################################
deep_compare_pair() {
    local base="$1"
    local other="$2"
    local tag_base
    local tag_other
    tag_base=$(echo "$base"  | sed 's#[/ ]#_#g')
    tag_other=$(echo "$other" | sed 's#[/ ]#_#g')
    local ts
    ts="$(now_ts)"
    local diff_file="deepdiff_${tag_base}_VS_${tag_other}_${ts}.diff"

    echo
    echo "====== DEEP COMPARE ======"
    echo "BASE : $base"
    echo "OTHER: $other"
    echo "Writing unified diff to: $diff_file"

    diff -ru --exclude='.git' "$base" "$other" >"$diff_file" 2>&1 || true

    local only_base=0
    local only_other=0
    local differ=0

    while IFS= read -r line; do
        case "$line" in
            "Only in "*)
                if [[ "$line" == *"$base"* ]]; then
                    ((only_base++))
                    echo "$(color "$GREEN" "  + [BASE only] $line")"
                elif [[ "$line" == *"$other"* ]]; then
                    ((only_other++))
                    echo "$(color "$YELLOW" "  + [OTHER only] $line")"
                else
                    echo "  ? $line"
                fi
                ;;
            "Files "*)
                if [[ "$line" == *" differ" ]]; then
                    ((differ++))
                    echo "$(color "$RED" "  * [DIFFER] $line")"
                else
                    echo "  ? $line"
                fi
                ;;
            *)
                ;;
        esac
    done < <(diff -qr --exclude='.git' "$base" "$other" 2>/dev/null || true)

    echo
    echo "Summary:"
    echo "  Files only in BASE : $only_base"
    echo "  Files only in OTHER: $only_other"
    echo "  Files differing    : $differ"

    if [[ "$HTML_ENABLED" -eq 1 ]]; then
        html_append_deep_compare_block "$base" "$other" "$diff_file"
    fi
}

deep_compare_from_scanfile() {
    local sorted="$1"

    local first_line
    first_line="$(head -n1 "$sorted")"
    [[ -z "$first_line" ]] && return 0

    local base_repo
    base_repo="$(awk -F'\t' '{print $2}' <<< "$first_line")"

    echo
    echo "====== DEEP COMPARE ACROSS VARIANTS ======"
    echo "Baseline (most active) repo:"
    echo "  $base_repo"
    echo

    while IFS=$'\t' read -r activity_epoch repo branch last_epoch last_human dirty ahead behind \
                                 staged unstaged untracked latest_epoch latest_human latest_path; do
        if [[ "$repo" == "$base_repo" ]]; then
            continue
        fi
        deep_compare_pair "$base_repo" "$repo"
    done < "$sorted"
}

########################################
# Modes
########################################
run_mode_standard() {
    local root="$1"
    local name="$2"

    info "Running STANDARD comparison mode…"
    info "Searching: $root"
    info "Looking for repos with names containing: $name"

    local repo_list
    repo_list="$(mktemp)"
    local scan_file
    scan_file="$(mktemp)"
    local sorted
    sorted="$(mktemp)"

    find_repos "$root" "$name" "$repo_list"

    if [[ ! -s "$repo_list" ]]; then
        error "No repos found matching *${name}* under: $root"
        rm -f "$repo_list" "$scan_file" "$sorted"
        return 1
    fi

    info "Found $(wc -l < "$repo_list") repo(s). Collecting metadata…"

    while IFS= read -r repo; do
        scan_repo_standard "$repo" >> "$scan_file" || warn "scan_repo_standard failed for $repo"
    done < "$repo_list"

    sort -nr -k1,1 "$scan_file" > "$sorted"

    echo
    print_standard_header

    while IFS=$'\t' read -r commit_epoch repo branch commit_human dirty ahead behind; do
        local dirty_colored="$dirty"
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored="$(color "$RED" "$dirty")"
        else
            dirty_colored="$(color "$GREEN" "$dirty")"
        fi
        printf "%-70s | %-25s | %-19s | %-7s | %-5s | %-6s\n" \
            "$repo" "$branch" "$commit_human" "$dirty_colored" "$ahead" "$behind"
    done < "$sorted"

    if [[ "$DEBUG_TEMP" -eq 1 ]]; then
        echo
        echo "[debug-temp] Keeping temp files for inspection:"
        echo "  repo_list = $repo_list"
        echo "  scan_file = $scan_file"
        echo "  sorted    = $sorted"
    else
        rm -f "$repo_list" "$scan_file" "$sorted"
    fi
}

run_mode_forensic() {
    local root="$1"
    local name="$2"

    info "Running FORENSIC mode…"
    info "Searching: $root"
    info "Looking for repos with names containing: $name"

    local repo_list
    repo_list="$(mktemp)"
    local scan_file
    scan_file="$(mktemp)"
    local sorted
    sorted="$(mktemp)"

    find_repos "$root" "$name" "$repo_list"

    if [[ ! -s "$repo_list" ]]; then
        error "No repos found matching *${name}* under: $root"
        rm -f "$repo_list" "$scan_file" "$sorted"
        return 1
    fi

    info "Found $(wc -l < "$repo_list") repo(s). Collecting forensic data…"

    if [[ "$DEBUG_SCAN" -eq 1 || "$DEBUG_TEMP" -eq 1 ]]; then
        echo "[debug-scan] repo_list file: $repo_list"
        cat "$repo_list"
        echo
    fi

    while IFS= read -r repo; do
        debug_scan "Invoking scan_repo_forensic on: $repo"
        scan_repo_forensic "$repo" >> "$scan_file" || warn "scan_repo_forensic failed for $repo"
    done < "$repo_list"

    if [[ ! -s "$scan_file" ]]; then
        error "Forensic scan produced no records (scan_file is empty)."
        if [[ "$DEBUG_TEMP" -eq 1 || "$DEBUG_SCAN" -eq 1 ]]; then
            echo "[debug-scan] scan_file = $scan_file (empty)"
        else
            rm -f "$repo_list" "$scan_file" "$sorted"
        fi
        return 1
    fi

    if [[ "$DEBUG_SCAN" -eq 1 ]]; then
        echo "[debug-scan] Raw forensic scan output (scan_file=$scan_file):"
        cat "$scan_file"
        echo
    fi

    sort -nr -k1,1 "$scan_file" > "$sorted"

    echo
    print_forensic_header

    local best_repo=""
    local best_epoch=0
    local first=1

    while IFS=$'\t' read -r activity_epoch repo branch last_epoch last_human dirty ahead behind \
                                 staged unstaged untracked latest_epoch latest_human latest_path; do
        if [[ $first -eq 1 ]]; then
            best_repo="$repo"
            best_epoch="$activity_epoch"
            first=0
        fi

        local dirty_colored="$dirty"
        if [[ "$dirty" == "dirty" ]]; then
            dirty_colored="$(color "$RED" "$dirty")"
        else
            dirty_colored="$(color "$GREEN" "$dirty")"
        fi

        printf "%-70s | %-20s | %-19s | %-19s | %-6s | %-6s | %-6s | %-6s | %-10s\n" \
            "$repo" "$branch" "$last_human" "$latest_human" \
            "$dirty_colored" "$staged" "$unstaged" "$untracked" "$activity_epoch"
    done < "$sorted"

    echo
    success "Likely LAST ACTIVE repo (by activity):"
    echo "   Path : $best_repo"
    echo "   Epoch: $best_epoch"
    echo "   Time : $(fmt_ts "$best_epoch")"

    if [[ "$HTML_ENABLED" -eq 1 ]]; then
        echo
        echo "📄 HTML report: $HTML_FILE"
        html_append_forensic_table "$sorted"
    fi

    if [[ "$DEEP_COMPARE" -eq 1 ]]; then
        deep_compare_from_scanfile "$sorted"
    fi

    if [[ "$DEBUG_TEMP" -eq 1 ]]; then
        echo
        echo "[debug-temp] Keeping temp files for inspection:"
        echo "  repo_list = $repo_list"
        echo "  scan_file = $scan_file"
        echo "  sorted    = $sorted"
    else
        rm -f "$repo_list" "$scan_file" "$sorted"
    fi
}

########################################
# main() — CLI parsing + dispatch
########################################
main() {
    local ROOT_FOLDER=""
    local REPO_NAME=""
    local MODE="standard"

    if [[ $# -eq 0 ]]; then
        cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [--mode standard|forensic]
       [--deep-compare] [--html] [--log]
       [--debug-find] [--debug-temp] [--debug-scan]
EOF
        return 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --root-folder)
                ROOT_FOLDER="$2"; shift 2 ;;
            --repo-name)
                REPO_NAME="$2"; shift 2 ;;
            --mode)
                MODE="$2"; shift 2 ;;
            --deep-compare)
                DEEP_COMPARE=1; shift ;;
            --html)
                HTML_ENABLED=1; shift ;;
            --log)
                LOG_ENABLED=1; shift ;;
            --debug-find)
                DEBUG_FIND=1; shift ;;
            --debug-temp)
                DEBUG_TEMP=1; shift ;;
            --debug-scan)
                DEBUG_SCAN=1; shift ;;
            -h|--help)
                cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [--mode standard|forensic]
       [--deep-compare] [--html] [--log]
       [--debug-find] [--debug-temp] [--debug-scan]
EOF
                return 0 ;;
            *)
                error "Unknown argument: $1"
                return 1 ;;
        esac
    done

    if [[ -z "$ROOT_FOLDER" ]]; then
        error "--root-folder is required"
        return 1
    fi
    if [[ -z "$REPO_NAME" ]]; then
        error "--repo-name is required"
        return 1
    fi
    if [[ ! -d "$ROOT_FOLDER" ]]; then
        error "Root folder does not exist: $ROOT_FOLDER"
        return 1
    fi

    case "$MODE" in
        standard|forensic) ;;
        *)
            error "Invalid --mode: $MODE (must be 'standard' or 'forensic')"
            return 1 ;;
    esac

    if [[ "$LOG_ENABLED" -eq 1 ]]; then
        local ts
        ts="$(now_ts)"
        LOG_FILE="${REPO_NAME}_Patch8_${ts}.log"
        echo "📄 Logging enabled → $LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    if [[ "$HTML_ENABLED" -eq 1 ]]; then
        local ts_html
        ts_html="$(now_ts)"
        HTML_FILE="repo_forensics_${REPO_NAME}_${ts_html}.html"
        html_init "Repo Forensic Report - ${REPO_NAME}" "$HTML_FILE"
    fi

    case "$MODE" in
        standard) run_mode_standard "$ROOT_FOLDER" "$REPO_NAME" ;;
        forensic) run_mode_forensic "$ROOT_FOLDER" "$REPO_NAME" ;;
    esac

    if [[ "$HTML_ENABLED" -eq 1 ]]; then
        html_close
        echo
        success "HTML report written to: $HTML_FILE"
    fi
}

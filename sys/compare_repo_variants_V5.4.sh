#!/usr/bin/env bash
# Placeholder for compare_repo_variants_V5.4.sh
# The full script will be delivered in chunked messages following this file.
echo "compare_repo_variants_V5.4.sh placeholder. Full content provided in chat." 

#!/usr/bin/env bash
###########################################################################
# compare_repo_variants_V5.4.sh
#
# Full-featured multi-repo comparison tool:
#   • Auto-detect multiple copies of the same repo
#   • Best-version heuristic:
#        DIRTY → NEWEST → AHEAD → BEHIND → ALPHABETICAL
#   • Sorted table output with color
#   • JSON, CSV, HTML, plain log output
#   • Full/summary/per-file diff modes
#   • Pattern-filtered diffing (NEW in V5.4)
#   • Clean argument parsing (order-independent)
#   • Dirty-detail: added/modified/deleted/renamed/untracked
#   • Log rotation (20 newest, 30 days old purge)
#   • Per-file diff color coding (NEW in V5.4)
#   • Grouped per-file diff summary (NEW in V5.4)
#
# Version: V5.4
###########################################################################

set -euo pipefail

#############################
# GLOBALS & DEFAULTS
#############################

ROOT_FOLDER=""
REPO_NAME=""
SORT_MODE="best"
DIFF_LEVEL="none"          # summary | per-file | full | none
OUTPUT_FORMAT="table"      # table | json | csv | html
ENABLE_LOG=false
DIRTY_DETAIL=false
GROUPED_SUMMARY=false

# Pattern filters for diff (NEW)
declare -a DIFF_PATTERNS=()

# Internals
NOW="$(date +%Y-%m-%d_%H-%M-%S)"
LOGFILE=""
BEST_PATH=""
TMP_REPOS=$(mktemp)
TMP_SORTED=$(mktemp)
TMP_FINAL=$(mktemp)

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
NC="\033[0m"

############################################
# ARGUMENT PARSER (ORDER-INDEPENDENT, V5.4)
############################################

print_help() {
    cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [options]

Required:
  --root-folder <path>       Root directory to search in
  --repo-name <name>         Repository name prefix (e.g. jsigconversiontools)

Diff options:
  --diff-level <level>       summary | per-file | full | none
  --diff-pattern <glob>      Add include pattern for diffing (can repeat)
  --grouped-summary          Group per-file diff output by extension (NEW)

Sort options:
  --sort <mode>              timestamp | dirty | best (default)

Output:
  --output <fmt>             table | json | csv | html

Flags:
  --best                     Enable best-version heuristic (same as --sort best)
  --log                      Write to logfile with rotation
  --dirty-detail             Show added/modified/deleted/renamed/untracked
  --help                     Show help

Examples:
  $0 --root-folder /mnt/Nightly --repo-name jsig --best --diff-level summary
  $0 --root-folder . --repo-name myrepo --diff-level full --diff-pattern '*.cpp'
EOF
}

# Parse all arguments into variables
while [[ $# -gt 0 ]]; do
    case "$1" in

        --root-folder)
            ROOT_FOLDER="$2"
            shift 2
            ;;

        --repo-name)
            REPO_NAME="$2"
            shift 2
            ;;

        --sort)
            SORT_MODE="$2"
            shift 2
            ;;

        --best)
            SORT_MODE="best"
            shift
            ;;

        --diff-level)
            DIFF_LEVEL="$2"
            shift 2
            ;;

        --diff-pattern)
            DIFF_PATTERNS+=("$2")
            shift 2
            ;;

        --grouped-summary)
            GROUPED_SUMMARY=true
            shift
            ;;

        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;

        --log)
            ENABLE_LOG=true
            shift
            ;;

        --dirty-detail)
            DIRTY_DETAIL=true
            shift
            ;;

        --help|-h)
            print_help
            exit 0
            ;;

        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

############################################
# VALIDATION
############################################

if [[ -z "$ROOT_FOLDER" || -z "$REPO_NAME" ]]; then
    echo "❌ ERROR: --root-folder and --repo-name are required."
    exit 1
fi

if [[ ! -d "$ROOT_FOLDER" ]]; then
    echo "❌ ERROR: Root folder does not exist: $ROOT_FOLDER"
    exit 1
fi

case "$DIFF_LEVEL" in
    none|summary|per-file|full) ;;
    *)
        echo "❌ Invalid --diff-level: $DIFF_LEVEL"
        exit 1
        ;;
esac

case "$SORT_MODE" in
    timestamp|dirty|best) ;;
    *)
        echo "❌ Invalid --sort: $SORT_MODE"
        exit 1
        ;;
esac

############################################
# COLOR HELPERS
############################################

color_dirty()   { echo -e "${RED}$1${NC}"; }
color_ahead()   { echo -e "${GREEN}$1${NC}"; }
color_behind()  { echo -e "${YELLOW}$1${NC}"; }
color_clean()   { echo -e "${CYAN}$1${NC}"; }
color_normal()  { echo -e "$1"; }

############################################
# LOGGING SYSTEM
############################################

log() {
    if [[ "$ENABLE_LOG" == true ]]; then
        # Strip ANSI colors for log file
        local clean_line
        clean_line="$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"
        echo "$clean_line" >> "$LOGFILE"
    fi
    echo -e "$1"
}

############################################
# INIT LOG FILE + ROTATION
############################################

if [[ "$ENABLE_LOG" == true ]]; then

    LOGFILE="${REPO_NAME}_comparison_${NOW}_${DIFF_LEVEL}.log"

    log "📄 Logging enabled → $LOGFILE"

    # ROTATION STRATEGY
    # Keep last 20 logs, delete logs older than 30 days
    log "🧹 Applying log rotation…"

    # delete logs older than 30 days
    find . -maxdepth 1 -name "${REPO_NAME}_comparison_*.log" -mtime +30 -print -delete \
        | sed 's/^/   removed old log → /'

    # keep last 20, delete rest
    LOG_COUNT=$(ls -1 ${REPO_NAME}_comparison_*.log 2>/dev/null | wc -l || true)
    if (( LOG_COUNT > 20 )); then
        ls -1t ${REPO_NAME}_comparison_*.log \
            | tail -n +21 \
            | while read -r old; do
                echo "   removed excess log → $old"
                rm -f "$old"
            done
    fi
fi

############################################
# DISCOVER REPOS MATCHING PREFIX
############################################

log "🔍 Searching: $ROOT_FOLDER"
log "🔎 Looking for repos matching: ${REPO_NAME}*"

find "$ROOT_FOLDER" -type d -name "${REPO_NAME}*" -print0 |
while IFS= read -r -d '' dir; do
    if [[ -d "$dir/.git" ]]; then
        echo "$dir" >> "$TMP_REPOS"
    fi
done

if [[ ! -s "$TMP_REPOS" ]]; then
    log "❌ No repositories found matching: ${REPO_NAME}*"
    exit 1
fi

############################################
# EXTRACT METADATA FROM EACH REPO
############################################

extract_repo_info() {
    local d="$1"

    pushd "$d" >/dev/null

    local branch last_ts epoch dirty ahead behind

    # Branch (fallback HEAD)
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")

    # Timestamp
    last_ts=$(git log -1 --format="%ci" 2>/dev/null || echo "1970-01-01 00:00:00")
    epoch=$(date -d "$last_ts" +%s || echo 0)

    # Dirty / untracked
    if [[ -n "$(git status --porcelain)" ]]; then
        dirty="dirty"
    else
        dirty="clean"
    fi

    # Ahead / behind
    ahead=$(git rev-list --left-right --count HEAD@{upstream}..HEAD 2>/dev/null | awk '{print $2}' || echo 0)
    behind=$(git rev-list --left-right --count HEAD..HEAD@{upstream} 2>/dev/null | awk '{print $1}' || echo 0)

    popd >/dev/null

    echo -e "${epoch}\t${d}\t${branch}\t${last_ts}\t${dirty}\t${ahead}\t${behind}"
}

log ""
log "Collecting repo metadata…"

while IFS= read -r d; do
    extract_repo_info "$d"
done < "$TMP_REPOS" > "$TMP_SORTED"

############################################
# SORT REPOS BASED ON SELECTED MODE
############################################

log ""
log "Sorting repos using mode: $SORT_MODE"

case "$SORT_MODE" in

    ############################################
    # SORT BY TIMESTAMP ONLY
    ############################################
    timestamp)
        sort -nrk1,1 "$TMP_SORTED" > "$TMP_FINAL"
        ;;

    ############################################
    # SORT BY DIRTY STATUS (dirty first)
    ############################################
    dirty)
        # dirty=1, clean=0 for sorting
        awk -F'\t' '
        {
            dirty_value = ($5 == "dirty") ? 1 : 0
            printf "%d\t%s\n", dirty_value, $0
        }' "$TMP_SORTED" \
        | sort -nrk1,1 \
        | cut -f2- \
        > "$TMP_FINAL"
        ;;

    ############################################
    # BEST HEURISTIC
    # DIRTY → NEWEST → AHEAD → BEHIND → PATH
    ############################################
    best)
        awk -F'\t' '
        {
            epoch   = $1
            path    = $2
            branch  = $3
            ts      = $4
            dirty   = $5
            ahead   = $6
            behind  = $7

            # dirty_value: dirty = 1, clean = 0
            dirty_value = (dirty == "dirty") ? 1 : 0

            # Print sortable line:
            # dirty_value epoch ahead (negative behind) path full_line
            # Note: We invert behind to sort fewer-behind earlier.
            printf "%d\t%d\t%d\t%d\t%s\t%s\n",
                dirty_value, epoch, ahead, -behind, path, $0
        }' "$TMP_SORTED" \
        | sort -t$'\t' -nrk1,1 -nrk2,2 -nrk3,3 -nk4,4 -k5,5 \
        | cut -f6- \
        > "$TMP_FINAL"
        ;;

    ############################################
    # DEFAULT (should never happen because validated earlier)
    ############################################
    *)
        echo "❌ Invalid sort mode: $SORT_MODE"
        exit 1
        ;;
esac


############################################
# Determine BEST repo (first in sorted list)
############################################

read -r BEST_EPOCH BEST_PATH BEST_BRANCH BEST_TS BEST_DIRTY BEST_AHEAD BEST_BEHIND < <(head -n1 "$TMP_FINAL")

log ""
log "🏆 BEST VERSION (by heuristic): $BEST_PATH"

############################################
# OUTPUT FORMATTING
############################################

print_table_header() {
    log ""
    log "REPO PATH                                                        | BRANCH               | LAST COMMIT          | DIRTY    | AHEAD  | BEHIND"
    log "——————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"
}

format_row_color() {
    local path="$2"
    local branch="$3"
    local ts="$4"
    local dirty="$5"
    local ahead="$6"
    local behind="$7"

    local dirty_c ahead_c behind_c

    # Color rules
    if [[ "$dirty" == "dirty" ]]; then
        dirty_c=$(color_dirty "$dirty")
    else
        dirty_c=$(color_clean "$dirty")
    fi

    if (( ahead > 0 )); then
        ahead_c=$(color_ahead "$ahead")
    else
        ahead_c="$ahead"
    fi

    if (( behind > 0 )); then
        behind_c=$(color_behind "$behind")
    else
        behind_c="$behind"
    fi

    printf "%-60s | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
        "$path" "$branch" "$ts" "$dirty_c" "$ahead_c" "$behind_c"
}

############################################
# TABLE OUTPUT
############################################

if [[ "$OUTPUT_FORMAT" == "table" ]]; then
    print_table_header
    while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
        format_row_color "$epoch" "$path" "$branch" "$ts" "$dirty" "$ahead" "$behind"
    done < "$TMP_FINAL"
fi

############################################
# JSON OUTPUT
############################################

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
    echo "["

    first=1
    while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
        if (( ! first )); then echo ","; fi
        first=0
        cat <<EOF
  {
    "path": "$path",
    "branch": "$branch",
    "last_commit": "$ts",
    "dirty": "$dirty",
    "ahead": $ahead,
    "behind": $behind,
    "timestamp_epoch": $epoch
  }
EOF
    done < "$TMP_FINAL"

    echo "]"
fi

############################################
# CSV OUTPUT
############################################

if [[ "$OUTPUT_FORMAT" == "csv" ]]; then
    echo "path,branch,last_commit,dirty,ahead,behind,timestamp_epoch"
    while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
        echo "\"$path\",\"$branch\",\"$ts\",\"$dirty\",$ahead,$behind,$epoch"
    done < "$TMP_FINAL"
fi

############################################
# HTML OUTPUT (INTERACTIVE TABLE)
############################################

if [[ "$OUTPUT_FORMAT" == "html" ]]; then
cat <<EOF
<html>
<head>
<style>
body { background: #111; color: #eee; font-family: monospace; }
table { border-collapse: collapse; width: 100%; }
th { background: #333; cursor: pointer; }
td, th { padding: 8px; border: 1px solid #444; }
tr:nth-child(even) { background: #222; }
tr:nth-child(odd) { background: #181818; }
.dirty { color: #ff6666; }
.ahead { color: #66ff66; }
.behind { color: #ffcc66; }
.clean { color: #66ccff; }
</style>
<script>
function sortTable(n) {
  var table = document.getElementById("repoTable");
  var switching = true;
  var dir = "desc";
  var switchcount = 0;

  while (switching) {
    switching = false;
    var rows = table.rows;

    for (var i = 1; i < (rows.length - 1); i++) {
      var a = rows[i].getElementsByTagName("td")[n];
      var b = rows[i + 1].getElementsByTagName("td")[n];
      var cmpA = a.innerText.toLowerCase();
      var cmpB = b.innerText.toLowerCase();

      if ((dir == "desc" && cmpA < cmpB) ||
          (dir == "asc"  && cmpA > cmpB)) {
        rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
        switching = true;
        switchcount++;
        break;
      }
    }

    if (switchcount == 0 && dir == "desc") {
      dir = "asc";
      switching = true;
    }
  }
}
</script>
</head>
<body>
<h2>Repo Comparison Report</h2>
<table id="repoTable">
<tr>
  <th onclick="sortTable(0)">Path</th>
  <th onclick="sortTable(1)">Branch</th>
  <th onclick="sortTable(2)">Last Commit</th>
  <th onclick="sortTable(3)">Dirty</th>
  <th onclick="sortTable(4)">Ahead</th>
  <th onclick="sortTable(5)">Behind</th>
</tr>
EOF

while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
    # Determine classes
    dirty_class="clean"
    [[ "$dirty" == "dirty" ]] && dirty_class="dirty"

    ahead_class=""
    (( ahead > 0 )) && ahead_class="ahead"

    behind_class=""
    (( behind > 0 )) && behind_class="behind"

cat <<EOF
<tr>
  <td>$path</td>
  <td>$branch</td>
  <td>$ts</td>
  <td class="$dirty_class">$dirty</td>
  <td class="$ahead_class">$ahead</td>
  <td class="$behind_class">$behind</td>
</tr>
EOF
done < "$TMP_FINAL"

cat <<EOF
</table>
</body>
</html>
EOF
fi

############################################
# DIFF PATTERN MATCHING (NEW in 5.4)
############################################

match_patterns() {
    local file="$1"

    # If no patterns supplied → always match
    if (( ${#DIFF_PATTERNS[@]} == 0 )); then
        return 0
    fi

    for pat in "${DIFF_PATTERNS[@]}"; do
        # Use fnmatch semantics
        if [[ "$file" == $pat ]]; then
            return 0
        fi
    done

    return 1
}

############################################
# GROUPED SUMMARY ACCUMULATORS (NEW)
############################################

declare -A GROUP_ADDED=([__init]=0)
declare -A GROUP_REMOVED=([__init]=0)
declare -A GROUP_DIFFER=([__init]=0)
declare -A GROUP_ONLY_BEST=([__init]=0)
declare -A GROUP_ONLY_OTHER=([__init]=0)

get_ext() {
    local f="$1"
    echo "${f##*.}"
}

############################################
# RUN DIFFS VS BEST REPO
############################################

log ""
log "====== DIFF SUMMARY vs BEST: $BEST_PATH ======"
log ""

run_diff_engine() {
    local other="$1"

    log "── Comparing:"
    log "   BEST : $BEST_PATH"
    log "   OTHER: $other"

    case "$DIFF_LEVEL" in

        ############################################################
        # SUMMARY MODE (count-only)
        ############################################################
        summary)
            local only_in_best=0
            local only_in_other=0
            local differ=0

            # raw diff listing
            while IFS= read -r line; do
                # Extract file paths
                if [[ "$line" =~ ^Only\ in\ ([^:]+):\ (.*)$ ]]; then
                    local dir="${BASH_REMATCH[1]}"
                    local f="${BASH_REMATCH[2]}"

                    # full file path
                    local full="$dir/$f"

                    # Must match patterns
                    if ! match_patterns "$full"; then
                        continue
                    fi

                    if [[ "$dir" == "$BEST_PATH" ]]; then
                        ((only_in_best++))
                    else
                        ((only_in_other++))
                    fi
                elif [[ "$line" =~ ^Files\ (.*)\ and\ (.*)\ differ$ ]]; then
                    local f1="${BASH_REMATCH[1]}"
                    # Apply pattern filter to either file
                    if match_patterns "$f1"; then
                        ((differ++))
                    fi
                fi

            done < <(diff -qr --exclude='.git' "$BEST_PATH" "$other" 2>/dev/null || true)

            log "   Files only in BEST:   $only_in_best"
            log "   Files only in OTHER:  $only_in_other"
            log "   Files differing:      $differ"
            ;;

        ############################################################
        # PER-FILE MODE (pattern-filtered, colorized)
        ############################################################
        per-file)
            log "   Per-file differences:"

            local any=0

            while IFS= read -r line; do

                # Handle "Only in <dir>: <file>"
                if [[ "$line" =~ ^Only\ in\ ([^:]+):\ (.*)$ ]]; then
                    local dir="${BASH_REMATCH[1]}"
                    local file="${BASH_REMATCH[2]}"
                    local full="$dir/$file"

                    # pattern filter
                    if ! match_patterns "$full"; then
                        continue
                    fi

                    any=1

                    if [[ "$dir" == "$BEST_PATH" ]]; then
                        log "   $(color_ahead "Only in BEST:") $file"
                    else
                        log "   $(color_behind "Only in OTHER:") $file"
                    fi

                    # grouped summary
                    if [[ "$GROUPED_SUMMARY" == true ]]; then
                        ext=$(get_ext "$file")
                        if [[ "$dir" == "$BEST_PATH" ]]; then
                            (( GROUP_ONLY_BEST[$ext]++ ))
                        else
                            (( GROUP_ONLY_OTHER[$ext]++ ))
                        fi
                    fi

                # Handle "Files <f1> and <f2> differ"
                elif [[ "$line" =~ ^Files\ (.*)\ and\ (.*)\ differ$ ]]; then
                    local f1="${BASH_REMATCH[1]}"
                    local f2="${BASH_REMATCH[2]}"

                    if match_patterns "$f1" || match_patterns "$f2"; then
                        any=1
                        log "   $(color_dirty "Files differ:") $f1"

                        # grouped summary
                        if [[ "$GROUPED_SUMMARY" == true ]]; then
                            ext=$(get_ext "$f1")
                            (( GROUP_DIFFER[$ext]++ ))
                        fi
                    fi
                fi

            done < <(diff -qr --exclude='.git' "$BEST_PATH" "$other" 2>/dev/null || true)

            if (( any == 0 )); then
                log "   (no differences matching patterns)"
            fi
            ;;

        ############################################################
        # FULL DIFF MODE (pattern-filtered)
        ############################################################
        full)
            # sanitized names for output file
            local safe_other
            safe_other=$(echo "$other" | sed 's#[/ ]#_#g')

            local diff_file="${REPO_NAME}_full_diff_${safe_other}_VS_${BEST_PATH//\//_}_${NOW}.diff"

            log "   Writing full unified diff to: $diff_file"

            # raw unified diff → filter by patterns
            # we keep context around matched files
            diff -ru --exclude='.git' "$BEST_PATH" "$other" 2>/dev/null \
            | awk -v pats="${DIFF_PATTERNS[*]}" '
                BEGIN {
                    split(pats, arr, " ")
                }
                # track file header lines
                /^--- / {
                    fname = $2
                    sub(/^a\//, "", fname)
                    show = 0
                    for (i in arr) {
                        pat = arr[i]
                        if (pat == "" || fname ~ pat) {
                            show = 1
                        }
                    }
                }
                {
                    if (show == 1)
                        print $0
                }
            ' > "$diff_file"
            ;;
    esac
}

############################################
# RUN DIFF ENGINE FOR EACH NON-BEST REPO
############################################

while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
    if [[ "$path" != "$BEST_PATH" ]]; then
        run_diff_engine "$path"
        log ""
    fi
done < "$TMP_FINAL"

############################################
# DIRTY DETAIL ENGINE
############################################

print_dirty_detail_for_repo() {
    local path="$1"
    local branch="$2"
    local ts="$3"

    pushd "$path" >/dev/null

    local status
    status="$(git status --porcelain 2>/dev/null || true)"

    if [[ -z "$status" ]]; then
        popd >/dev/null
        return
    fi

    log ""
    log "Repo: $path"
    log "  Branch: $branch"
    log "  Last commit: $ts"

    local modified=()
    local added=()
    local deleted=()
    local renamed=()
    local untracked=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local code="${line:0:2}"
        local file="${line:3}"

        case "$code" in
            "??") untracked+=("$file") ;;
            M*|*M) modified+=("$file") ;;
            A*|*A) added+=("$file") ;;
            D*|*D) deleted+=("$file") ;;
            R*|*R) renamed+=("$file") ;;
            *)
                modified+=("$file") ;;
        esac
    done <<< "$status"

    if ((${#modified[@]} > 0)); then
        log "  Modified:"
        for f in "${modified[@]}"; do
            log "    - $f"
        done
    fi

    if ((${#added[@]} > 0)); then
        log "  Added:"
        for f in "${added[@]}"; do
            log "    - $f"
        done
    fi

    if ((${#deleted[@]} > 0)); then
        log "  Deleted:"
        for f in "${deleted[@]}"; do
            log "    - $f"
        done
    fi

    if ((${#renamed[@]} > 0)); then
        log "  Renamed:"
        for f in "${renamed[@]}"; do
            log "    - $f"
        done
    fi

    if ((${#untracked[@]} > 0)); then
        log "  Untracked:"
        for f in "${untracked[@]}"; do
            log "    - $f"
        done
    fi

    popd >/dev/null
}

############################################
# RUN DIRTY DETAIL ON ALL DIRTY REPOS
############################################

if [[ "$DIRTY_DETAIL" == true ]]; then
    log ""
    log "====== DIRTY REPO DETAILS ======"

    while IFS=$'\t' read -r epoch path branch ts dirty ahead behind; do
        if [[ "$dirty" == "dirty" ]]; then
            print_dirty_detail_for_repo "$path" "$branch" "$ts"
        fi
    done < "$TMP_FINAL"
fi

############################################
# GROUPED SUMMARY OUTPUT (NEW in 5.4)
############################################

if [[ "$GROUPED_SUMMARY" == true && "$DIFF_LEVEL" == "per-file" ]]; then
    log ""
    log "====== GROUPED DIFF SUMMARY (by extension) ======"

    log "Extensions only in BEST:"
    for ext in "${!GROUP_ONLY_BEST[@]}"; do
        log "  .$ext : ${GROUP_ONLY_BEST[$ext]}"
    done

    log ""
    log "Extensions only in OTHER:"
    for ext in "${!GROUP_ONLY_OTHER[@]}"; do
        log "  .$ext : ${GROUP_ONLY_OTHER[$ext]}"
    done

    log ""
    log "Extensions differing in content:"
    for ext in "${!GROUP_DIFFER[@]}"; do
        log "  .$ext : ${GROUP_DIFFER[$ext]}"
    done
fi

############################################
# CLEANUP TEMP FILES
############################################

cleanup() {
    rm -f "$TMP_REPOS" "$TMP_SORTED" "$TMP_FINAL" 2>/dev/null || true
}
trap cleanup EXIT


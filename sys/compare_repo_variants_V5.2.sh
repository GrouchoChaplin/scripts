#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# DEFAULTS
# ────────────────────────────────────────────────────────────────
ROOT="."
REPO=""
OUTPUT=""
BEST=""
DO_LOG=""
DIFF_LEVEL="none"   # summary | per-file | full | none
CHECKSUM=""
DIRTY_DETAIL=""

TMPFILE=$(mktemp)
SORTED=$(mktemp)
FINAL=$(mktemp)

NOW=$(date +"%Y-%m-%d_%H-%M-%S")
LOGFILE=""

# Repos we actually processed (with .git)
REPO_DIRS=()

# diff patterns
DIFF_PATTERNS=()

# ────────────────────────────────────────────────────────────────
# COLORS (terminal only; logs get colors stripped)
# ────────────────────────────────────────────────────────────────
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ────────────────────────────────────────────────────────────────
# CLEANUP + LOG ROTATION
# ────────────────────────────────────────────────────────────────
cleanup() {
    local status=$?
    if [[ "${DO_LOG:-}" == "yes" && -n "${REPO:-}" ]]; then
        local LOGDIR="."
        # Delete logs older than 30 days
        find "$LOGDIR" -maxdepth 1 -name "${REPO}_comparison_"'*.log' -mtime +30 -delete 2>/dev/null || true

        # Keep only most recent 20 logs
        mapfile -t logs < <(ls -1t "${REPO}_comparison_"*.log 2>/dev/null || true)
        if (( ${#logs[@]} > 20 )); then
            for ((i=20; i<${#logs[@]}; i++)); do
                rm -f -- "${logs[i]}" 2>/dev/null || true
            done
        fi
    fi

    rm -f "$TMPFILE" "$SORTED" "$FINAL" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT

# ────────────────────────────────────────────────────────────────
usage() {
cat <<EOF
Usage:
  $0 --root-folder <path> --repo-name <name> [options]

Options:
  --output json          Output JSON
  --output csv           Output CSV
  --output html          Output HTML summary (printed to stdout)
  --best                 Compute and highlight BEST VERSION repo
  --log                  Also write output to: <repo>_comparison_<timestamp>[_<diff-level>].log
  --diff-level <lvl>     Diff level vs BEST repo (requires --best):
                         lvl = summary | per-file | full | none
                           summary  : counts of differing/only-in files
                           per-file : list per-file differences
                           full     : full unified diff into separate .diff files
  --diff-pattern <glob>  Restrict diff to files matching patterns (can repeat)
                         Example: --diff-pattern '*.dart' --diff-pattern 'lib/*.dart'
                         Applies to summary & per-file (full ignores patterns).
  --checksum             In per-file diff mode, show SHA256 for differing files
  --dirty-detail         Show modified/added/deleted/untracked per dirty repo
  -h, --help             Show help

Fixed sort order:
  Dirty → Newest → Ahead → Behind → Alphabetical

Examples:
  $0 --root-folder /run/media/.../Nightly --repo-name jsigconversiontools --best --log --diff-level summary
  $0 --root-folder ~/projects --repo-name myrepo --output json
  $0 --root-folder ~/bk --repo-name myrepo --best --diff-level per-file --diff-pattern '*.dart' --checksum
EOF
}

# ────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root-folder)
            ROOT="$2"; shift 2;;
        --repo-name)
            REPO="$2"; shift 2;;
        --output)
            OUTPUT="$2"; shift 2;;
        --best)
            BEST="yes"; shift;;
        --log)
            DO_LOG="yes"; shift;;
        --diff-level)
            DIFF_LEVEL="$2"; shift 2;;
        --checksum)
            CHECKSUM="yes"; shift;;
        --dirty-detail)
            DIRTY_DETAIL="yes"; shift;;
        --diff-pattern)
            DIFF_PATTERNS+=("$2"); shift 2;;
        -h|--help)
            usage; exit 0;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1;;
    esac
done

if [[ -z "$REPO" ]]; then
    echo "❌ Missing --repo-name"
    usage
    exit 1
fi

if [[ ! -d "$ROOT" ]]; then
    echo "❌ Root folder does not exist: $ROOT"
    exit 1
fi

case "$DIFF_LEVEL" in
    none|summary|per-file|full) ;;  # ok
    *)
        echo "❌ Invalid --diff-level: $DIFF_LEVEL (use: none|summary|per-file|full)"
        exit 1
        ;;
esac

# ────────────────────────────────────────────────────────────────
# ENABLE LOGGING (strip colors in log, keep in terminal)
# ────────────────────────────────────────────────────────────────
if [[ "$DO_LOG" == "yes" ]]; then
    LOGFILE="${REPO}_comparison_${NOW}"
    if [[ "$DIFF_LEVEL" != "none" ]]; then
        LOGFILE+="_${DIFF_LEVEL}"
    fi
    LOGFILE+=".log"
    echo "📄 Logging enabled → $LOGFILE" >&2
    exec > >(tee >(sed -r 's/\x1b\[[0-9;]*m//g' >>"$LOGFILE")) 2>&1
fi

# ────────────────────────────────────────────────────────────────
echo -e "🔍 Searching: ${CYAN}${ROOT}${RESET}"
echo -e "🔎 Looking for repos matching: ${YELLOW}${REPO}*${RESET}"
if [[ "$DIFF_LEVEL" != "none" ]]; then
    echo -e "🧩 Diff level requested: ${DIFF_LEVEL} (vs BEST repo)"
fi
if ((${#DIFF_PATTERNS[@]} > 0)); then
    echo "🎯 Diff file patterns:"
    for pat in "${DIFF_PATTERNS[@]}"; do
        echo "   - $pat"
    done
fi
echo

# ────────────────────────────────────────────────────────────────
# FIND CANDIDATE DIRECTORIES
# ────────────────────────────────────────────────────────────────
mapfile -t DIRS < <(
    find "$ROOT" -maxdepth 8 -type d -name "${REPO}*" -not -path "*/.git/*"
)

if [[ ${#DIRS[@]} -eq 0 ]]; then
    echo "❌ No matching directories found."
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# HELPER: pattern match for diff paths
# ────────────────────────────────────────────────────────────────
matches_diff_patterns() {
    local path="$1"
    # If no patterns, everything passes
    if ((${#DIFF_PATTERNS[@]} == 0)); then
        return 0
    fi
    for pat in "${DIFF_PATTERNS[@]}"; do
        if [[ "$path" == $pat ]]; then
            return 0
        fi
    done
    return 1
}

# ────────────────────────────────────────────────────────────────
# PROCESS EACH REPO
# ────────────────────────────────────────────────────────────────
for dir in "${DIRS[@]}"; do
    [[ ! -d "$dir/.git" ]] && continue

    pushd "$dir" >/dev/null

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    hash=$(git rev-parse --short HEAD 2>/dev/null || echo "NOHASH")
    ts_raw=$(git log -1 --format="%ct" 2>/dev/null || echo "0")
    ts_hr=$(git log -1 --format="%ci" 2>/dev/null || echo "NO COMMITS")

    # dirty? (including untracked)
    dirty="clean"
    status_out="$(git status --porcelain 2>/dev/null || true)"
    if [[ -n "$status_out" ]]; then
        dirty="dirty"
    fi

    # ahead/behind?
    ahead="0"
    behind="0"
    if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
        ahead=$(git rev-list --left-only --count @{u}...HEAD 2>/dev/null || echo "0")
        behind=$(git rev-list --right-only --count @{u}...HEAD 2>/dev/null || echo "0")
    fi

    # Store fields (tab-separated):
    # ts_raw   dir  branch  hash  dirty  ahead  behind  ts_hr
    echo -e "${ts_raw}\t${dir}\t${branch}\t${hash}\t${dirty}\t${ahead}\t${behind}\t${ts_hr}" \
        >> "$TMPFILE"

    REPO_DIRS+=("$dir")

    popd >/dev/null
done

# ────────────────────────────────────────────────────────────────
# MULTI-LEVEL SORT (Dirty → Newest → Ahead → Behind → Name)
# ────────────────────────────────────────────────────────────────
awk -F'\t' '
{
    ts=$1; dir=$2; br=$3; hash=$4; dirty=$5; ahead=$6; behind=$7; ts_hr=$8;
    dirtflag = (dirty=="dirty" ? 1 : 0);
    # prefix: dirtflag | ts | ahead | behind | dir | orig_line
    print dirtflag "\t" ts "\t" ahead "\t" behind "\t" dir "\t" $0;
}
' "$TMPFILE" \
| sort -t $'\t' -k1,1nr -k2,2nr -k3,3nr -k4,4n -k5,5 \
> "$SORTED"

# Strip sort prefix → FINAL holds original fields
cut -f6- "$SORTED" > "$FINAL"

# ────────────────────────────────────────────────────────────────
# BEST VERSION HEURISTIC
# ────────────────────────────────────────────────────────────────
BEST_PATH=""
if [[ "$BEST" == "yes" ]]; then
    BEST_PATH=$(
        awk -F'\t' '
        {
            ts=$1; dir=$2; br=$3; hash=$4; dirty=$5; ahead=$6; behind=$7;
            d=(dirty=="dirty"?1:0);
            score=(d*1000)+(ahead*10)+ts-behind;
            print score "\t" dir;
        }' "$FINAL" \
        | sort -nr | head -n1 | cut -f2
    )
fi

# ────────────────────────────────────────────────────────────────
# DIFF SUMMARY vs BEST
# ────────────────────────────────────────────────────────────────
run_diff_summaries() {
    [[ "$DIFF_LEVEL" == "none" ]] && return 0
    if [[ -z "$BEST_PATH" ]]; then
        echo "⚠️  Diff level requested, but BEST repo is not determined (use --best). Skipping diffs."
        return 0
    fi

    echo
    echo "====== DIFF SUMMARY vs BEST: $BEST_PATH ======"

    for dir in "${REPO_DIRS[@]}"; do
        # skip BEST itself
        if [[ "$dir" == "$BEST_PATH" ]]; then
            continue
        fi

        echo
        echo "── Comparing:"
        echo "   BEST : $BEST_PATH"
        echo "   OTHER: $dir"

        case "$DIFF_LEVEL" in
            summary)
                # Count differences using diff -qr (respecting patterns)
                only_in_best=0
                only_in_other=0
                differ=0

                # directory-level stats (top-level dirs)
                declare -A dir_best=()
                declare -A dir_other=()
                declare -A dir_diff=()

                while IFS= read -r line; do
                    case "$line" in
                        "Only in "*)
                            # Format: Only in DIR: FILE
                            # Extract DIR and FILE
                            # Example: Only in /path/to/dir: filename
                            dir_part=${line#Only in }
                            dir_part=${dir_part%%:*}
                            file_part=${line#*: }
                            full_path="${dir_part}/${file_part}"

                            if ! matches_diff_patterns "$full_path"; then
                                continue
                            fi

                            # determine which side
                            if [[ "$dir_part" == "$BEST_PATH"* ]]; then
                                ((only_in_best++))
                                rel="${full_path#$BEST_PATH/}"
                                top="${rel%%/*}"
                                [[ -z "$top" ]] && top="$rel"
                                ((dir_best["$top"]++))
                            elif [[ "$dir_part" == "$dir"* ]]; then
                                ((only_in_other++))
                                rel="${full_path#$dir/}"
                                top="${rel%%/*}"
                                [[ -z "$top" ]] && top="$rel"
                                ((dir_other["$top"]++))
                            fi
                            ;;
                        "Files "*)
                            # Format: Files PATH1 and PATH2 differ
                            path_part=${line#Files }
                            path1=${path_part%% and *}
                            path2=${path_part#* and }
                            path2=${path2% differ}

                            # use BEST side for dir summary
                            full_path="$path1"

                            if ! matches_diff_patterns "$full_path"; then
                                continue
                            fi

                            ((differ++))
                            rel="${full_path#$BEST_PATH/}"
                            top="${rel%%/*}"
                            [[ -z "$top" ]] && top="$rel"
                            ((dir_diff["$top"]++))
                            ;;
                    esac
                done < <(diff -qr --exclude='.git' "$BEST_PATH" "$dir" 2>/dev/null || true)

                echo "   Files only in BEST:   $only_in_best"
                echo "   Files only in OTHER:  $only_in_other"
                echo "   Files differing:      $differ"

                if ((only_in_best > 0)); then
                    echo "   Top-level dirs (BEST-only):"
                    for k in "${!dir_best[@]}"; do
                        echo "      $k: ${dir_best[$k]}"
                    done
                fi
                if ((only_in_other > 0)); then
                    echo "   Top-level dirs (OTHER-only):"
                    for k in "${!dir_other[@]}"; do
                        echo "      $k: ${dir_other[$k]}"
                    done
                fi
                if ((differ > 0)); then
                    echo "   Top-level dirs (differing files):"
                    for k in "${!dir_diff[@]}"; do
                        echo "      $k: ${dir_diff[$k]}"
                    done
                fi
                ;;

            per-file)
                echo "   Per-file differences:"
                diff_output="$(diff -qr --exclude='.git' "$BEST_PATH" "$dir" 2>/dev/null || true)"
                if [[ -z "$diff_output" ]]; then
                    echo "   (no differences)"
                else
                    while IFS= read -r line; do
                        case "$line" in
                            "Only in "*)
                                dir_part=${line#Only in }
                                dir_part=${dir_part%%:*}
                                file_part=${line#*: }
                                full_path="${dir_part}/${file_part}"

                                if ! matches_diff_patterns "$full_path"; then
                                    continue
                                fi
                                echo "   $line"
                                ;;
                            "Files "*)
                                path_part=${line#Files }
                                path1=${path_part%% and *}
                                path2=${path_part#* and }
                                path2=${path2% differ}

                                if ! matches_diff_patterns "$path1"; then
                                    continue
                                fi

                                if [[ "$CHECKSUM" == "yes" ]]; then
                                    sha1=$(sha256sum "$path1" 2>/dev/null | awk '{print $1}')
                                    sha2=$(sha256sum "$path2" 2>/dev/null | awk '{print $1}')
                                    echo "   $line"
                                    echo "      SHA256 BEST : $sha1"
                                    echo "      SHA256 OTHER: $sha2"
                                else
                                    echo "   $line"
                                fi
                                ;;
                        esac
                    done <<< "$diff_output"
                fi
                ;;

            full)
                # Full diff into a separate file (patterns NOT applied here)
                d_sanitized=$(echo "$dir" | sed 's#[/ ]#_#g')
                best_sanitized=$(echo "$BEST_PATH" | sed 's#[/ ]#_#g')
                diff_file="${REPO}_full_diff_${d_sanitized}_VS_${best_sanitized}_${NOW}.diff"
                echo "   Writing full unified diff to: $diff_file"
                diff -ru --exclude='.git' "$BEST_PATH" "$dir" >"$diff_file" 2>&1 || true
                ;;
        esac
    done
}

# ────────────────────────────────────────────────────────────────
# DIRTY DETAIL REPORTING
# ────────────────────────────────────────────────────────────────
print_dirty_details() {
    [[ "$DIRTY_DETAIL" != "yes" ]] && return 0

    echo
    echo "====== DIRTY REPO DETAILS ======"

    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        [[ "$dirty" != "dirty" ]] && continue

        echo
        echo "Repo: $dir"
        echo "  Branch: $br"
        echo "  Last commit: $ts_hr"

        pushd "$dir" >/dev/null

        status_out="$(git status --porcelain 2>/dev/null || true)"
        if [[ -z "$status_out" ]]; then
            echo "  (marked dirty, but no porcelain output)"
            popd >/dev/null
            continue
        fi

        modified=()
        added=()
        deleted=()
        renamed=()
        untracked=()

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            code="${line:0:2}"
            file="${line:3}"
            case "$code" in
                "??") untracked+=("$file");;
                M*|*M) modified+=("$file");;
                A*|*A) added+=("$file");;
                D*|*D) deleted+=("$file");;
                R*|*R) renamed+=("$file");;
                *)
                    modified+=("$file");;
            esac
        done <<< "$status_out"

        if ((${#modified[@]} > 0)); then
            echo "  Modified:"
            for f in "${modified[@]}"; do
                echo "    - $f"
            done
        fi
        if ((${#added[@]} > 0)); then
            echo "  Added:"
            for f in "${added[@]}"; do
                echo "    - $f"
            done
        fi
        if ((${#deleted[@]} > 0)); then
            echo "  Deleted:"
            for f in "${deleted[@]}"; do
                echo "    - $f"
            done
        fi
        if ((${#renamed[@]} > 0)); then
            echo "  Renamed:"
            for f in "${renamed[@]}"; do
                echo "    - $f"
            done
        fi
        if ((${#untracked[@]} > 0)); then
            echo "  Untracked:"
            for f in "${untracked[@]}"; do
                echo "    - $f"
            done
        fi

        popd >/dev/null
    done < "$FINAL"
}

# ────────────────────────────────────────────────────────────────
# HUMAN-READABLE OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ -z "$OUTPUT" ]]; then
    printf "%-64s | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
        "REPO PATH" "BRANCH" "LAST COMMIT" "DIRTY" "AHEAD" "BEHIND"
    printf "%s\n" "$(printf '—%.0s' {1..150})"

    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        color="$CYAN"
        if [[ "$dirty" == "dirty" ]]; then
            color="$RED"
        elif (( ahead > 0 )); then
            color="$GREEN"
        elif (( behind > 0 )); then
            color="$YELLOW"
        fi

        printf "${color}%-64s${RESET} | %-20s | %-20s | %-8s | %-6s | %-6s\n" \
            "$dir" "$br" "$ts_hr" "$dirty" "$ahead" "$behind"
    done < "$FINAL"

    echo
    if [[ -n "$BEST_PATH" ]]; then
        echo -e "🏆 BEST VERSION (by heuristic): ${GREEN}${BEST_PATH}${RESET}"
    fi

    # Diff summaries (if requested)
    run_diff_summaries

    # Dirty-detail report (if requested)
    print_dirty_details

    exit 0
fi

# ────────────────────────────────────────────────────────────────
# JSON OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "json" ]]; then
    echo "["
    first=true
    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        [[ $first == false ]] && echo ","
        first=false
cat <<EOF
  {
    "repo_path": "$dir",
    "branch": "$br",
    "last_commit": "$ts_hr",
    "timestamp": $ts,
    "dirty": "$dirty",
    "ahead": $ahead,
    "behind": $behind,
    "hash": "$hash",
    "best": $( [[ "$dir" == "$BEST_PATH" ]] && echo "true" || echo "false" )
  }
EOF
    done < "$FINAL"
    echo "]"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# CSV OUTPUT
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "csv" ]]; then
    echo "repo_path,branch,last_commit,timestamp,dirty,ahead,behind,hash,best"
    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        echo "\"$dir\",\"$br\",\"$ts_hr\",$ts,\"$dirty\",$ahead,$behind,\"$hash\",\"$( [[ "$dir" == "$BEST_PATH" ]] && echo true || echo false )\""
    done < "$FINAL"
    exit 0
fi

# ────────────────────────────────────────────────────────────────
# HTML OUTPUT (dark theme, clickable headers to sort)
# ────────────────────────────────────────────────────────────────
if [[ "$OUTPUT" == "html" ]]; then
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${REPO} repo comparison (${NOW})</title>
<style>
body { font-family: sans-serif; background: #111; color: #eee; }
table { border-collapse: collapse; width: 100%; margin-top: 1em; }
th, td { border: 1px solid #444; padding: 4px 8px; font-size: 13px; }
th { background: #222; cursor: pointer; }
tr.dirty { background-color: #441111; }
tr.ahead { background-color: #113311; }
tr.behind { background-color: #444411; }
tr.clean  { background-color: #111122; }
tr.best   { outline: 2px solid #55ff55; }
caption { font-weight: bold; margin-bottom: 0.5em; }
</style>
<script>
// Simple table sort by column index
function sortTable(n) {
  var table = document.getElementById("repotable");
  var rows = Array.prototype.slice.call(table.rows, 1); // skip header
  var asc = table.getAttribute("data-sortdir") !== "asc";
  rows.sort(function(a, b) {
    var A = a.cells[n].innerText;
    var B = b.cells[n].innerText;
    var numA = parseFloat(A);
    var numB = parseFloat(B);
    if (!isNaN(numA) && !isNaN(numB)) {
      return asc ? (numA - numB) : (numB - numA);
    }
    return asc ? A.localeCompare(B) : B.localeCompare(A);
  });
  rows.forEach(function(r){ table.tBodies[0].appendChild(r); });
  table.setAttribute("data-sortdir", asc ? "asc" : "desc");
}
</script>
</head>
<body>
<h1>Repo comparison for: ${REPO}</h1>
<p>Generated: ${NOW}</p>
<table id="repotable" data-sortdir="asc">
<caption>Dirty → Newest → Ahead → Behind → Alphabetical</caption>
<thead>
<tr>
  <th onclick="sortTable(0)">Repo Path</th>
  <th onclick="sortTable(1)">Branch</th>
  <th onclick="sortTable(2)">Last Commit</th>
  <th onclick="sortTable(3)">Dirty</th>
  <th onclick="sortTable(4)">Ahead</th>
  <th onclick="sortTable(5)">Behind</th>
</tr>
</thead>
<tbody>
EOF

    while IFS=$'\t' read -r ts dir br hash dirty ahead behind ts_hr; do
        rowclass="clean"
        if [[ "$dirty" == "dirty" ]]; then
            rowclass="dirty"
        elif (( ahead > 0 )); then
            rowclass="ahead"
        elif (( behind > 0 )); then
            rowclass="behind"
        fi
        if [[ "$dir" == "$BEST_PATH" ]]; then
            rowclass="$rowclass best"
        fi
        printf '<tr class="%s"><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
            "$rowclass" "$dir" "$br" "$ts_hr" "$dirty" "$ahead" "$behind"
    done < "$FINAL"

    cat <<EOF
</tbody>
</table>
EOF

    if [[ -n "$BEST_PATH" ]]; then
        echo "<p><strong>BEST VERSION:</strong> $BEST_PATH</p>"
    fi

    echo "</body></html>"
    exit 0
fi

echo "❌ Unknown --output mode: $OUTPUT"
exit 1

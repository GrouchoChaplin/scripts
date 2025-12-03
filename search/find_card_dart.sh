#!/usr/bin/env bash
#
# find_card_dart.sh — v1.4.6
#
# Search matching directories for files, show mtime + SHA256, group, diff,
# export JSON/CSV, generate HTML reports, etc.
#

set -euo pipefail

SCRIPT_NAME="find_card_dart.sh"
SCRIPT_VERSION="1.4.6"

############################################
# Defaults
############################################
MAX_DEPTH=""
SINCE=""
FORMAT="raw"
GROUP_MODE=""       # parent | filename | empty
FZF_MODE=0
PREVIEW=0
HASH_ONLY=0
DIFF_MODE=0
HTML_REPORT=""
SUMMARY_ONLY=0

PATTERN_DIR="*/features/card*"
PATTERN_FILE="*.dart"

COLOR_ENABLED=1
NO_COLOR=0
FORCE_COLOR=0

C_DATE="\033[1;36m"
C_SHA="\033[1;33m"
C_PATH="\033[1;32m"
C_RESET="\033[0m"

disable_colors() {
    C_DATE=""
    C_SHA=""
    C_PATH=""
    C_RESET=""
}

############################################
# Key sanitization for associative arrays
############################################
sanitize_key() {
    local k="$1"

    # Strip CR (\r)
    k="${k//$'\r'/}"

    # Strip leading whitespace
    k="${k#"${k%%[![:space:]]*}"}"

    # Strip trailing whitespace
    k="${k%"${k##*[![:space:]]}"}"

    # Remove ASCII control characters
    k="$(printf "%s" "$k" | tr -d '\000-\031')"

    # Fallback: never allow empty keys
    [[ -z "$k" ]] && k="_EMPTY_"

    printf "%s" "$k"
}

############################################
# Help
############################################
usage() {
    cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Usage:
  ${SCRIPT_NAME} [OPTIONS] DIR1 [DIR2 ...]

Search directories for files matching patterns, and display mtime + SHA256
with multiple views and export options.

Search/filter options:
  --pattern-dir PAT       Directory path pattern (default: "*/features/card*")
  --pattern-file PAT      File name pattern     (default: "*.dart")
  --max-depth N
  --since "WHEN"          Only include files newer than WHEN (find -newermt)

Output options:
  --format FMT            raw | table | json | csv   (default: raw)
  --group [parent|filename]
  --hash-only
  --summary-only

Tools:
  --diff
  --fzf
  --preview
  --html-report FILE

Color:
  --no-color
  --force-color

Other:
  --help
  --version
EOF
}

print_version() {
    echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
}

############################################
# Parse arguments
############################################
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pattern-dir)   PATTERN_DIR=$2; shift 2;;
        --pattern-file)  PATTERN_FILE=$2; shift 2;;
        --max-depth)     MAX_DEPTH=$2; shift 2;;
        --since)         SINCE=$2; shift 2;;
        --format)        FORMAT=$2; shift 2;;
        --group)
            if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
                GROUP_MODE="$2"; shift 2
            else
                GROUP_MODE="parent"; shift
            fi
            ;;
        --fzf)           FZF_MODE=1; shift;;
        --preview)       PREVIEW=1; shift;;
        --hash-only)     HASH_ONLY=1; shift;;
        --diff)          DIFF_MODE=1; shift;;
        --html-report)   HTML_REPORT=$2; shift 2;;
        --summary-only)  SUMMARY_ONLY=1; shift;;
        --no-color)      NO_COLOR=1; shift;;
        --force-color)   FORCE_COLOR=1; shift;;
        --help)          usage; exit 0;;
        --version)       print_version; exit 0;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1;;
        *)
            ARGS+=("$1"); shift;;
    esac
done

if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "ERROR: You must specify one or more directories." >&2
    exit 1
fi

TOP_DIRS=("${ARGS[@]}")

############################################
# Color detection
############################################
if [[ $NO_COLOR -eq 1 ]]; then
    COLOR_ENABLED=0
elif [[ $FORCE_COLOR -eq 1 ]]; then
    COLOR_ENABLED=1
elif [[ -t 1 ]]; then
    COLOR_ENABLED=1
else
    COLOR_ENABLED=0
fi

if [[ $COLOR_ENABLED -eq 0 ]]; then
    disable_colors
fi

############################################
# Build find options
############################################
FIND_OPTS=()
[[ -n "$MAX_DEPTH" ]] && FIND_OPTS+=( -maxdepth "$MAX_DEPTH" )
SINCE_OPT=()
[[ -n "$SINCE" ]] && SINCE_OPT+=( -newermt "$SINCE" )

############################################
# Collect files
############################################
RESULTS=()

collect_files() {
    find "${TOP_DIRS[@]}" \
        "${FIND_OPTS[@]}" \
        -type d -path "$PATTERN_DIR" 2>/dev/null |
    while IFS= read -r dir; do
        find "$dir" -type f -name "$PATTERN_FILE" "${SINCE_OPT[@]}" -print0
    done
}

while IFS= read -r -d '' FILE; do
    SHA=$(sha256sum "$FILE" | awk '{print $1}')
    DATE=$(stat -c "%y" "$FILE")
    PARENT=$(dirname "$FILE")
    BASENAME=$(basename "$FILE")

    RESULTS+=("$DATE|$SHA|$FILE|$PARENT|$BASENAME")
done < <(collect_files)

############################################
# Sort results
############################################
if [[ ${#RESULTS[@]} -eq 0 ]]; then
    echo "No matching files found."
    exit 0
fi

mapfile -t SORTED < <(printf '%s\n' "${RESULTS[@]}" | sort -r)

############################################
# Raw / table / JSON / CSV
############################################
output_raw() {
    for entry in "${SORTED[@]}"; do
        IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"
        if [[ $HASH_ONLY -eq 1 ]]; then
            printf "%s%s%s %s%s%s\n" \
                "$C_SHA" "$SHA" "$C_RESET" \
                "$C_PATH" "$FILE" "$C_RESET"
        else
            printf "%s%s%s %s%s%s %s%s%s\n" \
                "$C_DATE" "$DATE" "$C_RESET" \
                "$C_SHA" "$SHA" "$C_RESET" \
                "$C_PATH" "$FILE" "$C_RESET"
        fi
    done
}

output_table() {
    {
        echo -e "DATE\tSHA256\tFILE"
        for entry in "${SORTED[@]}"; do
            IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"
            echo -e "$DATE\t$SHA\t$FILE"
        done
    } | column -t -s $'\t'
}

output_json() {
    jq -Rn '
        [ inputs
          | split("|")
          | {"date":.[0],"sha256":.[1],"file":.[2],"parent":.[3],"basename":.[4]}
        ]
    ' <<<"$(printf '%s\n' "${SORTED[@]}")"
}

output_csv() {
    echo "date,sha256,file,parent,basename"
    for entry in "${SORTED[@]}"; do
        IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"
        printf '"%s","%s","%s","%s","%s"\n' \
            "$DATE" "$SHA" "$FILE" "$PARENT" "$BASENAME"
    done
}

############################################
# Group by parent / filename (Option B — clean rows)
############################################
output_grouped_by_parent() {
    printf '%s\n' "${SORTED[@]}" | awk -F'|' '
    {
        parent=$4; date=$1; sha=$2; file=$3;
        data[parent] = data[parent] sprintf("%s  %s  %s\n", date, sha, file);
    }
    END {
        for (p in data) {
            print "";
            printf "=== %s ===\n", p;
            printf "%-26s %-64s %s\n", "DATE", "SHA256", "FILE";
            printf "%-26s %-64s %s\n", "------------------------", "----------------------------------------------------------------", "----";
            printf "%s", data[p];
        }
    }'
}

output_grouped_by_filename() {
    printf '%s\n' "${SORTED[@]}" | awk -F'|' '
    {
        base=$5; date=$1; sha=$2; file=$3;
        data[base] = data[base] sprintf("%s  %s  %s\n", date, sha, file);
    }
    END {
        for (b in data) {
            print "";
            printf "=== %s ===\n", b;
            printf "%-26s %-64s %s\n", "DATE", "SHA256", "FILE";
            printf "%-26s %-64s %s\n", "------------------------", "----------------------------------------------------------------", "----";
            printf "%s", data[b];
        }
    }'
}

############################################
# Summary-only (set -u + sanitize_key)
############################################
output_summary() {
    declare -A base_counts parent_counts

    for entry in "${SORTED[@]}"; do
        IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"

        key="$(sanitize_key "$BASENAME")"
        base_counts["$key"]=$(( ${base_counts["$key"]:-0} + 1 ))

        pkey="$(sanitize_key "$PARENT")"
        parent_counts["$pkey"]=$(( ${parent_counts["$pkey"]:-0} + 1 ))
    done

    echo "Summary:"
    echo "  Total files: ${#SORTED[@]}"
    echo

    echo "By basename:"
    for base in "${!base_counts[@]:-}"; do
        printf "  %-40s %5d\n" "$base" "${base_counts[$base]}"
    done

    echo
    echo "By parent directory:"
    for parent in "${!parent_counts[@]:-}"; do
        printf "  %-60s %5d\n" "$parent" "${parent_counts[$parent]}"
    done
}

############################################
# Diff mode
############################################
run_diff_mode() {
    declare -A groups
    for entry in "${SORTED[@]}"; do
        IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"
        groups["$BASENAME"]+="$FILE"$'\n'
    done

    for base in "${!groups[@]:-}"; do
        mapfile -t files <<<"${groups[$base]}"
        (( ${#files[@]} < 2 )) && continue
        echo
        echo "#############################"
        echo "# Diffs for basename: $base"
        echo "#############################"
        for ((i=0; i<${#files[@]}-1; i++)); do
            for ((j=i+1; j<${#files[@]}; j++)); do
                f1=${files[i]}
                f2=${files[j]}
                echo
                echo "=== diff: $f1  VS  $f2 ==="
                diff -u --label "$f1" --label "$f2" "$f1" "$f2" || true
            done
        done
    done
}

############################################
# fzf dashboard
############################################
run_fzf() {
    printf '%s\n' "${SORTED[@]}" |
        fzf --with-nth=1,2,3 --delimiter="|" \
            --preview "echo {} | awk -F'|' '{print \$3}' | xargs bat --color=always"
}

############################################
# Preview mode
############################################
run_preview() {
    output_raw | less -R
}

############################################
# HTML report (awk-based counts)
############################################
output_html_report() {
    local out_file="$1"

    {
cat <<'HEAD'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>find_card_dart Report</title>
<style>
body{font-family:system-ui,sans-serif;margin:2rem;}
table{border-collapse:collapse;width:100%;margin-top:1rem;}
th,td{border:1px solid #ccc;padding:4px 8px;font-size:.85rem;}
th{background:#eee;}
.code{font-family:monospace;}
.chart{max-width:900px;margin:2rem auto;}
</style>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
<h1>find_card_dart Report</h1>
HEAD

        echo "<h2>Files</h2>"
        echo "<table>"
        echo "<tr><th>Date</th><th>SHA256</th><th>File</th><th>Parent</th><th>Basename</th></tr>"

        for entry in "${SORTED[@]}"; do
            IFS="|" read -r DATE SHA FILE PARENT BASENAME <<<"$entry"
            printf '<tr><td class="code">%s</td><td class="code">%s</td><td class="code">%s</td><td>%s</td><td>%s</td></tr>\n' \
                "$DATE" "$SHA" "$FILE" "$PARENT" "$BASENAME"
        done

        echo "</table>"

        echo "<div class='chart'><canvas id='basenameChart'></canvas></div>"
        echo "<div class='chart'><canvas id='parentChart'></canvas></div>"

        echo "<script>"
        printf '%s\n' "${SORTED[@]}" | awk -F'|' '
        {
            b=$5; p=$4
            basenameCount[b]++
            parentCount[p]++
        }
        END {
            printf "const basenameLabels = ["
            first=1
            for (b in basenameCount) {
                if (!first) printf ","
                gsub(/\\/,"\\\\",b)
                gsub(/"/,"\\\"",b)
                printf "\"%s\"", b
                first=0
            }
            print "];"

            printf "const basenameCounts = ["
            first=1
            for (b in basenameCount) {
                if (!first) printf ","
                printf "%d", basenameCount[b]
                first=0
            }
            print "];"

            printf "const parentLabels = ["
            first=1
            for (p in parentCount) {
                if (!first) printf ","
                gsub(/\\/,"\\\\",p)
                gsub(/"/,"\\\"",p)
                printf "\"%s\"", p
                first=0
            }
            print "];"

            printf "const parentCounts = ["
            first=1
            for (p in parentCount) {
                if (!first) printf ","
                printf "%d", parentCount[p]
                first=0
            }
            print "];"
        }'
cat <<'SCRIPT'
function makeChart(id, labels, data, label){
  new Chart(document.getElementById(id).getContext('2d'),{
    type:'bar',
    data:{labels:labels,datasets:[{label:label,data:data}]},
    options:{
      responsive:true,
      plugins:{legend:{display:false}},
      scales:{x:{ticks:{autoSkip:true,maxRotation:90,minRotation:45}}}
    }
  });
}
makeChart('basenameChart', basenameLabels, basenameCounts, 'Files per Basename');
makeChart('parentChart', parentLabels, parentCounts, 'Files per Parent Directory');
</script>
</body>
</html>
SCRIPT

    } > "$out_file"

    echo "HTML report written to: $out_file" >&2
}

############################################
# Dispatch
############################################
if [[ $FZF_MODE -eq 1 ]]; then
    run_fzf
    exit 0
fi

if [[ $DIFF_MODE -eq 1 ]]; then
    run_diff_mode
    [[ -n "$HTML_REPORT" ]] && output_html_report "$HTML_REPORT"
    exit 0
fi

if [[ $SUMMARY_ONLY -eq 1 ]]; then
    output_summary
    [[ -n "$HTML_REPORT" ]] && output_html_report "$HTML_REPORT"
    exit 0
fi

if [[ $PREVIEW -eq 1 ]]; then
    run_preview
    [[ -n "$HTML_REPORT" ]] && output_html_report "$HTML_REPORT"
    exit 0
fi

if [[ -n "$GROUP_MODE" ]]; then
    case "$GROUP_MODE" in
        parent)   output_grouped_by_parent ;;
        filename) output_grouped_by_filename ;;
        *)        echo "Invalid --group: $GROUP_MODE" >&2; exit 1;;
    esac

    [[ -n "$HTML_REPORT" ]] && output_html_report "$HTML_REPORT"
    exit 0
fi

case "$FORMAT" in
    raw)   output_raw ;;
    table) output_table ;;
    json)  output_json ;;
    csv)   output_csv ;;
    *)     echo "Invalid --format: $FORMAT" >&2; exit 1;;
esac

[[ -n "$HTML_REPORT" ]] && output_html_report "$HTML_REPORT"

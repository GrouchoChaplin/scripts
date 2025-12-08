#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.4
# ------------------------------------------------------------
# New in v1.4:
#  - --source-only: ignore native/binary artifacts like .so, .dll, .a, .o, .dylib
#    (CMakeLists.txt is always treated as source and is NOT excluded)
#  - --top-projects N: list top N projects by recency
#  - --rank-lib-only: only consider lib/ + pubspec.yaml for project recency ranking
# ------------------------------------------------------------

set -euo pipefail

VERSION="1.4"

########################################
# Color helpers
########################################
red()    { printf "\e[31m%s\e[0m" "$1"; }
green()  { printf "\e[32m%s\e[0m" "$1"; }
yellow() { printf "\e[33m%s\e[0m" "$1"; }
cyan()   { printf "\e[36m%s\e[0m" "$1"; }
bold()   { printf "\e[1m%s\e[0m" "$1"; }

########################################
# Defaults
########################################
TOP=20
TOP_PROJECTS=0
SINCE=""
HTML_REPORT=0
JSON_REPORT=0
CSV_REPORT=0
FZF_MODE=0
EXCLUDE_BUILD=1
SOURCE_ONLY=0
RANK_LIB_ONLY=0
PATH_PATTERNS=()

########################################
# Usage
########################################
usage() {
cat <<EOF
$(bold "Flutter Source Version Finder v$VERSION")

Usage:
  find_latest_flutter_source.sh --paths DIR1 [DIR2 ...] [options]

Options:
  --paths DIR1 DIR2 ...   Paths or glob patterns to scan (required)
  --top N                 Show top N modified files (default 20)
  --top-projects N        Show top N projects by recency
  --since YYYY-MM-DD      Only return files newer than this date
  --html-report           Generate flutter_source_report.html
  --json                  Generate flutter_source_report.json
  --csv                   Generate flutter_source_report.csv
  --fzf                   Launch interactive browser (if fzf is installed)
  --exclude-build         Exclude build dirs (default)
  --include-build         Include build dirs
  --source-only           Ignore native/binary files (.so, .dll, .a, .o, .dylib)
                          (CMakeLists.txt is still considered source)
  --rank-lib-only         Only consider lib/ + pubspec.yaml when ranking project recency
  --help                  Show help

Examples:
  find_latest_flutter_source.sh \\
      --paths "/run/media/*/ProjectWorkingCopyBackups/ir_imagery_tools*" \\
      --source-only --top 30 --top-projects 5 --html-report --rank-lib-only

EOF
exit 1
}

########################################
# Parse args
########################################
while [[ $# -gt 0 ]]; do
    case "$1" in
        --paths)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                PATH_PATTERNS+=("$1")
                shift
            done
            continue
            ;;
        --top) TOP="$2"; shift 2 ;;
        --top-projects) TOP_PROJECTS="$2"; shift 2 ;;
        --since) SINCE="$2"; shift 2 ;;
        --html-report) HTML_REPORT=1; shift ;;
        --json) JSON_REPORT=1; shift ;;
        --csv) CSV_REPORT=1; shift ;;
        --fzf) FZF_MODE=1; shift ;;
        --exclude-build) EXCLUDE_BUILD=1; shift ;;
        --include-build) EXCLUDE_BUILD=0; shift ;;
        --source-only) SOURCE_ONLY=1; shift ;;
        --rank-lib-only) RANK_LIB_ONLY=1; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ ${#PATH_PATTERNS[@]} -eq 0 ]]; then
    usage
fi

########################################
# Expand directory patterns
########################################
EXPANDED_PATHS=()

for pattern in "${PATH_PATTERNS[@]}"; do
    matches=( $pattern ) || true

    if [[ ${#matches[@]} -eq 0 ]]; then
        yellow "Warning: Pattern matched no directories: $pattern\n"
        continue
    fi

    for m in "${matches[@]}"; do
        [[ -d "$m" ]] && EXPANDED_PATHS+=("$m")
    done
done

if [[ ${#EXPANDED_PATHS[@]} -eq 0 ]]; then
    red "Error: No directories matched the --paths patterns"
    exit 1
fi

########################################
# Build safe include patterns
########################################
include_sources=(
    "-name" "*.dart"
    "-o" "-name" "pubspec.yaml"
    "-o" "-name" "pubspec.lock"
    "-o" "-name" "CMakeLists.txt"
    "-o" "-name" "*.cmake"
    "-o" "-name" "*.json"
    "-o" "-name" "*.yaml"
    "-o" "-path" "*/assets/*"
    "-o" "-path" "*/lib/*"
    "-o" "-path" "*/linux/*"
    "-o" "-path" "*/windows/*"
    "-o" "-path" "*/macos/*"
    "-o" "-path" "*/android/*"
)

build_excludes=(
    "!" "-path" "*/build/*"
    "!" "-path" "*/.dart_tool/*"
    "!" "-path" "*/linux/flutter/ephemeral/*"
    "!" "-path" "*/.idea/*"
    "!" "-path" "*/.vscode/*"
)

# Extra excludes when --source-only (ignore native/binary artifacts)
# NOTE: No mention of CMakeLists.txt here -> it is ALWAYS treated as source.
source_excludes=(
    "!" "-name" "*.so"
    "!" "-name" "*.a"
    "!" "-name" "*.o"
    "!" "-name" "*.dll"
    "!" "-name" "*.dylib"
)

########################################
# Construct find command
########################################
FIND_CMD=( find )

for d in "${EXPANDED_PATHS[@]}"; do
    FIND_CMD+=( "$d" )
done

FIND_CMD+=( -type f "(" "${include_sources[@]}" ")" )

if [[ $EXCLUDE_BUILD -eq 1 ]]; then
    for token in "${build_excludes[@]}"; do
        FIND_CMD+=( "$token" )
    done
fi

if [[ $SOURCE_ONLY -eq 1 ]]; then
    for token in "${source_excludes[@]}"; do
        FIND_CMD+=( "$token" )
    done
fi

FIND_CMD+=( -printf "%T@ %TY-%Tm-%Td %TH:%TM:%TS %p\n" )

########################################
# Execute scan
########################################
echo -e "$(cyan "Scanning Flutter projects…")"
RAW_OUTPUT=$(mktemp)
"${FIND_CMD[@]}" 2>/dev/null | sort -nr > "$RAW_OUTPUT"

########################################
# Filter by --since
########################################
if [[ -n "$SINCE" ]]; then
    since_epoch=$(date -d "$SINCE" +%s)
    FILTERED=$(mktemp)
    awk -v limit="$since_epoch" '$1 >= limit {print}' "$RAW_OUTPUT" > "$FILTERED"
    mv "$FILTERED" "$RAW_OUTPUT"
fi

########################################
# Find real project root upward
########################################
find_project_root() {
    local f="$1"
    local d
    d=$(dirname "$f")

    # walk upward until we find pubspec.yaml
    while [[ "$d" != "/" ]]; do
        if [[ -f "$d/pubspec.yaml" ]]; then
            echo "$d"
            return
        fi
        d=$(dirname "$d")
    done

    # fallback: directory of the file
    echo "$(dirname "$f")"
}

########################################
# Build project metadata
########################################
declare -A latest_src
declare -A latest_src_epoch
declare -A file_count
declare -A git_last_commit

while read -r epoch date time path; do
    project_root=$(find_project_root "$path")
    [[ -z "$project_root" ]] && continue

    epoch_int=${epoch%.*}
    base_name=$(basename "$path")

    # decide if this file participates in project recency ranking
    consider_for_rank=1
    if [[ $RANK_LIB_ONLY -eq 1 ]]; then
        if [[ "$path" != */lib/* && "$base_name" != "pubspec.yaml" ]]; then
            consider_for_rank=0
        fi
    fi

    if [[ $consider_for_rank -eq 1 ]]; then
        if [[ -z "${latest_src_epoch[$project_root]+x}" || $epoch_int -gt ${latest_src_epoch[$project_root]} ]]; then
            latest_src_epoch[$project_root]=$epoch_int
            latest_src[$project_root]="$date $time"
        fi
    fi

    # modify heatmap count (safe with set -u)
    file_count[$project_root]=$(( ${file_count[$project_root]:-0} + 1 ))

    # discover git commit (once)
    if [[ -d "$project_root/.git" && -z "${git_last_commit[$project_root]+x}" ]]; then
        git_last_commit[$project_root]=$(cd "$project_root" && git log -1 --pretty='%cs %h' 2>/dev/null || echo "(no git)")
    fi
done < "$RAW_OUTPUT"

########################################
# Determine best-guess latest project
########################################
best_project=""
best_epoch=0

for p in "${!latest_src_epoch[@]}"; do
    if [[ -z "$best_project" || ${latest_src_epoch[$p]} -gt $best_epoch ]]; then
        best_project="$p"
        best_epoch=${latest_src_epoch[$p]}
    fi
done

########################################
# Dashboard Summary
########################################
echo ""
echo "$(bold "📊 Dashboard Summary (v$VERSION)")"
echo "-----------------------------------------------------------------------------"

if [[ -n "$best_project" ]]; then
    echo "Best-guess latest project:"
    echo "  $(green "$best_project")  (latest ranked source: ${latest_src[$best_project]:-unknown})"
    if [[ $RANK_LIB_ONLY -eq 1 ]]; then
        echo "  (ranking based on lib/ + pubspec.yaml only)"
    fi
    echo "-----------------------------------------------------------------------------"
fi

printf "%-45s %-22s %-18s %-10s\n" "Project Root" "Latest Ranked Source" "Git Commit" "Files"

for p in "${!latest_src[@]}"; do
    ls="${latest_src[$p]}"
    fc="${file_count[$p]:-0}"
    gc="${git_last_commit[$p]:-(no git)}"

    printf "%-45s %-22s %-18s %-10s\n" "$(green "$p")" "$ls" "$gc" "$fc"
done

########################################
# Top N Projects by recency (optional)
########################################
if [[ $TOP_PROJECTS -gt 0 ]]; then
    echo ""
    echo "$(bold "🏆 Top $TOP_PROJECTS Projects by Recency")"
    echo "-----------------------------------------------------------------------------"

    TMP_PROJ=$(mktemp)
    for p in "${!latest_src_epoch[@]}"; do
        printf "%s %s\n" "${latest_src_epoch[$p]}" "$p" >> "$TMP_PROJ"
    done

    rank=1
    sort -nr "$TMP_PROJ" | head -n "$TOP_PROJECTS" | while read -r epoch_val proj; do
        ts="${latest_src[$proj]}"
        fc="${file_count[$proj]:-0}"
        gc="${git_last_commit[$proj]:-(no git)}"
        printf "#%d  %-45s %-22s %-18s %s files\n" "$rank" "$(green "$proj")" "$ts" "$gc" "$fc"
        rank=$((rank+1))
    done
fi

########################################
# Top N Files
########################################
echo ""
echo "$(bold "📄 Top $TOP Modified Files")"
echo "-----------------------------------------------------------------------------"
head -n "$TOP" "$RAW_OUTPUT"

########################################
# JSON output
########################################
if [[ $JSON_REPORT -eq 1 ]]; then
    JSON_FILE="flutter_source_report.json"
    echo "Generating JSON → $JSON_FILE"

    {
      echo "{"
      echo "\"results\": ["
      first=1
      while read -r epoch date time path; do
          [[ $first -eq 0 ]] && echo ","
          printf "  {\"timestamp\": \"%s %s\", \"path\": \"%s\"}" "$date" "$time" "$path"
          first=0
      done < "$RAW_OUTPUT"
      echo "]}"
    } > "$JSON_FILE"
fi

########################################
# CSV output
########################################
if [[ $CSV_REPORT -eq 1 ]]; then
    CSV_FILE="flutter_source_report.csv"
    echo "Generating CSV → $CSV_FILE"
    {
      echo "timestamp,path"
      while read -r epoch date time path; do
          echo "\"$date $time\",\"$path\""
      done < "$RAW_OUTPUT"
    } > "$CSV_FILE"
fi

########################################
# HTML output
########################################
if [[ $HTML_REPORT -eq 1 ]]; then
    REPORT="flutter_source_report.html"
    echo "Generating HTML → $REPORT"

cat <<EOF > "$REPORT"
<html><head>
<title>Flutter Source Report</title>
<style>
body { font-family: sans-serif; margin: 20px; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #aaa; padding: 6px; }
th { background: #eee; cursor: pointer; }
</style>
<script>
function sortTable(n) {
  var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount=0;
  table = document.getElementById("table1");
  switching = true;
  dir = "asc";
  while (switching) {
    switching = false;
    rows = table.rows;
    for (i=1; i<(rows.length-1); i++) {
      shouldSwitch=false;
      x = rows[i].getElementsByTagName("TD")[n];
      y = rows[i+1].getElementsByTagName("TD")[n];
      if (dir=="asc" && x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
        shouldSwitch=true; break;
      }
      if (dir=="desc" && x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
        shouldSwitch=true; break;
      }
    }
    if (shouldSwitch) {
      rows[i].parentNode.insertBefore(rows[i+1], rows[i]);
      switching=true;
      switchcount++;
    } else {
      if (switchcount==0 && dir=="asc") {
        dir="desc"; switching=true;
      }
    }
  }
}
</script>
</head><body>
<h2>Flutter Source Modification Report</h2>
<table id="table1">
<tr>
  <th onclick="sortTable(0)">Timestamp</th>
  <th onclick="sortTable(1)">Path</th>
</tr>
EOF

    while read -r epoch date time path; do
        echo "<tr><td>$date $time</td><td>$path</td></tr>" >> "$REPORT"
    done < "$RAW_OUTPUT"

    echo "</table></body></html>" >> "$REPORT"
fi

########################################
# FZF Mode
########################################
if [[ $FZF_MODE -eq 1 ]]; then
    if ! command -v fzf >/dev/null 2>&1; then
        echo "$(yellow "fzf not found — skipping interactive browser. Install with: sudo dnf install fzf")"
    else
        echo "$(cyan "Launching fzf browser…")"
        PREVIEW_CMD="sed -n '1,200p' {}"
        command -v bat &>/dev/null && PREVIEW_CMD="bat --style=numbers --color=always {}"
        cut -d' ' -f4- "$RAW_OUTPUT" | fzf --preview "$PREVIEW_CMD"
    fi
fi

echo ""
echo "$(green "Done (v$VERSION).")"
exit 0

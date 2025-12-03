#!/usr/bin/env bash
#
# find_latest_flutter_source.sh
# Flutter Source Version Finder v1.6
#
# - Scans dirs for Flutter-ish projects
# - Ranks projects by latest source modification time
# - Can rank using lib/ + pubspec.yaml only
# - Optional HTML report with SHA256 + project overview
# - Robust project-root detection for nested backup trees
#
set -euo pipefail

VERSION="1.6"

########################################
# Color helpers
########################################
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'
  GREEN=$'\e[32m'
  CYAN=$'\e[36m'
  YELLOW=$'\e[33m'
  RESET=$'\e[0m'
else
  BOLD=""; GREEN=""; CYAN=""; YELLOW=""; RESET=""
fi

bold()  { printf '%b%s%b' "$BOLD" "$1" "$RESET"; }
green() { printf '%b%s%b' "$GREEN" "$1" "$RESET"; }
cyan()  { printf '%b%s%b' "$CYAN" "$1" "$RESET"; }
yellow(){ printf '%b%s%b' "$YELLOW" "$1" "$RESET"; }

########################################
# Defaults
########################################
PATH_PATTERNS=()
TOP_FILES=20
TOP_PROJECTS=0
HTML_REPORT=0
FZF_MODE=0
EXCLUDE_BUILD=1
SOURCE_ONLY=0
RANK_LIB_ONLY=0
SINCE_EPOCH=0
DEBUG=0
VALIDATE_PROJECT_ROOTS=0

########################################
# Usage
########################################
usage() {
  cat <<EOF
$(bold "find_latest_flutter_source.sh – Flutter Source Version Finder v$VERSION")

Options:
  --paths DIR1 [DIR2 ...]   One or more directories or glob patterns to scan
  --top N                   Show top N modified files (default: $TOP_FILES)
  --top-projects N          Show top N projects by recency
  --since DATE              Only consider files modified on/after DATE
                            (DATE passed to 'date -d', e.g. "2025-11-22")
  --html-report             Generate flutter_source_report.html
  --fzf                     Enable interactive fzf browser for files
  --source-only             Only consider source/config files (no .so/.a/etc)
                            Still includes CMakeLists.txt and *.cmake
  --rank-lib-only           Only lib/ + pubspec.yaml affect project recency
  --exclude-build           Exclude build/.dart_tool/.git (default)
  --no-exclude-build        Include build/.dart_tool/.git
  --debug                   Verbose internal logging to stderr
  --validate-project-roots  Only list detected project roots and exit

  -h, --help                Show this help

Example:
  find_latest_flutter_source.sh \\
    --paths "/run/media/peddycoartte/MasterBackup/ProjectWorkingCopyBackups/ir_imagery_tools*" \\
    --source-only --rank-lib-only --top 30 --top-projects 5 --html-report
EOF
}

debug() {
  if [[ $DEBUG -eq 1 ]]; then
    echo "$(yellow "[DEBUG]") $*" >&2
  fi
}

########################################
# Argument parsing
########################################
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

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
    --top)
      TOP_FILES="$2"; shift 2 ;;
    --top-projects)
      TOP_PROJECTS="$2"; shift 2 ;;
    --since)
      SINCE_EPOCH=$(date -d "$2" +%s); shift 2 ;;
    --html-report)
      HTML_REPORT=1; shift ;;
    --fzf)
      FZF_MODE=1; shift ;;
    --source-only)
      SOURCE_ONLY=1; shift ;;
    --rank-lib-only)
      RANK_LIB_ONLY=1; shift ;;
    --exclude-build)
      EXCLUDE_BUILD=1; shift ;;
    --no-exclude-build|--include-build)
      EXCLUDE_BUILD=0; shift ;;
    --debug)
      DEBUG=1; shift ;;
    --validate-project-roots)
      VALIDATE_PROJECT_ROOTS=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ${#PATH_PATTERNS[@]} -eq 0 ]]; then
  PATH_PATTERNS=(.)
fi

########################################
# Expand glob patterns into real dirs
########################################
SCAN_DIRS=()
for pat in "${PATH_PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  matched=( $pat )
  if [[ ${#matched[@]} -eq 0 ]]; then
    debug "Pattern matched nothing: $pat"
    continue
  fi
  for d in "${matched[@]}"; do
    if [[ -d "$d" ]]; then
      SCAN_DIRS+=("$d")
    else
      debug "Not a directory (skipped): $d"
    fi
  done
done

if [[ ${#SCAN_DIRS[@]} -eq 0 ]]; then
  echo "No directories matched for --paths patterns." >&2
  exit 1
fi

debug "Scan dirs: ${SCAN_DIRS[*]}"

########################################
# Temp files
########################################
TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/flutter_source.XXXXXX")
RAW_FILES="$TMPDIR/raw_files.tsv"      # epoch \t timestamp \t path
SORTED_FILES="$TMPDIR/sorted_files.tsv"
TOP_FILES_TSV="$TMPDIR/top_files.tsv"
PROJECT_SUMMARY="$TMPDIR/project_summary.tsv"
TOP_PROJECTS_TSV="$TMPDIR/top_projects.tsv"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

########################################
# Helpers
########################################
is_source_file() {
  # Used only when SOURCE_ONLY=1
  local f="$1"
  local base
  base=$(basename "$f")

  # Always allow pubspec + CMake
  case "$base" in
    pubspec.yaml|pubspec.lock|CMakeLists.txt) return 0 ;;
  esac

  # Obvious code/config extensions
  case "$f" in
    *.dart|*.cmake|*.cc|*.cpp|*.c|*.h|*.hpp|*.json|*.yaml|*.yml|*.sh)
      return 0
      ;;
  esac

  # Anything under lib/ is considered source-ish
  if [[ "$f" == */lib/* ]]; then
    return 0
  fi

  # Exclude binary-ish things
  case "$f" in
    *.so|*.a|*.o|*.dll|*.dylib|*~|*.swp)
      return 1
      ;;
  esac

  # Default: treat as non-source to keep SOURCE_ONLY tight
  return 1
}

find_project_root() {
  local path="$1"
  local dir
  dir=$(dirname "$path")

  local last_with_lib=""
  # climb upwards, prefer pubspec.yaml
  while [[ "$dir" != "/" && "$dir" != "." ]]; do
    if [[ -f "$dir/pubspec.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    if [[ -d "$dir/lib" ]]; then
      last_with_lib="$dir"
    fi
    dir=$(dirname "$dir")
  done

  # fallback: lib-based root if we saw one
  if [[ -n "$last_with_lib" ]]; then
    echo "$last_with_lib"
    return 0
  fi

  # final fallback: one of the scan roots that prefixes path
  for root in "${SCAN_DIRS[@]}"; do
    case "$path" in
      "$root"/*) echo "$root"; return 0 ;;
    esac
  done

  echo ""
  return 1
}

is_ranked_source() {
  local path="$1"
  local base
  base=$(basename "$path")

  if [[ $RANK_LIB_ONLY -eq 1 ]]; then
    if [[ "$path" == */lib/* ]]; then
      return 0
    fi
    case "$base" in
      pubspec.yaml|pubspec.lock) return 0 ;;
    esac
    return 1
  fi

  # otherwise, rank all files that passed SOURCE_ONLY/filters
  return 0
}

########################################
# Scan files (raw list)
########################################
echo "$(cyan "Scanning Flutter projects…")"

> "$RAW_FILES"

for dir in "${SCAN_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue

  debug "Scanning dir: $dir"

  # base find (exclude build /.git etc if requested)
  FIND=(find "$dir" -type f)
  if [[ $EXCLUDE_BUILD -eq 1 ]]; then
    FIND+=( -not -path "*/build/*"
            -not -path "*/.dart_tool/*"
            -not -path "*/.git/*"
            -not -path "*/.idea/*"
            -not -path "*/.vscode/*"
            -not -path "*/linux/flutter/ephemeral/*" )
  fi

  # run find
  "${FIND[@]}" -print0 | while IFS= read -r -d '' f; do
    if [[ $SOURCE_ONLY -eq 1 ]] && ! is_source_file "$f"; then
      debug "SOURCE_ONLY filtered: $f"
      continue
    fi

    local_epoch=$(stat -c '%Y' "$f" 2>/dev/null || echo 0)
    if (( SINCE_EPOCH > 0 && local_epoch < SINCE_EPOCH )); then
      debug "SINCE filtered: $f"
      continue
    fi
    local_ts=$(stat -c '%y' "$f" 2>/dev/null | sed 's/ [+-][0-9]\{2\}:[0-9]\{2\}$//')
    printf '%s\t%s\t%s\n' "$local_epoch" "$local_ts" "$f" >> "$RAW_FILES"
  done
done

if [[ ! -s "$RAW_FILES" ]]; then
  echo "No files found matching criteria."
  exit 0
fi

debug "RAW_FILES lines: $(wc -l < "$RAW_FILES")"

########################################
# Sort and top N files
########################################
sort -r -n -k1,1 "$RAW_FILES" > "$SORTED_FILES"
head -n "$TOP_FILES" "$SORTED_FILES" > "$TOP_FILES_TSV"

########################################
# Aggregate by project (using ALL files)
########################################
declare -A any_latest_epoch
declare -A any_latest_ts
declare -A ranked_latest_epoch
declare -A ranked_latest_ts
declare -A file_count
declare -A git_last_commit

while IFS=$'\t' read -r epoch ts path; do
  pr=$(find_project_root "$path")
  if [[ -z "$pr" ]]; then
    debug "No project root for: $path"
    continue
  fi

  # count files regardless of ranking
  file_count["$pr"]=$(( ${file_count["$pr"]:-0} + 1 ))

  # track any-file latest timestamp
  if [[ -z "${any_latest_epoch[$pr]+x}" || epoch -gt ${any_latest_epoch[$pr]} ]]; then
    any_latest_epoch["$pr"]=$epoch
    any_latest_ts["$pr"]="$ts"
  fi

  # ranking subset (lib/pubspec if RANK_LIB_ONLY)
  if is_ranked_source "$path"; then
    if [[ -z "${ranked_latest_epoch[$pr]+x}" || epoch -gt ${ranked_latest_epoch[$pr]} ]]; then
      ranked_latest_epoch["$pr"]=$epoch
      ranked_latest_ts["$pr"]="$ts"
    fi
  fi

  # git info only once
  if [[ -d "$pr/.git" && -z "${git_last_commit[$pr]+x}" ]]; then
    git_last_commit["$pr"]=$(
      cd "$pr" && git log -1 --pretty='%cs %h' 2>/dev/null || echo "(no git)"
    )
  fi
done < "$SORTED_FILES"

if [[ ${#file_count[@]} -eq 0 ]]; then
  echo "No project roots detected (no pubspec.yaml or lib/ found)."
  exit 0
fi

########################################
# Build project summary (prefer ranked, fallback to any)
########################################
> "$PROJECT_SUMMARY"

use_ranked=1
if [[ ${#ranked_latest_epoch[@]} -eq 0 ]]; then
  use_ranked=0
  debug "No ranked sources found; falling back to all files for project recency."
fi

for pr in "${!file_count[@]}"; do
  local_epoch=0
  local_ts=""
  if [[ $use_ranked -eq 1 && -n "${ranked_latest_epoch[$pr]+x}" ]]; then
    local_epoch=${ranked_latest_epoch[$pr]}
    local_ts=${ranked_latest_ts[$pr]}
  else
    local_epoch=${any_latest_epoch[$pr]}
    local_ts=${any_latest_ts[$pr]}
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$local_epoch" \
    "$local_ts" \
    "${git_last_commit[$pr]:-(no git)}" \
    "${file_count[$pr]:-0}" \
    "$pr" \
    >> "$PROJECT_SUMMARY"
done

sort -r -n -k1,1 "$PROJECT_SUMMARY" > "$TOP_PROJECTS_TSV"

# best-guess latest project
read -r BEST_EPOCH BEST_TS BEST_GIT BEST_COUNT BEST_ROOT < <(head -n1 "$TOP_PROJECTS_TSV")

debug "Best project: $BEST_ROOT @ $BEST_TS"

########################################
# Validation mode (just show roots, then exit)
########################################
if [[ $VALIDATE_PROJECT_ROOTS -eq 1 ]]; then
  echo "$(bold "Detected project roots:")"
  while IFS=$'\t' read -r epoch ts git files root; do
    has_pub="no"
    [[ -f "$root/pubspec.yaml" ]] && has_pub="yes"
    printf "%s (files=%s, pubspec=%s)\n" "$root" "$files" "$has_pub"
  done < "$TOP_PROJECTS_TSV"
  exit 0
fi

########################################
# Dashboard Summary (CLI)
########################################
echo ""
echo "$(bold "📊 Dashboard Summary (v$VERSION)")"
echo "-----------------------------------------------------------------------------"
echo "Best-guess latest project:"
echo "  $(green "$BEST_ROOT")  (latest ranked source: $BEST_TS)"
if [[ $use_ranked -eq 1 && $RANK_LIB_ONLY -eq 1 ]]; then
  echo "  (ranking based on lib/ + pubspec.yaml only)"
elif [[ $use_ranked -eq 1 ]]; then
  echo "  (ranking based on all ranked sources)"
else
  echo "  (no ranked sources under lib/ + pubspec; using all files)"
fi
echo "-----------------------------------------------------------------------------"
printf "%-45s %-22s %-18s %-10s\n" "Project Root" "Latest Ranked Source" "Git Commit" "Files"

while IFS=$'\t' read -r epoch ts git files root; do
  printf "%-45s %-22s %-18s %-10s\n" "$(green "$root")" "$ts" "$git" "$files"
done < "$TOP_PROJECTS_TSV"

########################################
# Top N Projects by recency (CLI)
########################################
if (( TOP_PROJECTS > 0 )); then
  echo ""
  echo "$(bold "🏆 Top $TOP_PROJECTS Projects by Recency")"
  echo "-----------------------------------------------------------------------------"
  rank=1
  while IFS=$'\t' read -r epoch ts git files root && (( rank <= TOP_PROJECTS )); do
    printf "#%d  %s %s (%s) %s files\n" \
      "$rank" \
      "$(green "$root")" \
      "$ts" \
      "$git" \
      "$files"
    ((rank++))
  done < "$TOP_PROJECTS_TSV"
fi

########################################
# Top N modified files (CLI)
########################################
echo ""
echo "$(bold "📄 Top $TOP_FILES Modified Files")"
echo "-----------------------------------------------------------------------------"
head -n "$TOP_FILES" "$SORTED_FILES" | while IFS=$'\t' read -r epoch ts path; do
  printf "%s.0000000000 %s %s\n" "$epoch" "$ts" "$path"
done

########################################
# HTML report
########################################
if [[ $HTML_REPORT -eq 1 ]]; then
  HTML="flutter_source_report.html"
  echo ""
  echo "Generating HTML → $HTML"

  {
    cat <<'EOF'
<html><head>
  <title>Flutter Source Report</title>
  <style>
    body { font-family: sans-serif; margin: 20px; }
    h2, h3 { margin-top: 1.4em; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 1.2em; }
    th, td { border: 1px solid #aaa; padding: 6px; font-size: 13px; }
    th { background: #eee; cursor: pointer; }
    .mono { font-family: monospace; }
    .tag { display: inline-block; padding: 2px 6px; border-radius: 4px; background: #eef; margin-left: 6px; font-size: 11px; }
  </style>
  <script>
    function sortTable(tableId, n) {
      var table, rows, switching, i, x, y, shouldSwitch, dir, switchcount = 0;
      table = document.getElementById(tableId);
      switching = true;
      dir = "asc";
      while (switching) {
        switching = false;
        rows = table.rows;
        for (i = 1; i < (rows.length - 1); i++) {
          shouldSwitch = false;
          x = rows[i].getElementsByTagName("TD")[n];
          y = rows[i + 1].getElementsByTagName("TD")[n];
          if (!x || !y) continue;
          if (dir == "asc" && x.innerHTML.toLowerCase() > y.innerHTML.toLowerCase()) {
            shouldSwitch = true;
            break;
          }
          if (dir == "desc" && x.innerHTML.toLowerCase() < y.innerHTML.toLowerCase()) {
            shouldSwitch = true;
            break;
          }
        }
        if (shouldSwitch) {
          rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
          switching = true;
          switchcount++;
        } else {
          if (switchcount == 0 && dir == "asc") {
            dir = "desc"; switching = true;
          }
        }
      }
    }
  </script>
</head><body>
EOF

    echo "  <h2>Flutter Source Modification Report (v$VERSION)</h2>"

    # Best project block
    echo "  <h3>Best-Guess Latest Project</h3>"
    echo "  <p>"
    printf '    <span class="mono">%s</span><br/>\n' "$BEST_ROOT"
    printf '    Latest ranked source: <span class="mono">%s</span><br/>\n' "$BEST_TS"
    printf '    Git: <span class="mono">%s</span><br/>\n' "$BEST_GIT"
    printf '    Files scanned: <span class="mono">%s</span><br/>\n' "$BEST_COUNT"
    printf '    <span class="tag">Ranking mode: %s</span>\n' "$(
      if [[ $use_ranked -eq 1 && $RANK_LIB_ONLY -eq 1 ]]; then
        echo "lib/ + pubspec.yaml only"
      elif [[ $use_ranked -eq 1 ]]; then
        echo "all ranked sources"
      else
        echo "all files (no ranked lib/pubspec sources found)"
      fi
    )"
    echo ""
    echo "  </p>"

    # Projects overview table
    cat <<'EOF'
  <h3>Projects Overview</h3>
  <table id="projectsTable">
    <tr>
      <th onclick="sortTable('projectsTable', 0)">Latest Ranked Source</th>
      <th onclick="sortTable('projectsTable', 1)">Project Root</th>
      <th onclick="sortTable('projectsTable', 2)">Git Commit</th>
      <th onclick="sortTable('projectsTable', 3)">Files</th>
    </tr>
EOF

    while IFS=$'\t' read -r epoch ts git files root; do
      printf '    <tr><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td></tr>\n' \
        "$ts" "$root" "$git" "$files"
    done < "$TOP_PROJECTS_TSV"

    echo "  </table>"

    # Top N projects (same as CLI)
    if (( TOP_PROJECTS > 0 )); then
      echo "  <h3>Top ${TOP_PROJECTS} Projects by Recency</h3>"
      cat <<'EOF'
  <table id="topProjectsTable">
    <tr>
      <th onclick="sortTable('topProjectsTable', 0)">#</th>
      <th onclick="sortTable('topProjectsTable', 1)">Latest Ranked Source</th>
      <th onclick="sortTable('topProjectsTable', 2)">Project Root</th>
      <th onclick="sortTable('topProjectsTable', 3)">Git Commit</th>
      <th onclick="sortTable('topProjectsTable', 4)">Files</th>
    </tr>
EOF
      rank=1
      while IFS=$'\t' read -r epoch ts git files root && (( rank <= TOP_PROJECTS )); do
        printf '    <tr><td class="mono">%d</td><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td></tr>\n' \
          "$rank" "$ts" "$root" "$git" "$files"
        ((rank++))
      done < "$TOP_PROJECTS_TSV"
      echo "  </table>"
    fi

    # Top files table with SHA256
    echo "  <h3>Top ${TOP_FILES} Modified Files</h3>"
    cat <<'EOF'
  <table id="filesTable">
    <tr>
      <th onclick="sortTable('filesTable', 0)">Timestamp</th>
      <th onclick="sortTable('filesTable', 1)">SHA256</th>
      <th onclick="sortTable('filesTable', 2)">Path</th>
    </tr>
EOF

    head -n "$TOP_FILES" "$SORTED_FILES" | while IFS=$'\t' read -r epoch ts path; do
      if [[ -f "$path" ]]; then
        sha=$(sha256sum "$path" 2>/dev/null | awk '{print $1}')
      else
        sha="(missing)"
      fi
      printf '    <tr><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td></tr>\n' \
        "$ts" "$sha" "$path"
    done

    cat <<'EOF'
  </table>
</body></html>
EOF
  } > "$HTML"
fi

########################################
# fzf browser (optional)
########################################
if [[ $FZF_MODE -eq 1 ]]; then
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf requested but not found in PATH; skipping interactive mode." >&2
  else
    echo ""
    echo "Launching fzf browser…"
    awk -F'\t' '{printf "%s.0000000000 %s %s\n", $1, $2, $3}' "$TOP_FILES_TSV" | fzf
  fi
fi

echo ""
echo "$(green "Done (v$VERSION).")"

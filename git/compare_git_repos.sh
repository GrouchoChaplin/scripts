#!/usr/bin/env bash
# ---------------------------------------------------------------------
# compare_git_repos.sh
# Compare multiple Git repositories and find:
#   1) Which has the latest commit
#   2) Optionally compare Volume shader files (.glsl, .frag, .vert, .comp)
#
# Features:
#   • Parallelized shader diffing
#   • Visual diff viewer (--diff-view <meld|vimdiff>)
#   • CSV summary (--summary-csv)
#   • ZIP archive of differing files (--save-diffs)
#   • Full HTML diff report (--html-report)
#   • Auto-updated index.html for all reports
#
# Usage:
#   ./compare_git_repos.sh repo_paths.txt \
#       [--compare-shaders] \
#       [--extensions ".glsl,.frag,.vert,.comp"] \
#       [--summary-csv shader_diffs.csv] \
#       [--save-diffs shader_diffs.zip] \
#       [--html-report shader_diffs.html] \
#       [--diff-view meld|vimdiff]
# ---------------------------------------------------------------------

set -euo pipefail

REPOLIST_FILE="${1:-repo_paths.txt}"
COMPARE_SHADERS=false
DIFF_VIEWER=""
LOGFILE="compare_git_repos_$(date +%Y-%m-%d_T%H-%M-%S).log"
DIFF_SUMMARY="/tmp/shader_diff_summary.txt"
PARALLEL_JOBS=$(( $(nproc) - 2 ))

# --- Parse flags ---
shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --compare-shaders) COMPARE_SHADERS=true ;;
        --diff-view) DIFF_VIEWER="${2:-}"; shift ;;
        *)
            # Pass through; handled later by the shader block
            break ;;
    esac
    shift
done

# --- Verify repo list file ---
if [[ ! -f "$REPOLIST_FILE" ]]; then
    echo "❌ Repo list file not found: $REPOLIST_FILE"
    exit 1
fi

echo "📘 Comparing repositories listed in: $REPOLIST_FILE"
echo "🕒 Logging to: $LOGFILE"
echo "" > "$LOGFILE"

declare -A REPO_DATE_MAP
declare -A REPO_BRANCH_MAP
declare -A REPO_HASH_MAP

# ---------------------------------------------------------------------
# Step 1: Gather Git metadata
# ---------------------------------------------------------------------
while IFS= read -r REPO_PATH; do
    [[ -z "$REPO_PATH" ]] && continue
    [[ ! -d "$REPO_PATH/.git" ]] && echo "⚠️ Skipping (not a git repo): $REPO_PATH" && continue

    echo "🔍 Checking $REPO_PATH ..."
    cd "$REPO_PATH"

    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    HASH=$(git log -1 --pretty=%h 2>/dev/null || echo "none")
    DATE=$(git log -1 --pretty=%ci 2>/dev/null || echo "none")

    REPO_DATE_MAP["$REPO_PATH"]="$DATE"
    REPO_BRANCH_MAP["$REPO_PATH"]="$BRANCH"
    REPO_HASH_MAP["$REPO_PATH"]="$HASH"

    echo "📅 $DATE | 🌿 $BRANCH | 🔢 $HASH | 📁 $REPO_PATH" | tee -a "$LOGFILE"
done < "$REPOLIST_FILE"

# ---------------------------------------------------------------------
# Step 2: Sort and show latest commit
# ---------------------------------------------------------------------
echo ""
echo "--------------------------------------------------------------"
echo "🔎 Sorted by commit date:"
printf "%-25s | %-25s | %-10s | %s\n" "DATE" "BRANCH" "HASH" "REPO PATH"
echo "--------------------------------------------------------------"

for REPO in "${!REPO_DATE_MAP[@]}"; do
    printf "%s|%s|%s|%s\n" "${REPO_DATE_MAP[$REPO]}" "${REPO_BRANCH_MAP[$REPO]}" "${REPO_HASH_MAP[$REPO]}" "$REPO"
done | sort -r | tee -a "$LOGFILE"

LATEST=$(for REPO in "${!REPO_DATE_MAP[@]}"; do
    echo "${REPO_DATE_MAP[$REPO]}|$REPO"
done | sort -r | head -n1 | cut -d'|' -f2)

echo ""
echo "🏁 Latest commit is in:"
echo "➡️  $LATEST"
echo ""

# ---------------------------------------------------------------------
# Step 3: Shader Comparison (extensions + CSV + ZIP + HTML)
# ---------------------------------------------------------------------
if $COMPARE_SHADERS; then
    SHADER_EXTS=".glsl,.frag,.vert,.comp"
    SUMMARY_CSV=""
    SAVE_DIFFS=""
    HTML_REPORT=""

    # Parse additional shader-specific flags
    for (( i=1; i<=$#; i++ )); do
        case "${!i}" in
            --extensions) next=$((i+1)); SHADER_EXTS="${!next:-$SHADER_EXTS}" ;;
            --summary-csv) next=$((i+1)); SUMMARY_CSV="${!next}" ;;
            --save-diffs) next=$((i+1)); SAVE_DIFFS="${!next}" ;;
            --html-report) next=$((i+1)); HTML_REPORT="${!next}" ;;
        esac
    done

    echo "🎨 Comparing Volume shaders..."
    BASE="$LATEST"
    echo "🔹 Extensions: $SHADER_EXTS" | tee -a "$LOGFILE"
    echo "🔹 Base repo: $BASE" | tee -a "$LOGFILE"
    echo "" > "$DIFF_SUMMARY"
    [[ -n "$SUMMARY_CSV" ]] && echo "Shader,Repository,Status" > "$SUMMARY_CSV"

    if [[ -n "$SAVE_DIFFS" ]]; then
        DIFF_ARCHIVE_DIR=$(mktemp -d /tmp/shader_diffs_XXXX)
        echo "📦 Saving diffed files to: $DIFF_ARCHIVE_DIR"
    fi

    if [[ -n "$HTML_REPORT" ]]; then
        mkdir -p "$(dirname "$HTML_REPORT")"
        cat > "$HTML_REPORT" <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Shader Comparison Report</title>
<style>
body{font-family:monospace;background:#111;color:#eee;margin:2em;}
h1{color:#6cf;}
table{border-collapse:collapse;width:100%;margin-top:1em;}
th,td{border:1px solid #444;padding:4px 8px;}
th{background:#222;}
.diff{white-space:pre;font-size:0.9em;background:#1b1b1b;border:1px solid #333;padding:6px;margin:6px;}
.add{color:#7f7;}
.rem{color:#f77;}
.meta{color:#999;}
details{margin-bottom:1em;}
a{color:#6cf;text-decoration:none;}
a:hover{text-decoration:underline;}
</style></head><body><h1>Shader Comparison Report</h1>
<p><b>Generated:</b> $(date)</p>
<table><tr><th>Shader</th><th>Repository</th><th>Status</th></tr>
EOF
    fi

    # Build dynamic find pattern
    IFS=',' read -ra EXT_ARR <<< "$SHADER_EXTS"
    FIND_ARGS=()
    for ext in "${EXT_ARR[@]}"; do
        FIND_ARGS+=(-iname "*${ext}")
        FIND_ARGS+=(-o)
    done
    unset 'FIND_ARGS[-1]'

    mapfile -t BASE_SHADERS < <(find "$BASE" -type f \( "${FIND_ARGS[@]}" \) -path "*/Shaders/Volume/*" 2>/dev/null | sort)

    echo "Found ${#BASE_SHADERS[@]} shaders in base repo."
    if [[ ${#BASE_SHADERS[@]} -eq 0 ]]; then
        echo "⚠️  No shader files found in base repo ($BASE)"
        exit 0
    fi

    echo "⚡ Using up to $PARALLEL_JOBS parallel jobs"
    export LOGFILE BASE DIFF_SUMMARY SHADER_EXTS SUMMARY_CSV SAVE_DIFFS DIFF_ARCHIVE_DIR HTML_REPORT DIFF_VIEWER

    calc_repo_hash() {
        local repo="$1"
        IFS=',' read -ra exts <<< "$SHADER_EXTS"
        local find_args=()
        for e in "${exts[@]}"; do
            find_args+=(-iname "*${e}")
            find_args+=(-o)
        done
        unset 'find_args[-1]'
        (cd "$repo" && find . -type f -path "*/Shaders/Volume/*" \( "${find_args[@]}" \) \
            -exec sha1sum {} + | sort | sha1sum | awk '{print $1}')
    }

    BASE_HASH=$(calc_repo_hash "$BASE")
    export -f calc_repo_hash

    diff_shader_repo() {
        local REPO="$1"
        local BASE_REPO="$2"
        local REPO_HASH; REPO_HASH=$(calc_repo_hash "$REPO")

        if [[ "$REPO_HASH" == "$BASE_HASH" ]]; then
            echo "✅ Repo identical to base (skipped): $REPO" | tee -a "$LOGFILE"
            [[ -n "$SUMMARY_CSV" ]] && echo "\"All shaders\",\"$(basename "$REPO")\",\"Identical\"" >> "$SUMMARY_CSV"
            [[ -n "$HTML_REPORT" ]] && echo "<tr><td>All shaders</td><td>$(basename "$REPO")</td><td>Identical</td></tr>" >> "$HTML_REPORT"
            return
        fi

        local DIFF_FOUND=0
        for SHADER in "${BASE_SHADERS[@]}"; do
            local REL_PATH; REL_PATH=$(realpath --relative-to="$BASE_REPO" "$SHADER" 2>/dev/null || basename "$SHADER")
            local OTHER="$REPO/$REL_PATH"
            [[ ! -f "$OTHER" ]] && OTHER=$(find "$REPO" -type f -iname "$(basename "$REL_PATH")" | head -n1)

            if [[ -f "$OTHER" ]]; then
                local h1 h2; h1=$(sha1sum "$SHADER" | cut -d' ' -f1); h2=$(sha1sum "$OTHER" | cut -d' ' -f1)
                [[ "$h1" == "$h2" ]] && continue
                DIFF_FOUND=1
                echo "⚠️  Diff in: $REL_PATH ($REPO)" | tee -a "$LOGFILE"
                echo "$(basename "$REL_PATH") | $(basename "$REPO")" >> "$DIFF_SUMMARY"
                [[ -n "$SUMMARY_CSV" ]] && echo "\"$(basename "$REL_PATH")\",\"$(basename "$REPO")\",\"DIFF\"" >> "$SUMMARY_CSV"
                local DIFF_OUT; DIFF_OUT=$(diff -u "$SHADER" "$OTHER")
                echo "$DIFF_OUT" | sed 's/^/    /' >> "$LOGFILE"

                if [[ -n "$SAVE_DIFFS" ]]; then
                    local tdir="$DIFF_ARCHIVE_DIR/$(basename "$REPO")/$(dirname "$REL_PATH")"
                    mkdir -p "$tdir"
                    cp "$SHADER" "$tdir/$(basename "$SHADER").base"
                    cp "$OTHER"  "$tdir/$(basename "$OTHER").repo"
                fi

                if [[ -n "$HTML_REPORT" ]]; then
                    echo "<tr><td>$(basename "$REL_PATH")</td><td>$(basename "$REPO")</td><td>DIFF</td></tr>" >> "$HTML_REPORT"
                    echo "<tr><td colspan='3'><details><summary>View diff</summary><div class='diff'>" >> "$HTML_REPORT"
                    echo "$DIFF_OUT" | sed \
                        -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
                        -e 's/^+/<span class=\"add\">+/;s/$/<\/span>/' \
                        -e 's/^-/<span class=\"rem\">-/;s/$/<\/span>/' \
                        -e 's/^@/<span class=\"meta\">@/;s/$/<\/span>/' >> "$HTML_REPORT"
                    echo "</div></details></td></tr>" >> "$HTML_REPORT"
                fi

                # ✅ fixed visual diff block
                if [[ -n "$DIFF_VIEWER" ]]; then
                    case "$DIFF_VIEWER" in
                        meld) meld "$SHADER" "$OTHER" & ;;
                        vimdiff) vimdiff "$SHADER" "$OTHER" ;;
                    esac
                fi
            else
                echo "❌ Missing shader in $REPO: $REL_PATH" | tee -a "$LOGFILE"
                [[ -n "$SUMMARY_CSV" ]] && echo "\"$(basename "$REL_PATH")\",\"$(basename "$REPO")\",\"Missing\"" >> "$SUMMARY_CSV"
                [[ -n "$HTML_REPORT" ]] && echo "<tr><td>$(basename "$REL_PATH")</td><td>$(basename "$REPO")</td><td>Missing</td></tr>" >> "$HTML_REPORT"
                DIFF_FOUND=1
            fi
        done

        if [[ $DIFF_FOUND -eq 0 ]]; then
            echo "✅ No shader diffs found in: $REPO" | tee -a "$LOGFILE"
            [[ -n "$SUMMARY_CSV" ]] && echo "\"All shaders\",\"$(basename "$REPO")\",\"No diffs\"" >> "$SUMMARY_CSV"
            [[ -n "$HTML_REPORT" ]] && echo "<tr><td>All shaders</td><td>$(basename "$REPO")</td><td>No diffs</td></tr>" >> "$HTML_REPORT"
        fi
    }

    export -f diff_shader_repo
    export BASE_SHADERS BASE_HASH

    echo "${!REPO_DATE_MAP[@]}" | tr ' ' '\n' | grep -v "$BASE" | parallel -j"$PARALLEL_JOBS" diff_shader_repo {} "$BASE"

    if [[ -n "$SAVE_DIFFS" && -d "$DIFF_ARCHIVE_DIR" ]]; then
        zip -qr "$SAVE_DIFFS" "$DIFF_ARCHIVE_DIR"
        echo "📦 Saved diff archive: $SAVE_DIFFS"
        rm -rf "$DIFF_ARCHIVE_DIR"
    fi

    if [[ -s "$DIFF_SUMMARY" ]]; then
        echo "--------------------------------------------------------------"
        echo "🧾 Shader Diff Summary"
        echo "--------------------------------------------------------------"
        column -t -s"|" "$DIFF_SUMMARY" | sort | tee -a "$LOGFILE"
        echo "--------------------------------------------------------------"
        echo "🧮 Total shader diffs: $(wc -l < "$DIFF_SUMMARY")"
    else
        echo "✅ No shader differences detected."
        [[ -n "$SUMMARY_CSV" ]] && echo "\"All shaders\",\"All repos\",\"Identical\"" >> "$SUMMARY_CSV"
        [[ -n "$HTML_REPORT" ]] && echo "<tr><td>All shaders</td><td>All repos</td><td>Identical</td></tr>" >> "$HTML_REPORT"
    fi

    [[ -n "$HTML_REPORT" ]] && {
        echo "</table><p><b>Log:</b> $LOGFILE</p>" >> "$HTML_REPORT"
        [[ -n "$SUMMARY_CSV" ]] && echo "<p><b>CSV:</b> $SUMMARY_CSV</p>" >> "$HTML_REPORT"
        [[ -n "$SAVE_DIFFS" ]] && echo "<p><b>ZIP:</b> $SAVE_DIFFS</p>" >> "$HTML_REPORT"
        echo "</body></html>" >> "$HTML_REPORT"
        echo "🌐 HTML report written: $HTML_REPORT"
    }

    echo "📄 Detailed log: $LOGFILE"
fi

# ---------------------------------------------------------------------
# Step 5: Update HTML index of all reports
# ---------------------------------------------------------------------
if [[ -n "${HTML_REPORT:-}" ]]; then
    REPORT_DIR="$(dirname "$HTML_REPORT")"
    INDEX_HTML="${REPORT_DIR}/index.html"

    if [[ ! -f "$INDEX_HTML" ]]; then
        cat > "$INDEX_HTML" <<'EOF'
<!DOCTYPE html><html><head><meta charset="UTF-8">
<title>Shader Comparison Reports</title>
<style>
body{font-family:system-ui,monospace;background:#111;color:#eee;margin:2em;}
h1{color:#6cf;}
table{border-collapse:collapse;width:100%;margin-top:1em;}
th,td{border:1px solid #444;padding:4px 8px;}
th{background:#222;}
a{color:#6cf;text-decoration:none;}
a:hover{text-decoration:underline;}
</style>
</head><body>
<h1>Shader Comparison Reports</h1>
<table><tr><th>Date</th><th>HTML Report</th><th>CSV Summary</th><th>ZIP Archive</th></tr>
EOF
    fi

    RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
    HTML_NAME="$(basename "$HTML_REPORT")"
    CSV_LINK="$(basename "${SUMMARY_CSV:-}" 2>/dev/null || echo '-')"
    ZIP_LINK="$(basename "${SAVE_DIFFS:-}" 2>/dev/null || echo '-')"

    echo "<tr><td>${RUN_DATE}</td><td><a href=\"${HTML_NAME}\">${HTML_NAME}</a></td><td><a href=\"${CSV_LINK}\">${CSV_LINK}</a></td><td><a href=\"${ZIP_LINK}\">${ZIP_LINK}</a></td></tr>" >> "$INDEX_HTML"
    echo "</table></body></html>" >> "$INDEX_HTML.tmp"
    awk '!seen[$0]++' "$INDEX_HTML.tmp" > "$INDEX_HTML" && rm -f "$INDEX_HTML.tmp"

    echo "🗂️  Updated index: $INDEX_HTML"
fi

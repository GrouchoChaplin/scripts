#!/usr/bin/env bash
#
# mode_forensic.sh — forensic mode for V5.6-Patch3
#
# Responsibilities:
#   - Use scan_repo_forensic() to gather rich metadata per repo
#   - Compute a “most recent activity” timestamp per repo
#   - Select a probable “last worked on here” repo
#   - Print a detailed textual report
#   - Emit an ASCII activity timeline
#   - Generate an HTML report with sortable table + activity bars
#
# Requires:
#   - common.sh
#   - repo_scan.sh

###############################################
# run_mode_forensic ROOT PREFIX
###############################################
run_mode_forensic() {
    local root="$1"
    local prefix="$2"

    local repo_list_file
    repo_list_file="$(mktemp)"
    local meta_file
    meta_file="$(mktemp)"

    info "Searching: $root"
    info "Looking for repos matching prefix: ${prefix}*"

    find_repos "$root" "$prefix" "$repo_list_file"

    if [[ ! -s "$repo_list_file" ]]; then
        error "No repositories found matching: ${prefix}*"
        rm -f "$repo_list_file" "$meta_file"
        return 1
    fi

    info "Running forensic scan across repo variants…"

    ###########################################################
    # Collect forensic data
    ###########################################################
    while IFS= read -r repo; do
        scan_repo_forensic "$repo" >> "$meta_file"
    done < "$repo_list_file"

    ###########################################################
    # Print forensic summary per repo & determine best candidate
    ###########################################################
    echo
    echo "📊 Forensic summary per repo:"
    echo

    local best_repo=""
    local best_activity_epoch=0

    # We’ll also cache an activity TSV for timeline and HTML
    local activity_file
    activity_file="$(mktemp)"

    while IFS=$'\t' read -r path branch last_epoch last_human dirty ahead behind \
                              staged unstaged untracked \
                              latest_epoch latest_human latest_path; do

        # Compute "activity epoch" as the max of last commit and latest file modification
        local activity_epoch="$last_epoch"
        if (( latest_epoch > activity_epoch )); then
            activity_epoch="$latest_epoch"
        fi
        local activity_human
        activity_human="$(fmt_ts "$activity_epoch")"

        # Record for later use
        echo -e "${activity_epoch}\t${path}\t${branch}" >> "$activity_file"

        # Track best repo by highest activity epoch
        if (( activity_epoch > best_activity_epoch )); then
            best_activity_epoch="$activity_epoch"
            best_repo="$path"
        fi

        # Pretty printing
        echo "────────────────────────────────────────────────────────────────────────"
        echo "Repo:   $path"
        echo "Branch: $branch"
        echo "Dirty:  $dirty  (staged=${staged}, unstaged=${unstaged}, untracked=${untracked})"
        echo "Ahead/Behind vs upstream: ${ahead}/${behind}"
        echo "Last commit:            ${last_epoch}  (${last_human})"
        echo "Latest file change:     ${latest_epoch} (${latest_human})"
        echo "Computed activity time: ${activity_epoch} (${activity_human})"
        echo "Last-changed file:      ${latest_path}"
        echo

    done < "$meta_file"

    ###########################################################
    # Best guess: "where did I last work?"
    ###########################################################
    echo
    if [[ -n "$best_repo" && "$best_activity_epoch" -gt 0 ]]; then
        local best_human
        best_human="$(fmt_ts "$best_activity_epoch")"
        echo "🔥 Probable last active repo (most recent activity):"
        echo "    $best_repo"
        echo "    Activity time: $best_human (epoch ${best_activity_epoch})"
    else
        warn "Unable to determine a most-active repo (no activity timestamps found)."
    fi

    ###########################################################
    # ASCII timeline
    ###########################################################
    echo
    echo "⏱ ASCII activity timeline (most recent first):"
    echo

    ascii_timeline "$activity_file"

    ###########################################################
    # HTML report
    ###########################################################
    local report_name="forensic_report_$(now_ts).html"
    generate_html_report "$meta_file" "$report_name"

    echo
    success "HTML forensic report written to: ${report_name}"
    echo "You can open it with:"
    echo "  firefox \"${report_name}\" &"
    echo

    ###########################################################
    # Cleanup
    ###########################################################
    rm -f "$repo_list_file" "$meta_file" "$activity_file"
}

###############################################
# ascii_timeline META_ACTIVITY_FILE
#
# META_ACTIVITY_FILE: TSV with columns:
#   activity_epoch <TAB> path <TAB> branch
###############################################
ascii_timeline() {
    local activity_file="$1"

    if [[ ! -s "$activity_file" ]]; then
        echo "  (no activity data available)"
        return 0
    fi

    sort -nr -k1,1 "$activity_file" | while IFS=$'\t' read -r epoch path branch; do
        local ht
        ht="$(fmt_ts "$epoch")"
        printf "  %s  |  %s  |  %s\n" "$ht" "$path" "$branch"
    done
}

###############################################
# generate_html_report META_FILE OUTFILE
#
# META_FILE: TSV with columns from scan_repo_forensic():
#   1: repo_path
#   2: branch
#   3: last_commit_epoch
#   4: last_commit_human
#   5: dirty_flag
#   6: ahead
#   7: behind
#   8: staged_count
#   9: unstaged_count
#  10: untracked_count
#  11: latest_file_epoch
#  12: latest_file_human
#  13: latest_file_path
###############################################
generate_html_report() {
    local meta_file="$1"
    local outfile="$2"

    # First pass: compute min/max activity epoch for scaling bars
    local min_epoch=0
    local max_epoch=0

    while IFS=$'\t' read -r path branch last_epoch last_human dirty ahead behind \
                              staged unstaged untracked \
                              latest_epoch latest_human latest_path; do
        local activity_epoch="$last_epoch"
        if (( latest_epoch > activity_epoch )); then
            activity_epoch="$latest_epoch"
        fi

        if (( min_epoch == 0 || activity_epoch < min_epoch )); then
            min_epoch="$activity_epoch"
        fi
        if (( max_epoch == 0 || activity_epoch > max_epoch )); then
            max_epoch="$activity_epoch"
        fi
    done < "$meta_file"

    local span=$((max_epoch - min_epoch))
    (( span <= 0 )) && span=1

    cat > "$outfile" <<'EOF_HEAD'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <title>Repo Forensic Report</title>
  <style>
    body { background: #111; color: #eee; font-family: monospace; }
    h2 { color: #9cf; }
    table { border-collapse: collapse; width: 100%; margin-top: 1em; }
    th, td { border: 1px solid #444; padding: 6px 8px; }
    th { background: #333; cursor: pointer; }
    tr:nth-child(even) { background: #1a1a1a; }
    tr:nth-child(odd) { background: #151515; }
    .dirty { color: #ff6666; font-weight: bold; }
    .clean { color: #66ccff; }
    .timeline-container {
      width: 100%;
      background: #222;
      height: 10px;
      margin-top: 4px;
    }
    .timeline-bar {
      height: 10px;
      background: linear-gradient(to right, #4caf50, #ff9800);
    }
    small { color: #aaa; }
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

          var shouldSwitch = false;
          if (dir === "desc" && cmpA < cmpB) {
            shouldSwitch = true;
          } else if (dir === "asc" && cmpA > cmpB) {
            shouldSwitch = true;
          }

          if (shouldSwitch) {
            rows[i].parentNode.insertBefore(rows[i + 1], rows[i]);
            switching = true;
            switchcount++;
            break;
          }
        }

        if (switchcount === 0 && dir === "desc") {
          dir = "asc";
          switching = true;
        }
      }
    }
  </script>
</head>
<body>
  <h2>Repo Forensic Report</h2>
  <table id="repoTable">
    <tr>
      <th onclick="sortTable(0)">Path</th>
      <th onclick="sortTable(1)">Branch</th>
      <th onclick="sortTable(2)">Dirty</th>
      <th onclick="sortTable(3)">Ahead</th>
      <th onclick="sortTable(4)">Behind</th>
      <th onclick="sortTable(5)">Staged</th>
      <th onclick="sortTable(6)">Unstaged</th>
      <th onclick="sortTable(7)">Untracked</th>
      <th onclick="sortTable(8)">Last Commit</th>
      <th onclick="sortTable(9)">Latest File Change</th>
    </tr>
EOF_HEAD

    # Second pass: emit rows
    while IFS=$'\t' read -r path branch last_epoch last_human dirty ahead behind \
                              staged unstaged untracked \
                              latest_epoch latest_human latest_path; do
        local activity_epoch="$last_epoch"
        if (( latest_epoch > activity_epoch )); then
            activity_epoch="$latest_epoch"
        fi

        local width=$(( (activity_epoch - min_epoch) * 100 / span ))
        (( width < 5 )) && width=5
        (( width > 100 )) && width=100

        local dirty_class
        if [[ "$dirty" == "dirty" ]]; then
            dirty_class="dirty"
        else
            dirty_class="clean"
        fi

        # Escape HTML special chars in path/latest_path minimally (just & and <, > not very likely here)
        local esc_path esc_latest
        esc_path="${path//&/&amp;}"
        esc_path="${esc_path//</&lt;}"
        esc_latest="${latest_path//&/&amp;}"
        esc_latest="${esc_latest//</&lt;}"

        cat >> "$outfile" <<EOF_ROW
    <tr>
      <td>${esc_path}</td>
      <td>${branch}</td>
      <td class="${dirty_class}">${dirty}</td>
      <td>${ahead}</td>
      <td>${behind}</td>
      <td>${staged}</td>
      <td>${unstaged}</td>
      <td>${untracked}</td>
      <td>${last_human}</td>
      <td>
        ${latest_human}<br/>
        <small>${esc_latest}</small>
        <div class="timeline-container">
          <div class="timeline-bar" style="width: ${width}%"></div>
        </div>
      </td>
    </tr>
EOF_ROW
    done < "$meta_file"

    cat >> "$outfile" <<'EOF_TAIL'
  </table>
</body>
</html>
EOF_TAIL
}

# lib/mode_forensic.sh — forensic mode logic

run_mode_forensic() {
    local tmp_repos="$1"
    local tmp_meta
    tmp_meta=$(mktemp)

    log_info ""
    log_info "🕵️ Running forensic scan across repo variants…"

    while IFS= read -r repo; do
        scan_repo_forensic "$repo"
    done < "$tmp_repos" > "$tmp_meta"

    log_info ""
    log_info "📊 Forensic summary per repo:"
    echo "PATH"
    echo "  Branch / Dirty / Staged / Unstaged / Untracked"
    echo "  Last commit ............... (epoch, human)"
    echo "  Latest file modification .. (epoch, human, path)"
    echo

    local best_repo=""
    local best_activity_epoch=0

    while IFS=$'\t' read -r path branch last_epoch last_human dirty staged unstaged untracked latest_epoch latest_human latest_path; do
        local activity_epoch
        if (( latest_epoch > last_epoch )); then
            activity_epoch=$latest_epoch
        else
            activity_epoch=$last_epoch
        fi

        echo "$path"
        echo "  Branch:    $branch"
        echo "  Dirty:     $dirty (staged=$staged, unstaged=$unstaged, untracked=$untracked)"
        echo "  Last commit:        $last_epoch  ($last_human)"
        echo "  Latest file change: $latest_epoch ($latest_human)  $latest_path"
        echo

        if (( activity_epoch > best_activity_epoch )); then
            best_activity_epoch=$activity_epoch
            best_repo="$path"
        fi
    done < "$tmp_meta"

    if [[ -n "$best_repo" ]]; then
        local best_human
        best_human=$(human_time "$best_activity_epoch")
        log_good "🔥 Probable last active repo: $best_repo"
        log_good "   Most recent activity time: $best_human (epoch $best_activity_epoch)"
    fi

    # ASCII timeline
    echo
    log_info "⏱ ASCII activity timeline (most recent first):"
    ascii_timeline "$tmp_meta"

    # HTML report
    local report="forensic_report_$(date +%Y-%m-%d_%H-%M-%S).html"
    generate_html_report "$tmp_meta" "$report"
    log_good ""
    log_good "📄 HTML forensic report written to: $report"

    rm -f "$tmp_meta" 2>/dev/null || true
}

# Build an ASCII timeline where each repo is a row
ascii_timeline() {
    local meta="$1"
    # We recompute activity epoch like above and sort
    local tmp_act
    tmp_act=$(mktemp)

    while IFS=$'\t' read -r path branch last_epoch last_human dirty staged unstaged untracked latest_epoch latest_human latest_path; do
        local activity_epoch
        if (( latest_epoch > last_epoch )); then
            activity_epoch=$latest_epoch
        else
            activity_epoch=$last_epoch
        fi
        echo -e "${activity_epoch}\t${path}\t${branch}" >> "$tmp_act"
    done < "$meta"

    sort -nrk1,1 "$tmp_act" | while IFS=$'\t' read -r epoch path branch; do
        local ht
        ht=$(human_time "$epoch")
        printf "  %s  |  %s  |  %s\n" "$ht" "$path" "$branch"
    done

    rm -f "$tmp_act" 2>/dev/null || true
}

generate_html_report() {
    local meta="$1"
    local outfile="$2"

    cat > "$outfile" <<'EOF'
<html>
<head>
  <meta charset="UTF-8" />
  <title>Repo Forensic Report</title>
  <style>
    body { background: #111; color: #eee; font-family: monospace; }
    table { border-collapse: collapse; width: 100%; margin-top: 1em; }
    th, td { border: 1px solid #444; padding: 6px 8px; }
    th { background: #333; cursor: pointer; }
    tr:nth-child(even) { background: #1a1a1a; }
    tr:nth-child(odd) { background: #151515; }
    .dirty { color: #ff6666; }
    .clean { color: #66ccff; }
    .timeline-bar {
      height: 10px;
      background: linear-gradient(to right, #4caf50, #ff9800);
    }
    .container { width: 100%; background: #222; }
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
<h2>Repo Forensic Report</h2>
<table id="repoTable">
  <tr>
    <th onclick="sortTable(0)">Path</th>
    <th onclick="sortTable(1)">Branch</th>
    <th onclick="sortTable(2)">Dirty</th>
    <th onclick="sortTable(3)">Staged</th>
    <th onclick="sortTable(4)">Unstaged</th>
    <th onclick="sortTable(5)">Untracked</th>
    <th onclick="sortTable(6)">Last Commit</th>
    <th onclick="sortTable(7)">Latest File Change</th>
  </tr>
EOF

    # Determine relative activity scale
    local min_epoch=0 max_epoch=0
    while IFS=$'\t' read -r path branch last_epoch last_human dirty staged unstaged untracked latest_epoch latest_human latest_path; do
        local activity_epoch=$last_epoch
        if (( latest_epoch > activity_epoch )); then
            activity_epoch=$latest_epoch
        fi
        if (( min_epoch == 0 || activity_epoch < min_epoch )); then
            min_epoch=$activity_epoch
        fi
        if (( max_epoch == 0 || activity_epoch > max_epoch )); then
            max_epoch=$activity_epoch
        fi
    done < "$meta"

    local span=$((max_epoch - min_epoch))
    if (( span == 0 )); then
        span=1
    fi

    while IFS=$'\t' read -r path branch last_epoch last_human dirty staged unstaged untracked latest_epoch latest_human latest_path; do
        local activity_epoch=$last_epoch
        if (( latest_epoch > activity_epoch )); then
            activity_epoch=$latest_epoch
        fi
        local width=$(( (activity_epoch - min_epoch) * 100 / span ))
        [[ "$width" -lt 5 ]] && width=5

        local dirty_class
        if [[ "$dirty" == "dirty" ]]; then
            dirty_class="dirty"
        else
            dirty_class="clean"
        fi

        cat >> "$outfile" <<EOFROW
  <tr>
    <td>$path</td>
    <td>$branch</td>
    <td class="$dirty_class">$dirty</td>
    <td>$staged</td>
    <td>$unstaged</td>
    <td>$untracked</td>
    <td>$last_human</td>
    <td>
      $latest_human<br/>
      <small>$latest_path</small>
      <div class="container">
        <div class="timeline-bar" style="width: ${width}%;"></div>
      </div>
    </td>
  </tr>
EOFROW
    done < "$meta"

    cat >> "$outfile" <<'EOF_END'
</table>
</body>
</html>
EOF_END
}

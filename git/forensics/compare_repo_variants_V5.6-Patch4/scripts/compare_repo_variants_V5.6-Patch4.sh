\
    #!/usr/bin/env bash
    #
    # compare_repo_variants_V5.6-Patch4.sh
    #
    # Enhanced V5.6-Patch4 toolkit entry point.
    #
    # Primary goal: given a root folder and a repo name pattern,
    # discover all variants of that repo (across backups, copies, etc.)
    # and answer:
    #
    #   "Where did I last leave off working on repo X?"
    #
    # by ranking repos using commit recency + uncommitted work timestamps.
    #
    # Columns in output:
    #   RANK, LAST_WORK_TIME, STATUS, BRANCH, AHEAD/BEHIND, FLAGS, REPO_PATH
    #
    # Flags:
    #   U = has untracked files
    #   M = has modified (unstaged) files
    #   S = has staged (but uncommitted) changes
    #   D = dirty (any of U/M/S)
    #

    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/utils_V5.6-Patch4.sh"

    METADATA_SCRIPT="${SCRIPT_DIR}/extract_repo_metadata_V5.6-Patch4.sh"

    if [[ ! -x "$METADATA_SCRIPT" ]]; then
        log_warn "Metadata script not executable; attempting to chmod +x: $METADATA_SCRIPT"
        chmod +x "$METADATA_SCRIPT" 2>/dev/null || true
    fi

    ROOT_FOLDER=""
    MODE="standard"   # reserved for future; 'forensic' is more verbose but same ranking
    LOG_DIR="./logs"
    REPO_PATTERNS=()
    SHADER_PATTERN=""
    TOP_N=20

    usage() {
        cat <<EOF
    Usage:
      $(basename "$0") --root-folder PATH --repo-name NAME [options]

    Required:
      --root-folder PATH      Top-level directory to search.
      --repo-name NAME        Basename pattern of repo(s) to match.
                              You can pass this multiple times, e.g.
                                --repo-name jsigconversiontools --repo-name jsigconversiontools*

    Optional:
      --mode MODE             'standard' (default) or 'forensic' (extra detail).
      --shader-pattern PAT    Optional shader glob relative to repo root, e.g.
                                'JSIG_Data/Shaders/Volume/volumetric_cloud_shader*.glsl'
      --log-dir PATH          Where to write log + TSV (default: ./logs).
      --top N                 Limit display to top N ranked repos (default: 20).
      --help                  This help.

    The script:
      1) Finds all '.git' dirs under --root-folder.
      2) Filters by repo basename matching any --repo-name pattern.
      3) Extracts metadata for each repo.
      4) Ranks by LAST_WORK_EPOCH (commit vs. dirty file timestamps).
      5) Prints a human-readable summary, with the top candidate first.
    EOF
    }

    # Simple pattern matcher: does "name" match any glob or substring in REPO_PATTERNS?
    repo_name_matches() {
        local name="$1" pat
        if [[ "${#REPO_PATTERNS[@]}" -eq 0 ]]; then
            # no patterns provided -> match all
            return 0
        fi
        for pat in "${REPO_PATTERNS[@]}"; do
            if [[ "$name" == $pat ]]; then
                return 0
            fi
        done
        return 1
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --root-folder)
                ROOT_FOLDER="${2:-}"
                shift 2
                ;;
            --repo-name)
                REPO_PATTERNS+=("${2:-}")
                shift 2
                ;;
            --mode)
                MODE="${2:-}"
                shift 2
                ;;
            --shader-pattern)
                SHADER_PATTERN="${2:-}"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="${2:-}"
                shift 2
                ;;
            --top)
                TOP_N="${2:-}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$ROOT_FOLDER" ]]; then
        log_error "--root-folder is required"
        usage
        exit 1
    fi
    if [[ "${#REPO_PATTERNS[@]}" -eq 0 ]]; then
        log_warn "No --repo-name provided; all git repos under root will be considered."
    fi

    ROOT_FOLDER="$(abspath "$ROOT_FOLDER")"
    LOG_DIR="$(abspath "$LOG_DIR")"
    mkdir -p "$LOG_DIR"

    require_cmd git find sort awk || exit 1

    TS_ID="$(date +'%Y-%m-%d_T%H-%M-%S')"
    LOG_PATH="${LOG_DIR}/compare_repo_variants_${TS_ID}.log"
    TSV_PATH="${LOG_DIR}/compare_repo_variants_${TS_ID}.tsv"

    log_info "V5.6-Patch4 compare starting"
    log_info "  root-folder : $ROOT_FOLDER"
    log_info "  mode        : $MODE"
    log_info "  log-path    : $LOG_PATH"
    log_info "  tsv-path    : $TSV_PATH"
    log_info "  repo-names  : ${REPO_PATTERNS[*]:-(ALL)}"
    log_info "  shader-pat  : ${SHADER_PATTERN:-<none>}"

    # tee all script output to log as well
    exec > >(tee -a "$LOG_PATH") 2>&1

    # Discover repo roots
    log_info "Scanning for git repositories under: $ROOT_FOLDER ..."
    mapfile -d '' git_dirs < <(find "$ROOT_FOLDER" -type d -name ".git" -print0 2>/dev/null || true)

    if [[ "${#git_dirs[@]}" -eq 0 ]]; then
        log_warn "No .git directories found under root."
        exit 0
    fi

    log_info "Found ${#git_dirs[@]} .git directories. Filtering by repo name..."

    repo_roots=()
    declare -A seen

    for gd in "${git_dirs[@]}"; do
        gd="${gd%$'\n'}"
        root="${gd%/.git}"
        base="$(basename "$root")"
        if repo_name_matches "$base"; then
            key="$(abspath "$root")"
            if [[ -z "${seen[$key]:-}" ]]; then
                seen["$key"]=1
                repo_roots+=("$key")
            fi
        fi
    done

    if [[ "${#repo_roots[@]}" -eq 0 ]]; then
        log_warn "No repositories matched the requested --repo-name patterns."
        exit 0
    fi

    log_info "Candidate repositories: ${#repo_roots[@]}"

    # Write header to TSV
    {
        printf '# V5.6-Patch4 repo metadata\n'
        printf '# Generated: %s\n' "$(ts)"
        printf '# Columns:\n'
        printf '# 1: REPO_PATH\n'
        printf '# 2: BRANCH\n'
        printf '# 3: HEAD_HASH\n'
        printf '# 4: HEAD_DATE_HUMAN\n'
        printf '# 5: HEAD_DATE_EPOCH\n'
        printf '# 6: AHEAD\n'
        printf '# 7: BEHIND\n'
        printf '# 8: STATUS\n'
        printf '# 9: HAS_UNTRACKED\n'
        printf '# 10: HAS_MODIFIED\n'
        printf '# 11: HAS_STAGED\n'
        printf '# 12: LAST_WORK_EPOCH\n'
        printf '# 13: LAST_WORK_HUMAN\n'
        printf '# 14: DIR_MTIME_EPOCH\n'
        printf '# 15: DIR_MTIME_HUMAN\n'
        printf '# 16: SHADER_STATUS\n'
        printf '# 17: SHADER_LAST_EPOCH\n'
        printf '# 18: SHADER_LAST_HUMAN\n'
        printf '\n'
    } > "$TSV_PATH"

    tmp_data="$(mktemp)"
    trap 'rm -f "$tmp_data"' EXIT

    log_info "Collecting metadata for each repo..."

    for r in "${repo_roots[@]}"; do
        log_info "  -> $r"
        if ! row="$("$METADATA_SCRIPT" --repo "$r" ${SHADER_PATTERN:+--shader-pattern "$SHADER_PATTERN"} 2>>"$LOG_PATH")"; then
            log_warn "Metadata extraction failed for $r (see log)."
            continue
        fi
        printf '%s\n' "$row" >> "$tmp_data"
        printf '%s\n' "$row" >> "$TSV_PATH"
    done

    if [[ ! -s "$tmp_data" ]]; then
        log_warn "No metadata rows collected (all repos failed?)."
        exit 0
    fi

    # Ranking: sort by column 12 (LAST_WORK_EPOCH) descending
    log_info "Ranking repositories by LAST_WORK_EPOCH (most recent activity first)..."

    printf '\n'
    printf '%s\n' "======================================================================"
    printf '%s\n' "   V5.6-Patch4 Repo Activity Ranking  (most recent work at the top)"
    printf '%s\n' "======================================================================"
    printf '\n'
    printf 'RANK  LAST_WORK_TIME        STATUS  BRANCH              A/B   FLAGS  REPO_PATH\n'
    printf '----  -------------------   ------  -----------------   ----  -----  ---------\n'

    rank=0

    sort -t $'\t' -k12,12nr "$tmp_data" | head -n "$TOP_N" | \
    while IFS=$'\t' read -r REPO_PATH BRANCH HEAD_HASH HEAD_DATE_HUMAN HEAD_DATE_EPOCH \
                             AHEAD BEHIND STATUS HAS_UNTRACKED HAS_MODIFIED HAS_STAGED \
                             LAST_WORK_EPOCH LAST_WORK_HUMAN DIR_MTIME_EPOCH DIR_MTIME_HUMAN \
                             SHADER_STATUS SHADER_LAST_EPOCH SHADER_LAST_HUMAN; do
        rank=$((rank+1))

        FLAGS=""
        [[ "$HAS_UNTRACKED" == "1" ]] && FLAGS+="U"
        [[ "$HAS_MODIFIED" == "1" ]] && FLAGS+="M"
        [[ "$HAS_STAGED"   == "1" ]] && FLAGS+="S"
        [[ "$STATUS" != "clean" ]] && FLAGS+="D"
        [[ -z "$FLAGS" ]] && FLAGS="-"

        # ahead/behind summary
        AB="${AHEAD}/${BEHIND}"

        # mark the top repo with a star
        STAR=" "
        if [[ "$rank" -eq 1 ]]; then
            STAR="*"
        fi

        printf '%-3s%s  %-19s  %-6s  %-17s  %4s  %-5s  %s\n' \
            "$rank" "$STAR" "$LAST_WORK_HUMAN" "$STATUS" "$BRANCH" "$AB" "$FLAGS" "$REPO_PATH"
    done

    printf '\n'
    printf 'Legend:\n'
    printf '  A/B   = ahead/behind relative to upstream (0/0 if none).\n'
    printf '  FLAGS = U (untracked) M (modified) S (staged) D (dirty overall)\n'
    printf '  *     = best candidate for "where you last left off"\n'
    printf '\n'
    printf 'TSV with full details:\n'
    printf '  %s\n' "$TSV_PATH"
    printf '\n'
    printf 'Log file:\n'
    printf '  %s\n' "$LOG_PATH"
    printf '\n'
    log_info "Done."

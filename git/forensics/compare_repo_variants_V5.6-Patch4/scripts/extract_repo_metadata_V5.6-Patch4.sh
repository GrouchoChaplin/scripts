\
    #!/usr/bin/env bash
    #
    # extract_repo_metadata_V5.6-Patch4.sh
    #
    # Extracts per-repository metadata used by compare_repo_variants_V5.6-Patch4.sh
    # to answer: "Where did I last leave off working on repo X?"
    #
    # Output: one TAB-separated line with the following columns:
    #
    # 1  REPO_PATH
    # 2  BRANCH
    # 3  HEAD_HASH
    # 4  HEAD_DATE_HUMAN
    # 5  HEAD_DATE_EPOCH
    # 6  AHEAD
    # 7  BEHIND
    # 8  STATUS           ("clean" or "dirty")
    # 9  HAS_UNTRACKED    (0/1)
    # 10 HAS_MODIFIED     (0/1)
    # 11 HAS_STAGED       (0/1)
    # 12 LAST_WORK_EPOCH  (max of HEAD_DATE_EPOCH and any dirty/untracked file mtimes)
    # 13 LAST_WORK_HUMAN
    # 14 DIR_MTIME_EPOCH
    # 15 DIR_MTIME_HUMAN
    # 16 SHADER_STATUS        ("none","clean","dirty","missing")
    # 17 SHADER_LAST_EPOCH
    # 18 SHADER_LAST_HUMAN
    #
    # Usage:
    #   extract_repo_metadata_V5.6-Patch4.sh --repo PATH [--shader-pattern 'volumetric_cloud_shader*.glsl']
    #

    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/utils_V5.6-Patch4.sh"

    REPO_PATH=""
    SHADER_PATTERN=""

    usage() {
        cat <<EOF
    Usage:
      $(basename "$0") --repo PATH [--shader-pattern PATTERN]

    Options:
      --repo PATH           Path to the git repository (working tree root).
      --shader-pattern PAT  Optional glob for shader files relative to repo root
                            (e.g. 'JSIG_Data/Shaders/Volume/volumetric_cloud_shader*.glsl')
    EOF
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                REPO_PATH="${2:-}"
                shift 2
                ;;
            --shader-pattern)
                SHADER_PATTERN="${2:-}"
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

    if [[ -z "$REPO_PATH" ]]; then
        log_error "--repo is required"
        usage
        exit 1
    fi

    REPO_PATH="$(abspath "$REPO_PATH")"

    if [[ ! -d "$REPO_PATH/.git" ]]; then
        log_error "Not a git working tree (no .git): $REPO_PATH"
        exit 1
    fi

    require_cmd git stat || exit 1

    cd "$REPO_PATH"

    # Basic git metadata
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "DETACHED")"
    HEAD_HASH="$(git rev-parse --short=10 HEAD 2>/dev/null || echo "NOHEAD")"
    HEAD_DATE_EPOCH="$(git log -1 --format='%ct' 2>/dev/null || echo 0)"
    HEAD_DATE_HUMAN="$(epoch_to_human "$HEAD_DATE_EPOCH")"

    # Ahead/behind relative to upstream (if any)
    AHEAD=0
    BEHIND=0
    if git rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" >/dev/null 2>&1; then
        # output: AHEAD BEHIND
        read -r BEHIND AHEAD <<<"$(git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null || echo "0 0")"
    fi

    # Working tree status
    STATUS="clean"
    HAS_UNTRACKED=0
    HAS_MODIFIED=0
    HAS_STAGED=0

    # Porcelain v1 is fine here
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        STATUS="dirty"
        x="${line:0:1}"
        y="${line:1:1}"
        # staged if index status is not space
        if [[ "$x" != " " ]]; then
            HAS_STAGED=1
        fi
        # modified if work-tree status is M or D etc.
        if [[ "$y" != " " && "$y" != "?" ]]; then
            HAS_MODIFIED=1
        fi
        # untracked
        if [[ "$x$y" == "??" ]]; then
            HAS_UNTRACKED=1
        fi
    done < <(git status --porcelain)

    # Determine last work epoch: start with HEAD date
    LAST_WORK_EPOCH="$HEAD_DATE_EPOCH"

    # Look at modified + untracked files
    # Note: -m: modified; -o: others (untracked); --exclude-standard: ignore .gitignore'd
    while IFS= read -r -d '' f; do
        e="$(get_file_epoch "$f" || echo 0)"
        if [[ "$e" -gt "$LAST_WORK_EPOCH" ]]; then
            LAST_WORK_EPOCH="$e"
        fi
    done < <(git ls-files -m -o --exclude-standard -z)

    LAST_WORK_HUMAN="$(epoch_to_human "$LAST_WORK_EPOCH")"

    # Directory mtime
    DIR_MTIME_EPOCH="$(get_file_epoch "$REPO_PATH" || echo 0)"
    DIR_MTIME_HUMAN="$(epoch_to_human "$DIR_MTIME_EPOCH")"

    # Shader info
    SHADER_STATUS="none"
    SHADER_LAST_EPOCH=0

    if [[ -n "$SHADER_PATTERN" ]]; then
        shopt -s nullglob
        mapfile -t shader_files < <(eval "printf '%s\n' $SHADER_PATTERN" 2>/dev/null || true)
        # If that pattern is relative, globbing above might fail; instead, use find
        if [[ "${#shader_files[@]}" -eq 0 ]]; then
            # Try a find relative to repo
            while IFS= read -r -d '' sf; do
                shader_files+=("${sf#./}")
            done < <(find . -type f -path "$SHADER_PATTERN" -print0 2>/dev/null || true)
        fi
        shopt -u nullglob

        if [[ "${#shader_files[@]}" -eq 0 ]]; then
            SHADER_STATUS="missing"
        else
            # Any dirty or untracked shader?
            local_dirty=0
            for sf in "${shader_files[@]}"; do
                # remove leading ./ if present
                sf="${sf#./}"
                if git status --porcelain -- "$sf" | grep -q .; then
                    local_dirty=1
                fi
                e="$(get_file_epoch "$sf" || echo 0)"
                if [[ "$e" -gt "$SHADER_LAST_EPOCH" ]]; then
                    SHADER_LAST_EPOCH="$e"
                fi
            done
            if [[ "$local_dirty" -eq 1 ]]; then
                SHADER_STATUS="dirty"
            else
                SHADER_STATUS="clean"
            fi
        fi
    fi

    SHADER_LAST_HUMAN="$(epoch_to_human "$SHADER_LAST_EPOCH")"

    # Emit tab-separated row
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$REPO_PATH" \
        "$BRANCH" \
        "$HEAD_HASH" \
        "$HEAD_DATE_HUMAN" \
        "$HEAD_DATE_EPOCH" \
        "$AHEAD" \
        "$BEHIND" \
        "$STATUS" \
        "$HAS_UNTRACKED" \
        "$HAS_MODIFIED" \
        "$HAS_STAGED" \
        "$LAST_WORK_EPOCH" \
        "$LAST_WORK_HUMAN" \
        "$DIR_MTIME_EPOCH" \
        "$DIR_MTIME_HUMAN" \
        "$SHADER_STATUS" \
        "$SHADER_LAST_EPOCH" \
        "$SHADER_LAST_HUMAN"

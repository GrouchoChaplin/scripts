\
    #!/usr/bin/env bash
    #
    # shader_compare_V5.6-Patch4.sh
    #
    # Lightweight helper to compare shader files across multiple repo variants.
    #
    # This is optional sugar on top of compare_repo_variants_V5.6-Patch4.sh and is meant
    # for targeted questions like:
    #
    #   "Which repo has the newest volumetric_cloud_shader.glsl?"
    #
    # Usage:
    #   shader_compare_V5.6-Patch4.sh --shader-path RELPATH --repo PATH [--repo PATH ...]
    #
    # Example:
    #   shader_compare_V5.6-Patch4.sh \
    #       --shader-path JSIG_Data/Shaders/Volume/volumetric_cloud_shader.glsl \
    #       --repo /path/to/repo.A \
    #       --repo /path/to/repo.B
    #

    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/utils_V5.6-Patch4.sh"

    SHADER_PATH=""
    REPOS=()

    usage() {
        cat <<EOF
    Usage:
      $(basename "$0") --shader-path RELPATH --repo PATH [--repo PATH ...]

    Options:
      --shader-path RELPATH   Path to shader file relative to repo root.
      --repo PATH             Repo working tree path. You can pass this multiple times.

    This script:
      - checks presence of the shader in each repo
      - reports last modification time and SHA256
      - prints a small ranked table (newest first)
    EOF
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --shader-path)
                SHADER_PATH="${2:-}"
                shift 2
                ;;
            --repo)
                REPOS+=("${2:-}")
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

    if [[ -z "$SHADER_PATH" || "${#REPOS[@]}" -eq 0 ]]; then
        log_error "--shader-path and at least one --repo are required."
        usage
        exit 1
    fi

    require_cmd sha256sum stat || exit 1

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT

    for r in "${REPOS[@]}"; do
        r_abs="$(abspath "$r")"
        f="${r_abs}/${SHADER_PATH}"
        if [[ ! -f "$f" ]]; then
            printf '%s\tMISSING\t0\t-\n' "$r_abs" >> "$tmp"
            continue
        fi

        e="$(get_file_epoch "$f" || echo 0)"
        h="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
        printf '%s\tPRESENT\t%s\t%s\n' "$r_abs" "$e" "$h" >> "$tmp"
    done

    printf '\n'
    printf 'Shader comparison: %s\n' "$SHADER_PATH"
    printf '===============================================\n\n'
    printf 'RANK  LAST_MOD_TIME        STATUS   SHA256                                REPO_PATH\n'
    printf '----  -------------------  -------  ------------------------------------  ---------\n'

    rank=0
    sort -t $'\t' -k3,3nr "$tmp" | while IFS=$'\t' read -r RPATH STATUS EPOCH HASH; do
        rank=$((rank+1))
        human="$(epoch_to_human "$EPOCH")"
        [[ "$STATUS" == "MISSING" ]] && human="-"
        printf '%-3d   %-19s  %-7s  %-36s  %s\n' "$rank" "$human" "$STATUS" "$HASH" "$RPATH"
    done

    printf '\n'
    printf 'Note: MISSING entries are sorted last.\n\n'

#!/usr/bin/env bash
set -euo pipefail

P=4
N=50
ROOT=""
FILE=""
FILE_PATTERN=""
CSV_OUT=""
JSON_OUT=""

usage() {
    echo "Usage:"
    echo "  $0 --root DIR (--file NAME | --file-pattern GLOB) [-N NUM] [-P NUM] [--csv out.csv] [--json out.json]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2;;
        --file) FILE="$2"; shift 2;;
        --file-pattern) FILE_PATTERN="$2"; shift 2;;
        -N|--count) N="$2"; shift 2;;
        -P|--parallel) P="$2"; shift 2;;
        --csv) CSV_OUT="$2"; shift 2;;
        --json) JSON_OUT="$2"; shift 2;;
        *) usage;;
    esac
done

[[ -z "$ROOT" ]] && usage
[[ -z "$FILE" && -z "$FILE_PATTERN" ]] && usage

if [[ -n "$FILE" ]]; then
    if [[ "$FILE" == *"*"* || "$FILE" == *"?"* || "$FILE" == *"["* ]]; then
        FIND_EXPR=(-name "$FILE")
    else
        FIND_EXPR=(-type f -name "$FILE")
    fi
else
    FIND_EXPR=(-type f -name "$FILE_PATTERN")
fi

parallel_stat() {
    stat --printf="%Y %n\n" "$1" 2>/dev/null || true
}
export -f parallel_stat

RESULTS=$(find "$ROOT" -maxdepth 12 "${FIND_EXPR[@]}" -print0 \
    | parallel -0 -P "$P" parallel_stat {} \
    | sort -rn \
    | head -n "$N")

if [[ -n "$CSV_OUT" ]]; then
    echo "timestamp,path" > "$CSV_OUT"
    while read -r ts path; do
        echo "$ts,\"$path\"" >> "$CSV_OUT"
    done <<< "$RESULTS"
fi

if [[ -n "$JSON_OUT" ]]; then
    echo "[" > "$JSON_OUT"
    first=1
    while read -r ts path; do
        [[ $first -eq 0 ]] && echo "," >> "$JSON_OUT"
        first=0
        printf '{"timestamp": %s, "path": "%s"}' "$ts" "$path" >> "$JSON_OUT"
    done <<< "$RESULTS"
    echo "]" >> "$JSON_OUT"
fi

echo "$RESULTS"

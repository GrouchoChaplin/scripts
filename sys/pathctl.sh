#!/usr/bin/env bash
# pathctl.sh - Manage PATH and LD_LIBRARY_PATH safely
# Version: 1.0
# Usage:
#   pathctl.sh add path /my/new/bin
#   pathctl.sh remove path /my/bin
#   pathctl.sh add ld    /my/lib
#   pathctl.sh remove ld /my/lib
#
# To apply the result:
#   eval "$(pathctl.sh add path /opt/mybin)"

set -euo pipefail

clean_list() {
    # Deduplicate while preserving order
    awk -v RS=":" '!seen[$0]++ { printf "%s%s", sep, $0; sep=":" }'
}

remove_entry() {
    local entry="$1"
    awk -v RS=":" -v target="$entry" '$0 != target { printf "%s%s", sep, $0; sep=":" }'
}

add_entry() {
    local entry="$1"
    awk -v RS=":" -v target="$entry" '
        { items[NR]=$0 }
        END {
            found=0
            for(i=1;i<=NR;i++){
                if(items[i] == target) found=1
            }
            for(i=1;i<=NR;i++){
                printf "%s%s", sep, items[i]; sep=":"
            }
            if(!found) printf "%s%s", sep, target
        }'
}

print_usage() {
    cat <<EOF
Usage:
  pathctl.sh add path <dir>
  pathctl.sh remove path <dir>
  pathctl.sh add ld <dir>
  pathctl.sh remove ld <dir>

Example:
  eval "\$(pathctl.sh add path /opt/mybin)"
EOF
}

[[ $# -ge 3 ]] || { print_usage; exit 1; }

action="$1"   # add | remove
target="$2"   # path | ld
dir="$3"

# Normalize path:
dir="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"

# Choose variable
if [[ "$target" == "path" ]]; then
    current="${PATH:-}"
    varname="PATH"
elif [[ "$target" == "ld" ]]; then
    current="${LD_LIBRARY_PATH:-}"
    varname="LD_LIBRARY_PATH"
else
    print_usage
    exit 1
fi

case "$action" in
    add)
        newval="$(printf "%s" "$current" | add_entry "$dir" | clean_list)"
        ;;
    remove)
        newval="$(printf "%s" "$current" | remove_entry "$dir" | clean_list)"
        ;;
    *)
        print_usage
        exit 1
        ;;
esac

echo "export $varname=\"$newval\""

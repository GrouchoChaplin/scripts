#!/usr/bin/env bash
#
# compare_repo_variants_V5.6_Patch8_modular.sh
#
# Modular wrapper that loads all logic from lib/core.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${SCRIPT_DIR}/lib/core.sh" ]]; then
    echo "❌ Missing core library: ${SCRIPT_DIR}/lib/core.sh" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/core.sh"

# After sourcing, all functions and CLI parsing logic are available.
# We just invoke the "main" function provided by core.sh.
main "$@"

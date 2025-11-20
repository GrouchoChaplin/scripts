#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify_env.sh — Modular Environment Diagnostic + Startup Profiler
#
# Verifies aliases, environment variables, dev tools, and optionally measures:
#   • Overall shell startup time
#   • Per-module load time (with --verbose)
#
# Usage:
#   ./verify_env.sh          # silent summary
#   ./verify_env.sh --verbose   # detailed per-file profiling
# ---------------------------------------------------------------------------

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

pass() { echo -e "${GREEN}✔ PASS${RESET}  $1"; }
warn() { echo -e "${YELLOW}⚠ WARN${RESET}  $1"; }
fail() { echo -e "${RED}✖ FAIL${RESET}  $1"; }

VERBOSE=false
[[ "$1" == "--verbose" ]] && VERBOSE=true

echo "──────────────────────────────────────────────"
echo "🔍 Verifying environment setup..."
echo "──────────────────────────────────────────────"

# --- 1️⃣ Check: init_all.sh sourcing ----------------------------------------
if grep -q "init_all.sh" ~/.bashrc 2>/dev/null; then
    pass "~/.bashrc sources init_all.sh"
else
    fail "~/.bashrc does NOT source init_all.sh"
fi

# --- 2️⃣ Aliases ------------------------------------------------------------
if alias reloadEnv &>/dev/null; then
    pass "reloadEnv alias active"
else
    fail "reloadEnv alias not found"
fi

declare -a core_aliases=(ll gsr glo gss)
for a in "${core_aliases[@]}"; do
    if alias "$a" &>/dev/null; then
        pass "alias $a defined"
    else
        fail "alias $a missing"
    fi
done

# --- 3️⃣ Environment variables ----------------------------------------------
[[ -n "$UNUSED_PROCS" ]] && pass "UNUSED_PROCS = $UNUSED_PROCS" || fail "UNUSED_PROCS not set"
[[ -n "$PS1" ]] && pass "PS1 prompt defined" || warn "PS1 not defined"

# --- 4️⃣ Git branch prompt --------------------------------------------------
if [[ -n "$(type -t git_branch)" ]]; then
    pass "git_branch() function loaded"
else
    warn "git_branch() not found (prompt may not show branch)"
fi

# --- 5️⃣ CUDA ---------------------------------------------------------------
if [[ -n "$CUDA_HOME" && -x "$CUDA_HOME/bin/nvcc" ]]; then
    pass "CUDA detected at $CUDA_HOME"
elif [[ -n "$CUDA_HOME" ]]; then
    warn "CUDA_HOME set but nvcc missing"
else
    warn "CUDA not detected (expected if not installed)"
fi

# --- 6️⃣ Dev tools ----------------------------------------------------------
if command -v gcc &>/dev/null; then
    pass "GCC detected: $(gcc --version | head -n1)"
else
    warn "GCC not found"
fi

if command -v cmake &>/dev/null; then
    pass "CMake detected: $(cmake --version | head -n1)"
else
    warn "CMake not found"
fi

if command -v conan &>/dev/null; then
    pass "Conan available"
else
    warn "Conan not installed"
fi

if [[ -n "$VCPKG_ROOT" ]]; then
    pass "vcpkg path: $VCPKG_ROOT"
else
    warn "vcpkg not configured"
fi

if alias devinfo &>/dev/null; then
    pass "devinfo alias active"
else
    warn "devinfo alias missing"
fi

# --- 7️⃣ Measure shell startup time -----------------------------------------
echo
echo "⏱ Measuring interactive shell startup time..."
SECONDS=0
bash --login -i -c "exit" >/dev/null 2>&1
DURATION=$SECONDS

if (( DURATION < 1 )); then
    pass "Shell startup time: <1s (excellent)"
elif (( DURATION < 2 )); then
    pass "Shell startup time: ${DURATION}s (good)"
elif (( DURATION < 4 )); then
    warn "Shell startup time: ${DURATION}s (okay)"
else
    fail "Shell startup time: ${DURATION}s (slow — investigate heavy scripts)"
fi

# --- 8️⃣ Verbose mode: per-module profiling ---------------------------------
if $VERBOSE; then
    echo
    echo "📊 Per-module load time breakdown:"
    echo "──────────────────────────────────────────────"

    SCRIPT_ROOT="$HOME/projects/peddycoartte/scripts"
    total_time=0
    while IFS= read -r -d '' f; do
        start=$(date +%s%3N)
        bash -c "source '$f' 2>/dev/null" >/dev/null 2>&1
        end=$(date +%s%3N)
        diff=$((end - start))
        printf "  %s %s\n" "$(printf '%6dms' "$diff")" "${f#$SCRIPT_ROOT/}"
        total_time=$((total_time + diff))
    done < <(find "$SCRIPT_ROOT" -type f -name "*.sh" ! -path "*/.cache/*" -print0 | sort -z)

    echo "──────────────────────────────────────────────"
    printf "  Total measured load time: %dms\n" "$total_time"
fi

# --- Summary ---------------------------------------------------------------
echo "──────────────────────────────────────────────"
echo "✅ Environment verification complete."
echo "──────────────────────────────────────────────"

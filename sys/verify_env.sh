#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify_env.sh  —  Diagnostic for modular Bash environment
#
# Checks:
#   • .bashrc sourcing of init_all.sh
#   • Aliases present
#   • Key environment variables set
#   • Git prompt & reload alias
#   • CUDA / DevTools detection
#
# Run anytime with:
#   ./verify_env.sh
# ---------------------------------------------------------------------------

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

pass() { echo -e "${GREEN}✔ PASS${RESET}  $1"; }
warn() { echo -e "${YELLOW}⚠ WARN${RESET}  $1"; }
fail() { echo -e "${RED}✖ FAIL${RESET}  $1"; }

echo "──────────────────────────────────────────────"
echo "🔍 Verifying environment setup..."
echo "──────────────────────────────────────────────"

# --- Check 1: init_all.sh sourcing -----------------------------------------
if grep -q "init_all.sh" ~/.bashrc 2>/dev/null; then
    pass "~/.bashrc sources init_all.sh"
else
    fail "~/.bashrc does NOT source init_all.sh"
fi

# --- Check 2: reloadEnv alias ---------------------------------------------
if alias reloadEnv &>/dev/null; then
    pass "reloadEnv alias is active"
else
    fail "reloadEnv alias not found"
fi

# --- Check 3: core aliases -------------------------------------------------
declare -a core_aliases=(ll gsr glo gss)
for a in "${core_aliases[@]}"; do
    if alias "$a" &>/dev/null; then
        pass "alias $a is defined"
    else
        fail "alias $a is missing"
    fi
done

# --- Check 4: environment variables ---------------------------------------
[[ -n "$UNUSED_PROCS" ]] && pass "UNUSED_PROCS = $UNUSED_PROCS" || fail "UNUSED_PROCS not set"
[[ -n "$PS1" ]] && pass "PS1 prompt variable set" || warn "PS1 not defined"

# --- Check 5: Git branch prompt -------------------------------------------
if [[ -n "$(type -t git_branch)" ]]; then
    pass "git_branch() function loaded"
else
    warn "git_branch() not found (prompt may not show branch)"
fi

# --- Check 6: CUDA ---------------------------------------------------------
if [[ -n "$CUDA_HOME" && -x "$CUDA_HOME/bin/nvcc" ]]; then
    pass "CUDA detected at $CUDA_HOME"
elif [[ -n "$CUDA_HOME" ]]; then
    warn "CUDA_HOME set but nvcc missing"
else
    warn "CUDA not detected (expected if not installed)"
fi

# --- Check 7: Dev tools ----------------------------------------------------
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

# --- Check 8: devinfo alias ------------------------------------------------
if alias devinfo &>/dev/null; then
    pass "devinfo alias active"
else
    warn "devinfo alias missing"
fi

echo "──────────────────────────────────────────────"
echo "✅ Environment verification complete."
echo "──────────────────────────────────────────────"

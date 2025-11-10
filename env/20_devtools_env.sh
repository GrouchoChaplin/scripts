#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 20_devtools_env.sh — Development toolchain environment setup
#
# Detects and configures compiler, build, and package management tools.
# Designed for Rocky/RHEL, Fedora, and Ubuntu systems.
#
# Loaded automatically by init_all.sh after CUDA and core environment scripts.
# ---------------------------------------------------------------------------

# --- Only run in interactive shells ----------------------------------------
[[ $- != *i* ]] && return

# --- Compiler Toolset Detection --------------------------------------------
# Prefer gcc-toolset (Rocky/RHEL), fallback to system GCC or Clang.

if command -v scl_source &>/dev/null; then
    # Handle GCC toolsets on RHEL-based systems
    for version in 14 13 12 11 10; do
        if [[ -d "/opt/rh/gcc-toolset-${version}" ]]; then
            # shellcheck disable=SC1091
            source "/opt/rh/gcc-toolset-${version}/enable"
            export GCC_TOOLSET_VERSION="$version"
            break
        fi
    done
fi

# Fallback to standard compilers if toolset not found
if ! command -v gcc &>/dev/null && command -v clang &>/dev/null; then
    export CC="clang"
    export CXX="clang++"
else
    export CC="${CC:-gcc}"
    export CXX="${CXX:-g++}"
fi

# --- CMake Detection -------------------------------------------------------
if command -v cmake &>/dev/null; then
    export CMAKE_BIN="$(command -v cmake)"
else
    echo "⚠️  CMake not found — some build scripts may fail." >&2
fi

# --- Conan (C++ package manager) -------------------------------------------
if command -v conan &>/dev/null; then
    export CONAN_HOME="$HOME/.conan2"
else
    echo "⚠️  Conan not installed (pip install conan recommended)." >&2
fi

# --- Vcpkg (Microsoft C++ package manager) ---------------------------------
if [[ -d "$HOME/vcpkg" ]]; then
    export VCPKG_ROOT="$HOME/vcpkg"
    export PATH="$VCPKG_ROOT:$PATH"
elif [[ -d "/opt/vcpkg" ]]; then
    export VCPKG_ROOT="/opt/vcpkg"
    export PATH="$VCPKG_ROOT:$PATH"
fi

# --- Ninja build system ----------------------------------------------------
if command -v ninja &>/dev/null; then
    export NINJA_BIN="$(command -v ninja)"
else
    echo "⚠️  Ninja not installed — CMake may fall back to Makefiles." >&2
fi

# --- Python / Virtualenvs --------------------------------------------------
if command -v python3 &>/dev/null; then
    export PYTHON_BIN="$(command -v python3)"
    export PYTHONUSERBASE="$HOME/.local"
else
    echo "⚠️  Python3 not found — certain dev utilities may fail." >&2
fi

# --- Add convenient aliases ------------------------------------------------
alias gccver='${CC:-gcc} --version | head -n1'
alias clangver='clang --version | head -n1 2>/dev/null || echo "clang not installed"'
alias cmver='cmake --version | head -n1 2>/dev/null || echo "cmake not installed"'
alias devinfo='echo -e "Compiler: ${CC:-unknown}\nC++: ${CXX:-unknown}\nCMake: ${CMAKE_BIN:-not found}\nConan: $(command -v conan || echo none)\nVcpkg: ${VCPKG_ROOT:-none}\nPython: ${PYTHON_BIN:-none}\nCUDA: ${CUDA_HOME:-none}"'
alias gss='git status -s'

# --- Optional message (disabled by default) --------------------------------
# echo "[env] Development tools environment loaded."

export PATH="$HOME/projects/3rdParty/flutter/bin:$PATH"


#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 10_cuda_env.sh — Optional CUDA environment setup
#
# Safely adds CUDA paths if CUDA is installed.
# This file is sourced automatically by init_all.sh after 01_core_env.sh.
# ---------------------------------------------------------------------------

# --- Only run in interactive shells ----------------------------------------
[[ $- != *i* ]] && return

CUDA_DIR="/usr/local/cuda"
CUDA_BIN="$CUDA_DIR/bin"
CUDA_LIB64="$CUDA_DIR/lib64"

# --- Detect and load CUDA ---------------------------------------------------
if [[ -d "$CUDA_DIR" && -x "$CUDA_BIN/nvcc" ]]; then
    # Update PATH and LD_LIBRARY_PATH if not already included
    case ":$PATH:" in
        *":$CUDA_BIN:"*) ;;  # already present
        *) export PATH="$CUDA_BIN:$PATH" ;;
    esac

    case ":$LD_LIBRARY_PATH:" in
        *":$CUDA_LIB64:"*) ;;
        *) export LD_LIBRARY_PATH="$CUDA_LIB64:${LD_LIBRARY_PATH:-}" ;;
    esac

    export CUDA_HOME="$CUDA_DIR"
    export CUDADIR="$CUDA_DIR"

    # Optional: Set NVCC color output (if available)
    export NVCC_PRETTY_OUTPUT=1

    # Optional: Define a helper alias to check the active CUDA version
    alias cudaver='nvcc --version | grep "release"'

    # Uncomment to show confirmation on load
    # echo "[env] CUDA detected and environment loaded."
else
    # Only warn once per session
    if [[ -z "${CUDA_WARNED:-}" ]]; then
        echo "⚠️  CUDA not found at $CUDA_DIR — skipping CUDA environment setup." >&2
        export CUDA_WARNED=1
    fi
fi

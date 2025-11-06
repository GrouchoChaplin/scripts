#!/usr/bin/env bash
#
# Description: Adds git branch info and command logging to Bash prompt.
# Author:      peddycoartte
# Created:     2025-11-06 17:34:14
# Usage:       
#

set -e
set -o pipefail

# --- Ensure log directory exists ---
LOG_DIR="$HOME/.logs/BASH"
mkdir -p "$LOG_DIR"

# --- Enhanced command logger ---
log_command() {
  # Log only for non-root users
  if [[ "$(id -u)" -ne 0 ]]; then
    local ts cmd dir
    ts="$(date '+%Y-%m-%d.%H:%M:%S')"
    dir="$(pwd)"
    cmd="$(history 1 | sed 's/^ *[0-9]* *//')"  # strip history number
    echo "[$ts] $dir :: $cmd" >> "$LOG_DIR/bash-history-$(date '+%Y-%m-%d').log"
  fi
}
PROMPT_COMMAND="log_command${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# --- Fast git branch function ---
git_branch() {
  # Return nothing if not in a git repo
  local branch
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  [[ -n $branch ]] && echo "($branch)"
}

# --- Color definitions ---
RED='\[\033[0;31m\]'
GREEN='\[\033[0;32m\]'
BLUE='\[\033[0;34m\]'
CYAN='\[\033[0;36m\]'
RESET='\[\033[0m\]'

# --- Fancy, informative prompt ---
export PS1="${BLUE}[\u@\h ${CYAN}\W${GREEN}\$(git_branch)${BLUE}]${RESET}\$ "

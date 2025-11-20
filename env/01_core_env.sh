#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# 01_core_env.sh  —  Core environment setup
#
# Loads before other environment modules (e.g., aliases, CUDA, etc.)
# Provides clean PATH management, colorized tools, locale sanity,
# and shell behavior that improves safety and readability.
# ---------------------------------------------------------------------------

# --- Safety: only load in interactive shells --------------------------------
[[ $- != *i* ]] && return

# --- PATH management --------------------------------------------------------
# Cleanly ensure /usr/local/bin and ~/bin come first
case ":$PATH:" in
    *":$HOME/bin:"*) ;; # already in path
    *) export PATH="$HOME/bin:$PATH" ;;
esac

case ":$PATH:" in
    *":/usr/local/bin:"*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac

# --- Locale / Encoding ------------------------------------------------------
# Make sure UTF-8 is always active (avoids Python, Git, grep issues)
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# --- Umask (default file permissions) --------------------------------------
# Default: 0022 = user RWX, group R-X, others R-X
# For shared dev environments, 0027 is safer (no group write access)
umask 0022

# --- Editor defaults --------------------------------------------------------
export EDITOR="vim"
export VISUAL="vim"

# --- Less & grep colorization ----------------------------------------------
export LESS="-R -M -N"
export LESSHISTFILE=-
#export GREP_OPTIONS="--color=auto"
export GREP_COLORS='mt=1;31'

# --- LS colors --------------------------------------------------------------
if command -v dircolors &>/dev/null; then
    eval "$(dircolors -b)"
fi

# --- Bash completion (if available) ----------------------------------------
if [ -f /etc/bash_completion ] && [ -n "$PS1" ]; then
    # shellcheck disable=SC1091
    source /etc/bash_completion
fi

# --- History control --------------------------------------------------------
export HISTCONTROL=ignoredups:erasedups
export HISTSIZE=5000
export HISTFILESIZE=20000
shopt -s histappend      # append to history file, don't overwrite
shopt -s cmdhist         # multi-line commands saved as one entry

# --- Directory navigation shortcuts ----------------------------------------
shopt -s autocd          # allow typing dir name to cd into it
shopt -s cdspell         # autocorrect typos in cd paths
shopt -s checkwinsize    # auto-update LINES and COLUMNS

# --- Prompt coloring (fallback, if git prompt fails) ------------------------
if [[ -z "${PS1:-}" ]]; then
    export PS1="[\u@\h \W]\$ "
fi

# --- Confirmation -----------------------------------------------------------
# Uncomment for debug info during startup
# echo "[env] Core environment loaded (01_core_env.sh)"

alias cls='printf "\33[2J"';
alias h='history'
alias updateNOW='export NOW=$(date "+%Y_%m_%d_T%H_%M_%S") && echo $NOW'

export SCRIPT_PREAMBLE="$HOME/projects/scripts/sys/script_preamble.sh"
export SCRIPTS_HOME=/home/peddycoartte/projects/scripts
export PATH="${SCRIPTS_HOME}/backup":$PATH
export PATH="${SCRIPTS_HOME}/conda":$PATH
export PATH="${SCRIPTS_HOME}/env":$PATH
export PATH="${SCRIPTS_HOME}/git":$PATH
export PATH="${SCRIPTS_HOME}/net":$PATH
export PATH="${SCRIPTS_HOME}/search":$PATH
export PATH="${SCRIPTS_HOME}/sys":$PATH
export PATH="${SCRIPTS_HOME}/sys/ownership_tools":$PATH
export PATH="${SCRIPTS_HOME}/test":$PATH

export PROMPT_COMMAND='if [ "$(id -u)" -ne 0 ]; then 
    echo "$(date "+%Y-%m-%d.%H:%M:%S") $(pwd) $(history 1)" >> ~/.logs/BASH/bash-history-$(date "+%Y-%m-%d").log; 
fi'
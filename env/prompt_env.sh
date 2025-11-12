#!/usr/bin/env bash
# ------------------------------------------------------------------
# dynamic_git_prompt.sh
# Shows a colorized git-aware Bash prompt.
# If $SHOW_FULL_PATH is set, uses full path; otherwise, shows only folder name.
# ------------------------------------------------------------------

# --- Git branch helper with color + symbols + detached HEAD support ---
git_branch() {
  local ref branch color symbol

  # Get branch name or detached commit hash
  ref=$(git symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    branch="$ref"
  else
    branch=$(git rev-parse --short HEAD 2>/dev/null) || return
    branch="detached@$branch"
  fi

  # Determine color and symbol
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
      color="\033[0;33m"  # 🟡 Untracked
      symbol="+"
    elif ! git diff --quiet 2>/dev/null; then
      color="\033[1;31m"  # 🔴 Unstaged
      symbol="*"
    elif ! git diff --cached --quiet 2>/dev/null; then
      color="\033[0;33m"  # 🟡 Staged
      symbol="+"
    else
      color="\033[0;32m"  # 🟢 Clean
      symbol="✔"
    fi
  fi

  echo -e " (${color}${branch}${symbol}\033[0m)"
}

# --- Determine whether to show full path or just folder ---
if [[ -n "${SHOW_FULL_PATH:-}" ]]; then
  # Show full path (\w)
  PATH_FORMAT="\[\033[38;5;27m\][\w]\[\033[0m\]"
else
  # Show only folder (\W)
  PATH_FORMAT="\[\033[38;5;27m\][\W]\[\033[0m\]"
fi

# --- Final PS1 construction ---
# user@host = color 11 (yellow)
# folder = color 27 (cyan-blue)
# $ = color 10 (green)
export PS1="\[\033[38;5;11m\]\u@\h\[\033[0m\] ${PATH_FORMAT}\$(git_branch)\[\033[38;5;10m\]\$\[\033[0m\] "

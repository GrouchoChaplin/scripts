# --- Git branch helper with live color + symbols + detached HEAD support ---
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
    if git diff --quiet 2>/dev/null; then
      if git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        color="\033[0;32m"   # 🟢 Clean
        symbol="✔"
      else
        color="\033[0;33m"   # 🟡 Staged or untracked
        symbol="+"
      fi
    else
      color="\033[1;31m"     # 🔴 Unstaged changes
      symbol="*"
    fi
  fi

  # Print directly with ANSI color codes (no prompt escapes)
  echo -e " (${color}${branch}${symbol}\033[0m)"
}

# --- PS1 prompt: user@host cwd (branch status) ---
export PS1="\[\e[36m\]\u@\h\[\e[0m\] \[\e[34m\]\W\[\e[0m\]\$(git_branch)\[\e[32m\]\$\[\e[0m\] "

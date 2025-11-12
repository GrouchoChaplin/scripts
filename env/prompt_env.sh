# --- Git branch helper with color status and detached HEAD support ---
git_branch() {
  local ref branch color

  # Get branch or commit (detached)
  ref=$(git symbolic-ref --short -q HEAD 2>/dev/null)
  if [ -n "$ref" ]; then
    branch="$ref"
  else
    branch=$(git rev-parse --short HEAD 2>/dev/null) || return
    branch="detached@$branch"
  fi

  # Determine color
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git diff --quiet 2>/dev/null; then
      if git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        color="\e[32m"   # green = clean
      else
        color="\e[33m"   # yellow = staged/untracked
      fi
    else
      color="\e[31m"     # red = unstaged
    fi
  fi

  # ✅ Use double quotes and properly escaped sequences
  echo " (\[${color}\]${branch}\[\e[0m\])"
}


# --- PS1: user@host cwd (branch) ---
export PS1="\[\e[36m\]\u@\h\[\e[0m\] \[\e[34m\]\W\[\e[0m\]\$(git_branch)\[\e[32m\]\$\[\e[0m\] "

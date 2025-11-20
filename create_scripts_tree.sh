#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create_scripts_tree.sh
# Creates or updates a modular directory tree for your personal scripts repo.
# Supports Git initialization and dynamic README regeneration.
#
# Usage:
#   ./create_scripts_tree.sh [target_path] [--git-init] [--origin <url>] [--update-readme]
# ---------------------------------------------------------------------------

set -euo pipefail

# --- Parse arguments ---
ROOT="${1:-$HOME/projects/peddycoartte/scripts}"
GIT_INIT=false
ORIGIN_URL=""
UPDATE_README=false

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --git-init) GIT_INIT=true ;;
        --origin) ORIGIN_URL="$2"; shift ;;
        --update-readme) UPDATE_README=true ;;
        *)
            echo "⚠️  Unknown option: $1"
            echo "Usage: $0 [target_path] [--git-init] [--origin <url>] [--update-readme]"
            exit 1 ;;
    esac
    shift
done

# --- Function: generate markdown tree ---
generate_tree_md() {
    local path="$1"
    if command -v tree &>/dev/null; then
        echo '```'
        tree -L 2 --noreport "$path" | sed "s|$HOME|~|"
        echo '```'
    else
        echo '```'
        find "$path" -maxdepth 2 -type d | sed "s|$HOME|~|" | sed 's|^|├── |'
        echo '```'
    fi
}

# --- Function: generate README dynamically ---
generate_readme() {
    local readme="$ROOT/README.md"
    echo "🧾 Generating dynamic README.md"
    cat > "$readme" <<EOF
# 🧰 Scripts Repository

Personal Bash & system utilities that autoload automatically via \`init_all.sh\`.

## 📦 Current Structure
$(generate_tree_md "$ROOT")

## ⚙️ Auto-Loader
The [\`init_all.sh\`](./init_all.sh) script automatically sources all
\`.sh\` files one level deep under each subdirectory.

Add this to your \`~/.bashrc\`:
\`\`\`bash
if [ -f "\$HOME/projects/peddycoartte/scripts/init_all.sh" ]; then
    source "\$HOME/projects/peddycoartte/scripts/init_all.sh"
fi
\`\`\`

## 🧩 Setup Helper
[\`setup_bash_env.sh\`](./setup_bash_env.sh) bootstraps this environment:
- Creates folder tree if missing  
- Backs up your \`~/.bashrc\`  
- Adds loader snippet automatically  

## 💡 Notes
- All scripts are safe to source; none execute automatically.
- Ideal for Git, system maintenance, backups, and personal CLI tools.
EOF
    echo "✅ README.md updated."
}

# --- Short-circuit: update only README if requested ---
if $UPDATE_README; then
    if [ ! -d "$ROOT" ]; then
        echo "❌ Directory $ROOT does not exist. Cannot update README."
        exit 1
    fi
    generate_readme
    exit 0
fi

# --- Create directories ---
echo "🧩 Creating directory structure under: $ROOT"
mkdir -p "$ROOT/git" "$ROOT/sys" "$ROOT/net"

# --- Helper: create placeholder file if missing ---
create_file() {
    local file="$1"
    local desc="$2"
    if [ -f "$file" ]; then
        echo "✅ $file already exists."
    else
        echo "📄 Creating $file ($desc)"
        cat > "$file" <<EOF
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ${file##*/} - $desc
# ---------------------------------------------------------------------------

[[ "\${BASH_SOURCE[0]}" != "\${0}" ]] || {
    echo "❌ This script is meant to be sourced, not executed directly."
    exit 1
}

# TODO: Implement $desc logic here.
EOF
        chmod +x "$file"
    fi
}

# --- Create core scripts if missing ---
create_file "$ROOT/git/git_branch_search.sh" "Git branch search utility (main function + alias)"
create_file "$ROOT/git/git_branch_search_completion.sh" "Tab completion for git_branch_search"
create_file "$ROOT/sys/backup_nightly.sh" "Nightly backup automation script"
create_file "$ROOT/sys/cleanup_temp.sh" "Temporary file cleanup tool"
create_file "$ROOT/net/ping_tools.sh" "Network reachability and ping utilities"
create_file "$ROOT/init_all.sh" "Autoload all .sh files from subfolders"
create_file "$ROOT/setup_bash_env.sh" "Installer that sets up the Bash environment"

# --- Create or update README dynamically ---
generate_readme

# --- Print tree summary ---
echo
echo "✅ Directory tree created successfully!"
echo
if command -v tree &>/dev/null; then
    tree -L 2 "$ROOT"
else
    find "$ROOT" -maxdepth 2 -type d -print
fi
echo

# --- Optional Git initialization ---
if $GIT_INIT; then
    echo "🔧 Initializing Git repository..."
    cd "$ROOT"

    if [ -d .git ]; then
        echo "✅ Git repo already initialized."
    else
        git init
        echo "✅ Git repo created."
    fi

    # Stage and commit if no history
    if ! git rev-parse HEAD &>/dev/null; then
        git add .
        git commit -m "Initial commit: directory tree, placeholders, and dynamic README"
        echo "📦 Initial commit created."
    fi

    # Add or update remote
    if [[ -n "$ORIGIN_URL" ]]; then
        if git remote get-url origin &>/dev/null; then
            echo "🔄 Updating remote 'origin' → $ORIGIN_URL"
            git remote set-url origin "$ORIGIN_URL"
        else
            echo "🔗 Setting remote 'origin' → $ORIGIN_URL"
            git remote add origin "$ORIGIN_URL"
        fi
    fi

    echo
    echo "✅ Git setup complete."
    git status -sb
    echo
fi

echo "🎉 Done! Your scripts tree is ready at: $ROOT"
echo "📘 README.md dynamically reflects your current structure."

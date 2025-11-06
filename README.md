# 🧰 Scripts Repository

Personal Bash & system utilities that autoload automatically via `init_all.sh`.

## 📦 Current Structure
```
~/projects/scripts/
├── backup
│   └── nightly_backup.sh
├── create_script_file.sh
├── create_scripts_tree.sh
├── env
│   ├── 01_core_env.sh
│   ├── 10_cuda_env.sh
│   ├── 20_devtools_env.sh
│   ├── aliases_env.sh
│   ├── cuda_env.sh
│   ├── prompt_env.sh
│   └── README.md
├── git
│   ├── git_branch_search_completion.sh
│   ├── git_branch_search.sh
│   ├── git_search_file_branches.sh
│   └── git_search_file_remote_branches.sh
├── init_all.sh
├── net
│   └── ping_tools.sh
├── README.md
├── setup_bash_env.sh
└── sys
    ├── backup_nightly.sh
    ├── cleanup_temp.sh
    ├── create_tagged_archive.sh
    ├── extract_archive.sh
    ├── manage_locate_paths.log
    ├── manage_locate_paths.sh
    ├── verify_archive_file.sh
    └── verify_env.sh
```

## ⚙️ Auto-Loader
The [`init_all.sh`](./init_all.sh) script automatically sources all
`.sh` files one level deep under each subdirectory.

Add this to your `~/.bashrc`:
```bash
if [ -f "$HOME/projects/scripts/init_all.sh" ]; then
    source "$HOME/projects/scripts/init_all.sh"
fi
```

## 🧩 Setup Helper
[`setup_bash_env.sh`](./setup_bash_env.sh) bootstraps this environment:
- Creates folder tree if missing  
- Backs up your `~/.bashrc`  
- Adds loader snippet automatically  

## 💡 Notes
- All scripts are safe to source; none execute automatically.
- Ideal for Git, system maintenance, backups, and personal CLI tools.

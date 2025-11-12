# 🧰 Scripts Repository

Personal Bash & system utilities that autoload automatically via `init_all.sh`.

## 📦 Current Structure
```
~/projects/scripts
├── backup
│   └── nightly_backup.sh
├── conda
│   └── check_conda_libs.sh
├── create_script_file.sh
├── create_scripts_tree.sh
├── env
│   ├── 01_core_env.sh
│   ├── 10_cuda_env.sh
│   ├── 20_devtools_env.sh
│   ├── aliases_env.sh
│   ├── cuda_env.sh
│   ├── list_env_vars.sh
│   ├── prompt_env.sh
│   └── README.md
├── git
│   ├── compare_git_repos.sh
│   ├── git_branch_search_completion.sh
│   ├── git_branch_search.sh
│   ├── git_latest_info.sh
│   ├── git_modified.sh
│   ├── git_search_file_branches.sh
│   └── git_search_file_remote_branches.sh
├── init_all.sh
├── net
│   └── ping_tools.sh
├── README.md
├── search
│   └── fast_find_parallel.sh
├── setup_bash_env.sh
├── sys
│   ├── backup_nightly.sh
│   ├── cleanup_temp.sh
│   ├── create_tagged_archive.sh
│   ├── extract_archive.sh
│   ├── find_shaders_sha256.sh
│   ├── find_volume_shaders.sh
│   ├── git_prompt.sh
│   ├── manage_locate_paths.log
│   ├── manage_locate_paths.sh
│   ├── ownership_tools
│   ├── script_preamble.sh
│   ├── sort_files_by_mtime.sh
│   ├── system_info.sh
│   ├── update_anaconda.sh
│   ├── verify_archive_file.sh
│   └── verify_env.sh
└── test
    └── test_script_preable.sh
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

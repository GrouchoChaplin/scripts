# 🧩 Environment Modules Overview

This directory defines modular environment layers for your system.
Each `.sh` file is automatically sourced in lexical order (01_, 10_, 20_, etc.)
by the global loader `~/projects/peddycoartte/scripts/init_all.sh`.

---

## 📦 Load Order

| Load Stage | File | Purpose |
|-------------|------|----------|
| **01_core_env.sh** | Sets PATH, LANG, umask, colorized tools, bash completion, and safe defaults. |
| **my_aliases_env.sh** | Defines all aliases, prompt (`PS1`), and general environment variables. |
| **10_cuda_env.sh** | Enables CUDA paths (`/usr/local/cuda`) if installed, skips otherwise. |
| **20_devtools_env.sh** | Detects dev tools like gcc-toolset, cmake, conan, vcpkg, python, etc. |

Files load in this order automatically.  
You can add more using numeric prefixes, e.g.:


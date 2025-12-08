\
    # compare_repo_variants_V5.6-Patch4 – Enhanced Toolkit

    This directory contains the **enhanced V5.6-Patch4** version of the
    "compare repo variants" toolkit, focused on answering:

    > **"Where did I last leave off working on repo X?"**

    by scanning backups / copies of a git repository and ranking them by
    recent activity (commits + uncommitted work).

    ## Scripts

    All scripts live in `scripts/`:

    - `utils_V5.6-Patch4.sh`  
      Shared helpers (logging, colors, epoch utilities, `abspath`, etc.).

    - `extract_repo_metadata_V5.6-Patch4.sh`  
      Given a repo path, emits a single TSV row with commit info, ahead/behind,
      dirty status, untracked/modified/staged flags, directory mtime, and an
      overall `LAST_WORK_EPOCH` that takes into account uncommitted work.

    - `compare_repo_variants_V5.6-Patch4.sh`  
      Main entry point. Scans a `--root-folder` for `.git` repos matching
      `--repo-name` patterns, collects metadata, ranks by `LAST_WORK_EPOCH`,
      and prints a summary table. The top-ranked repo is your best candidate
      for "*where you last left off*".

    - `shader_compare_V5.6-Patch4.sh`  
      Optional helper that compares a single shader file (by relative path)
      across multiple repos, reporting last modification time and SHA256.

    ## Quickstart

    ```bash
    cd scripts
    chmod +x *.sh

    ./compare_repo_variants_V5.6-Patch4.sh \
        --root-folder /run/media/peddycoartte/MasterBackup/Nightly \
        --repo-name jsigconversiontools \
        --log-dir /tmp/git_forensics_logs \
        --top 15
    ```

    This will:

    1. Find all `.git` repos under the Nightly backup tree whose basename
       matches `jsigconversiontools`.
    2. Collect per-repo metadata.
    3. Rank by "last work epoch".
    4. Print a colorized summary and write a full TSV + log to `--log-dir`.

    The TSV path is printed at the end of the run.

    ## Shader comparison example

    ```bash
    ./shader_compare_V5.6-Patch4.sh \
        --shader-path JSIG_Data/Shaders/Volume/volumetric_cloud_shader.glsl \
        --repo /path/to/repo.A \
        --repo /path/to/repo.B
    ```

    This is optional sugar when you specifically want to see which repo has
    which shader version.

    ## Notes

    - These scripts assume a POSIX-ish environment (RHEL/Rocky 8 is ideal).
    - Dependencies: `git`, `find`, `sort`, `awk`, `stat`, and `sha256sum`
      for the shader helper.
    - All timestamps are in local time, with an underlying epoch field that
      is used for ranking.

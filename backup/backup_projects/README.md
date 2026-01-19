# backup_projects.sh v1.1

Dual‑mode backup script for:

- **Source**: `$HOME/projects`
- **Mirror**: `$HOME/project_backups/mirror/projects`
- **Snapshots**: `$HOME/project_backups/snapshots/<timestamp>/`

## Modes

Exactly one of:

- `--mirror` – keep a single up‑to‑date mirror of `projects/`.
- `--snapshot` – create a timestamped snapshot (Time‑Machine style).
- `--doctor` – run health checks only (no rsync).

## Key Options

- `--dry-run` – trial run, no changes.
- `--verbose` – increase rsync verbosity.
- `--progress` – per‑file progress.
- `--no-delete` – do **not** delete files removed from source.
- `--exclude-dir DIR` – exclude a directory or pattern under the source.
  - Examples:
    - `--exclude-dir JSIG`
    - `--exclude-dir "$HOME/projects/3rdParty"`
- `--exclude-file FILE` – read exclude patterns from `FILE` (one per line).
  - Lines starting with `#` or blank lines are ignored.
  - Patterns are interpreted relative to the source root.
- `--keep N` – keep only newest `N` snapshots (default as in script).
- `--help` – show usage.

## Typical Usage

### Mirror (with exclusions)

```bash
./backup_projects.sh --mirror \
  --exclude-dir "$HOME/projects/3rdParty" \
  --exclude-dir "$HOME/projects/IRImageryTool.KEEPJIC" \
  --exclude-dir "$HOME/projects/ProjectsRestored" \
  --exclude-dir "$HOME/projects/ir_imagery_tools_LatestWIP_REV6.RESTORED" \
  --exclude-dir "$HOME/projects/ir_imagery_tools.TEMP.RESTORED" \
  --exclude-dir "$HOME/projects/IRImageryTool" \
  --exclude-dir "$HOME/projects/JSIG"
```

### Snapshot with an exclude file

```bash
./backup_projects.sh --snapshot --progress --exclude-file examples/exclude-list.txt
```

## Exclude File Format

See `examples/exclude-list.txt` in this package. Each non‑empty, non‑comment line is passed to rsync as:

```bash
--exclude=<line>
```

relative to the source root (by default `$HOME/projects`).

## Installation

1. Copy `backup_projects.sh` somewhere on your `$PATH` or into your home bin:

   ```bash
   install -m 755 backup_projects.sh "$HOME/bin/backup_projects.sh"
   ```

2. Optionally create `$HOME/project_backups/` in advance, or let the script create it.

3. (Optional) Create a config file at:

   ```bash
   $HOME/project_backups/backup.conf
   ```

   to override defaults like `SRC`, `BACKUP_ROOT`, `KEEP_SNAPSHOTS`, or add default `EXCLUDE_DIRS`.

## Config Overrides

The script sources (if present):

```bash
$BACKUP_ROOT/backup.conf
```

You can set, for example:

```bash
SRC="$HOME/projects"
KEEP_SNAPSHOTS=40
EXCLUDE_DIRS=(
  "$HOME/projects/3rdParty"
  "$HOME/projects/ProjectsRestored"
)
EXCLUDE_FILE="$HOME/projects/exclude-projects.txt"
```

Config runs **before** safety checks and rsync, after CLI parsing.

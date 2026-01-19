# Example Commands for backup_projects.sh v1.1

## Mirror with explicit excludes

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

## Snapshot using an exclude file

```bash
./backup_projects.sh --snapshot --progress \
  --exclude-file examples/exclude-list.txt
```

## Doctor mode (no rsync, just checks)

```bash
./backup_projects.sh --doctor
```

# Dart Backup Reconciliation Toolkit

This toolkit helps you analyze multiple Flutter/Dart backups and reconstruct a
single tree containing the **latest version of every Dart file**.

It consists of:

- `find_latest_flutter_source_v1.9.2.sh`
- `reconstruct_latest_tree_v1.0.sh`

---

## 1. Analyzer – `find_latest_flutter_source.sh`

Scan a base directory for backup folders, find all `.dart` files, group them,
and identify the newest version in each group.

### Key features

- Scans subdirectories matching a pattern (e.g. `*ir_imagery_tools*`)
- Groups files by:
  - `basename` (e.g. all `main.dart`)
  - `relpath` (relative path under `lib/`)
  - `fullpath` (no grouping)
- Shows for each group:
  - newest path, time, size, SHA256
- Optional per-instance listing with:
  - `Path | Modification Time | Size | SHA256`
- CSV export (`--csv`)
- JSON export (`--json`)
- Diff-vs-latest summary (`--diff-vs-latest`)
- Parallel hashing using `xargs -P` when available

### Example

```bash
./find_latest_flutter_source_v1.9.2.sh \
  --paths "/run/media/peddycoartte/MasterBackup/ProjectWorkingCopyBackups" \
  --pattern "*ir_imagery_tools*" \
  --group-by relpath \
  --include-instances \
  --diff-vs-latest \
  --color-newest \
  --csv dart_audit.csv \
  --json dart_audit.json \
  --log-file dart_audit.log

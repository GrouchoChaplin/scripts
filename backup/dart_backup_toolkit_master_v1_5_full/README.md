# Dart Backup Reconciliation Toolkit

Deterministic, auditable reconciliation of Dart/Flutter source trees across many backup roots.

This repository contains:

- `find_latest_flutter_source_vX.sh` – Analyzer
- `reconstruct_latest_tree_vX.sh`   – Reconstructor
- `compare_reconstructed_trees.sh`  – Tree comparer
- `dart_backup_launcher.sh`         – Interactive launcher
- `presets.d/`                      – Named presets
- `docs/`                           – Markdown documentation
- `site/`                           – Static HTML docs (GitHub Pages-ready)

## Quick Start

```bash
./dart_backup_launcher.sh
```

Use the menu to:

1. Run analyzer with presets.
2. Run reconstructor (with safety lock).
3. Compare reconstructed trees.
4. View logs, dashboards, and recent artifacts.
5. Export dashboard summaries to Markdown for Obsidian.

For full documentation, see:

- `docs/UnifiedToolkitDocs.md`
- Or visit the GitHub Pages site (if enabled) at:<br>
  `https://<your-username>.github.io/<your-repo>/`

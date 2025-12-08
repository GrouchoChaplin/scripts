#!/bin/bash

./compare_repo_variants_V5.3.sh \
  --root-folder /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10 \
  --repo-name jsigconversiontools \
  --best --log \
  --diff-level per-file \
  --diff-pattern '*.dart' \
  --diff-pattern '*.txt' \
  --diff-pattern 'linux/native/libs/GDALUtils/*' \
  --diff-pattern '*.cpp' \
  --diff-pattern '*.h' \
  --diff-pattern '*.md' \
  --dirty-detail

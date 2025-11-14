#!/bin/bash

./compare_repo_variants_V5.6_Patch6.sh \
  --root-folder /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10 \
  --repo-name jsigconversiontools \
  --mode forensic \
  --debug-find



# for r in \
#   /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs/jsigconversiontools \
#   /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs/jsigconversiontools.oops \
#   /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs/jsigconversiontools.oops_2 \
#   /run/media/peddycoartte/MasterBackup/Nightly/2025-10-10/projects/jctcs/TEMP/jsigconversiontools
# do
#   echo "=== Testing repo: $r ==="
#   git -C "$r" log -1 --format='%ct' 2>/dev/null
#   git -C "$r" status --porcelain 2>/dev/null | wc -l
#   echo
# done


echo "LIST REPOS:"
ls -l /tmp/*repo_list* 2>/dev/null
cat /tmp/*repo_list* 2>/dev/null

echo
echo "SCAN FORENSIC OUTPUT:"
ls -l /tmp/*scan_file* 2>/dev/null
cat /tmp/*scan_file* 2>/dev/null



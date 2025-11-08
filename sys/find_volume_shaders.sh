#!/usr/bin/env bash

PROCS="$(($(nproc)-4))" 
find /run/media/peddycoartte/MasterBackup/Nightly/2025-10-??/projects \
  -type d -name Shaders -print0 2>/dev/null | \
  xargs -0 -P "$PROCS" -I {} bash -c '
    [ -d "{}/Volume" ] && \
    find "{}/Volume" -type f -name "volumetric_cloud_shader*.*" \
      -printf "%T@ %TY-%Tm-%Td %TH:%TM:%.2TS %p\n" 2>/dev/null
  ' | \
  sort -n | \
  cut -d' ' -f2-


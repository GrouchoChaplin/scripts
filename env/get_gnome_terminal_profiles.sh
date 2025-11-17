#!/usr/bin/env bash

# Get list as an array, one UUID per element
mapfile -t UUIDS < <(gsettings get org.gnome.Terminal.ProfilesList list \
    | tr -d "[]'," \
    | tr ' ' '\n')

for uuid in "${UUIDS[@]}"; do
    [ -z "$uuid" ] && continue
    NAME=$(dconf read /org/gnome/terminal/legacy/profiles:/:$uuid/visible-name)
    echo "$uuid → $NAME"
done

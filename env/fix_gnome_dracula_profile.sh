#!/usr/bin/env bash

UUID="3b69a251-1e97-4d55-8902-965d11ded59c"
BASE="/org/gnome/terminal/legacy/profiles:/:$UUID/"
SCHEMA="org.gnome.Terminal.Legacy.Profile:$BASE"

echo "🔧 Fixing Dracula profile name…"
gsettings set $SCHEMA visible-name "'Dracula'"

echo "🎨 Applying correct Rocky 8 color keys…"

gsettings set $SCHEMA background-color "'#282A36'"
gsettings set $SCHEMA foreground-color "'#F8F8F2'"
gsettings set $SCHEMA use-theme-colors false

# RHEL 8 cursor API
gsettings set $SCHEMA cursor-background-color "'#FF79C6'"
gsettings set $SCHEMA cursor-foreground-color "'#282A36'"

# Dracula palette (16-color)
gsettings set $SCHEMA palette \
"['#000000', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#BBBBBB', \
'#44475A', '#FF5555', '#50FA7B', '#F1FA8C', '#BD93F9', '#FF79C6', '#8BE9FD', '#FFFFFF']"

echo "✨ Fix complete!"
echo "➡️ Open a NEW GNOME Terminal window to confirm the Dracula theme."

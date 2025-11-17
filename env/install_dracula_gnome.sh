#!/usr/bin/env bash

SCHEMA="org.gnome.Terminal.Legacy.Profile"
BASE="/org/gnome/terminal/legacy/profiles:/"

echo "🎨 Installing GNOME Terminal Dracula theme (Rocky/RHEL 8 mode)…"

# 1) Get current profile list
LIST=$(gsettings get org.gnome.Terminal.ProfilesList list)

# 2) Generate new UUID
UUID=$(uuidgen)

echo "🆕 Creating profile UUID: $UUID"

# 3) Add new profile to list
gsettings set org.gnome.Terminal.ProfilesList list \
"$(echo $LIST | sed "s/]$/, '$UUID']/")"

# 4) Set profile name
gsettings set $SCHEMA:$BASE:$UUID/ visible-name "'Dracula'"

echo "🎨 Applying Dracula colors…"

# Dracula palette
gsettings set $SCHEMA:$BASE:$UUID/ background-color "'#282A36'"
gsettings set $SCHEMA:$BASE:$UUID/ foreground-color "'#F8F8F2'"
gsettings set $SCHEMA:$BASE:$UUID/ bold-color "'#FFFFFF'"
gsettings set $SCHEMA:$BASE:$UUID/ bold-color-same-as-fg true
gsettings set $SCHEMA:$BASE:$UUID/ use-theme-colors false

# Dracula palette array
gsettings set $SCHEMA:$BASE:$UUID/ palette \
"['#000000','#FF5555','#50FA7B','#F1FA8C','#BD93F9','#FF79C6','#8BE9FD','#BBBBBB','#44475A','#FF5555','#50FA7B','#F1FA8C','#BD93F9','#FF79C6','#8BE9FD','#FFFFFF']"

# Cursor + selection
gsettings set $SCHEMA:$BASE:$UUID/ cursor-color "'#FF79C6'"
gsettings set $SCHEMA:$BASE:$UUID/ cursor-background-color "'#282A36'"
gsettings set $SCHEMA:$BASE:$UUID/ highlight-background-color "'#44475A'"
gsettings set $SCHEMA:$BASE:$UUID/ highlight-foreground-color "'#F8F8F2'"

echo "🎉 Dracula profile created!"

echo "⚙️ Setting Dracula as the default profile…"
gsettings set org.gnome.Terminal.ProfilesList default "'$UUID'"

echo "✅ Done!"
echo "Open a NEW GNOME Terminal window to see Dracula theme enabled."

#!/usr/bin/env bash

# Automatically set the GNOME Terminal "Dracula" profile as default

echo "🔍 Searching for Dracula GNOME Terminal profile..."

# Get list of profile UUIDs
PROFILE_LIST=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d "[],'")

# Iterate through profiles to find one named "Dracula"
for UUID in $PROFILE_LIST; do
    PROFILE_NAME=$(gsettings get org.gnome.Terminal.ProfilesList :$UUID visible-name 2>/dev/null)

    # Remove quotes for comparison
    PROFILE_NAME=$(echo "$PROFILE_NAME" | tr -d "'")

    if [[ "$PROFILE_NAME" == "Dracula" ]]; then
        echo "🎉 Found Dracula profile: $UUID"
        DRACULA_UUID="$UUID"
        break
    fi
done

# If not found → exit
if [[ -z "$DRACULA_UUID" ]]; then
    echo "❌ Dracula profile not found! Did you run the installer?"
    echo "Try: bash terminal/gnome/dracula.sh"
    exit 1
fi

# Set default profile
echo "⚙️ Setting Dracula as the default GNOME Terminal profile..."
gsettings set org.gnome.Terminal.ProfilesList default "$DRACULA_UUID"

echo "✅ Done!"
echo "➡️ All new GNOME Terminal windows/tabs will now use the Dracula profile."

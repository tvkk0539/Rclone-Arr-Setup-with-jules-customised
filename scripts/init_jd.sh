#!/bin/bash

# Helper script to enable JDownloader 2 automation
# This avoids the "fresh install" crash by injecting the config AFTER initialization.

CONFIG_DIR="configs/jdownloader/cfg"
TARGET_FILE="$CONFIG_DIR/org.jdownloader.extensions.eventscripter.EventScripterExtension.scripts.json"
INIT_CHECK_FILE="$CONFIG_DIR/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"

echo "Checking JDownloader initialization..."

if [ ! -f "$INIT_CHECK_FILE" ]; then
    echo "Error: JDownloader has not initialized yet."
    echo "Please wait a few minutes for the container to start up fully, then try again."
    exit 1
fi

echo "JDownloader is initialized. Enabling automation..."

# Create the automation config
cat <<EOF > "$TARGET_FILE"
[
  {
    "eventTrigger": "ON_PACKAGE_FINISHED",
    "enabled": true,
    "name": "Rclone Upload",
    "script": "var script = \"/scripts/jd_manage.sh\";\nvar path = package.getDownloadFolder();\nvar name = package.getName();\ncallAsync(function() {}, script, name, path);",
    "eventTriggerSettings": {},
    "id": 1698745632145
  }
]
EOF

# Set permissions
CURRENT_USER=${SUDO_USER:-$USER}
if [ -z "$CURRENT_USER" ]; then
    # Fallback if running as root without sudo
    chown -R 1000:1000 "$CONFIG_DIR"
else
    chown -R "$CURRENT_USER:$CURRENT_USER" "$CONFIG_DIR"
fi

echo "Configuration injected. Restarting JDownloader..."
docker compose restart jdownloader

echo "Done! Automation enabled."

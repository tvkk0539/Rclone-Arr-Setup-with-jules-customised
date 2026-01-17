#!/bin/bash

# JDownloader 2 Configuration Helper Script

pre_configure_jdownloader() {
    echo -e "\n${BLUE}Pre-configuring JDownloader...${NC}"
    mkdir -p configs/jdownloader/cfg

    # 1. Create GUI Settings file (Prevents 'jq: error' during container init)
    if [ ! -f "configs/jdownloader/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.json" ]; then
        # We disable the tray icon to prevent the "Tray isn't supported" error on startup
        echo '{"trayiconenabled": false}' > configs/jdownloader/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.json
    fi

    # 2. Set Default Download Path to /downloads
    echo '{"defaultdownloadfolder" : "/downloads"}' > configs/jdownloader/cfg/org.jdownloader.settings.GeneralSettings.json

    # 3. Enable "Subfolder by Package" (Packagizer Rule)
    # This requires a specific Packagizer rule to be injected.
    # We force-create the rule list with the "SubFolderByPackageRule" enabled.
    # This guarantees that every package gets its own folder named after the package.
    cat > configs/jdownloader/cfg/org.jdownloader.controlling.packagizer.PackagizerSettings.rulelist.json <<EOF
[
  {
    "id": "SubFolderByPackageRule",
    "enabled": true,
    "name": "Create Subfolder by Packagename",
    "matchAlwaysFilter": {
      "enabled": true
    },
    "downloadDestination": "<jd:packagename>",
    "iconKey": "folder",
    "staticRule": true
  }
]
EOF

    # 4. Disable "Various Package" Grouping (Linkgrabber Settings)
    # We set variouspackagelimit to 0 to prevent JDownloader from grouping single files into a "Various" package.
    # This ensures that even single files get their own package folder (named after the file).
    echo '{"variouspackagelimit" : 0}' > configs/jdownloader/cfg/org.jdownloader.settings.LinkgrabberSettings.json

    # 5. Inject Pre-Installed Extensions (Snapshot Deployment)
    # The user provided a zip of pre-installed extensions to bypass the manual "Install Now" step.
    EXTENSIONS_URL="https://github.com/tvkk0539/Rclone-Arr-Setup-with-jules-customised/releases/download/v1/jdownloader_extensions.zip"
    EXTENSIONS_DIR="configs/jdownloader/extensions"

    echo -e "${BLUE}Downloading JDownloader Extensions...${NC}"
    mkdir -p "$EXTENSIONS_DIR"

    if wget -qO /tmp/jd_extensions.zip "$EXTENSIONS_URL"; then
        echo "Extracting extensions..."
        # We use -j to flatten the directory structure and extract only .jar files
        unzip -o -q -j /tmp/jd_extensions.zip "*.jar" -d "$EXTENSIONS_DIR"
        rm /tmp/jd_extensions.zip
        echo -e "${GREEN}Extensions pre-installed successfully.${NC}"

        # Pre-Enable Event Scripter
        # Since we installed the JAR, we can safe-enable it immediately.
        # This prevents the race condition where JDownloader starts, sees the new JAR, and defaults it to "Disabled".
        JD_EXT_FILE="configs/jdownloader/cfg/org.jdownloader.extensions.eventscripter.EventScripterExtension.json"
        if [ ! -f "$JD_EXT_FILE" ]; then
            echo '{"freshinstall":false,"enabled":true}' > "$JD_EXT_FILE"
            echo "Auto-enabled Event Scripter Extension."
        fi
    else
        echo -e "${YELLOW}Failed to download extensions. You may need to install them manually.${NC}"
    fi

    # Fix specific permissions for JDownloader (Container runs as user 1000)
    chown -R 1000:1000 configs/jdownloader
}

post_configure_jdownloader() {
    # 8. Post-Deployment Automation (JDownloader)
    # We check if JDownloader is running and inject the automation script if needed.
    if docker compose ps --services --filter "status=running" | grep -q "jdownloader"; then
        echo -e "\n${BLUE}[Auto-Config] Checking JDownloader Automation...${NC}"
        JD_CONFIG_DIR="configs/jdownloader/cfg"
        JD_CONFIG_FILE="$JD_CONFIG_DIR/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
        JD_SCRIPT_FILE="$JD_CONFIG_DIR/org.jdownloader.extensions.eventscripter.EventScripterExtension.scripts.json"

        # Wait for JDownloader to initialize its config files (max 180 seconds)
        echo -n "Waiting for JDownloader to initialize..."
        for i in $(seq 1 36); do
            if [ -f "$JD_CONFIG_FILE" ]; then
                echo -e " ${GREEN}Done.${NC}"

                # Check if automation script needs injection
                if [ ! -f "$JD_SCRIPT_FILE" ]; then
                    echo "Injecting Rclone Upload script..."
                    # We stop JD to safely inject the script (though technically less critical for scripts, good practice)
                    docker compose stop jdownloader

                    cat <<EOF > "$JD_SCRIPT_FILE"
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

                    # Fix permissions (Must be user 1000 for JDownloader)
                    chown -R 1000:1000 "$JD_CONFIG_DIR"

                    # Restart JDownloader to load the new config
                    # We used 'stop' earlier, so we use 'start' or 'up -d' here
                    echo "Starting JDownloader to apply changes..."
                    docker compose start jdownloader
                    echo -e "${GREEN}JDownloader Automation Enabled!${NC}"
                else
                    echo -e "${GREEN}Automation script already active.${NC}"
                fi
                break
            fi

            echo -n "."
            sleep 5
        done

        if [ ! -f "$JD_CONFIG_FILE" ]; then
            echo -e "\n${YELLOW}JDownloader is taking too long to start.${NC}"
            echo "Automation skipped."
        fi
    fi
}

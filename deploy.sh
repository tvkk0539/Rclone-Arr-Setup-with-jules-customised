#!/bin/bash

# Rclone-Arr-Setup Deployment Script
# Supports: Ubuntu, Debian
# Updated: Fixed JDownloader headless mode connectivity issues

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}       Rclone-Arr-Setup Auto-Deployer           ${NC}"
echo -e "${BLUE}=================================================${NC}"

# Function to check JDownloader MyJDownloader connection
check_jdownloader_connection() {
    echo -e "\n${BLUE}Checking JDownloader MyJDownloader connection...${NC}"
    
    # Wait for JDownloader to start
    echo -n "Waiting for JDownloader to initialize (60 seconds max)..."
    CONNECTED=false
    for i in $(seq 1 60); do
        if docker logs jdownloader 2>&1 | grep -q "MyJDownloader: Connected" || \
           docker logs jdownloader 2>&1 | grep -q "MyJDownloader.*ready"; then
            echo -e " ${GREEN}Connected to MyJDownloader!${NC}"
            CONNECTED=true
            
            # Extract connection info
            CONNECTION_INFO=$(docker logs jdownloader 2>&1 | tail -50 | grep -A2 -B2 "MyJDownloader")
            echo -e "\n${GREEN}Connection Status:${NC}"
            echo "$CONNECTION_INFO" | grep -E "(Connected|Device|Session|ready)" | head -10
            
            # Get device ID
            DEVICE_ID=$(docker logs jdownloader 2>&1 | grep "Device ID:" | tail -1 | awk '{print $NF}')
            if [ ! -z "$DEVICE_ID" ]; then
                echo -e "Device ID: ${BLUE}$DEVICE_ID${NC}"
            fi
            return 0
        fi
        sleep 1
        echo -n "."
    done
    
    if [ "$CONNECTED" = false ]; then
        echo -e "\n${YELLOW}JDownloader started but still connecting to MyJDownloader...${NC}"
        echo -e "${BLUE}This can take 2-3 minutes for initial connection.${NC}"
        echo -e "Check status with: docker logs jdownloader | grep -i myjdownloader"
        return 1
    fi
}

# 1. Check Root/Sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Please run this script with sudo or as root.${NC}"
  echo "Usage: sudo ./deploy.sh"
  exit 1
fi

# 2. Update System
echo -e "\n${GREEN}[1/7] Updating System Repositories...${NC}"
apt-get update -qq

# 3. Check & Install Docker
echo -e "\n${GREEN}[2/7] Checking Docker Installation...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    echo -e "${GREEN}Docker installed successfully.${NC}"
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

# Install Docker Compose Plugin if missing
if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Docker Compose plugin not found. Installing...${NC}"
    apt-get install -y docker-compose-plugin
else
    echo -e "${GREEN}Docker Compose is ready.${NC}"
fi

# 4. Configure Environment Variables
echo -e "\n${GREEN}[3/7] Configuring Project Environment...${NC}"

# Check if we are in the project folder
if [ ! -f "docker-compose.yml" ]; then
    echo -e "${YELLOW}docker-compose.yml not found. Cloning repository...${NC}"

    # Install git if missing
    if ! command -v git &> /dev/null; then
        apt-get install -y git
    fi

    git clone https://github.com/vinayak-7-0-3/Rclone-Arr-Setup.git
    cd Rclone-Arr-Setup || exit 1
    echo -e "${GREEN}Cloned and entered repository.${NC}"
fi

# Get the directory where the script is located (should be repo root)
REPO_ROOT=$(pwd)
CURRENT_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo ~$CURRENT_USER)

echo -e "Project Root detected as: ${BLUE}$REPO_ROOT${NC}"

# Ask for Rclone Remote Name
echo -e "\n${YELLOW}Step 3a: Rclone Configuration${NC}"
read -p "Enter your Rclone Remote Name (e.g., 'drive'): " INPUT_REMOTE
RCLONE_REMOTE=${INPUT_REMOTE:-drive}

# Ask for Rclone WebUI Credentials
echo -e "\n${YELLOW}Step 3b: Security${NC}"
read -p "Create a username for Rclone WebUI [admin]: " INPUT_USER
RCLONE_USER=${INPUT_USER:-admin}

read -p "Create a password for Rclone WebUI [password]: " INPUT_PASS
RCLONE_PASS=${INPUT_PASS:-password}

# Generate/Ask for RPC Secret
RANDOM_SECRET=$(openssl rand -hex 12)
read -p "Enter RPC Secret for Aria2 (Press Enter to generate random): " INPUT_RPC
RPC_SECRET=${INPUT_RPC:-$RANDOM_SECRET}

# Generate/Ask for Encryption Key for Homarr
RANDOM_KEY=$(openssl rand -hex 32)
read -p "Enter Homarr Encryption Key (Press Enter to generate random): " INPUT_KEY
HOMARR_KEY=${INPUT_KEY:-$RANDOM_KEY}

# Ask for JDownloader 2 Mode
echo -e "\n${YELLOW}Step 3c: JDownloader 2 Configuration${NC}"
echo "1) Standard Mode (VNC Web Interface + Optional MyJDownloader)"
echo "2) Headless Mode (No Web/VNC, Saves RAM, REQUIRES MyJDownloader Account)"
read -p "Select Mode [1/2] (Default: 1): " JD_MODE

JD_HEADLESS=0
JD_EMAIL=""
JD_PASSWORD=""
JD_DEVICE="JDownloader-Docker-$(openssl rand -hex 4)"  # Add random suffix to avoid conflicts

if [ "$JD_MODE" == "2" ]; then
    echo -e "${BLUE}Headless Mode Selected. You MUST provide MyJDownloader credentials.${NC}"
    JD_HEADLESS=1

    while [ -z "$JD_EMAIL" ]; do
        read -p "Enter MyJDownloader Email: " JD_EMAIL
    done

    while [ -z "$JD_PASSWORD" ]; do
        read -s -p "Enter MyJDownloader Password: " JD_PASSWORD
        echo ""
    done

    read -p "Enter Device Name [JDownloader-Docker-$RANDOM_SUFFIX]: " INPUT_DEVICE
    if [ ! -z "$INPUT_DEVICE" ]; then
        JD_DEVICE="$INPUT_DEVICE"
    fi
    echo -e "${GREEN}Device name set to: ${JD_DEVICE}${NC}"
    
    # Warn about device name conflicts
    echo -e "${YELLOW}Note: If '$JD_DEVICE' is already in use on MyJDownloader, connection will fail.${NC}"
    echo -e "${YELLOW}You can remove old devices at https://my.jdownloader.org${NC}"
else
    echo -e "${BLUE}Standard Mode Selected.${NC}"
    # Still ask for MyJDownloader optionally
    echo -e "\n${YELLOW}Optional: MyJDownloader Setup (for remote access)${NC}"
    read -p "Enter MyJDownloader Email (or press Enter to skip): " JD_EMAIL
    if [ ! -z "$JD_EMAIL" ]; then
        read -s -p "Enter MyJDownloader Password: " JD_PASSWORD
        echo ""
        read -p "Enter Device Name [JDownloader-Docker]: " INPUT_DEVICE
        JD_DEVICE=${INPUT_DEVICE:-JDownloader-Docker}
    fi
fi

# Set Downloads Folder
DOWNLOADS_FOLDER="$USER_HOME/downloads"
echo -e "\nSetting downloads folder to: ${BLUE}$DOWNLOADS_FOLDER${NC}"
mkdir -p "$DOWNLOADS_FOLDER"
chown -R "$CURRENT_USER:$CURRENT_USER" "$DOWNLOADS_FOLDER"

# Create .env file
echo -e "\n${GREEN}Generating .env file...${NC}"
cat > .env <<EOL
# Generated by deploy.sh

# Storage Paths
MEDIA_SERVER_ROOT=$REPO_ROOT
DOWNLOADS_FOLDER=$DOWNLOADS_FOLDER

# Rclone Configuration
RCLONE_REMOTE=$RCLONE_REMOTE
RCLONE_USER=$RCLONE_USER
RCLONE_PASS=$RCLONE_PASS

# Network
DOCKER_NETWORK=nginx_network

# Security
SECRET_ENCRYPTION_KEY=$HOMARR_KEY
RPC_SECRET=$RPC_SECRET

# JDownloader Configuration
JDOWNLOADER_HEADLESS=$JD_HEADLESS
MYJDOWNLOADER_EMAIL=$JD_EMAIL
MYJDOWNLOADER_PASSWORD=$JD_PASSWORD
MYJDOWNLOADER_DEVICE_NAME=$JD_DEVICE
EOL

# Fix permissions for .env so regular user can read it
chown "$CURRENT_USER:$CURRENT_USER" .env

echo -e "${GREEN}.env file created successfully!${NC}"

# Pre-configure JDownloader for headless mode BEFORE container starts
if [ "$JD_HEADLESS" == "1" ]; then
    echo -e "\n${BLUE}Pre-configuring JDownloader for Headless Mode...${NC}"
    mkdir -p configs/jdownloader/cfg
    
    # Create MyJDownloader authentication config
    cat > configs/jdownloader/cfg/org.jdownloader.api.myjdownloader.MyJDownloaderSettings.json <<EOF
{
  "autoconnectenabledv2" : true,
  "email" : "${JD_EMAIL}",
  "password" : "${JD_PASSWORD}",
  "devicename" : "${JD_DEVICE}",
  "autoconnectenabled" : true,
  "directconnectmode" : "LAN",
  "connectipandport" : "",
  "lastlocalport" : 3129,
  "debugenabled" : false,
  "maxdownloadspeed" : 0,
  "maxuploadspeed" : 0
}
EOF
    
    # Disable premium server (optional)
    cat > configs/jdownloader/cfg/org.jdownloader.extensions.jdpremserv.JDPremServSettings.json <<EOF
{
  "premiumhosterlist" : "",
  "enabled" : false,
  "autoconnect" : true
}
EOF
    
    # Force headless mode in settings
    cat > configs/jdownloader/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.json <<EOF
{
  "trayiconenabled": false,
  "forcewindowstate": "normal",
  "mainframevisible": false,
  "silentmode": true
}
EOF
    
    echo -e "${GREEN}MyJDownloader configuration created.${NC}"
fi

# 5. Directory Structure
echo -e "\n${GREEN}[4/7] Creating Directory Structure...${NC}"
mkdir -p configs/rclone
mkdir -p configs/aria2
mkdir -p configs/radarr
mkdir -p configs/prowlarr
mkdir -p configs/qbittorrent
mkdir -p configs/aria2
mkdir -p configs/homarr
mkdir -p configs/jellyfin
mkdir -p configs/jdownloader
mkdir -p configs/profilarr
mkdir -p mount
mkdir -p logs
mkdir -p scripts

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

# Fix Log Permissions (Crucial for Docker containers running as non-root)
# qBittorrent (user 1000) needs to write to this folder
chmod -R 777 logs

 # Ensure Aria2 config exists with the correct hook
 if [ ! -f configs/aria2/aria2.conf ]; then
     echo "Creating default Aria2 config..."
     cat <<EOF > configs/aria2/aria2.conf
dir=/downloads
rpc-secret=${RPC_SECRET}
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=6800
rpc-allow-origin-all=true
on-download-complete=/scripts/aria_manage.sh
input-file=/config/aria2.session
save-session=/config/aria2.session
save-session-interval=60
force-save=true
log=/logs/aria2.log
log-level=notice
EOF
 else
     # Update existing config if hook is missing
     if ! grep -q "on-download-complete" configs/aria2/aria2.conf; then
         echo "on-download-complete=/scripts/aria_manage.sh" >> configs/aria2/aria2.conf
         echo "Updated Aria2 config with automation hook."
     fi
 fi

# Fix ownership of all configs
chown -R "$CURRENT_USER:$CURRENT_USER" configs logs scripts

# Pre-Create JDownloader Configs to prevent Startup Crash
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

# 4. Disable "Various Package" Grouping
echo '{"variouspackagelimit" : 0}' > configs/jdownloader/cfg/org.jdownloader.settings.LinkgrabberSettings.json

# 5. Inject Pre-Installed Extensions
EXTENSIONS_URL="https://github.com/tvkk0539/Rclone-Arr-Setup-with-jules-customised/releases/download/v1/jdownloader_extensions.zip"
EXTENSIONS_DIR="configs/jdownloader/extensions"

echo -e "${BLUE}Downloading JDownloader Extensions...${NC}"
mkdir -p "$EXTENSIONS_DIR"

if wget -qO /tmp/jd_extensions.zip "$EXTENSIONS_URL"; then
    echo "Extracting extensions..."
    unzip -o -q -j /tmp/jd_extensions.zip "*.jar" -d "$EXTENSIONS_DIR"
    rm /tmp/jd_extensions.zip
    echo -e "${GREEN}Extensions pre-installed successfully.${NC}"

    # Pre-Enable Event Scripter
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

# 6. Rclone Config Setup
echo -e "\n${GREEN}[5/7] Setting up Rclone Config...${NC}"
CONFIG_FILE="configs/rclone/rclone.conf"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}Existing rclone.conf found. Skipping setup.${NC}"
else
    echo -e "${YELLOW}No rclone.conf found.${NC}"
    echo "1) I have an existing rclone.conf content (Paste it)"
    echo "2) I want to run the Config Wizard (Create New)"
    read -p "Select option [1/2]: " OPTION

    if [ "$OPTION" == "1" ]; then
        echo -e "${YELLOW}Paste your config content below. Press Ctrl+D when finished:${NC}"
        cat > "$CONFIG_FILE"
        echo -e "${GREEN}Config saved to: $REPO_ROOT/$CONFIG_FILE${NC}"
    else
        echo -e "${BLUE}Starting Rclone Wizard...${NC}"
        echo -e "${YELLOW}IMPORTANT: If asked for auto-config, say NO (n) because this is a headless server.${NC}"
        docker run --rm -it -v "$REPO_ROOT/configs/rclone:/config/rclone" rclone/rclone config --config /config/rclone/rclone.conf
        echo -e "${GREEN}Config saved to: $REPO_ROOT/$CONFIG_FILE${NC}"
    fi
fi

# Fix config permissions
chown "$CURRENT_USER:$CURRENT_USER" "$CONFIG_FILE" 2>/dev/null

# Smart Fix: Check if Remote Name matches Config
ACTUAL_REMOTE_NAME=$(grep -m 1 "^\[" "$CONFIG_FILE" | tr -d '[]')

if [ ! -z "$ACTUAL_REMOTE_NAME" ] && [ "$ACTUAL_REMOTE_NAME" != "$RCLONE_REMOTE" ]; then
    echo -e "\n${YELLOW}WARNING: Mismatch detected!${NC}"
    echo "You entered remote name: '$RCLONE_REMOTE'"
    echo "But your config file has: '$ACTUAL_REMOTE_NAME'"
    echo -e "${GREEN}Auto-correcting .env file to use '$ACTUAL_REMOTE_NAME'...${NC}"

    sed -i "s/RCLONE_REMOTE=$RCLONE_REMOTE/RCLONE_REMOTE=$ACTUAL_REMOTE_NAME/" .env
    RCLONE_REMOTE=$ACTUAL_REMOTE_NAME
fi

# 7. Start Services
echo -e "\n${GREEN}[6/7] Starting Services...${NC}"

# Create network if not exists
if ! docker network inspect nginx_network &>/dev/null; then
    docker network create nginx_network
    echo -e "Created docker network: nginx_network"
fi

# Service Selection Logic
CORE_SERVICES="rclone"
OPTIONAL_SERVICES=("homarr" "radarr" "prowlarr" "qbittorrent" "aria2" "ariang" "jellyseerr" "profilarr" "jellyfin" "jdownloader")

echo -e "\n${BLUE}Installation Mode:${NC}"
echo "1) Full Installation (Install Everything)"
echo "2) Custom Installation (Select apps to SKIP)"
echo "3) Selective Installation (Select apps to INSTALL)"
read -p "Select option [1]: " INSTALL_MODE

if [ "$INSTALL_MODE" == "2" ]; then
    echo -e "\n${YELLOW}Custom Installation (SKIP Mode).${NC}"
    echo "The following core services will ALWAYS be installed: $CORE_SERVICES"
    echo -e "\nSelect the apps you do NOT want to install:"

    for i in "${!OPTIONAL_SERVICES[@]}"; do
        echo "$((i+1)). ${OPTIONAL_SERVICES[$i]}"
    done

    echo -e "\nEnter the numbers of the apps to SKIP (separated by space)."
    echo "Example: To skip Radarr and Homarr, type: 1 2"
    read -p "Skip apps: " SKIP_INDICES

    SERVICES_TO_RUN="$CORE_SERVICES"

    for i in "${!OPTIONAL_SERVICES[@]}"; do
        SERVICE_NUM=$((i+1))
        SERVICE_NAME="${OPTIONAL_SERVICES[$i]}"

        if [[ " $SKIP_INDICES " =~ " $SERVICE_NUM " ]]; then
            echo -e "${RED}Skipping $SERVICE_NAME${NC}"
        else
            SERVICES_TO_RUN="$SERVICES_TO_RUN $SERVICE_NAME"
            echo -e "${GREEN}Adding $SERVICE_NAME${NC}"
        fi
    done

    # Auto-include mount if jellyfin is selected
    if [[ "$SERVICES_TO_RUN" == *"jellyfin"* ]]; then
         SERVICES_TO_RUN="$SERVICES_TO_RUN mount"
         echo -e "${GREEN}Auto-enabling Rclone Mount (Required for Jellyfin)${NC}"
    fi

    echo -e "\nStarting specific services: $SERVICES_TO_RUN"
    docker compose up -d $SERVICES_TO_RUN

elif [ "$INSTALL_MODE" == "3" ]; then
    echo -e "\n${YELLOW}Selective Installation (INCLUDE Mode).${NC}"
    echo "The following core services will ALWAYS be installed: $CORE_SERVICES"
    echo -e "\nSelect the apps you WANT to install:"

    for i in "${!OPTIONAL_SERVICES[@]}"; do
        echo "$((i+1)). ${OPTIONAL_SERVICES[$i]}"
    done

    echo -e "\nEnter the numbers of the apps to INSTALL (separated by space)."
    echo "Example: To install only Homarr and qBittorrent, type: 1 4"
    read -p "Install apps: " INCLUDE_INDICES

    SERVICES_TO_RUN="$CORE_SERVICES"

    for i in "${!OPTIONAL_SERVICES[@]}"; do
        SERVICE_NUM=$((i+1))
        SERVICE_NAME="${OPTIONAL_SERVICES[$i]}"

        if [[ " $INCLUDE_INDICES " =~ " $SERVICE_NUM " ]]; then
            SERVICES_TO_RUN="$SERVICES_TO_RUN $SERVICE_NAME"
            echo -e "${GREEN}Adding $SERVICE_NAME${NC}"
        else
            echo -e "${RED}Skipping $SERVICE_NAME${NC}"
        fi
    done

    # Auto-include mount if jellyfin is selected
    if [[ "$SERVICES_TO_RUN" == *"jellyfin"* ]]; then
         SERVICES_TO_RUN="$SERVICES_TO_RUN mount"
         echo -e "${GREEN}Auto-enabling Rclone Mount (Required for Jellyfin)${NC}"
    fi

    echo -e "\nStarting specific services: $SERVICES_TO_RUN"
    docker compose up -d $SERVICES_TO_RUN

else
    echo -e "\n${GREEN}Starting ALL services...${NC}"
    docker compose up -d
fi

# 8. Post-Deployment Automation
echo -e "\n${GREEN}[7/7] Post-Deployment Configuration...${NC}"

# JDownloader specific configuration
if [[ "$SERVICES_TO_RUN" == *"jdownloader"* ]] || [ "$INSTALL_MODE" != "2" ] && [ "$INSTALL_MODE" != "3" ]; then
    echo -e "\n${BLUE}[Auto-Config] Configuring JDownloader...${NC}"
    
    # Wait a moment for container to start
    sleep 10
    
    # For headless mode, check MyJDownloader connection
    if [ "$JD_HEADLESS" == "1" ]; then
        echo -e "${BLUE}Waiting for JDownloader to connect to MyJDownloader...${NC}"
        echo -e "This can take 1-3 minutes for initial connection."
        echo -e "Checking connection status..."
        
        check_jdownloader_connection
        
        # Check for specific errors
        echo -e "\n${BLUE}Checking for common issues...${NC}"
        JD_LOGS=$(docker logs jdownloader 2>&1 | tail -100)
        
        if echo "$JD_LOGS" | grep -q "Device name already exists"; then
            echo -e "${RED}ERROR: Device name '$JD_DEVICE' is already in use!${NC}"
            echo -e "${YELLOW}Solution:${NC}"
            echo "1. Go to https://my.jdownloader.org"
            echo "2. Log in with email: $JD_EMAIL"
            echo "3. Remove old device named '$JD_DEVICE'"
            echo "4. Restart JDownloader: docker restart jdownloader"
        fi
        
        if echo "$JD_LOGS" | grep -q "Invalid credentials"; then
            echo -e "${RED}ERROR: Invalid MyJDownloader credentials${NC}"
            echo -e "${YELLOW}Solution: Update .env file with correct credentials and restart:${NC}"
            echo "1. Edit .env file"
            echo "2. Fix MYJDOWNLOADER_EMAIL and MYJDOWNLOADER_PASSWORD"
            echo "3. Run: docker compose restart jdownloader"
        fi
        
        if echo "$JD_LOGS" | grep -q "Connection refused" || echo "$JD_LOGS" | grep -q "Failed to connect"; then
            echo -e "${YELLOW}Network connection issue detected.${NC}"
            echo -e "JDownloader might be having trouble reaching MyJDownloader servers."
            echo -e "This often resolves itself after a few minutes."
        fi
        
        echo -e "\n${GREEN}Headless JDownloader Setup Complete!${NC}"
        echo -e "Access JDownloader via: ${BLUE}https://my.jdownloader.org${NC}"
        echo -e "Login with email: ${BLUE}$JD_EMAIL${NC}"
        echo -e "Device name: ${BLUE}$JD_DEVICE${NC}"
        
    else
        # For standard mode, wait for VNC
        echo -n "Waiting for JDownloader VNC interface (port 5800)..."
        for i in $(seq 1 30); do
            if docker compose ps jdownloader 2>/dev/null | grep -q "Up" || \
               nc -z localhost 5800 2>/dev/null; then
                echo -e " ${GREEN}Ready!${NC}"
                break
            fi
            sleep 2
            echo -n "."
        done
        
        # If MyJDownloader credentials were provided, check connection
        if [ ! -z "$JD_EMAIL" ] && [ ! -z "$JD_PASSWORD" ]; then
            echo -e "\n${BLUE}Checking MyJDownloader connection for standard mode...${NC}"
            sleep 20  # Give it more time to start
            check_jdownloader_connection
        fi
    fi
    
    # Inject automation script if JDownloader is running
    JD_CONFIG_DIR="configs/jdownloader/cfg"
    JD_CONFIG_FILE="$JD_CONFIG_DIR/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
    JD_SCRIPT_FILE="$JD_CONFIG_DIR/org.jdownloader.extensions.eventscripter.EventScripterExtension.scripts.json"
    
    # Wait for JDownloader config
    echo -n "Waiting for JDownloader configuration files..."
    for i in $(seq 1 36); do
        if [ -f "$JD_CONFIG_FILE" ]; then
            echo -e " ${GREEN}Done.${NC}"
            
            # Inject automation script
            if [ ! -f "$JD_SCRIPT_FILE" ]; then
                echo "Injecting Rclone Upload automation script..."
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
                
                chown -R 1000:1000 "$JD_CONFIG_DIR"
                echo "Starting JDownloader to apply automation..."
                docker compose start jdownloader
                echo -e "${GREEN}JDownloader Automation Enabled!${NC}"
            else
                echo -e "${GREEN}Automation script already active.${NC}"
            fi
            break
        fi
        sleep 5
        echo -n "."
    done
fi

echo -e "\n${GREEN}Deployment Complete!${NC}"

# Get External IP Address
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')
IP_ADDRESS=${PUBLIC_IP:-localhost}

echo -e "\n${BLUE}=================================================${NC}"
echo -e "${BLUE}       Access Your Services                     ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "Homarr (Dashboard) : http://$IP_ADDRESS:7575"
echo -e "Jellyfin (Stream)  : http://$IP_ADDRESS:8096"
echo -e "Jellyseerr (Request): http://$IP_ADDRESS:5055"
echo -e "Radarr             : http://$IP_ADDRESS:7878"
echo -e "qBittorrent        : http://$IP_ADDRESS:8080"

# JDownloader access based on mode
if [ "$JD_HEADLESS" == "1" ]; then
    echo -e "JDownloader 2      : ${GREEN}Headless Mode${NC} - Use https://my.jdownloader.org"
    echo -e "                   Email: ${JD_EMAIL}"
    echo -e "                   Device: ${JD_DEVICE}"
    echo -e "                   Note: Initial connection may take 2-3 minutes"
else
    echo -e "JDownloader 2      : http://$IP_ADDRESS:5800"
    if [ ! -z "$JD_EMAIL" ]; then
        echo -e "                   MyJDownloader: https://my.jdownloader.org"
    fi
    echo -e "                   VNC Password: (leave empty for no password)"
fi

echo -e "AriaNg (Aria2 UI)  : http://$IP_ADDRESS:6880"
echo -e "Rclone WebUI       : http://$IP_ADDRESS:5572"
echo -e "${BLUE}=================================================${NC}"
echo -e "Login Credentials:"
echo -e "qBittorrent : admin / adminadmin"
echo -e "Rclone WebUI: $RCLONE_USER / $RCLONE_PASS"
echo -e "-------------------------------------------------"
echo -e "Generated Keys (Saved in .env):"
echo -e "Homarr Encryption Key: $HOMARR_KEY"
echo -e "Aria2 RPC Secret     : $RPC_SECRET"
echo -e "${BLUE}=================================================${NC}"

# Troubleshooting information
echo -e "\n${YELLOW}Troubleshooting Commands:${NC}"
echo -e "Check JDownloader logs: ${BLUE}docker logs jdownloader${NC}"
echo -e "Check JDownloader status: ${BLUE}docker compose ps jdownloader${NC}"
echo -e "Restart JDownloader: ${BLUE}docker compose restart jdownloader${NC}"
echo -e "Check MyJDownloader connection: ${BLUE}docker logs jdownloader | grep -i myjdownloader${NC}"

if [ "$JD_HEADLESS" == "1" ]; then
    echo -e "\n${YELLOW}If MyJDownloader shows 'no connected jdownloader found':${NC}"
    echo "1. Wait 2-3 minutes for initial connection"
    echo "2. Check logs: docker logs jdownloader | tail -50"
    echo "3. Verify device name '$JD_DEVICE' is not already in use"
    echo "4. Try: docker compose restart jdownloader"
    echo "5. Manual check: curl http://$IP_ADDRESS:5800 (should fail in headless mode)"
fi

echo -e "\n${GREEN}Setup complete! Services are starting up...${NC}"
echo -e "${BLUE}Note: Some services may take a few minutes to fully initialize.${NC}"

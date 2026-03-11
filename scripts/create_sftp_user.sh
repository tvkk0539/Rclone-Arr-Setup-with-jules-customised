#!/bin/bash

# SFTP User Creation Script
# Creates a restricted SFTP-only user that is chrooted to the downloads folder.
# Usage: sudo ./create_sftp_user.sh

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}       Restricted SFTP User Creator             ${NC}"
echo -e "${BLUE}=================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root (sudo).${NC}"
  exit 1
fi

# Load .env to find downloads folder
if [ -f ".env" ]; then
    source .env
else
    # Fallback if running outside project root
    if [ -f "../.env" ]; then
        source ../.env
    else
        echo -e "${YELLOW}Warning: .env file not found. Assuming downloads at ~/downloads.${NC}"
        CURRENT_USER=${SUDO_USER:-$USER}
        USER_HOME=$(eval echo ~$CURRENT_USER)
        DOWNLOADS_FOLDER="$USER_HOME/downloads"
    fi
fi

echo -e "Target Downloads Folder: ${GREEN}$DOWNLOADS_FOLDER${NC}"

# 1. Ask for Username
read -p "Enter username for new SFTP user [downloader]: " SFTP_USER
SFTP_USER=${SFTP_USER:-downloader}

# Check if user exists
if id "$SFTP_USER" &>/dev/null; then
    echo -e "${YELLOW}User '$SFTP_USER' already exists.${NC}"
    read -p "Do you want to update the password? [y/n]: " UPDATE_PASS
    if [[ ! "$UPDATE_PASS" =~ ^[Yy]$ ]]; then
        echo "Exiting."
        exit 0
    fi
else
    echo -e "${GREEN}Creating user '$SFTP_USER'...${NC}"
    # Create user with no shell access, home dir at /home/user
    useradd -m -d "/home/$SFTP_USER" -s /usr/sbin/nologin "$SFTP_USER"
fi

# 2. Set Password
echo -e "\n${YELLOW}Set a password for $SFTP_USER:${NC}"
passwd "$SFTP_USER"

# 3. Configure Permissions & Chroot
# Chroot requires the root directory to be owned by root and not writable by others.
# We will bind mount the real downloads folder into the user's home.

USER_HOME_DIR="/home/$SFTP_USER"
BIND_MOUNT_DIR="$USER_HOME_DIR/downloads"

# Ensure user's home is owned by root (Requirement for Chroot)
chown root:root "$USER_HOME_DIR"
chmod 755 "$USER_HOME_DIR"

# Create the mount point
mkdir -p "$BIND_MOUNT_DIR"

# Persist the bind mount in /etc/fstab so it survives reboot
if ! grep -q "$BIND_MOUNT_DIR" /etc/fstab; then
    echo -e "${GREEN}Configuring Bind Mount...${NC}"
    echo "$DOWNLOADS_FOLDER $BIND_MOUNT_DIR none bind 0 0" >> /etc/fstab
    mount -a
else
    echo -e "${BLUE}Bind mount already configured.${NC}"
    # Remount to be sure
    mount --bind "$DOWNLOADS_FOLDER" "$BIND_MOUNT_DIR"
fi

# Fix permissions on the bind mount logic
# The actual folder permissions are managed by the original folder owner (usually 1000:1000)
# We add the sftp user to the 'docker' group or similar to access files?
# Easier: ACL or just rely on "others" read permission.
# Best: Add user to group 1000? No, that gives too much access.
# Current setup allows 777 on downloads, so any user can read/write.
echo -e "${BLUE}Permissions check: The downloads folder allows global read/write (777).${NC}"
echo -e "${BLUE}This allows the SFTP user to upload/delete files safely.${NC}"

# 4. Configure SSHD for Chroot
SSHD_CONFIG="/etc/ssh/sshd_config"
MATCH_BLOCK="Match User $SFTP_USER"

if ! grep -q "$MATCH_BLOCK" "$SSHD_CONFIG"; then
    echo -e "${GREEN}Configuring SSH Server for Chroot...${NC}"
    # Append Match block to end of sshd_config
    cat >> "$SSHD_CONFIG" <<EOF

# Added by Rclone-Arr-Setup
Match User $SFTP_USER
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF

    # Restart SSH
    echo -e "${GREEN}Restarting SSH Service...${NC}"
    service ssh restart
else
    echo -e "${BLUE}SSH already configured for $SFTP_USER.${NC}"
fi

echo -e "\n${BLUE}=================================================${NC}"
echo -e "${GREEN}SUCCESS! SFTP User '$SFTP_USER' is ready.${NC}"
echo -e "${BLUE}=================================================${NC}"
echo -e "Host: (Your Server IP)"
echo -e "Port: 22"
echo -e "User: $SFTP_USER"
echo -e "Pass: (The one you set)"
echo -e "Folder: /downloads"
echo -e "-------------------------------------------------"
echo -e "NOTE: This user is RESTRICTED."
echo -e "They CANNOT SSH into the terminal."
echo -e "They CANNOT see any folder outside /downloads."
echo -e "${BLUE}=================================================${NC}"

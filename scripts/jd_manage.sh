#!/bin/sh

# JDownloader 2 Post-Processing Script
# Compatible with Alpine/Busybox sh (POSIX)

# 1. Setup Environment
# ------------------
case "$RCLONE_REMOTE" in
    *:*) ;;                 # Already has colon
    *) RCLONE_REMOTE="${RCLONE_REMOTE}:" ;; # Append colon
esac

RCLONE_DEST="${RCLONE_REMOTE}/UnSorted/JDownloader"
RCLONE_HTTP_URL="http://rclone:5572"

# 2. Parse Arguments
# ------------------
# $1 - Package Name
# $2 - Download Directory (Absolute Path)

PACKAGE_NAME="$1"
DOWNLOAD_PATH="$2"
LOG_FILE="/logs/jd_postprocess.log"

# 3. Logging Helper
# -----------------
log_message() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$LOG_FILE"
}

log_message "----------------------------------------"
log_message "Processing Package: $PACKAGE_NAME"
log_message "Download path: $DOWNLOAD_PATH"

if [ -z "$PACKAGE_NAME" ] || [ -z "$DOWNLOAD_PATH" ]; then
    log_message "Error: Missing arguments. Exiting."
    exit 1
fi

# 4. SAFETY CHECK (The "Smart" Logic)
# -----------------------------------
# We must prevent the script from processing the root /downloads folder.
# This happens if "Create Subfolder by Package" is disabled.
# If we run on root, we might upload/delete other active downloads.

if [ "$DOWNLOAD_PATH" = "/downloads" ] || [ "$DOWNLOAD_PATH" = "/output" ]; then
    log_message "SAFETY ALERT: Download path is the root directory ($DOWNLOAD_PATH)."
    log_message "ABORTING upload to prevent accidental deletion of other files."
    log_message "SOLUTION: Enable 'Create Subfolder by Package' in JDownloader settings."
    exit 1
fi

# Double check: Ensure we are not deleting the system root
if [ "$DOWNLOAD_PATH" = "/" ]; then
    log_message "CRITICAL: Download path is system root! Aborting."
    exit 1
fi


# 5. Upload Function
# ------------------
run_rclone_move() {
    local src="$1"
    local response
    local status

    log_message "Attempting move to: $RCLONE_DEST"

    if [ -d "$src" ]; then
        log_message "Source is a directory. Using sync/move."

        DATA=$(cat <<EOF
{
    "srcFs": "$src",
    "dstFs": "$RCLONE_DEST/$PACKAGE_NAME",
    "deleteEmptySrcDirs": true
}
EOF
)
        response=$(curl -s -X POST \
            -u "$RCLONE_USER:$RCLONE_PASS" \
            -H "Content-Type: application/json" \
            -d "$DATA" \
            "$RCLONE_HTTP_URL/sync/move" 2>&1)

    else
        # Fallback for single file (rarely hit given getDownloadFolder behavior)
        log_message "Source is a file. Using operations/movefile."

        DATA=$(cat <<EOF
{
    "srcFs": "/",
    "dstFs": "$RCLONE_DEST",
    "srcRemote": "$src",
    "dstRemote": "$PACKAGE_NAME"
}
EOF
)
        response=$(curl -s -X POST \
            -u "$RCLONE_USER:$RCLONE_PASS" \
            -H "Content-Type: application/json" \
            -d "$DATA" \
            "$RCLONE_HTTP_URL/operations/movefile" 2>&1)
    fi

    status=$?

    if [ $status -ne 0 ]; then
        log_message "Critical: Failed to contact Rclone API. Curl exit code: $status"
        log_message "Response: $response"
        return 1
    fi

    case "$response" in
        *"error"*)
            log_message "Rclone API returned error: $response"
            return 1
            ;;
        *)
            log_message "Rclone move successful."
            return 0
            ;;
    esac
}

# 6. Execution Logic
# ------------------
if run_rclone_move "$DOWNLOAD_PATH"; then
    log_message "Upload verified. Cleaning up local files."
    # The safety check in Step 4 ensures we are deleting a subfolder, not root.
    rm -rf "$DOWNLOAD_PATH"
else
    log_message "Upload failed. Preserving local files."
    exit 1
fi

log_message "Job Complete."
log_message "----------------------------------------"

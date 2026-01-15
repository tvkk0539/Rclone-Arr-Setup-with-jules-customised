#!/bin/sh

# JDownloader 2 Post-Processing Script
# Compatible with Alpine/Busybox sh (POSIX)

# 1. Setup Environment
# ------------------
# Rclone Remote: Ensure it ends with ':' if not present
# We use 'case' for pattern matching in POSIX sh
case "$RCLONE_REMOTE" in
    *:*) ;;                 # Already has colon, do nothing
    *) RCLONE_REMOTE="${RCLONE_REMOTE}:" ;; # Append colon
esac

# Append the destination path
RCLONE_DEST="${RCLONE_REMOTE}/UnSorted/JDownloader"

# Rclone API Configuration
RCLONE_HTTP_URL="http://rclone:5572"
# RCLONE_USER and RCLONE_PASS are inherited from the container environment

# 2. Parse Arguments
# ------------------
# $1 - Package Name (e.g., "MyMovie")
# $2 - Download Directory (e.g., "/output/MyMovie")

PACKAGE_NAME="$1"
DOWNLOAD_PATH="$2"
LOG_FILE="/logs/jd_postprocess.log"

# 3. Logging Helper
# -----------------
log_message() {
    # 'date' formatting might vary on minimal systems, but standard usage works
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$LOG_FILE"
}

log_message "----------------------------------------"
log_message "Processing Package: $PACKAGE_NAME"
log_message "Download path: $DOWNLOAD_PATH"

if [ -z "$PACKAGE_NAME" ] || [ -z "$DOWNLOAD_PATH" ]; then
    log_message "Error: Missing arguments. Exiting."
    exit 1
fi

# 4. Upload Function
# ------------------
run_rclone_move() {
    local src="$1"
    local response
    local status

    log_message "Attempting move to: $RCLONE_DEST"

    if [ -d "$src" ]; then
        log_message "Source is a directory. Using sync/move."
        # Construct JSON payload manually to avoid dependency on 'jq'
        # Note: We escape double quotes inside variables if necessary,
        # but package names usually are safe-ish.
        # Ideally we'd use a tool, but we are in minimal sh.

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

    # Check curl exit code
    if [ $status -ne 0 ]; then
        log_message "Critical: Failed to contact Rclone API. Curl exit code: $status"
        log_message "Response: $response"
        return 1
    fi

    # Check for "error" in JSON response (rudimentary string check)
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

# 5. Execution Logic
# ------------------
if run_rclone_move "$DOWNLOAD_PATH"; then
    log_message "Upload verified. Cleaning up local files."
    # Safety check: ensure we don't delete root
    if [ "$DOWNLOAD_PATH" != "/" ]; then
        rm -rf "$DOWNLOAD_PATH"
    fi
else
    log_message "Upload failed. Preserving local files."
    exit 1
fi

log_message "Job Complete."
log_message "----------------------------------------"

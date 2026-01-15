#!/bin/bash

# JDownloader 2 Post-Processing Script
# Save this as jd_manage.sh and make it executable with chmod +x

# Ensure we have the colon for remote path
if [[ "${RCLONE_REMOTE}" != *":"* ]]; then
    RCLONE_REMOTE="${RCLONE_REMOTE}:"
fi
RCLONE_REMOTE="${RCLONE_REMOTE}/UnSorted/JDownloader"

RCLONE_HTTP_URL="http://rclone:5572"    # rclone HTTP API URL
RCLONE_USER="${RCLONE_USER}"
RCLONE_PASS="${RCLONE_PASS}"

# Arguments passed by JDownloader Event Scripter:
# $1 - Package Name
# $2 - Download Directory (Absolute Path)

PACKAGE_NAME="$1"
DOWNLOAD_PATH="$2"

LOG_FILE="/logs/jd_postprocess.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "----------------------------------------"
log_message "Processing JDownloader Package: $PACKAGE_NAME"
log_message "Download path: $DOWNLOAD_PATH"

if [ -z "$PACKAGE_NAME" ] || [ -z "$DOWNLOAD_PATH" ]; then
    log_message "Error: Missing arguments. Exiting."
    exit 1
fi

run_rclone_move() {
    local source_path="$1"

    log_message "Running rclone move via HTTP API from: $source_path to: $RCLONE_REMOTE"

    # Check if source is a directory or file and use appropriate endpoint
    if [ -d "$source_path" ]; then
        log_message "Source is a directory, using sync/move endpoint"

        local json_payload=$(cat <<EOF
{
    "srcFs": "$source_path",
    "dstFs": "$RCLONE_REMOTE/$PACKAGE_NAME",
    "deleteEmptySrcDirs": true
}
EOF
)

        local response=$(curl -s -X POST \
            -u "$RCLONE_USER:$RCLONE_PASS" \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "$RCLONE_HTTP_URL/sync/move" 2>&1)

    else
        log_message "Source is a file, using operations/movefile endpoint"

        local json_payload=$(cat <<EOF
{
    "srcFs": "/",
    "dstFs": "$RCLONE_REMOTE",
    "srcRemote": "$source_path",
    "dstRemote": "$PACKAGE_NAME"
}
EOF
)

        local response=$(curl -s -X POST \
            -u "$RCLONE_USER:$RCLONE_PASS" \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            "$RCLONE_HTTP_URL/operations/movefile" 2>&1)
    fi

    local curl_exit_code=$?

    if [ $curl_exit_code -eq 0 ]; then
        # Check if response contains error
        if echo "$response" | grep -q '"error"'; then
            log_message "Rclone move failed with error: $response"
            return 1
        else
            log_message "Rclone move completed successfully"
            return 0
        fi
    else
        log_message "Failed to connect to rclone HTTP API. curl exit code: $curl_exit_code"
        log_message "Response: $response"
        return 1
    fi
}

if run_rclone_move "$DOWNLOAD_PATH"; then
    log_message "Upload successful. Cleaning up local files."
    # Force delete the source path to prevent ghost space
    rm -rf "$DOWNLOAD_PATH"
else
    log_message "Rclone move failed. Keeping local files."
fi

log_message "Post-processing completed for: $PACKAGE_NAME"
log_message "----------------------------------------"

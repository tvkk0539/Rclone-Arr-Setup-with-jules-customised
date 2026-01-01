#!/bin/bash

# qBittorrent Post-Processing Script (HTTP API Version)
# Save this as .sh and make it executable with chmod +x


RCLONE_REMOTE="${RCLONE_REMOTE}:/UnSorted"
RCLONE_HTTP_URL="http://rclone:5572"    # rclone HTTP API URL
RCLONE_USER="${RCLONE_USER}"
RCLONE_PASS="${RCLONE_PASS}"


# Arguments passed by qBittorrent:
# %N - Torrent name
# %F - Content path (directory for multi-file torrents, file path for single-file)
# %D - Save directory
# %L - Categories

# so use ->  qbit_manage.sh "%N" "%F" "%L"      in qbit script run field

TORRENT_NAME="$1"
CONTENT_PATH="$2"
TORRENT_CATEGORY="$3"

LOG_FILE="/logs/qbit_postprocess.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}


check_excluded_categories() {
    local category="$1"
    
    log_message "Checking category: $category"
    
    # Convert tags to lowercase for case-insensitive comparison
    local category_lower=$(echo "$category" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$category_lower" == *"radarr"* ]] || [[ "$category_lower" == *"sonarr"* ]]; then
        return 0
    else
        return 1
    fi
}

log_message "----------------------------------------"
log_message "Processing torrent: $TORRENT_NAME"
log_message "Content path: $CONTENT_PATH"
log_message "Category: $TORRENT_CATEGORY"

# Check if torrent has excluded tags
if check_excluded_categories "$TORRENT_CATEGORY"; then
    log_message "Torrent is in radarr/sonarr category. Skipping rclone move operation."
    log_message "Post-processing completed for: $TORRENT_NAME (skipped due to tags)"
    log_message "----------------------------------------"
    exit 0
fi

log_message "No excluded tags found. Proceeding with rclone move operation."

run_rclone_move() {
    local source_path="$1"
    
    log_message "Running rclone move via HTTP API from: $source_path to: $RCLONE_REMOTE"
    
    # Check if source is a directory or file and use appropriate endpoint
    if [ -d "$source_path" ]; then
        log_message "Source is a directory, using sync/move endpoint"
        
        local json_payload=$(cat <<EOF
{
    "srcFs": "$source_path",
    "dstFs": "$RCLONE_REMOTE/$TORRENT_NAME",
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
    "dstRemote": "$TORRENT_NAME"
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
        else
            log_message "Rclone move completed successfully"
        fi
    else
        log_message "Failed to connect to rclone HTTP API. curl exit code: $curl_exit_code"
        log_message "Response: $response"
    fi
}



cleanup_empty_folder() {
    local folder_path="$1"
    local max_attempts=6    # 6hr cuz of sleep an hour
    local lock_file="/tmp/locks/cleanup_$(echo "$folder_path" | md5sum | cut -d' ' -f1).lock"
    local attempt=0

    # making sure only one script is looking for a folder (binary locking)
    if [ -e "$lock_file" ]; then
        log_message "Cleanup skipping - Another process already watching"
        return 0
    fi

    touch "$lock_file"

    while [ $attempt -lt $max_attempts ]; do
        if [ ! -d "$folder_path" ]; then
            rm -f "$lock_file"
            log_message "--------- $folder_path -- cleanded up ---------"
            return 0
        fi
        
        if [ ! "$(ls -A "$folder_path" 2>/dev/null)" ]; then
            if rmdir "$folder_path" 2>/dev/null; then
                rm -f "$lock_file"
                log_message "--------- $folder_path -- cleanded up ---------"
                return 0
            else
                return 1
            fi
        fi
        

        log_message "--------- Retrying cleanup for $folder_path ---------"
        
        sleep 3600

        attempt=$((attempt + 1))
    done
    rm -f "$lock_file"
    log_message "--------- $folder_path -- cleaning failed ---------"
    return 1
}




run_rclone_move "$CONTENT_PATH"

sleep 300 # helpfull for smaller files

if [ -d "$CONTENT_PATH" ]; then
    log_message "Running background cleanup for $CONTENT_PATH"
    cleanup_empty_folder "$CONTENT_PATH" &
fi



log_message "Post-processing completed for: $TORRENT_NAME"
log_message "----------------------------------------"
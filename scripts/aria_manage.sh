#!/bin/bash

# Aria2 Post-Processing Script (HTTP API Version)
# Save this as .sh and make it executable with chmod +x


# Ensure we have the colon for remote path
if [[ "${RCLONE_REMOTE}" != *":"* ]]; then
    RCLONE_REMOTE="${RCLONE_REMOTE}:"
fi
RCLONE_REMOTE="${RCLONE_REMOTE}/UnSorted"

COMPLETED_DIR="/downloads/aria_downloads"    # Directory where completed downloads go (seperate folder for radarr to watch)
RCLONE_HTTP_URL="http://rclone:5572"   # rclone HTTP API URL
RCLONE_USER="${RCLONE_USER}"
RCLONE_PASS="${RCLONE_PASS}"


# Arguments passed by aria2:
# $1 - GID (download identifier)
# $2 - Number of files
# $3 - File path (for single file) or directory path (for multi-file)

GID="$1"
FILE_COUNT="$2"
DOWNLOAD_PATH="$3"

LOG_FILE="/logs/aria2_postprocess.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}


get_download_name() {
    if [ -e "$1" ]; then
        basename "$1"
    else
        echo "unknown"
    fi
}

DOWNLOAD_NAME=$(get_download_name "$DOWNLOAD_PATH")


log_message "----------------------------------------"
log_message "Processing download: $DOWNLOAD_NAME (GID: $GID)"
log_message "File count: $FILE_COUNT"
log_message "Download path: $DOWNLOAD_PATH"

# Check for empty path (Metadata download or error)
if [ -z "$DOWNLOAD_PATH" ] || [ "$FILE_COUNT" -eq 0 ]; then
    log_message "Download path is empty or file count is 0. Likely metadata/magnet resolution."
    log_message "Skipping rclone move."
    log_message "----------------------------------------"
    exit 0
fi



is_media() {
    local name="$1"
    
    # Check for media-like patterns (year in parentheses, common movie extensions)
    if [[ "$name" =~ \([0-9]{4}\) ]] || 
       [[ "$name" =~ \.(mkv|mp4|avi|mov|wmv|flv|m4v)$ ]] ||
       [[ "$name" =~ (720p|1080p|2160p|4K|BluRay|WEB-DL|WEBRip|HDTV) ]]; then
        return 0  # Is likely a media
    else
        return 1  # Not likely a media
    fi
}


move_to_completed() {
    local source_path="$1"
    local item_name="$2"
    
    mkdir -p "$COMPLETED_DIR"
    
    log_message "Moving to completed folder: $COMPLETED_DIR"
    
    mv "$source_path" "$COMPLETED_DIR/"
    log_message "Moved : $item_name to $COMPLETED_DIR/"
}




run_rclone_move() {
    local source_path="$1"
    
    log_message "Running rclone move via HTTP API from: $source_path to: $RCLONE_REMOTE"
    
    # Check if source is a directory or file and use appropriate endpoint
    # Not really needed for Aria2 as it will only handle files - but just in case if needed
    if [ -d "$source_path" ]; then
        log_message "Source is a directory, using sync/move endpoint"
        
        local json_payload=$(cat <<EOF
{
    "srcFs": "$source_path",
    "dstFs": "$RCLONE_REMOTE/$DOWNLOAD_NAME",
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
    "dstRemote": "$DOWNLOAD_NAME"
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





# main logic
run_rclone_move "$DOWNLOAD_PATH"
sleep 300
if [ -d "$DOWNLOAD_PATH" ]; then
    log_message "Running background cleanup for $DOWNLOAD_PATH"
    cleanup_empty_folder "$DOWNLOAD_PATH" &
fi

log_message "Post-processing completed for: $DOWNLOAD_NAME (GID: $GID)"
log_message "----------------------------------------"
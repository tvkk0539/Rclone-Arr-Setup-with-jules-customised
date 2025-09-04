#!/bin/bash

# Radarr Post-Processing Script (HTTP API Version)
# Save this as radarr_manage.sh and make it executable with chmod +x
# Configure in Radarr: Settings -> Connect -> Custom Script

RCLONE_REMOTE="${RCLONE_REMOTE}/Movies"  # Movies destination
RCLONE_HTTP_URL="http://rclone:5572"     # rclone HTTP API URL
RCLONE_USER="${RCLONE_USER}"
RCLONE_PASS="${RCLONE_PASS}"

# Radarr environment variables (automatically provided):
# radarr_eventtype - Type of event (Download, Rename, MovieFileDelete, etc.)
# radarr_movie_title - Movie title
# radarr_movie_year - Movie release year
# radarr_movie_imdbid - IMDB ID
# radarr_movie_path - Full path to the movie directory
# radarr_moviefile_path - Full path to the movie file
# radarr_moviefile_relativepath - Relative path to the movie file
# radarr_moviefile_id - Movie file ID
# radarr_moviefile_sourcepath - Original source path before processing
# radarr_moviefile_sourcefolder - Original source folder before processing

EVENT_TYPE="$radarr_eventtype"
MOVIE_TITLE="$radarr_movie_title"
MOVIE_YEAR="$radarr_movie_year"
MOVIE_PATH="$radarr_movie_path"

LOG_FILE="/logs/radarr_postprocess.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "----------------------------------------"
log_message "Radarr event triggered: $EVENT_TYPE"
log_message "Movie: $MOVIE_TITLE ($MOVIE_YEAR)"
log_message "Movie directory: $MOVIE_PATH"

# Only process on Download and Upgrade events
if [[ "$EVENT_TYPE" != "Download" && "$EVENT_TYPE" != "Upgrade" ]]; then
    log_message "Event type '$EVENT_TYPE' - skipping upload"
    log_message "----------------------------------------"
    exit 0
fi

run_rclone_move() {
    local source_path="$1"
    local dest_name="$2"
    
    log_message "Running rclone move via HTTP API from: $source_path"
    log_message "Destination: $RCLONE_REMOTE/$dest_name"
    

    log_message "Source is a directory, using sync/move endpoint"
        
    local json_payload=$(cat <<EOF
{
    "srcFs": "$source_path",
    "dstFs": "$RCLONE_REMOTE/$dest_name",
    "deleteEmptySrcDirs": true
}
EOF
)
        
    local response=$(curl -s -X POST \
        -u "$RCLONE_USER:$RCLONE_PASS" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "$RCLONE_HTTP_URL/sync/move" 2>&1)
            
    
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
        
        sleep 10

        attempt=$((attempt + 1))
    done
    rm -f "$lock_file"
    log_message "--------- $folder_path -- cleaning failed ---------"
    return 1
}



# Wait a few seconds to ensure file operations are complete
sleep 10

# Create a safe directory name for the movie
#SAFE_MOVIE_NAME="${MOVIE_TITLE// /_}"
#SAFE_MOVIE_NAME="${SAFE_MOVIE_NAME//[^a-zA-Z0-9._-]/_}"
MOVIE_DIR_NAME=$(basename "$MOVIE_PATH")
#MOVIE_DIR_NAME="${SAFE_MOVIE_NAME}_${MOVIE_YEAR}"

run_rclone_move "$MOVIE_PATH" "$MOVIE_DIR_NAME"

sleep 10

cleanup_empty_folder "$MOVIE_PATH"

log_message "Post-processing completed for: $MOVIE_TITLE ($MOVIE_YEAR)"
log_message "----------------------------------------"
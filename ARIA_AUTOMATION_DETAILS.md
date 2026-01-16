# Aria2 Automation Script: Detailed Change Log & Learning Guide

This document explains the evolution of the `scripts/aria_manage.sh` automation script. It details how the script behaved **Before** the specific cleanup updates and how it behaves **After**, serving as a reference for understanding the automation logic.

---

## The Problem
Even though files were successfully uploading to Cloud Storage (via Rclone), two issues persisted on the local server:
1.  **GUI Clutter:** The download task remained visible in the AriaNg dashboard (the GUI) as "Completed" or "Active".
2.  **Ghost Files:** A small control file (e.g., `Movie.mkv.aria2`) was often left behind on the disk, cluttering the directory.

---

## Detailed Comparison: Before vs. After

### 1. Task Removal from GUI (AriaNg)

**Before:**
*   The script would upload the file to Rclone.
*   It would *attempt* to delete the local file via standard commands.
*   **Result:** The task stayed in the "Completed" list in AriaNg. You had to manually log in and click "Remove" to clear the list.

**After:**
*   A new function `remove_download_from_aria2` was implemented.
*   Once the upload is confirmed successful, the script sends a JSON-RPC command to the Aria2 backend (using the `RPC_SECRET` for authentication).
*   **Command:** *"Hey, delete the task with ID `GID`."* (`aria2.removeDownloadResult`)
*   **Result:** The task automatically disappears from the AriaNg dashboard immediately after upload.

### 2. Local File Cleanup (The `.aria2` file)

**Before:**
*   The script only tried to delete the *main* download path (e.g., `downloads/Movie.mkv`).
*   It did **not** explicitly account for the hidden helper file that Aria2 creates to track download progress.
*   **Result:** The main movie file might be moved/deleted, but `Movie.mkv.aria2` was often left behind.

**After:**
*   A specific check was added:
    ```bash
    if [ -e "${DOWNLOAD_PATH}.aria2" ]; then
        rm -f "${DOWNLOAD_PATH}.aria2"
    fi
    ```
*   The script now explicitly looks for that `.aria2` file and deletes it immediately after the main file is processed.
*   **Result:** The folder is completely clean with no leftovers.

### 3. "Double Cleanup" Logic

**Before:**
*   The script relied mostly on Rclone's `move` command (which is designed to delete the source file after a successful transfer).
*   If Rclone "moved" the file but the local filesystem didn't release the space or file handle immediately, the script assumed it was done.

**After:**
*   A "force cleanup" step was added.
*   Even if Rclone reports a successful move, the script runs a `rm -rf` command on the local folder path to guarantee removal.
    ```bash
    if [ -e "$DOWNLOAD_PATH" ]; then
        log_message "Force cleaning up local path: $DOWNLOAD_PATH"
        rm -rf "$DOWNLOAD_PATH"
    fi
    ```
*   **Result:** "Ghost space" usage is prevented, and storage is freed up instantly.

---

## Summary Workflow (New Script)

1.  **Download Finishes:** Aria2 triggers the `aria_manage.sh` script.
2.  **Upload:** Script sends the file/folder to Cloud Storage (`rclone move`).
3.  **Verify:** Script checks the exit code to ensure the upload was successful.
4.  **GUI Clean:** Script calls Aria2 API to "Remove this task from the list."
5.  **Disk Clean:** Script force-deletes the local file/folder **AND** the `.aria2` control file.
6.  **Done:** Zero trace left on the local server; the file exists only in the cloud.

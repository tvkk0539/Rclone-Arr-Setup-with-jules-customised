# Manual Upload & Troubleshooting Guide

This guide explains what happens when a download finishes and what to do if it gets "stuck" on your VM.

---

## 1. How Automation Works (The Chain of Events)

Ideally, you never have to touch anything. Here is the process:

1.  **Download**: qBittorrent downloads file to `/downloads` on your VM.
2.  **Trigger**: When it hits 100%, qBittorrent looks at its settings.
    *   *Is "Run external program" checked?* -> **YES**.
    *   *What command?* -> `/scripts/qbit_manage.sh`.
3.  **Script Action**: The script wakes up.
    *   It checks the file path.
    *   It talks to Rclone.
    *   It uploads the file to Google Drive.
4.  **Cleanup**: The script deletes the file from your VM to free up space.

**If Step 2 is unchecked, the chain breaks.** The file sits on your VM forever.

---

## 2. Fixing "Stuck" Downloads

If you downloaded a file *before* you configured the settings in Step 3C of the main guide, that file is stuck.

### Option A: The Easy Fix (Re-Download)
Since the file is already "Finished", qBittorrent won't try to trigger the script again.
1.  Right-click the torrent in qBittorrent.
2.  **Delete** (and check "Also delete the files on the hard disk").
3.  Add the Magnet Link again.
4.  Since you fixed the settings now, it will work this time!

### Option B: The "Hacker" Fix (Force Upload)
You can manually force the script to run without re-downloading.

1.  **Find the file name**:
    Go to the **Content** tab in qBittorrent and see the exact folder or filename (e.g., `Big.Buck.Bunny.1080p.mp4`).

2.  **Run the Command**:
    Open your VM terminal and paste this (replace the filename!):
    ```bash
    docker exec -it qbittorrent /scripts/qbit_manage.sh "Big.Buck.Bunny.1080p.mp4" "/downloads/Big.Buck.Bunny.1080p.mp4" ""
    ```

3.  **Check Rclone**:
    Go to your Rclone WebUI (`:5572`). You should see the file appear in `UnSorted`.

---

## 3. How to check if it worked?

Always check the logs!
```bash
cat logs/qbit_postprocess.log
```

*   **Empty file or Missing?** -> The script never ran.
    *   Check qBittorrent settings (Is the box checked?).
    *   Check Permissions: Run `chmod -R 777 logs/`.
*   **"Permission denied"?** -> Run `chmod -R 777 logs/`.
*   **"Upload Successful"?** -> It worked!
*   **"Error"?** -> Check if your Rclone config is correct.

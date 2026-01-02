# Rclone Mount Configuration Guide: Performance vs. Resources

This guide explains the two Rclone Mount configurations available in your `docker-compose.yml` file. You can toggle between them depending on your server's hardware (CPU/RAM) and your performance needs.

---

## The Two Options

We have provided two different ways to mount your Cloud Drive to your server.

### Option 1: High Performance (Default / Active)
**Best for:** Smooth streaming (Jellyfin/Plex), preventing API bans, and fast library scans.
**Hardware:** Requires some free disk space for cache (up to 10GB by default).

```yaml
    command: >
      mount ${RCLONE_REMOTE}: /data/mount
      --allow-other
      --dir-cache-time 1000h
      --poll-interval 10s
      --vfs-cache-mode full
      --vfs-cache-max-size 10G
      --vfs-cache-max-age 12h
      --config /config/rclone/rclone.conf
```

#### What does it do?
*   **`--vfs-cache-mode full`**: This is the magic setting. When you start watching a movie, Rclone downloads chunks of it ahead of time and saves them to your local disk.
    *   *Result:* If your internet hiccups, the movie keeps playing from the cache. Rewinding/Fast-forwarding is instant.
*   **`--dir-cache-time 1000h`**: Remembers the list of files for a long time.
    *   *Result:* Jellyfin can scan your library in seconds instead of hours, because it doesn't need to ask Google Drive for every single filename.
*   **`--poll-interval 10s`**: Checks for changes in the cloud frequently so new uploads appear quickly.

---

### Option 2: Low Resource (Friend's Suggestion)
**Best for:** Very weak VPS (e.g., 1 vCPU, 512MB RAM), saving disk space.
**Hardware:** Uses minimal CPU and almost no disk space.

```yaml
    command: >
      mount ${RCLONE_REMOTE}: /data/mount
      --allow-other
      --dir-cache-time 1000h
      --vfs-cache-mode writes
      --read-only
      --config /config/rclone/rclone.conf
```

#### What does it do?
*   **`--vfs-cache-mode writes`**: Only caches files when you are *uploading* them. When *reading* (streaming), it pulls data directly from the cloud byte-by-byte.
    *   *Risk:* Streaming relies 100% on real-time network stability. Buffering is more likely.
*   **`--dir-cache-time 1000h`**: We added this to speed up library scans. It uses a tiny amount of RAM to remember file lists, preventing API bans.
*   **`--read-only`**: Adds a safety layer where Jellyfin cannot delete files from your cloud drive.

---

## Comparison Table

| Feature | Option 1 (High Performance) | Option 2 (Low Resource) |
| :--- | :--- | :--- |
| **Streaming Quality** | **Smooth** (Buffered) | **Variable** (Direct Stream) |
| **Disk Space Usage** | Moderate (Cache up to 10GB) | **Low** (Almost zero) |
| **CPU/RAM Usage** | Moderate | **Low** |
| **Library Scan Speed**| **Instant** | Slow |
| **File Safety** | Read/Write | Read-Only |

---

## How to Switch

1.  Open `docker-compose.yml`:
    ```bash
    nano docker-compose.yml
    ```
2.  Scroll down to the `mount` service.
3.  **To use Low Resource Mode:**
    *   Add `#` in front of the lines under "Option 1".
    *   Remove `#` from the lines under "Option 2".
4.  Save and Restart:
    ```bash
    docker compose up -d mount
    ```

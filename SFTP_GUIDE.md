# SFTP Guide: Maximum Speed & Security

This guide explains how to transfer files from your server to your devices (PC/Mobile) using **SFTP (Secure File Transfer Protocol)**.

---

## 1. Why use SFTP? (Speed Comparison)

You have two ways to access your files:

1.  **File Browser (Web)**:
    *   **Pros**: Convenient. Just open Chrome/Safari. No app needed.
    *   **Cons**: Slower for huge files (50GB+). If internet drops for 1 second, download fails.
    *   **Best for**: Renaming files, checking downloads, grabbing small subtitles.

2.  **SFTP (App)**:
    *   **Pros**: **Maximum Speed**. Uses your full internet bandwidth. Resumes downloads if connection drops.
    *   **Cons**: Requires an app (FileZilla, etc.).
    *   **Best for**: Downloading entire seasons, 4K movies, or backing up terabytes of data.

---

## 2. Option A: The "Quick" Way (Using Root/Sudo)

You can already connect right now using your main server login.

*   **Host**: `Your-Server-IP`
*   **Port**: `22`
*   **User**: `root` (or your username)
*   **Password**: Your SSH Password (or Key)

**⚠️ Warning**: This gives the app **FULL CONTROL** over your server. If you accidentally drag a system folder to "Trash", you could break your server. Be careful!

---

## 3. Option B: The "Professional" Way (Restricted User)

We recommend creating a special user account just for file transfers.
*   This user can **ONLY** see the `/downloads` folder.
*   They cannot run commands or SSH into the terminal.
*   If you share this login with a friend, they cannot hack your server.

### How to set it up:

1.  SSH into your server as root.
2.  Run this command:
    ```bash
    cd Rclone-Arr-Setup
    sudo ./scripts/create_sftp_user.sh
    ```
3.  Enter a username (e.g., `downloader`).
4.  Set a password.

**That's it!** You now have a safe login.

---

## 4. How to Connect (Apps)

### Windows / Mac / Linux (PC)
**App**: [FileZilla](https://filezilla-project.org/) (Free)

1.  Open FileZilla.
2.  **Host**: `sftp://<YOUR_IP>`
3.  **Username**: `downloader` (or whatever you created)
4.  **Password**: (The password you set)
5.  **Port**: `22`
6.  Click **Quickconnect**.

### Android
**App**: [Solid Explorer](https://play.google.com/store/apps/details?id=pl.solidexplorer2) (Recommended) or **MixPlorer**.

1.  Open App -> New Connection (`+`).
2.  Select **SFTP**.
3.  **Remote Host**: `Your-Server-IP`
4.  **Username**: `downloader`
5.  **Password**: ****
6.  Connect.

### iOS (iPhone / iPad)
**App**: [Documents by Readdle](https://apps.apple.com/us/app/documents-file-reader-browser/id364901807) (Free) or **Owlfiles**.

1.  Open App -> Connections -> Add Connection.
2.  Select **SFTP Server**.
3.  **Host**: `Your-Server-IP`
4.  **Login**: `downloader`
5.  **Password**: ****
6.  Save.

---

## 5. Pro Tips for Speed

*   **Wired Connection**: If downloading 50GB+, connect your PC via Ethernet cable instead of Wi-Fi for stable speeds.
*   **Parallel Downloads**: In FileZilla, go to **Transfer Settings** and set "Maximum simultaneous transfers" to **2** or **4**. This downloads multiple parts of the file at once (like IDM).
*   **Resume**: If a download fails, just right-click it and choose **Resume**. It will continue from where it left off!

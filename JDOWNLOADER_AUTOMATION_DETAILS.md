# JDownloader 2 Automation: Deep Dive & Logic Guide

This document explains the "Brain" behind the JDownloader 2 automation. It details how the system handles multiple downloads simultaneously, ensures safety, and cleans up after itself without user intervention.

Use this as a reference to understand the **Logic** and **Safety Mechanisms** implemented in `scripts/jd_manage.sh`.

---

## 1. The Core Concept: "Packages" are King

JDownloader 2 does not just download files randomly. It groups them into **Packages**.
*   **Example:** If you add a link for "Toy Story 3", JDownloader creates a package named `Toy Story 3`.
*   **The Golden Rule:** By default, JDownloader creates a **Subfolder** for every package.
    *   Path: `/downloads/Toy Story 3/`
    *   Inside: `Toy Story 3.mkv`

**Why is this important?**
Because it allows us to isolate every download. We never touch the main `/downloads` folder; we only touch the specific *Subfolder* for that specific movie.

---

## 2. How Concurrent Downloads Work (The "Safety Logic")

**The Scenario:**
You are downloading 3 movies at the same time:
1.  **Avatar** (50GB) - *Downloading (10%)* -> Folder: `/downloads/Avatar/`
2.  **Titanic** (40GB) - *Finished (100%)* -> Folder: `/downloads/Titanic/`
3.  **Shrek** (20GB) - *Downloading (80%)* -> Folder: `/downloads/Shrek/`

**The Process:**
1.  **Titanic Finishes.**
2.  JDownloader triggers our script (`jd_manage.sh`).
3.  It passes two specific pieces of information to the script:
    *   **Package Name:** `Titanic`
    *   **Path:** `/downloads/Titanic/`
4.  The Script executes:
    *   *"Upload everything inside `/downloads/Titanic/` to the cloud."*
    *   *"Delete the folder `/downloads/Titanic/`."*
5.  **Result:**
    *   `Titanic` is gone (uploaded).
    *   `Avatar` and `Shrek` are **completely untouched**. Their folders were never even looked at.

**Conclusion:**
You can download 100 files at once. The script is "surgical"—it only operates on the *one specific folder* that just finished.

---

## 3. The "Safety Guard" (Root Protection)

What if something goes wrong? What if you disabled "Create Subfolder"?

**The Danger:**
If "Create Subfolder" is OFF, all files go directly into `/downloads/`.
*   If the script tries to "Clean up" after *Titanic*, it might look at `/downloads/` and say *"Upload and delete everything here!"*.
*   **Catastrophe:** It would delete *Avatar* and *Shrek* before they are finished.

**The Solution (The Code Guard):**
We implemented a strict safety check in the script. Before doing anything, it asks:

> *"Is the target folder the main `/downloads` root?"*

```bash
# Code Snippet from scripts/jd_manage.sh

if [ "$DOWNLOAD_PATH" = "/downloads" ] || [ "$DOWNLOAD_PATH" = "/output" ]; then
    log_message "SAFETY ALERT: Download path is the root directory."
    log_message "ABORTING upload to prevent accidental deletion of active downloads."
    exit 1
fi
```

*   **If YES:** The script **PANICS and STOPS**. It refuses to touch anything. It logs a warning telling you to fix your settings.
*   **If NO (It's a subfolder):** It proceeds safely.

---

## 4. The Workflow: Step-by-Step

Here is the lifecycle of a download in this system:

1.  **Injection (Start):**
    *   When the container starts, `deploy.sh` injects a "Listener" into JDownloader (The Event Scripter).
    *   It says: *"Listen for the `ON_PACKAGE_FINISHED` event."*

2.  **The Event (Finish):**
    *   A download hits 100%. extraction finishes.
    *   The "Listener" wakes up and runs: `/scripts/jd_manage.sh "MovieName" "/downloads/MovieName"`.

3.  **The Script (Action):**
    *   **Check:** Is `curl` installed? (Yes)
    *   **Check:** Is this a safe subfolder? (Yes)
    *   **Action:** Call Rclone API (`/sync/move`).
        *   *"Move `/downloads/MovieName` to `Remote:/UnSorted/JDownloader/MovieName`"*

4.  **The Cleanup (End):**
    *   Rclone confirms: *"Upload Complete."*
    *   Script runs: `rm -rf "/downloads/MovieName"`.
    *   Disk space is freed instantly.

---

## 5. Technical Improvements (Under the Hood)

For the curious developer, here is how we made the script "Robust":

*   **POSIX Compliance:** We switched from `bash` to `sh`.
    *   *Why?* Docker containers often use "Alpine Linux", which is super small and doesn't have `bash`. Using `sh` ensures it runs on *any* Linux system.
*   **No `jq` Dependency:**
    *   *Why?* Most scripts use a tool called `jq` to write JSON data. JDownloader doesn't have it.
    *   *Fix:* We manually construct the JSON text inside the script, so it needs zero external tools.
*   **Direct API calls:**
    *   Instead of running `rclone move ...` (which requires configuring Rclone *inside* the JDownloader container), we talk to the **Rclone Container** via HTTP.
    *   This keeps the JDownloader container clean and lightweight.

---

## 6. Case Study: The "Subfolder by Package" Fix (Before vs After)

One of the most critical parts of this automation is ensuring that **every download gets its own folder**. We call this "Isolation".
Without isolation, our "Delete" script is dangerous.

### The Problem: The "Fake" Checkbox
In the JDownloader Web Interface, there is a setting called **"Subfolder by Package"**.
We tried to enable this via the deployment script by setting `subfolderbypackageenabled: true`.
**It failed.**

**Why?**
We discovered that "Subfolder by Package" is **not just a setting**. It is actually a secret **Packagizer Rule**.
*   When you check the box in the UI, JDownloader creates a rule behind the scenes.
*   When running in "Headless Mode" (no GUI), just flipping the "true" switch wasn't enough to create the rule.

### The Solution: Direct Rule Injection

Instead of trying to "Check the box", we decided to **manually inject the Brain Rule** directly into JDownloader's configuration.

#### The Code Change (Before vs After)

**Before (The Failed Attempt):**
We tried to change the `GeneralSettings` file. JDownloader ignored this because it lacked the logic to execute it.
```bash
# This did NOTHING in Headless Mode
echo '{"subfolderbypackageenabled" : true}' > configs/jdownloader/cfg/org.jdownloader.settings.GeneralSettings.json
```

**After (The Success):**
We injected the actual logic into the `PackagizerSettings.rulelist.json` file. This is the file JDownloader reads to decide *how* to handle packages.

```bash
# We define a STATIC RULE: "Always move downloads to <jd:packagename>"
cat > configs/jdownloader/cfg/org.jdownloader.controlling.packagizer.PackagizerSettings.rulelist.json <<EOF
[
  {
    "id": "SubFolderByPackageRule",
    "enabled": true,
    "name": "Create Subfolder by Packagename",
    "matchAlwaysFilter": { "enabled": true },
    "downloadDestination": "<jd:packagename>",
    "staticRule": true
  }
]
EOF
```

### The "Missing Checkbox" Mystery
After applying this fix, users noticed something strange:
> *"The automation works perfect! But when I check the Web UI, the 'Subfolder' checkbox is still empty!"*

**Why does this happen?**
*   **The Checkbox (UI)**: This is just a toggle switch for the user. It doesn't know we modified the engine files directly.
*   **The Rule (Engine)**: The engine reads our injected rule file and executes it 100% of the time.

**Analogy:**
Imagine a light switch on the wall (The Checkbox).
We went into the ceiling and hard-wired the light to be ON (The Rule).
The light is **ON**, even though the switch on the wall is still in the "OFF" position.

**Result:**
The system is **Safe**, **Robust**, and **Permanent**, even if the UI looks different.

# Comprehensive Guide: Rclone Media Server Stack on GCP

## 1. What is this project?

This project allows you to run a complete "Netflix-like" media server on a cloud server (like a Google Cloud VM) **without using the server's limited hard drive space for storage**.

### How it works:
1.  **Jellyseerr**: You use this beautiful website to "request" movies.
2.  **Radarr**: It sees the request and finds the movie on torrent sites (via Prowlarr).
3.  **qBittorrent**: Downloads the movie.
4.  **Automation Scripts**: As soon as the download finishes, a special script **moves the file to your Cloud Storage** (Google Drive, OneDrive, etc.) using **Rclone**.
5.  **Result**: You have a huge media library stored in the cloud, but managed automatically by your server.

---

## 2. Setting up your GCP VM

Since you have Google Cloud credits, here is how to set up the Virtual Machine.

1.  Go to **Google Cloud Console** -> **Compute Engine** -> **VM Instances**.
2.  Click **Create Instance**.
3.  **Region**: Choose a region close to you (e.g., `asia-south1` for Mumbai, `us-central1` for US).
4.  **Machine Type**: Choose based on your usage:
    *   **Option A: 4 GB RAM (`e2-medium`) - Recommended**: Best if you plan to use **Jellyfin** to stream movies. Jellyfin needs more RAM to run smoothly without crashing.
    *   **Option B: 2 GB RAM (`e2-small`) - Saver Mode**: Good if you **only** want to download/upload and **do not** use Jellyfin. The download tools are lightweight and run fine on 2GB.
    *   *Pro Tip*: You can start with `e2-small` to save money. If you later decide to stream, you can just "Stop" the VM, edit the settings to upgrade to `e2-medium`, and start it again!
5.  **Boot Disk**:
    *   Click "Change".
    *   Select **Ubuntu**.
    *   Version: **Ubuntu 22.04 LTS**.
    *   Size: **30 GB** or **50 GB** (Standard Persistent Disk is fine).
6.  **Firewall**: Check both **Allow HTTP traffic** and **Allow HTTPS traffic**.
7.  Click **Create**.

### Open Ports
You need to allow specific ports so you can access the websites.
1.  Search for **"Firewall rules"** in GCP Console.
2.  Click **Create Firewall Rule**.
3.  **Name**: `allow-media-ports`
4.  **Targets**: `All instances in the network`
5.  **Source IPv4 ranges**: `0.0.0.0/0`
6.  **Protocols and ports**: Select `TCP` and enter:
    `7575,8080,6880,5572,7878,9696,5055,5060,8096`
7.  Click **Create**.

---

## 3. Installing Software

SSH into your new VM (click the "SSH" button in the GCP console) and run these commands one by one.

### Update the System
```bash
sudo apt update && sudo apt upgrade -y
```

### Install Docker & Docker Compose
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to the docker group (so you don't need 'sudo' for docker commands)
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin -y
```
*Note: You might need to log out and log back in for the user group change to take effect. Type `exit` and SSH again.*

---

## 4. Installation & Setup

### Clone the Repository
```bash
git clone https://github.com/vinayak-7-0-3/Rclone-Arr-Setup
cd Rclone-Arr-Setup
```

### Configure Environment Variables
1.  Copy the sample file:
    ```bash
    cp sample.env .env
    ```
2.  Edit the file:
    ```bash
    nano .env
    ```
3.  Change the following lines:
    *   `MEDIA_SERVER_ROOT`: Change this to the full path of your folder. Run `pwd` to see it. usually `/home/your_username/Rclone-Arr-Setup`.
    *   `DOWNLOADS_FOLDER`: Create a folder for temporary downloads: `mkdir -p ~/downloads` and set this path (e.g., `/home/your_username/downloads`).
    *   `RCLONE_REMOTE`: Name of your remote (we will set this up next, usually named `drive` or `onedrive`).
    *   `RCLONE_USER` / `RCLONE_PASS`: Create a username and password for the Rclone Web UI.
    *   `RPC_SECRET`: Create a random password for Aria2.
    *   `SECRET_ENCRYPTION_KEY`: A secret key for Homarr to encrypt your sessions.
        *   *How to get it*: Run `openssl rand -hex 32` in your terminal to generate one, or just type a very long random string yourself (e.g., `my_super_secret_homarr_key_12345`).

    Save and exit (Ctrl+O, Enter, Ctrl+X).

---

## 5. Setting up Rclone (Crucial Step)

This connects your server to your Cloud Storage (Google Drive, etc.).

### Option A: I have an existing `rclone.conf` file (Easiest)
If you have used Rclone before and have a file with your accounts:

1.  **Open `rclone.conf` on your computer** with Notepad or a text editor. Copy everything inside.
2.  **Create the file on your VM**:
    ```bash
    mkdir -p configs/rclone
    nano configs/rclone/rclone.conf
    ```
3.  **Paste the content** into the terminal.
4.  **Save and Exit**: Press `Ctrl+O`, `Enter`, then `Ctrl+X`.
5.  **Important**: Check the name in the square brackets `[...]` in your file (e.g., `[my_drive]`).
    *   Open your `.env` file (`nano .env`).
    *   Update `RCLONE_REMOTE=my_drive` to match that name.
    *   **Done!** You can skip to Step 6.

### Option B: I need to create a new connection (The Wizard)
If you are starting from scratch, follow these steps:

1.  Create config directory:
    ```bash
    mkdir -p configs/rclone
    ```
2.  **Run the Configuration Wizard**:
    Run this command in your VM terminal (you do not need to be inside a container):
    ```bash
    docker run --rm -it -v $(pwd)/configs/rclone:/config/rclone rclone/rclone config --config /config/rclone/rclone.conf
    ```
    *   *What this command does*: It starts a temporary Rclone container. We tell it explicitly to save the config to `/config/rclone/rclone.conf` so it matches our setup. The `-v` part makes sure that file is saved **on your VM's hard drive** (in `configs/rclone/`), so the other services can find it later.

3.  **Follow the Wizard**:
    *   Type `n` for **New Remote**.
    *   **name**: Enter the name you put in `.env` (e.g., `drive`).
    *   **Storage**: Choose your provider (e.g., `drive` for Google Drive).
    *   **Client ID / Secret**: Leave blank (Press Enter).
    *   **Scope**: Pick option `1` (Full Access).
    *   **Root Folder ID**: Leave blank.
    *   **Service Account**: Leave blank.

4.  **The Tricky Part (Authentication)**:
    *   It will ask: `Use auto config?`
    *   **YOU MUST SAY NO (`n`)**.
    *   *Why?* Because your VM has no browser to open the Google Login page.

5.  **The "Remote" Login**:
    *   Rclone will show you a long command that looks like: `rclone authorize "drive" "eyJhbGciOi..."`
    *   **Copy that command.**
    *   Open a terminal **on your own personal computer** (where you have Rclone installed).
    *   Paste and run that command.
    *   A browser window will pop up on your computer. Log in to Google.
    *   Rclone on your computer will then give you a **Code**.
    *   **Copy that Code**.

6.  **Finish**:
    *   Go back to your VM terminal.
    *   **Paste the Code**.
    *   Type `q` to quit.

    Now your VM is connected to Google Drive!

### The Magic of Rclone: Upload vs. Mount
We use Rclone in two ways in this project:
1.  **The Uploader**: When you download a movie, scripts send it to the cloud immediately.
2.  **The Mount (Streaming)**: We use a special container (`rclone-mount`) that tricks your server into thinking your Google Drive is a **local folder** (`/data/movies`). This allows **Jellyfin** to play movies directly from the cloud without downloading them!

---

## 6. Launching the Services

Start everything up!

```bash
# Create the network defined in your .env
docker network create nginx_network  # Or whatever you named DOCKER_NETWORK

# Start containers
docker compose up -d
```

Check if everything is running:
```bash
docker compose ps
```

---

## 7. Connecting the Services

Now open your browser and go to your VM's External IP address with the ports.
Example: `http://<YOUR_VM_IP>:7575` (Homarr Dashboard).

### Step A: Configure Prowlarr (Indexer Manager)
1.  Go to `http://<YOUR_VM_IP>:9696`
2.  **Add Indexers**: Go to "Indexers" -> "Add Indexer". Search for "1337x" or "RARBG" and save.
3.  **Connect to Radarr**:
    *   Go to **Settings** -> **Apps**.
    *   Click **+** and choose **Radarr**.
    *   **Prowlarr Server**: `http://prowlarr:9696`
    *   **Radarr Server**: `http://radarr:7878`
    *   **API Key**: Get this from Radarr (Settings -> General).
    *   Click **Save**.

### Step B: Configure Radarr (Movie Manager)
1.  Go to `http://<YOUR_VM_IP>:7878`
2.  **Add Download Client (qBittorrent)**:
    *   **Settings** -> **Download Clients**.
    *   Click **+** -> **qBittorrent**.
    *   **Name**: qBittorrent
    *   **Host**: `qbittorrent`
    *   **Port**: `8080`
    *   **Username/Password**: `admin` / `adminadmin` (default).
    *   **Category**: `radarr` (Important!).
    *   Click **Test** then **Save**.
3.  **Setup the Custom Script**:
    *   **Settings** -> **Connect**.
    *   Click **+** -> **Custom Script**.
    *   **Name**: Rclone Upload
    *   **Path**: `/scripts/radarr_manage.sh`
    *   **Tags**: (Leave empty)
    *   **Arguments**: (Leave empty)
    *   **On Grab**: No
    *   **On Download**: **Yes** (Check this)
    *   **On Upgrade**: **Yes** (Check this)
    *   Click **Save**.
4.  **Root Folder**: When adding a movie, set the Root Folder to anything (e.g., `/movies`). It doesn't matter much because the script moves the file away, but Radarr needs a place to *think* the file goes.

### Step C: Configure qBittorrent
1.  Go to `http://<YOUR_VM_IP>:8080`
2.  Login: `admin` / `adminadmin`.
3.  **Tools** -> **Options** -> **Downloads**.
4.  Check **"Run external program on torrent completion"**.
5.  Paste this exact command:
    ```bash
    /scripts/qbit_manage.sh "%N" "%F" "%L"
    ```
6.  Click **Save**.

### Step D: Configure Jellyfin (The Streamer)

*Note: The code installed Jellyfin for you, but you must do the initial "Welcome" setup yourself.*

1.  **Open the Web Interface**:
    *   Go to `http://<YOUR_VM_IP>:8096` in your browser.
2.  **The Setup Wizard**:
    *   **Language**: Select your preferred language and click **Next**.
    *   **User Account**: Create a username and password (e.g., `admin`). You will use this to log in later.
3.  **Add Media Library** (The Important Part):
    *   It will ask to "Setup your media libraries". Click **+ Add Media Library**.
    *   **Content type**: Select **Movies**.
    *   **Display Name**: Type `Movies` (or whatever you like).
    *   **Folders**: Click the **+ (Plus)** button next to "Folders".
    *   **Select the Path**:
        *   You will see a list of folders. Click on `/` (Root).
        *   Scroll down and click on `data`.
        *   Click on `movies`.
        *   *Why this folder?* This is where our `rclone-mount` container is "projecting" your Google Drive files.
        *   Click **OK** once you are in `/data/movies`.
    *   Click **OK** again to save the library.
4.  **Finish Setup**:
    *   **Metadata Language**: Choose your language (English).
    *   **Remote Access**: Leave "Allow remote connections" **Checked** (Important!).
    *   Click **Finish**.
5.  **Login**:
    *   Log in with the user you just created.
    *   Give it a moment to scan your library. If you have files in the cloud, posters should start appearing!

---

## 8. How to Use

1.  Open **Jellyseerr** (`http://<YOUR_VM_IP>:5055`).
2.  Login and follow the setup wizard to connect it to your Radarr and Jellyfin.
3.  Search for a movie (e.g., "The Matrix").
4.  Click **Request**.
5.  **What happens next?**
    *   Jellyseerr tells Radarr.
    *   Radarr finds a torrent via Prowlarr.
    *   Radarr sends it to qBittorrent.
    *   qBittorrent downloads it to your VM.
    *   **Once finished**: The `radarr_manage.sh` script triggers.
    *   The script tells Rclone to move the file to your Google Drive `Movies` folder.
    *   The file is deleted from your VM to save space.
    *   **Watching**: Open Jellyfin, scan your library, and the movie will appear, streaming directly from the cloud!

---

## 9. Deep Dive: Understanding the Components

You might be wondering: "Why do we need so many services? What are they all doing?"

### A. Rclone: The "Uploader" vs. The "Virtual Drive"

Rclone is the most important tool here, and it does two very different jobs:

**1. The Uploader (Space Saver)**
*   **What it does:** When a movie finishes downloading, our scripts tell Rclone: *"Take this file and send it to Google Drive/OneDrive."*
*   **Why it's important:** This is why your VM (which only has 30GB-50GB space) never runs out of space, even if you have 1000 movies.
*   **Important Limitation (The Golden Rule):** The download happens on your **VM's disk** first. It is only moved to the cloud *after* it finishes.
    *   *Example*: If you have a **30GB** VM, you **cannot** download a **50GB** movie. The disk will fill up before the move happens.
    *   *Advice*: Keep your individual downloads smaller than your free disk space (e.g., stick to 10GB-20GB movies).
*   **How it works:** It uses the Rclone API to upload files in the background.

**2. The Virtual Drive (The "Mount")**
*   **The Problem:** Normally, if you want to watch a movie stored on Google Drive, you have to download it first.
*   **The Solution:** We use Rclone to "Mount" your Google Drive. This tricks your computer (and Jellyfin) into thinking Google Drive is just a regular **folder** on your hard drive.
*   **Why it's cool:** You can point Jellyfin to this "Folder", and it will play the movie **directly from the cloud** instantly, without downloading the whole thing again.

### B. Jellyseerr vs. Jellyfin

Many people get these confused. Here is the difference:

**1. Jellyseerr (The "Menu")**
*   **What it is:** A beautiful catalog of all movies and TV shows in existence (like the Netflix home screen).
*   **Purpose:** You use it to **find** things you want to watch. When you see a movie you like, you click a **"Request"** button.
*   **Analogy:** It is like the **Waiter** who takes your order at a restaurant.
*   *Note: You cannot watch movies on Jellyseerr.*

**2. Jellyfin (The "TV Screen")**
*   **What it is:** A media player/server (similar to Plex).
*   **Purpose:** It takes the video file that is stored in your cloud (via the Rclone Mount) and plays it on your browser, TV, or phone.
*   **Analogy:** It is like the **TV Screen** where you actually watch the show.

**So, the full flow is:**
1.  **You** tell the **Waiter (Jellyseerr)** what you want.
2.  The **Kitchen (Radarr/qBittorrent)** cooks it (downloads it).
3.  The **Delivery Guy (Rclone Uploader)** puts it in the **Freezer (Cloud Storage)**.
4.  When you want to eat, the **Magic Bridge (Rclone Mount)** brings it to your **TV (Jellyfin)** instantly!

---

## 10. Advanced: Power Saving & Manual Control

If you have a small VM (like the e2-medium), running everything at once might be heavy.
The good news is that **Jellyfin** (the streaming part) is separate from the **Downloaders** (Radarr/qBittorrent).

You can save CPU and RAM by turning on the "Streaming Mode" only when you want to watch a movie.

**Option A: Run Everything (Default)**
Use this if you want everything on all the time.
```bash
docker compose up -d
```

**Option B: Run ONLY the Download Tools (Save CPU)**
If you are just downloading movies and not watching anything right now, use this. It leaves Jellyfin and the Rclone Mount OFF.
```bash
docker compose up -d qbittorrent radarr prowlarr rclone aria2
```

**Option C: Turn OFF Jellyfin when you are done watching**
When you finish your movie, run this to stop the heavy services. Your downloads will still work in the background!
```bash
docker compose stop jellyfin rclone-mount
```

**Option D: Turn ON Jellyfin when you want to watch**
Ready for movie night? Turn the streaming services back on:
```bash
docker compose up -d jellyfin rclone-mount
```

Enjoy your flexible media server!

---

## 11. Understanding Your Dashboard (Homarr)

Think of **Homarr** as your "Control Center".

*   **Before Homarr**: You had to remember "Jellyfin is on port 8096", "Radarr is on 7878", "qBittorrent is 8080".
*   **With Homarr**: You just go to `http://<YOUR_VM_IP>:7575`. It gives you a beautiful screen with buttons for everything.

### Features
1.  **Launcher**: It has big icons. Click "Radarr" to open Radarr. Click "Jellyfin" to open Jellyfin.
2.  **Integration**: You can configure it to show you *live info* on the dashboard.
    *   *Example*: You can make the qBittorrent button show your current download speed!
    *   *Example*: You can make the Radarr button show how many movies are missing.
3.  **Customization**: You can drag and drop the icons to arrange them how you like.

### How to Add Your First App
When you first open Homarr, it might be empty or have default apps.
1.  Click the **Edit Mode** button (top right, usually a pencil icon).
2.  Click **Add Tile** -> **App**.
3.  **App Name**: Type `Jellyfin`.
4.  **Internal Address**: `http://jellyfin:8096` (This is how Homarr finds it inside Docker).
5.  **External Address**: `http://<YOUR_VM_IP>:8096` (This is how *you* find it).
6.  Click **Save**.
7.  Exit Edit Mode.

Now you have a one-click button to open your media player!

---

## 12. Port Reference & GCP Firewall Cheat Sheet

Use this list to know which port does what, and copy the code below to open them all in Google Cloud Firewall.

| Application | Port | Purpose |
| :--- | :--- | :--- |
| **Homarr** | `7575` | **Dashboard** (Start Here). Links to everything else. |
| **Jellyfin** | `8096` | **Streaming**. Watch your movies here. |
| **Jellyseerr** | `5055` | **Requests**. Browse movies and click "Request". |
| **Radarr** | `7878` | **Movie Manager**. Settings for movies. |
| **qBittorrent** | `8080` | **Downloader**. See download progress. |
| **Prowlarr** | `9696` | **Indexer Manager**. Connects torrent sites. |
| **Aria2** | `6880` | **Alternative Downloader** (AriaNg UI). |
| **Rclone WebUI** | `5572` | **Cloud Manager**. See your Google Drive files. |
| **Profilarr** | `5060` | **Profile Manager**. Advanced settings. |

### GCP Firewall Command
When creating your Firewall Rule in Google Cloud Console:
1.  **Name**: `allow-media-ports`
2.  **Targets**: `All instances in the network`
3.  **Source ranges**: `0.0.0.0/0`
4.  **Protocols and ports**: Paste exactly this list:
    ```
    7575,8096,5055,7878,8080,9696,6880,5572,5060
    ```

---

## 13. Finding Your Passwords & Keys

If you used the automated `deploy.sh` script, it generated some passwords for you (like the **Homarr Encryption Key** or **Aria2 Secret**).

**Where are they?**
They are safely stored in a file called `.env` in your project folder.

**How to see them:**
Run this command in your terminal:
```bash
cat .env
```

You will see a list like this:
```env
RCLONE_USER=admin
RCLONE_PASS=password
SECRET_ENCRYPTION_KEY=a1b2c3d4...  <-- This is your Homarr Key
RPC_SECRET=xyz...                  <-- This is your Aria2 Key
```
Copy what you need from there!

---

## 14. Troubleshooting: "Site Can't Be Reached"

If you deployed everything successfully but your browser says **"This site can't be reached"**, it is usually one of two simple problems.

### Problem 1: You are using the Wrong IP (Internal IP)
The script might tell you an IP address starting with `10.x.x.x` or `192.168.x.x`. This is the VM's **private** address. You cannot access this from your home computer.

**The Fix: Find your External IP**
1.  Go to the **Google Cloud Console**.
2.  Go to **Compute Engine** -> **VM Instances**.
3.  Look for the column named **External IP**.
4.  Copy that number (e.g., `34.123.45.67`).
5.  Use that in your browser: `http://34.123.45.67:7575`.

### Problem 2: The Firewall is Blocking You
By default, Google blocks all connections to your VM except SSH. Even if the server is running, the "door" is locked.

**The Fix: Open the Ports**
You must create the Firewall Rule mentioned in **Section 12**.
1.  Go to **VPC Network** -> **Firewall**.
2.  Click **Create Firewall Rule**.
3.  **Name**: `allow-media-ports`.
4.  **Targets**: Select `All instances in the network`.
5.  **Source IPv4 ranges**: Type `0.0.0.0/0`.
6.  **Protocols and ports**: Select **TCP** and paste this exact list:
    ```
    7575,8096,5055,7878,8080,9696,6880,5572,5060
    ```
7.  Click **Create**.
8.  Wait 1 minute and try your link again!

---

## 15. Restarting & Updating

If you need to restart your server or apply changes, be careful!

**The "Danger" of `docker compose up -d`**
If you run `docker compose up -d` by itself, it will try to start **EVERY** app in the file.
*   *Scenario*: You used the script to skip Jellyfin.
*   *Mistake*: You run `docker compose up -d`.
*   *Result*: **Jellyfin starts anyway**, using up your RAM.

**The Correct Way to Restart**
Always use the `deploy.sh` script again. It remembers the logic.
```bash
sudo ./deploy.sh
```
1.  Choose **Option 2 (Custom Installation)**.
2.  Enter the numbers of the apps you want to **SKIP**.
3.  It will restart only the apps you want.

**The Manual Way (For Experts)**
If you don't want to use the script, you must list every app you want to start:
```bash
docker compose up -d radarr qbittorrent rclone rclone-mount homarr
```
*(This is annoying to type, so just use the script!)*

### Problem 3: Everything seems fine, but still nothing?
If you are sure you have the right IP and the Firewall rule is correct, let's look inside the VM.

**Is Nginx needed?**
No. You do **NOT** need Nginx to access the dashboard via ports (like `:7575`). The script sets everything up directly.

**Diagnostic Steps:**
Run these commands in your VM terminal to see what is happening:

1.  **Check if the apps are actually running:**
    ```bash
    docker compose ps
    ```
    *   Look at the "State" column. It should say `Up`. If it says `Exit` or `Restarting`, the app crashed.

2.  **Check if the port is open:**
    ```bash
    sudo lsof -i :7575
    ```
    *   If you see output like `docker-pr ... LISTEN`, it means the server is ready and listening.
    *   If you see **nothing**, the app is not running.

**Common Mistake: The Firewall Target**
When you created the Google Firewall rule, go back and check the **"Targets"** setting.
*   **Correct**: `All instances in the network`
*   **Incorrect**: `Specified target tags` (If you chose this, the rule is active but **not applying to your VM**!)

---

## 16. File Locations (Where is everything?)

It can be confusing to know where files are, because Docker "maps" folders.

| What is it? | Location on YOUR VM (Host) | Location inside Docker (Container) |
| :--- | :--- | :--- |
| **Rclone Config** | `~/Rclone-Arr-Setup/configs/rclone/rclone.conf` | `/config/rclone/rclone.conf` |
| **Downloads** | `~/downloads` | `/downloads` |
| **Logs** | `~/Rclone-Arr-Setup/logs` | `/logs` |
| **Automation Scripts** | `~/Rclone-Arr-Setup/scripts` | `/scripts` |

**The Magic Link:**
When you see `-v ...:/...` in the code, it connects the **Left Side** (Your VM) to the **Right Side** (The Container).
So if you edit the file on your VM, the Container sees the change immediately!

### Problem 4: `rclone-mount` is Restarting (Name Mismatch)
If you run `docker compose ps` and see `rclone-mount` has state **Restarting**, it usually means the name in your `.env` doesn't match your config.

**Example:**
*   You told the script your remote is named `gdrive`.
*   But your `rclone.conf` has `[gdrive2tb001]`.

**The Fix:**
1.  Open your `.env` file: `nano .env`
2.  Find `RCLONE_REMOTE=gdrive`
3.  Change it to the name inside the brackets: `RCLONE_REMOTE=gdrive2tb001`
4.  Save and Restart: `docker compose up -d`

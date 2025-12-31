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
4.  **Machine Type**: `e2-medium` (2 vCPUs, 4GB RAM) is a good starting point. You can upgrade later if needed.
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

    Save and exit (Ctrl+O, Enter, Ctrl+X).

---

## 5. Setting up Rclone (Crucial Step)

This connects your server to your Cloud Storage (Google Drive, etc.).

1.  Create config directory:
    ```bash
    mkdir -p configs/rclone
    ```
2.  Run the interactive setup wizard:
    ```bash
    docker run --rm -it -v $(pwd)/configs/rclone:/config/rclone rclone/rclone config
    ```
3.  Follow the prompts:
    *   `n` for **New remote**.
    *   **name**: Enter the name you put in `.env` (e.g., `drive`).
    *   **Storage**: Choose your provider (e.g., `drive` for Google Drive).
    *   Follow the specific authentication steps for your provider.
        *   *Tip for Headless (Server) Setup*: Since your VM has no browser, when it asks "Use auto config?", say **No** (`n`). It will give you a command to run on your *local computer* to authorize access and give you a code to paste back into the terminal.

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
1.  Go to `http://<YOUR_VM_IP>:8096`.
2.  Follow the setup wizard.
3.  **Add Media Library**:
    *   Content type: **Movies**.
    *   Folders: Click **+** and navigate to `/data/movies`.
        *   *Note: If you don't see your cloud files yet, make sure you actually have files in your cloud storage!*
    *   Finish the setup.
4.  Now you can login and watch movies!

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

Enjoy your automated cloud media server!

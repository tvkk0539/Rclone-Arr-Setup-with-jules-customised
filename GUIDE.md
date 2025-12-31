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
    `7575,8080,6880,5572,7878,9696,5055,5060`
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
3.  **Setup the Custom Script (The Magic Part)**:
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

---

## 8. How to Use

1.  Open **Jellyseerr** (`http://<YOUR_VM_IP>:5055`).
2.  Login and follow the setup wizard to connect it to your Radarr.
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

Enjoy your automated cloud media server!

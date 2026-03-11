# 🎬 Arr Services with Rclone Integration

A complete Docker-based media server stack featuring automated downloads, cloud storage integration, and modern web interfaces. Perfect for managing your media collection with automated workflows and cloud backup.


> **⚠️ Disclaimer**: This project is for educational and personal use only. It is designed to help manage legally owned media content.


## ✨ Features

### Core Services
- **🎭 Radarr** - Movie collection management with automatic rclone uploads
- **🔍 Prowlarr** - Universal indexer manager
- **📡 qBittorrent + VueTorrent** - Modern torrent client with beautiful UI
- **⚡ Aria2 + AriaNg** - High-speed download manager with web interface
- **☁️ Rclone + WebUI** - Cloud storage integration with HTTP API
- **📂 File Browser** - Web-based file manager to access downloads remotely
- **🎯 Jellyseerr** - Request management for movies and TV shows
- **🏠 Homarr** - Beautiful dashboard for all services
- **📊 Profilarr** - Profile and quality management
- **🚢 Docker** - For containerizing and internal networking of Arr services

### Smart Upload Logic
- **Manual Downloads**: qBittorrent and Aria2 automatically upload non-media files to cloud storage
- **Media Downloads**: Radarr takes full control of media files and uploads organized content
- **Category-Based Processing**: Respects Radarr/Sonarr categories to avoid conflicts
- **Automatic Cleanup**: Empty folders are cleaned up after successful uploads

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose installed
- Basic understanding of Docker concepts
- Cloud storage provider supported by rclone (Google Drive, OneDrive, etc.)

### 1. Clone the Repository
```bash
git clone github.com/vinayak-7-0-3/Rclone-Arr-Setup
cd Rclone-Arr-Setup
```

### 2. Setup Environment
```bash
# Copy the sample environment file
cp sample.env .env

# Edit the environment file with your settings
nano .env
```

### 3. Configure Rclone
```bash
# Create rclone config directory
mkdir -p configs/rclone

# Configure your cloud storage (interactive setup)
docker run --rm -it -v $(pwd)/configs/rclone:/config/rclone rclone/rclone config

# Or copy your existing rclone.conf
cp ~/rclone.conf configs/rclone/rclone.conf
```

### 4. Start Services
```bash
# Create external network (if not exists) - use your network name
docker network create ${DOCKER_NETWORK}

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

## ⚙️ Configuration

### Environment Variables (.env)
Create your `.env` file with these variables:

```env
# Storage Paths
MEDIA_SERVER_ROOT=/path/to/Rclone-Arr-Setup   # this is the cloned repo root folder
DOWNLOADS_FOLDER=/path/to/downloads

# Rclone Configuration
RCLONE_REMOTE=your-remote-name
RCLONE_USER=your-username
RCLONE_PASS=your-password

# use your above created network here
DOCKER_NETWORK=nginx_network

# for Homarr
# visit their documentation for generating one key
# https://homarr.dev/docs/getting-started/installation/docker/#installation
SECRET_ENCRYPTION_KEY=

# Aria2 Configuration
RPC_SECRET=your-secret-key
```

### Service URLs (Default Ports)
After starting, access your services at:

- **Homarr Dashboard**: `http://localhost:7575`
- **File Browser**: `http://localhost:8081`
- **qBittorrent**: `http://localhost:8080`
- **AriaNg**: `http://localhost:6880`
- **Rclone WebUI**: `http://localhost:5572`
- **Radarr**: `http://localhost:7878`
- **Prowlarr**: `http://localhost:9696`
- **Jellyseerr**: `http://localhost:5055`
- **Profilarr**: `http://localhost:5060`

## 🔧 Service Configuration

### 1. Prowlarr Setup
1. Access Prowlarr web interface
2. Add your preferred indexers
3. Configure Radarr integration:
   - Add Radarr as an application
   - Use `http://radarr:7878` as the server URL
   - Get API key from Radarr settings

### 2. Radarr Setup
1. Access Radarr web interface
2. Add download clients:
   - **qBittorrent**: `http://qbittorrent:8080`
3. Configure custom script in Connect settings:
   - Path: `/scripts/radarr_manage.sh`
   - Triggers: On Download, On Upgrade

### 3. qBittorrent Setup
1. Access qBittorrent web interface
2. Go to Options → Downloads → Run external program
3. Add: `/scripts/qbit_manage.sh "%N" "%F" "%L"`
4. Set categories:
   - Create `radarr` category for Radarr downloads
   - Manual downloads can use any other category

### 4. Aria2 Setup
1. Edit `configs/aria2/aria2.conf`
2. Add post-processing hook:
   ```
   on-download-complete=/scripts/aria_manage.sh
   ```
3. Restart aria2 container: `docker-compose restart aria2`

### 5. Rclone Setup
- Your rclone config should be in `configs/rclone/rclone.conf`
- The HTTP API is automatically configured with your credentials
- WebUI available for manual operations and monitoring

## 📁 Folder Structure

```
arr-services/
├── docker-compose.yml
├── .env
├── sample.env
├── README.md
├── configs/
│   ├── qBittorrent/         # qBittorrent config (auto-created)
│   ├── aria2/               # Aria2 config (auto-created)
│   ├── rclone/              # Place your rclone.conf here
│   ├── radarr/              # Radarr config (auto-created)
│   ├── prowlarr/            # Prowlarr config (auto-created)
│   ├── homarr/              # Homarr config (auto-created)
│   ├── jellyseer/           # Jellyseerr config (auto-created)
│   └── profilarr/           # Profilarr config (auto-created)
├── scripts/
│   ├── aria_manage.sh       # Aria2 post-processing
│   ├── qbit_manage.sh       # qBittorrent post-processing
│   └── radarr_manage.sh     # Radarr post-processing
└── logs/                    # Application logs
```

## 🔄 How It Works

### Upload Logic
1. **Media Files**: Detected by filename patterns (TODO)
   - Moved to completed folder for Radarr processing
   - Radarr organizes and uploads to `Movies/` folder
   
1. **For Manual Uploads**
   - Directly uploaded to `UnSorted/` folder
   - Immediate cloud storage transfer

2. **Category-Based**: qBittorrent respects categories
   - Radarr/Sonarr send torrent with category to download clients
   - `radarr`/`sonarr` categories → Wait for Arr processing
   - Other categories → Direct upload

## 🛠️ Troubleshooting

### Common Issues

**Services not starting?**
```bash
# Check logs
docker-compose logs [service-name]

# Check network
docker network ls | grep <your-docker-network>
```

**Rclone not working?**
```bash
# Test rclone config
docker exec rclone rclone lsd your-remote-name:
```

**Scripts not executing?**
```bash
# Check script permissions
ls -la scripts/
chmod +x scripts/*.sh
```

**Upload failures?**
```bash
# Check logs
tail -f logs/qbit_postprocess.log
tail -f logs/aria2_postprocess.log
tail -f logs/radarr_postprocess.log
```

### Log Files
- qBittorrent: `/logs/qbit_postprocess.log`
- Aria2: `/logs/aria2_postprocess.log`
- Radarr: `/logs/radarr_postprocess.log`

## 📋 TODO - Future Implementations

- [ ] **Full fledge guide** showing every tips and tricks
- [ ] **Add Sonarr** for TV show management
- [ ] **Add Lidarr** for music collection management
- [ ] **Smart Media Detection** - Auto-route manual downloads to appropriate Arr services
- [ ] **Nginx Proxy Manager** for reverse proxy and SSL certificates
- [ ] **File Browser** for web-based file management
- [ ] **Jellyfin** media server integration
- [ ] **Bazarr** for subtitle management

## 🤝 Contributing

### Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## ⭐ Show Your Support

If this project helped you set up your media server, please consider:

- ⭐ **Star this repository** - It helps others discover the project!
- 🔄 **Share with friends** - Spread the word about automated media management
- 🐛 **Report issues** - Help make this project better for everyone
- 💡 **Suggest features** - What would make this even more awesome?
- 📖 **Improve docs** - Found something unclear? PRs welcome!


## For More Help
**Visit our telegram group**

[![Static Badge](https://img.shields.io/badge/support-pink?style=for-the-badge)](https://t.me/weebzgroup)

---

**Happy streaming! 🍿**
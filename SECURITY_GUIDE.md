# Security & Networking Guide for Beginners

This guide explains the "Why" and "How" of network security on Google Cloud Platform (GCP), specifically for your media server project.

---

## 1. The "Open Door" Policy (Firewalls)

When you create a Firewall Rule in GCP (like the one with 20 ports we discussed), you are essentially drilling holes in the wall protecting your server.

### The "One Big Rule" Approach
You created a single rule that opens **TCP & UDP** for many ports (`3128, 3389, 7575, 8080...`) to **0.0.0.0/0** (The entire world).

**Is this okay?**
*   **For Learning:** Yes, it is convenient. You don't have to manage 10 different rules.
*   **For Production:** It is risky.

### The Risks
1.  **Unnecessary Exposure**:
    *   You opened **Port 3389 (RDP/Remote Desktop)**. This is a favorite target for hackers. If you ever install a Windows VM or an RDP tool on this network, hackers will try to brute-force the password immediately.
    *   You opened **Port 3128 (Squid Proxy)**. If your proxy doesn't have a password, people can use *your* server to browse the web illegally, and *you* get the blame.
2.  **Global Scope**:
    *   Your rule targets `All instances in the network`.
    *   If you create a **second VM** (e.g., a private database), this firewall rule applies to it too! You might accidentally expose your database because of the rule you made for your media server.

### The "Pro" Way: Target Tags
Instead of applying rules to "All instances", you can use **Tags**.

**Example:**
1.  **Tag your Media VM**: Go to VM Settings -> Edit -> Network Tags -> Add `media-server`.
2.  **Tag your Proxy VM**: Add `proxy-server`.
3.  **Create Rule A**: Open ports `7575, 8080` only for Target Tag `media-server`.
4.  **Create Rule B**: Open ports `3128` only for Target Tag `proxy-server`.

**Result**: Your Proxy VM doesn't have media ports open, and your Media VM doesn't have proxy ports open. Much safer!

---

## 2. TCP vs. UDP

You asked if enabling both TCP and UDP for all apps is okay.

*   **TCP (Transmission Control Protocol)**:
    *   Think of it like a **Phone Call**. "Hello? Can you hear me? Yes. Okay, here is the data."
    *   **Used by**: Websites (HTTP), Dashboards (Homarr, Radarr), SSH, RDP.
    *   **Your Apps**: 99% of your apps (7575, 7878, 8080) *only* use TCP. Opening UDP for them does nothing (it's like opening a door that leads to a brick wall).

*   **UDP (User Datagram Protocol)**:
    *   Think of it like **Mailing a Letter**. You send it and hope it arrives. It's faster because you don't wait for a "Hello".
    *   **Used by**: Streaming (sometimes), Gaming, Torrenting (finding peers).
    *   **Your Apps**: qBittorrent uses UDP (usually port 6881) to talk to other downloaders faster.

**Conclusion**: Opening UDP for your dashboards (7575) is harmless but useless. Opening UDP for qBittorrent is helpful.

---

## 3. Essential Security Checklist

Since your ports are open to the world (`0.0.0.0/0`), your **only defense** is the Login Screen of each app.

1.  **qBittorrent**:
    *   Default User: `admin`
    *   Default Pass: `adminadmin`
    *   **ACTION**: Change this immediately in `Tools -> Options -> Web UI`.

2.  **Radarr / Prowlarr / Sonarr**:
    *   Default: **No Password** (Anyone can delete your movies!).
    *   **ACTION**: Go to `Settings -> General -> Security`. Change "Authentication" to **Forms** (Login Page) and set a username/password.

3.  **Rclone WebUI**:
    *   You set this in `deploy.sh`. Make sure it's strong!

4.  **Squid / Dante (Proxies)**:
    *   **CRITICAL**: Never run an "Open Proxy" (no password) on the internet. Bots will find it in minutes and use it for spam. Always enable authentication.

Stay safe!

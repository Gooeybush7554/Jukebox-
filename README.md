# 📻 Jukebox.sh

A lightweight, terminal-based jukebox and radio stream controller powered by Bash and `mpv` inside Termux.

## 🚀 Features
- **Centralized Audio Engine:** Consolidated playback functions to reduce duplicate code.
- **IPC Socket Control:** Synchronized socket handling for safe track and stream switching.
- **Smart Stream Buffering:** Built-in 10-second cache protection to prevent stream dropouts.
- **Zero Terminal Clutter:** Background processes run cleanly without generating `nohup.out` logs.
- **Self-Healing Dependencies:** Automatically detects and installs missing packages on startup.

## 🛠️ Requirements
The script automatically manages its own dependencies. If you ever need to install components manually in Termux, use:
- **Command:** `pkg install mpv socat yt-dlp streamripper sox -y`

## 📂 Project Structure
- `Jukebox.sh` - The main interactive menu script with built-in auto-installer.
- `README.md` - This documentation and setup guide.
- `backup_jukebox.sh` - Automated backup script.

## 🎛️ How It Works
1. **Dependency Check:** On startup, the script verifies if `mpv`, `socat`, `yt-dlp`, `streamripper`, and `sox` are installed. If any are missing, it updates Termux repositories and installs them seamlessly.
2. **Teardown:** Kills exact active `mpv` binary instances and purges old IPC sockets.
3. **Buffer Management:** Spawns a background `mpv` instance with explicit network caching.
4. **Synchronization:** Holds the UI menu response briefly until the fresh IPC socket registers.
#!/bin/bash
# --- Jukebox Backup Utility ---

BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="jukebox_backup_${TIMESTAMP}.tar.gz"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo -e "\e[1;34m[!] Archiving Jukebox files...\e[0m"

# Compress script files
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}" Jukebox.sh README.md 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "\e[1;32m[+] Backup successful: ${BACKUP_DIR}/${BACKUP_NAME}\e[0m"
else
    echo -e "\e[1;31m[-] Backup failed!\e[0m"
fi

To use it: Run chmod +x backup_jukebox.sh then execute it with ./backup_jukebox.sh
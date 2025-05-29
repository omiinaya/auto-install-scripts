#!/bin/bash
# Line 1
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Automatically detects the container's storage from its configuration
# Skips stop if container is already stopped, uses exact backup filename
# Usage: ./change_ct_id.sh <current_ct_id> <new_ct_id>

# Line 7: Check if exactly 2 arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <current_ct_id> <new_ct_id>"
    exit 1
fi

# Line 12: Define variables
CURRENT_CT_ID="$1"
NEW_CT_ID="$2"

# Line 16: Validate that both arguments are positive integers
if ! [[ "$CURRENT_CT_ID" =~ ^[0-9]+$ ]] || ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Both CT IDs must be positive integers."
    exit 1
fi

# Line 21: Define backup storage and existing backup file
BACKUP_STORAGE="local"
BACKUP_DIR="/var/lib/vz/dump"
EXISTING_BACKUP="$BACKUP_DIR/vzdump-lxc-$CURRENT_CT_ID-2025_05_28-21_49_00.tar.zst"

# Line 26: Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Line 31: Check if Proxmox tools are available
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1; then
    echo "Error: Proxmox tools (pct or vzdump) not found. Is this a Proxmox system?"
    exit 1
fi

# Line 36: Check if the current CT ID exists
if ! pct status "$CURRENT_CT_ID" >/dev/null 2>&1; then
    echo "Error: Container with ID $CURRENT_CT_ID does not exist."
    exit 1
fi

# Line 41: Check if the new CT ID is already in use
if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
    echo "Error: Container with ID $NEW_CT_ID already exists."
    exit 1
fi

# Line 46: Check if backup storage exists
if ! pvesm status | grep -q "^$BACKUP_STORAGE"; then
    echo "Error: Backup storage '$BACKUP_STORAGE' not found."
    exit 1
fi

# Line 51: Detect container storage from configuration
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Line 57: Extract storage from rootfs line
CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    echo "Error: Could not detect container storage from $CONFIG_FILE."
    exit 1
fi

# Line 62: Verify container storage exists
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    echo "Error: Container storage '$CONTAINER_STORAGE' not found."
    exit 1
fi
echo "Detected container storage: $CONTAINER_STORAGE"

# Line 68: Check if the container is unprivileged
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    echo "Detected unprivileged container. Will use --unprivileged flag for restore."
fi

# Line 74: Stop the container if running
echo "Checking container $CURRENT_CT_ID status..."
STATUS=$(pct status "$CURRENT_CT_ID" 2>/dev/null)
if echo "$STATUS" | grep -q "status: running"; then
    echo "Stopping container $CURRENT_CT_ID..."
    pct stop "$CURRENT_CT_ID" || {
        echo "Error: Failed to stop container $CURRENT_CT_ID."
        exit 1
    }
else
    echo "Container $CURRENT_CT_ID is already stopped (status: $STATUS)."
fi

# Line 85: Check for existing backup or create a new one
BACKUP_FILE="$EXISTING_BACKUP"
echo "Checking for existing backup: $BACKUP_FILE..."
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Existing backup not found. Checking permissions and path..."
    ls -l "$BACKUP_DIR" 2>/dev/null || echo "Error: Cannot access $BACKUP_DIR"
    echo "Creating new backup of container $CURRENT_CT_ID..."
    # Run vzdump and capture its output to get the exact filename
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    if [ $VZDUMP_STATUS -ne 0 ]; then
        echo "Error: Backup failed for container $CURRENT_CT_ID."
        echo "$VZDUMP_OUTPUT"
        exit 1
    fi
    # Extract the backup filename from vzdump output
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: No backup file found after vzdump. Expected in $BACKUP_DIR."
        ls -l "$BACKUP_DIR" 2>/dev/null
        exit 1
    fi
    echo "New backup created: $BACKUP_FILE"
fi

# Line 104: Delete the original container
echo "Deleting original container $CURRENT_CT_ID..."
pct destroy "$CURRENT_CT_ID" || {
    echo "Error: Failed to delete container $CURRENT_CT_ID."
    exit 1
}

# Line 110: Restore the container with the new CT ID
echo "Restoring container as $NEW_CT_ID..."
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    echo "Error: Failed to restore container as $NEW_CT_ID."
    exit 1
}

# Line 116: Start the new container
echo "Starting container $NEW_CT_ID..."
pct start "$NEW_CT_ID" || {
    echo "Error: Failed to start container $NEW_CT_ID."
    exit 1
}

# Line 122: Verify the container is running
if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    echo "Success: Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running."
else
    echo "Warning: Container $NEW_CT_ID restored but not running. Check logs with 'journalctl -u pve*'."
    exit 1
fi

# Line 129: Optional cleanup (commented out)
# echo "Cleaning up backup file $BACKUP_FILE..."
# rm -f "$BACKUP_FILE"

# Line 132: Exit successfully
exit 0
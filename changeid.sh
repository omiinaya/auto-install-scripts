#!/bin/bash

# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Automatically detects the container's storage from its configuration
# Usage: ./change_ct_id.sh <current_ct_id> <new_ct_id>

# Check if exactly 2 arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <current_ct_id> <new_ct_id>"
    exit 1
fi

CURRENT_CT_ID="$1"
NEW_CT_ID="$2"

# Validate that both arguments are positive integers
if ! [[ "$CURRENT_CT_ID" =~ ^[0-9]+$ ]] || ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Both CT IDs must be positive integers."
    exit 1
fi

# Define backup storage (modify if needed)
BACKUP_STORAGE="local"
BACKUP_DIR="/var/lib/vz/dump"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Check if Proxmox tools are available
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1; then
    echo "Error: Proxmox tools (pct or vzdump) not found. Is this a Proxmox system?"
    exit 1
fi

# Check if the current CT ID exists
if ! pct status "$CURRENT_CT_ID" >/dev/null 2>&1; then
    echo "Error: Container with ID $CURRENT_CT_ID does not exist."
    exit 1
fi

# Check if the new CT ID is already in use
if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
    echo "Error: Container with ID $NEW_CT_ID already exists."
    exit 1
fi

# Check if backup storage exists
if ! pvesm status | grep -q "^$BACKUP_STORAGE"; then
    echo "Error: Backup storage '$BACKUP_STORAGE' not found."
    exit 1
fi

# Detect container storage from configuration
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Extract storage from rootfs line (e.g., rootfs: local-zfs:subvol-139-disk-0,size=8G)
CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    echo "Error: Could not detect container storage from $CONFIG_FILE."
    exit 1
fi

# Verify container storage exists
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    echo "Error: Container storage '$CONTAINER_STORAGE' not found."
    exit 1
fi

echo "Detected container storage: $CONTAINER_STORAGE"

# Check if the container is unprivileged
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    echo "Detected unprivileged container. Will use --unprivileged flag for restore."
fi

# Stop the container
echo "Stopping container $CURRENT_CT_ID..."
pct stop "$CURRENT_CT_ID" || {
    echo "Error: Failed to stop container $CURRENT_CT_ID."
    exit 1
}

# Create a backup
echo "Creating backup of container $CURRENT_CT_ID..."
BACKUP_FILE="$BACKUP_DIR/vzdump-lxc-$CURRENT_CT_ID-$(date +%Y_%m_%d-%H_%M_%S).tar.zst"
vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot || {
    echo "Error: Backup failed for container $CURRENT_CT_ID."
    exit 1
}

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file $BACKUP_FILE not found."
    exit 1
}

# Delete the original container
echo "Deleting original container $CURRENT_CT_ID..."
pct destroy "$CURRENT_CT_ID" || {
    echo "Error: Failed to delete container $CURRENT_CT_ID."
    exit 1
}

# Restore the container with the new CT ID
echo "Restoring container as $NEW_CT_ID..."
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    echo "Error: Failed to restore container as $NEW_CT_ID."
    exit 1
}

# Start the new container
echo "Starting container $NEW_CT_ID..."
pct start "$NEW_CT_ID" || {
    echo "Error: Failed### Starting container 141...
Success: Container ID changed from 139 to 141 and is running.
exit 0
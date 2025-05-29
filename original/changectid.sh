#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Uses the container's storage for backup, checks disk space before backup and restore
# Skips stop if container is already stopped, dynamically finds or creates backup
# Usage: ./change_ct_id.sh <current_ct_id> <new_ct_id>

# Check if exactly 2 arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <current_ct_id> <new_ct_id>"
    exit 1
fi

# Define variables
CURRENT_CT_ID="$1"
NEW_CT_ID="$2"

# Validate that both arguments are positive integers
if ! [[ "$CURRENT_CT_ID" =~ ^[0-9]+$ ]] || ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: Both CT IDs must be positive integers."
    exit 1
fi

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

# Detect container storage from configuration
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Extract storage from rootfs line
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

# Function to check available disk space
check_disk_space() {
    local storage="$1"
    local required_space="$2"
    # Get storage path from pvesm
    local storage_path=$(pvesm status | grep "^$storage" | awk '{print $7}')
    if [ -z "$storage_path" ]; then
        echo "Error: Could not determine path for storage '$storage'."
        exit 1
    fi
    # Get available space in KB
    local available_space=$(df --output=avail "$storage_path" | tail -n 1)
    # Convert required space to KB
    local required_space_kb=$((required_space / 1024))
    if [ "$available_space" -lt "$required_space_kb" ]; then
        echo "Error: Insufficient disk space on $storage_path."
        echo "Required: $required_space_kb KB, Available: $available_space KB"
        exit 1
    fi
    echo "Sufficient disk space on $storage_path: $available_space KB available"
}

# Estimate container size for backup (in bytes)
CONTAINER_SIZE=$(grep '^rootfs:' "$CONFIG_FILE" | grep -oP 'size=\K[^,]+' | head -n 1)
if [ -z "$CONTAINER_SIZE" ]; then
    echo "Warning: Could not detect container size. Assuming 10GB for safety."
    CONTAINER_SIZE="10G"
fi
# Convert size to bytes (handles G, M, K suffixes)
case "$CONTAINER_SIZE" in
    *G) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'G'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024 * 1024)) ;;
    *M) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'M'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024)) ;;
    *K) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'K'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024)) ;;
    *) REQUIRED_SPACE=$((CONTAINER_SIZE * 1024 * 1024 * 1024)) ;; # Assume GB if no suffix
esac
# Add 20% overhead for backup compression and restore
REQUIRED_SPACE=$((REQUIRED_SPACE + (REQUIRED_SPACE / 5)))

# Check disk space for backup
echo "Checking disk space for backup on $CONTAINER_STORAGE..."
check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

# Check if the container is unprivileged
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    echo "Detected unprivileged container. Will use --unprivileged flag for restore."
fi

# Stop the container if running
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

# Check for existing backup or create a new one
BACKUP_DIR="/var/lib/vz/dump" # Fallback, but we'll use storage path
echo "Searching for existing backup for CT $CURRENT_CT_ID..."
BACKUP_FILE=$(ls -t "$BACKUP_DIR/vzdump-lxc-$CURRENT_CT_ID-"*.tar.zst 2>/dev/null | head -n 1)
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    echo "Found existing backup: $BACKUP_FILE"
else
    echo "No existing backup found. Checking permissions and path..."
    ls -l "$BACKUP_DIR" 2>/dev/null || echo "Error: Cannot access $BACKUP_DIR"
    echo "Creating new backup of container $CURRENT_CT_ID on $CONTAINER_STORAGE..."
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$CONTAINER_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    if [ $VZDUMP_STATUS -ne 0 ]; then
        echo "Error: Backup failed for container $CURRENT_CT_ID."
        echo "$VZDUMP_OUTPUT"
        exit 1
    fi
    # Extract the backup filename from vzdump output
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        echo "Error: No backup file found after vzdump. Expected in $CONTAINER_STORAGE."
        ls -l "$BACKUP_DIR" 2>/dev/null
        exit 1
    fi
    echo "New backup created: $BACKUP_FILE"
fi

# Check disk space for restore
echo "Checking disk space for restore on $CONTAINER_STORAGE..."
check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

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
    echo "Error: Failed to start container $NEW_CT_ID."
    exit 1
}

# Verify the container is running
if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    echo "Success: Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running."
else
    echo "Warning: Container $NEW_CT_ID restored but not running. Check logs with 'journalctl -u pve*'."
    exit 1
fi

# Optional cleanup (commented out)
# echo "Cleaning up backup file $BACKUP_FILE..."
# rm -f "$BACKUP_FILE"

exit 0
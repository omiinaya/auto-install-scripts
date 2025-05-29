#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore with a whiptail menu
# Lists available containers, prompts for new ID, and checks for conflicts
# Automatically detects the container's storage from its configuration
# Skips stop if container is already stopped, dynamically finds or creates backup

# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Error: whiptail is required but not installed. Install it with 'apt install whiptail'."
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    whiptail --title "Error" --msgbox "This script must be run as root." 8 60
    exit 1
fi

# Check if Proxmox tools are available
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1; then
    whiptail --title "Error" --msgbox "Proxmox tools (pct or vzdump) not found. Is this a Proxmox system?" 8 60
    exit 1
fi

# Get list of containers
CONTAINERS=()
while read -r ctid status; do
    if [[ -n "$ctid" && "$ctid" =~ ^[0-9]+$ ]]; then
        name=$(pct config "$ctid" | grep -E '^hostname:' | awk '{print $2}' || echo "Unnamed")
        CONTAINERS+=("$ctid" "$name ($ctid) - $status")
    fi
done < <(pct list | tail -n +2 | awk '{print $1 " " $3}')

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    whiptail --title "Error" --msgbox "No containers found on this system." 8 60
    exit 1
fi

# Prompt user to select a container
CURRENT_CT_ID=$(whiptail --title "Select Container" --menu "Choose a container to change its ID:" 20 80 10 "${CONTAINERS[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$CURRENT_CT_ID" ]; then
    whiptail --title "Cancelled" --msgbox "Operation cancelled by user." 8 60
    exit 1
fi

# Check if the current CT ID exists
if ! pct status "$CURRENT_CT_ID" >/dev/null 2>&1; then
    whiptail --title "Error" --msgbox "Container with ID $CURRENT_CT_ID does not exist." 8 60
    exit 1
fi

# Prompt for new CT ID
while true; do
    NEW_CT_ID=$(whiptail --title "Enter New ID" --inputbox "Enter the new container ID for CT $CURRENT_CT_ID:" 8 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        whiptail --title "Cancelled" --msgbox "Operation cancelled by user." 8 60
        exit 1
    fi

    # Validate new ID is a positive integer
    if ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
        whiptail --title "Error" --msgbox "New CT ID must be a positive integer." 8 60
        continue
    fi

    # Check if new CT ID is already in use
    if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
        whiptail --title "Error" --msgbox "Container with ID $NEW_CT_ID already exists. Choose another ID." 8 60
        continue
    fi
    break
done

# Confirm action
if ! whiptail --title "Confirm" --yesno "Change container ID from $CURRENT_CT_ID to $NEW_CT_ID?\nThis will stop, back up, delete, and restore the container." 10 60; then
    whiptail --title "Cancelled" --msgbox "Operation cancelled by user." 8 60
    exit 1
fi

# Define backup storage
BACKUP_STORAGE="local"
BACKUP_DIR="/var/lib/vz/dump"

# Check if backup storage exists
if ! pvesm status | grep -q "^$BACKUP_STORAGE"; then
    whiptail --title "Error" --msgbox "Backup storage '$BACKUP_STORAGE' not found." 8 60
    exit 1
fi

# Detect container storage from configuration
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    whiptail --title "Error" --msgbox "Configuration file $CONFIG_FILE not found." 8 60
    exit 1
fi

# Extract storage from rootfs line
CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    whiptail --title "Error" --msgbox "Could not detect container storage from $CONFIG_FILE." 8 60
    exit 1
fi

# Verify container storage exists
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    whiptail --title "Error" --msgbox "Container storage '$CONTAINER_STORAGE' not found." 8 60
    exit 1
fi
whiptail --title "Info" --msgbox "Detected container storage: $CONTAINER_STORAGE" 8 60

# Check if the container is unprivileged
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    whiptail --title "Info" --msgbox "Detected unprivileged container. Will use --unprivileged flag for restore." 8 60
fi

# Stop the container if running
whiptail --title "Info" --msgbox "Checking container $CURRENT_CT_ID status..." 8 60
STATUS=$(pct status "$CURRENT_CT_ID" 2>/dev/null)
if echo "$STATUS" | grep -q "status: running"; then
    whiptail --title "Info" --msgbox "Stopping container $CURRENT_CT_ID..." 8 60
    pct stop "$CURRENT_CT_ID" || {
        whiptail --title "Error" --msgbox "Failed to stop container $CURRENT_CT_ID." 8 60
        exit 1
    }
else
    whiptail --title "Info" --msgbox "Container $CURRENT_CT_ID is already stopped (status: $STATUS)." 8 60
fi

# Check for existing backup or create a new one
whiptail --title "Info" --msgbox "Searching for existing backup for CT $CURRENT_CT_ID..." 8 60
BACKUP_FILE=$(ls -t "$BACKUP_DIR/vzdump-lxc-$CURRENT_CT_ID-"*.tar.zst 2>/dev/null | head -n 1)
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    whiptail --title "Info" --msgbox "Found existing backup: $BACKUP_FILE" 8 60
else
    whiptail --title "Info" --msgbox "No existing backup found. Creating new backup of container $CURRENT_CT_ID..." 8 60
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    if [ $VZDUMP_STATUS -ne 0 ]; then
        whiptail --title "Error" --msgbox "Backup failed for container $CURRENT_CT_ID.\n$VZDUMP_OUTPUT" 10 60
        exit 1
    fi
    # Extract the backup filename from vzdump output
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        whiptail --title "Error" --msgbox "No backup file found after vzdump. Expected in $BACKUP_DIR." 8 60
        exit 1
    fi
    whiptail --title "Info" --msgbox "New backup created: $BACKUP_FILE" 8 60
fi

# Delete the original container
whiptail --title "Info" --msgbox "Deleting original container $CURRENT_CT_ID..." 8 60
pct destroy "$CURRENT_CT_ID" || {
    whiptail --title "Error" --msgbox "Failed to delete container $CURRENT_CT_ID." 8 60
    exit 1
}

# Restore the container with the new CT ID
whiptail --title "Info" --msgbox "Restoring container as $NEW_CT_ID..." 8 60
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    whiptail --title "Error" --msgbox "Failed to restore container as $NEW_CT_ID." 8 60
    exit 1
}

# Start the new container
whiptail --title "Info" --msgbox "Starting container $NEW_CT_ID..." 8 60
pct start "$NEW_CT_ID" || {
    whiptail --title "Error" --msgbox "Failed to start container $NEW_CT_ID." 8 60
    exit 1
}

# Verify the container is running
if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    whiptail --title "Success" --msgbox "Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running." 8 60
else
    whiptail --title "Warning" --msgbox "Container $NEW_CT_ID restored but not running. Check logs with 'journalctl -u pve*'." 8 60
    exit 1
fi

# Optional cleanup (commented out)
# whiptail --title "Info" --msgbox "Cleaning up backup file $BACKUP_FILE..." 8 60
# rm -f "$BACKUP_FILE"

exit 0
#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Uses whiptail to select the current container and new CT ID
# Robust error handling, logging, and disk space checks

LOG_FILE="/var/log/change_ct_id.log"
VERBOSE=0

# Parse --verbose flag
for arg in "$@"; do
    if [ "$arg" = "--verbose" ]; then
        VERBOSE=1
        shift
    fi
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

debug_log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[DEBUG] $*" | tee -a "$LOG_FILE"
    fi
}

# Check for whiptail
if ! command -v whiptail >/dev/null 2>&1; then
    log "Error: whiptail not found. Please install it with 'apt install whiptail'."
    exit 2
fi

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    log "Error: This script must be run as root."
    exit 1
fi

# Check for Proxmox tools
for tool in pct vzdump pvesm; do
    if ! command -v $tool >/dev/null 2>&1; then
        log "Error: Proxmox tool '$tool' not found. Is this a Proxmox system?"
        exit 2
    fi
done

# Get containers for menu
CONTAINERS=$(pct list | tail -n +2 | awk '{print $1 " ["$2"] "$3}')
if [ -z "$CONTAINERS" ]; then
    log "Error: No containers found on this system."
    exit 1
fi
MENU_OPTIONS=()
while read -r line; do
    CT_ID=$(echo "$line" | awk '{print $1}')
    DESC=$(echo "$line" | cut -d' ' -f2-)
    MENU_OPTIONS+=("$CT_ID" "$DESC")
done <<< "$CONTAINERS"

CURRENT_CT_ID=$(whiptail --title "Select Container" --menu "Choose a container to change its ID:" 20 70 10 "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Menu cancelled."
    exit 1
fi
log "Selected container: $CURRENT_CT_ID"

if ! pct status "$CURRENT_CT_ID" >/dev/null 2>&1; then
    log "Error: Container with ID $CURRENT_CT_ID does not exist."
    exit 1
fi

NEW_CT_ID=$(whiptail --title "Enter New Container ID" --inputbox "Enter the new ID for container $CURRENT_CT_ID:" 10 40 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Input cancelled."
    exit 1
fi
if [ -z "$NEW_CT_ID" ] || ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
    log "Error: New CT ID must be a positive integer."
    exit 1
fi
if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
    log "Error: Container with ID $NEW_CT_ID already exists."
    exit 1
fi
log "New container ID: $NEW_CT_ID"

CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    log "Error: Configuration file $CONFIG_FILE not found."
    exit 2
fi

CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    log "Error: Could not detect container storage from $CONFIG_FILE."
    exit 2
fi
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    log "Error: Container storage '$CONTAINER_STORAGE' not found."
    exit 2
fi
log "Detected container storage: $CONTAINER_STORAGE"

# Disk space check function
check_disk_space() {
    local storage="$1"
    local required="$2"
    local storage_path=$(pvesm status | grep "^$storage" | awk '{print $7}')
    if [ -z "$storage_path" ]; then
        log "Error: Could not determine path for storage '$storage'."
        exit 2
    fi
    local available=$(df --block-size=1 --output=avail "$storage_path" | tail -n 1)
    if [ "$available" -lt "$required" ]; then
        log "Error: Insufficient disk space on $storage_path. Required: $((required / 1024 / 1024)) MB, Available: $((available / 1024 / 1024)) MB"
        exit 2
    fi
    log "Sufficient disk space on $storage_path: $((available / 1024 / 1024)) MB available"
}

# Estimate container size
CONTAINER_DISK=$(pvesm list "$CONTAINER_STORAGE" | grep "lxc/$CURRENT_CT_ID/" | awk '{print $2}' | head -n 1)
if [ -n "$CONTAINER_DISK" ]; then
    REQUIRED_SPACE=$CONTAINER_DISK
else
    CONTAINER_SIZE=$(grep '^rootfs:' "$CONFIG_FILE" | grep -oP 'size=\K[^,]+' | head -n 1)
    if [ -n "$CONTAINER_SIZE" ]; then
        case "$CONTAINER_SIZE" in
            *G) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'G'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024 * 1024)) ;;
            *M) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'M'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024)) ;;
            *K) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'K'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024)) ;;
            *) REQUIRED_SPACE=$((CONTAINER_SIZE * 1024 * 1024 * 1024)) ;;
        esac
    else
        REQUIRED_SPACE=$((10 * 1024 * 1024 * 1024))
    fi
fi
REQUIRED_SPACE=$((REQUIRED_SPACE + (REQUIRED_SPACE / 5)))

check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

# Use container storage for backup
BACKUP_STORAGE="$CONTAINER_STORAGE"
check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE"

UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    log "Detected unprivileged container. Will use --unprivileged flag for restore."
fi

STATUS=$(pct status "$CURRENT_CT_ID" 2>/dev/null)
if echo "$STATUS" | grep -q "status: running"; then
    log "Stopping container $CURRENT_CT_ID..."
    pct stop "$CURRENT_CT_ID" || { log "Error: Failed to stop container $CURRENT_CT_ID."; exit 2; }
    log "Stopped CT $CURRENT_CT_ID"
else
    log "Container $CURRENT_CT_ID is already stopped (status: $STATUS)."
fi

log "Searching for existing backup for CT $CURRENT_CT_ID..."
BACKUP_FILE=$(pvesm list "$BACKUP_STORAGE" | grep "vzdump-lxc-$CURRENT_CT_ID-" | awk '{print $1}' | head -n 1)
if [ -n "$BACKUP_FILE" ]; then
    BACKUP_PATH=$(pvesm path "$BACKUP_FILE")
    if [ -f "$BACKUP_PATH" ]; then
        log "Found existing backup: $BACKUP_PATH"
    else
        BACKUP_FILE=""
    fi
fi
if [ -z "$BACKUP_FILE" ]; then
    log "No existing backup found. Creating new backup on $BACKUP_STORAGE..."
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    if [ $VZDUMP_STATUS -ne 0 ]; then
        log "Error: Backup failed for container $CURRENT_CT_ID."
        log "$VZDUMP_OUTPUT"
        exit 2
    fi
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        log "Error: No backup file found after vzdump."
        exit 2
    fi
    log "New backup created: $BACKUP_FILE"
fi

check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

log "Restoring container as $NEW_CT_ID..."
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    log "Error: Failed to restore container as $NEW_CT_ID. Old container $CURRENT_CT_ID preserved."
    exit 2
}
log "Restored CT $NEW_CT_ID"

log "Starting container $NEW_CT_ID..."
pct start "$NEW_CT_ID" || {
    log "Error: Failed to start container as $NEW_CT_ID. Old container $CURRENT_CT_ID preserved."
    exit 2
}
log "Started CT $NEW_CT_ID"

if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    log "Success: Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running."
else
    log "Error: Container $NEW_CT_ID restored but not running. Old container $CURRENT_CT_ID preserved."
    log "Check logs with 'journalctl -u pve*'."
    exit 2
fi

log "Deleting original container $CURRENT_CT_ID..."
pct destroy "$CURRENT_CT_ID" || {
    log "Warning: Failed to delete original container $CURRENT_CT_ID. New container $NEW_CT_ID is running."
    exit 2
}
log "Deleted CT $CURRENT_CT_ID"

exit 0
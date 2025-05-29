#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Uses whiptail to select the current container and new CT ID
# Automatically configures backup storage if none exists
# Checks disk space before backup and restore
# Skips stop if container is already stopped, dynamically finds or creates backup
# Delays deletion of old container until new container is confirmed running
# Supports --verbose flag for detailed debug logging

# Initialize logging
LOG_FILE="/var/log/change_ct_id.log"
VERBOSE=0

# Check for --verbose flag
for arg in "$@"; do
    if [ "$arg" = "--verbose" ]; then
        VERBOSE=1
        shift
    fi
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
    echo "$*"
}

debug_log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[DEBUG] $*" | tee -a "$LOG_FILE"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [DEBUG] $*" >> "$LOG_FILE"
}

# Check if whiptail is available
debug_log "Checking for whiptail: $(command -v whiptail)"
if ! command -v whiptail >/dev/null 2>&1; then
    log "Error: whiptail not found. Please install it with 'apt install whiptail'."
    exit 2
fi

# Check if running as root
debug_log "Checking user ID: $(id -u)"
if [ "$(id -u)" -ne 0 ]; then
    log "Error: This script must be run as root."
    exit 1
fi

# Check if Proxmox tools are available
debug_log "Checking Proxmox tools: pct=$(command -v pct), vzdump=$(command -v vzdump), pvesm=$(command -v pvesm)"
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1 || ! command -v pvesm >/dev/null 2>&1; then
    log "Error: Proxmox tools (pct, vzdump, or pvesm) not found. Is this a Proxmox system?"
    exit 2
fi

# Get list of containers for whiptail menu
debug_log "Fetching container list with 'pct list'"
CONTAINERS=$(pct list | tail -n +2 | awk '{print $1 " " $2 " " $3}')
if [ -z "$CONTAINERS" ]; then
    log "Error: No containers found on this system."
    exit 1
fi
debug_log "Found containers: $(echo "$CONTAINERS" | wc -l) entries"

# Build whiptail menu options
MENU_OPTIONS=()
while read -r line; do
    CT_ID=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $2}')
    HOSTNAME=$(echo "$line" | awk '{print $3}')
    MENU_OPTIONS+=("$CT_ID" "[$STATUS] $HOSTNAME")
    debug_log "Added menu option: CT_ID=$CT_ID, Status=$STATUS, Hostname=$HOSTNAME"
done <<< "$CONTAINERS"

# Display whiptail menu to select current CT ID
debug_log "Displaying whiptail menu for container selection"
CURRENT_CT_ID=$(whiptail --title "Select Container" --menu "Choose a container to change its ID:" 15 60 6 \
    "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Menu cancelled."
    exit 1
fi
log "Selected container: $CURRENT_CT_ID"
debug_log "User selected container: CURRENT_CT_ID=$CURRENT_CT_ID"

# Check if the selected CT ID exists
debug_log "Verifying container $CURRENT_CT_ID exists with 'pct status'"
if ! pct status "$CURRENT_CT_ID" >/dev/null 2>&1; then
    log "Error: Container with ID $CURRENT_CT_ID does not exist."
    exit 1
fi

# Prompt for new CT ID using whiptail input box
debug_log "Prompting for new CT ID with whiptail inputbox"
NEW_CT_ID=$(whiptail --title "Enter New Container ID" --inputbox "Enter the new ID for container $CURRENT_CT_ID:" 10 40 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Input cancelled."
    exit 1
fi
debug_log "User entered new CT ID: NEW_CT_ID=$NEW_CT_ID"

# Validate new CT ID
if [ -z "$NEW_CT_ID" ]; then
    log "Error: New CT ID cannot be empty."
    exit 1
fi
if ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
    log "Error: New CT ID must be a positive integer."
    exit 1
fi
debug_log "Validating new CT ID: Checking if $NEW_CT_ID is already in use"
if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
    log "Error: Container with ID $NEW_CT_ID already exists."
    exit 1
fi
log "New container ID: $NEW_CT_ID"

# Detect container configuration
debug_log "Reading config file for CT $CURRENT_CT_ID: /etc/pve/lxc/$CURRENT_CT_ID.conf"
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    log "Error: Configuration file $CONFIG_FILE not found."
    exit 2
fi

# Extract storage from rootfs line
debug_log "Extracting storage from $CONFIG_FILE"
CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    log "Error: Could not detect container storage from $CONFIG_FILE."
    exit 2
fi
debug_log "Detected container storage: $CONTAINER_STORAGE"

# Verify container storage exists
debug_log "Verifying storage $CONTAINER_STORAGE with 'pvesm status'"
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    log "Error: Container storage '$CONTAINER_STORAGE' not found."
    exit 2
fi
log "Detected container storage: $CONTAINER_STORAGE"

# Function to check available disk space (in bytes)
check_disk_space() {
    local storage="$1"
    local required_space="$2"
    log "Checking disk space for $storage..."
    debug_log "Starting disk space check for storage=$storage, required_space=$required_space bytes"
    local storage_type=$(pvesm status | grep "^$storage" | awk '{print $2}')
    debug_log "Storage type: $storage_type"
    debug_log "pvesm status output: $(pvesm status | grep "^$storage")"
    local storage_info=$(pvesm get "$storage" --human-readable false 2>/dev/null)
    local pvesm_get_exit=$?
    debug_log "pvesm get exit code: $pvesm_get_exit, output: $storage_info"
    local available_space=""

    if [ "$storage_type" = "zfs" ] || [ "$storage_type" = "zfspool" ]; then
        debug_log "ZFS/zfspool storage detected, attempting to find subvolume for CT $CURRENT_CT_ID"
        debug_log "Running: pvesm list $storage"
        local pvesm_list_output=$(pvesm list "$storage" 2>/dev/null)
        debug_log "pvesm list output: $pvesm_list_output"
        local zfs_subvol=$(echo "$pvesm_list_output" | grep "subvol-$CURRENT_CT_ID-disk-" | awk '{print $1}' | sed "s|^$storage:||")
        if [ -n "$zfs_subvol" ]; then
            local full_subvol="$storage/$zfs_subvol"
            debug_log "Found ZFS subvolume: $full_subvol"
            debug_log "Running: zfs get -p -H -o value available $full_subvol"
            available_space=$(zfs get -p -H -o value available "$full_subvol" 2>/dev/null)
            local zfs_get_exit=$?
            debug_log "zfs get exit code: $zfs_get_exit, output: $available_space"
            if [ $zfs_get_exit -eq 0 ] && [ -n "$available_space" ] && [[ "$available_space" =~ ^[0-9]+$ ]]; then
                debug_log "ZFS subvolume available space: $available_space bytes"
            else
                debug_log "Warning: Could not get available space for subvolume $full_subvol"
                available_space=""
            fi
        else
            debug_log "No ZFS subvolume found for CT $CURRENT_CT_ID"
        fi
        if [ -z "$available_space" ]; then
            debug_log "Falling back to ZFS pool"
            local zfs_pool=$(echo "$storage_info" | grep '^pool' | awk '{print $2}')
            debug_log "ZFS pool from pvesm get: $zfs_pool"
            if [ -z "$zfs_pool" ]; then
                debug_log "No pool field in pvesm get, trying zfs list"
                debug_log "Running: zfs list -H -o name"
                zfs_pool=$(zfs list -H -o name 2>/dev/null | grep -v '/backup$' | head -n 1)
                debug_log "zfs list output: $(zfs list -H -o name 2>/dev/null)"
                debug_log "ZFS pool from zfs list: $zfs_pool"
            fi
            if [ -n "$zfs_pool" ]; then
                debug_log "Running: zfs get -p -H -o value available $zfs_pool"
                available_space=$(zfs get -p -H -o value available "$zfs_pool" 2>/dev/null)
                local zfs_get_exit=$?
                debug_log "zfs get exit code: $zfs_get_exit, output: $available_space"
                if [ $zfs_get_exit -eq 0 ] && [ -n "$available_space" ] && [[ "$available_space" =~ ^[0-9]+$ ]]; then
                    debug_log "ZFS pool available space: $available_space bytes"
                else
                    debug_log "Error: Could not get available space for pool $zfs_pool"
                    available_space=""
                fi
            else
                debug_log "No ZFS pool found"
            fi
        fi
        if [ -z "$available_space" ]; then
            log "Error: Could not determine available space for ZFS storage '$storage'."
            exit 2
        fi
    else
        debug_log "Non-ZFS storage detected, attempting to get path"
        if [ $pvesm_get_exit -ne 0 ]; then
            log "Error: Could not retrieve storage info for '$storage'."
            debug_log "pvesm get failed with exit code $pvesm_get_exit"
            exit 2
        fi
        local storage_path=$(echo "$storage_info" | grep '^path' | awk '{print $2}')
        if [ "$storage_type" = "nfs" ]; then
            debug_log "NFS storage detected, using mountpoint from pvesm status"
            storage_path=$(pvesm status | grep "^$storage" | awk '{print $7}')
            debug_log "NFS mountpoint: $storage_path"
        fi
        debug_log "Storage path from pvesm get: $storage_path"
        if [ -z "$storage_path" ] || [ ! -d "$storage_path" ]; then
            log "Error: Invalid or inaccessible storage path for '$storage'."
            debug_log "Storage path invalid: $storage_path"
            exit 2
        fi
        debug_log "Running: df --block-size=1 --output=avail $storage_path"
        available_space=$(df --block-size=1 --output=avail "$storage_path" | tail -n 1)
        local df_exit=$?
        debug_log "df exit code: $df_exit, output: $available_space"
        if [ $df_exit -ne 0 ] || [ -z "$available_space" ] || ! [[ "$available_space" =~ ^[0-9]+$ ]]; then
            log "Error: Could not determine available space for storage '$storage'."
            debug_log "Invalid df output: $available_space"
            exit 2
        fi
        debug_log "Non-ZFS storage path: $storage_path, available space: $available_space bytes"
    fi

    debug_log "Comparing available_space=$available_space with required_space=$required_space"
    if [ "$available_space" -lt "$required_space" ]; then
        log "Error: Insufficient disk space on storage '$storage'."
        log "Required: $((required_space / 1024 / 1024)) MB, Available: $((available_space / 1024 / 1024)) MB"
        exit 2
    fi
    log "Sufficient disk space on storage '$storage': $((available_space / 1024 / 1024)) MB available"
}

# Function to configure backup storage
configure_backup_storage() {
    debug_log "Checking for backup storage"
    local backup_storages=$(pvesm status | grep "backup" | awk '{print $1}')
    debug_log "Found backup storages: $backup_storages"
    if [ -n "$backup_storages" ]; then
        BACKUP_STORAGE=$(echo "$backup_storages" | head -n 1)
        debug_log "Using existing backup storage: $BACKUP_STORAGE"
        return 0
    fi

    debug_log "No backup storage found, attempting to configure one"
    # Try mrx-nas (NFS)
    if pvesm status | grep -q "^mrx-nas"; then
        debug_log "Configuring mrx-nas for backups"
        pvesm set mrx-nas --content backup 2>/dev/null
        local set_exit=$?
        debug_log "pvesm set mrx-nas exit code: $set_exit"
        if [ $set_exit -eq 0 ] && pvesm status | grep "^mrx-nas" | grep -q "backup"; then
            BACKUP_STORAGE="mrx-nas"
            debug_log "Successfully configured mrx-nas for backups"
            return 0
        fi
        debug_log "Failed to configure mrx-nas for backups"
    fi

    # Try creating a ZFS dataset on rpool
    debug_log "Attempting to create ZFS dataset rpool/backup"
    zfs create rpool/backup 2>/dev/null
    local zfs_create_exit=$?
    debug_log "zfs create exit code: $zfs_create_exit"
    if [ $zfs_create_exit -eq 0 ]; then
        debug_log "Configuring ZFS dataset as directory storage"
        pvesm add dir zfs-backup --path /rpool/backup --content backup --is_mountpoint yes 2>/dev/null
        local pvesm_add_exit=$?
        debug_log "pvesm add zfs-backup exit code: $pvesm_add_exit"
        if [ $pvesm_add_exit -eq 0 ]; then
            BACKUP_STORAGE="zfs-backup"
            debug_log "Successfully configured zfs-backup for backups"
            return 0
        fi
        debug_log "Failed to configure zfs-backup storage"
        zfs destroy rpool/backup 2>/dev/null
    fi

    # Try local storage
    if pvesm status | grep -q "^local"; then
        debug_log "Configuring local storage for backups"
        pvesm set local --content backup 2>/dev/null
        local set_exit=$?
        debug_log "pvesm set local exit code: $set_exit"
        if [ $set_exit -eq 0 ] && pvesm status | grep "^local" | grep -q "backup"; then
            BACKUP_STORAGE="local"
            debug_log "Successfully configured local for backups"
            return 0
        fi
        debug_log "Failed to configure local for backups"
    fi

    log "Error: Could not configure a storage for backups."
    debug_log "Failed to configure any backup storage"
    exit 2
}

# Estimate container size (try actual usage first, then config, then default)
debug_log "Estimating container size for CT $CURRENT_CT_ID"
CONTAINER_DISK=$(pvesm list "$CONTAINER_STORAGE" | grep "lxc/$CURRENT_CT_ID/" | awk '{print $2}' | head -n 1)
if [ -n "$CONTAINER_DISK" ]; then
    REQUIRED_SPACE=$CONTAINER_DISK
    debug_log "Estimated container size from pvesm: $((REQUIRED_SPACE / 1024 / 1024)) MB"
else
    CONTAINER_SIZE=$(grep '^rootfs:' "$CONFIG_FILE" | grep -oP 'size=\K[^,]+' | head -n 1)
    if [ -n "$CONTAINER_SIZE" ]; then
        case "$CONTAINER_SIZE" in
            *G) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'G'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024 * 1024)) ;;
            *M) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'M'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024)) ;;
            *K) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'K'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024)) ;;
            *) REQUIRED_SPACE=$((CONTAINER_SIZE * 1024 * 1024 * 1024)) ;;
        esac
        debug_log "Estimated container size from config: $((REQUIRED_SPACE / 1024 / 1024)) MB"
    else
        REQUIRED_SPACE=$((10 * 1024 * 1024 * 1024)) # Default 10GB
        debug_log "Warning: No size detected, using default 10GB"
    fi
fi
# Add 20% overhead for backup and restore
REQUIRED_SPACE=$((REQUIRED_SPACE + (REQUIRED_SPACE / 5)))
debug_log "Required space after 20% overhead: $((REQUIRED_SPACE / 1024 / 1024)) MB"

# Check disk space for backup
check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

# Configure backup storage
configure_backup_storage

# Check disk space for backup storage
debug_log "Checking disk space for backup storage $BACKUP_STORAGE"
check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE"

# Check if the container is unprivileged
debug_log "Checking if CT $CURRENT_CT_ID is unprivileged"
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    log "Detected unprivileged container. Will use --unprivileged flag for restore."
    debug_log "Unprivileged container detected, setting UNPRIVILEGED=$UNPRIVILEGED"
fi

# Stop the container if running
debug_log "Checking status of CT $CURRENT_CT_ID"
STATUS=$(pct status "$CURRENT_CT_ID" 2>/dev/null)
if echo "$STATUS" | grep -q "status: running"; then
    log "Stopping container $CURRENT_CT_ID..."
    debug_log "Attempting to stop CT $CURRENT_CT_ID"
    pct stop "$CURRENT_CT_ID" || {
        log "Error: Failed to stop container $CURRENT_CT_ID."
        exit 2
    }
    debug_log "Stopped CT $CURRENT_CT_ID"
else
    log "Container $CURRENT_CT_ID is already stopped (status: $STATUS)."
    debug_log "CT $CURRENT_CT_ID already stopped: $STATUS"
fi

# Check for existing backup or create a new one
log "Searching for existing backup for CT $CURRENT_CT_ID..."
debug_log "Searching backups in $BACKUP_STORAGE with 'pvesm list'"
BACKUP_FILE=$(pvesm list "$BACKUP_STORAGE" | grep "vzdump-lxc-$CURRENT_CT_ID-" | awk '{print $1}' | head -n 1)
if [ -n "$BACKUP_FILE" ]; then
    debug_log "Found backup file entry: $BACKUP_FILE"
    BACKUP_PATH=$(pvesm path "$BACKUP_FILE")
    if [ -f "$BACKUP_PATH" ]; then
        log "Found existing backup: $BACKUP_PATH"
        debug_log "Verified backup file exists: $BACKUP_PATH"
    else
        debug_log "Backup file $BACKUP_PATH does not exist"
        BACKUP_FILE=""
    fi
fi
if [ -z "$BACKUP_FILE" ]; then
    log "No existing backup found. Creating new backup on $BACKUP_STORAGE..."
    debug_log "Creating new backup with vzdump for CT $CURRENT_CT_ID"
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    debug_log "vzdump exit status: $VZDUMP_STATUS"
    if [ $VZDUMP_STATUS -ne 0 ]; then
        log "Error: Backup failed for container $CURRENT_CT_ID."
        log "$VZDUMP_OUTPUT"
        debug_log "Backup failed: $VZDUMP_OUTPUT"
        exit 2
    fi
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        log "Error: No backup file found after vzdump."
        debug_log "No backup file found or invalid: $BACKUP_FILE"
        exit 2
    fi
    log "New backup created: $BACKUP_FILE"
    debug_log "New backup created: $BACKUP_FILE"
fi

# Check disk space for restore
debug_log "Checking disk space for restore on $CONTAINER_STORAGE"
check_disk_space "$CONTAINER_STORAGE" "$REQUIRED_SPACE"

# Restore the container with the new CT ID
log "Restoring container as $NEW_CT_ID..."
debug_log "Restoring CT $NEW_CT_ID from $BACKUP_FILE"
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    log "Error: Failed to restore container as $NEW_CT_ID. Old container $CURRENT_CT_ID preserved."
    debug_log "Restore failed for CT $NEW_CT_ID"
    exit 2
}
debug_log "Restored CT $NEW_CT_ID"

# Start the new container
log "Starting container $NEW_CT_ID..."
debug_log "Starting CT $NEW_CT_ID"
pct start "$NEW_CT_ID" || {
    log "Error: Failed to start container as $NEW_CT_ID. Old container $CURRENT_CT_ID preserved."
    debug_log "Start failed for CT $NEW_CT_ID"
    exit 2
}
debug_log "Started CT $NEW_CT_ID"

# Verify the container is running
debug_log "Verifying CT $NEW_CT_ID is running"
if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    log "New container $NEW_CT_ID is running."
    debug_log "Verified CT $NEW_CT_ID is running"
else
    log "Error: Container $NEW_CT_ID restored but not running. Old container $CURRENT_CT_ID preserved."
    log "Check logs with 'journalctl -u pve*'."
    debug_log "CT $NEW_CT_ID not running"
    exit 2
fi

# Delete the original container (only after new container is confirmed running)
log "Deleting original container $CURRENT_CT_ID..."
debug_log "Deleting CT $CURRENT_CT_ID"
pct destroy "$CURRENT_CT_ID" || {
    log "Warning: Failed to delete original container $CURRENT_CT_ID. New container $NEW_CT_ID is running."
    debug_log "Failed to delete CT $CURRENT_CT_ID"
    exit 2
}
debug_log "Deleted CT $CURRENT_CT_ID"

# Final success message
log "Success: Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running."
debug_log "Operation completed successfully"

# Optional cleanup (commented out)
# log "Cleaning up backup file $BACKUP_FILE..."
# rm -f "$BACKUP_FILE"
# debug_log "Cleaned up backup: $BACKUP_FILE"

exit 0
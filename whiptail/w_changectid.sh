#!/bin/bash
# Script to change the ID of a Proxmox LXC container (CT) or virtual machine (VM) using backup and restore
# Uses whiptail to select the CT/VM and new ID
# Automatically configures backup storage within the same storage as the CT/VM, or falls back to another storage
# Checks disk space before backup and restore, using ZFS pool space to avoid subvolume quotas
# Validates ZFS dataset mountpoints for dir storages
# Skips stop if CT/VM is already stopped, dynamically finds or creates backup
# Delays deletion of old CT/VM until new one is confirmed running
# Supports --verbose flag for detailed debug logging with timestamps

# Initialize logging
LOG_FILE="/var/log/change_ct_vm_id.log"
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
        echo "[DEBUG $(date '+%Y-%m-%d %H:%M:%S.%N')] $*" | tee -a "$LOG_FILE"
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
debug_log "Checking Proxmox tools: pct=$(command -v pct), vzdump=$(command -v vzdump), pvesm=$(command -v pvesm), qm=$(command -v qm)"
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1 || ! command -v pvesm >/dev/null 2>&1 || ! command -v qm >/dev/null 2>&1; then
    log "Error: Proxmox tools (pct, vzdump, pvesm, or qm) not found. Is this a Proxmox system?"
    exit 2
fi

# Get list of CTs and VMs for whiptail menu
debug_log "Fetching CT list with 'pct list'"
CT_LIST=$(pct list | tail -n +2 | awk '{print "CT " $1 " [" $2 "] " $3}')
debug_log "Fetching VM list with 'qm list'"
VM_LIST=$(qm list | tail -n +2 | awk '{print "VM " $1 " [" $3 "] " $2}')
if [ -z "$CT_LIST" ] && [ -z "$VM_LIST" ]; then
    log "Error: No containers or virtual machines found on this system."
    exit 1
fi
debug_log "Found CTs: $(echo "$CT_LIST" | wc -l), VMs: $(echo "$VM_LIST" | wc -l)"

# Build whiptail menu options
MENU_OPTIONS=()
while read -r line; do
    if [ -n "$line" ]; then
        ID=$(echo "$line" | awk '{print $2}')
        DESC=$(echo "$line" | cut -d' ' -f3-)
        MENU_OPTIONS+=("$ID" "$line")
    fi
done <<< "$CT_LIST
$VM_LIST"

# Display whiptail menu to select CT or VM
debug_log "Displaying whiptail menu for CT/VM selection"
SELECTED_ITEM=$(whiptail --title "Select Container or VM" --menu "Choose a container or VM to change its ID:" 20 80 12 \
    "${MENU_OPTIONS[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Menu cancelled."
    exit 1
fi
CURRENT_ID="$SELECTED_ITEM"
ENTITY_TYPE=$(echo "$CT_LIST
$VM_LIST" | grep "^.* $CURRENT_ID " | awk '{print $1}')
log "Selected $ENTITY_TYPE: $CURRENT_ID"
debug_log "User selected $ENTITY_TYPE: CURRENT_ID=$CURRENT_ID"

# Check if the selected CT/VM exists
debug_log "Verifying $ENTITY_TYPE $CURRENT_ID exists"
if [ "$ENTITY_TYPE" = "CT" ]; then
    if ! pct status "$CURRENT_ID" >/dev/null 2>&1; then
        log "Error: Container with ID $CURRENT_ID does not exist."
        exit 1
    fi
else
    if ! qm status "$CURRENT_ID" >/dev/null 2>&1; then
        log "Error: Virtual machine with ID $CURRENT_ID does not exist."
        exit 1
    fi
fi

# Prompt for new ID using whiptail input box
debug_log "Prompting for new $ENTITY_TYPE ID with whiptail inputbox"
NEW_ID=$(whiptail --title "Enter New $ENTITY_TYPE ID" --inputbox "Enter the new ID for $ENTITY_TYPE $CURRENT_ID:" 10 40 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    log "Input cancelled."
    exit 1
fi
debug_log "User entered new $ENTITY_TYPE ID: NEW_ID=$NEW_ID"

# Validate new ID
if [ -z "$NEW_ID" ]; then
    log "Error: New $ENTITY_TYPE ID cannot be empty."
    exit 1
fi
if ! [[ "$NEW_ID" =~ ^[0-9]+$ ]]; then
    log "Error: New $ENTITY_TYPE ID must be a positive integer."
    exit 1
fi
debug_log "Validating new $ENTITY_TYPE ID: Checking if $NEW_ID is already in use"
if pct status "$NEW_ID" >/dev/null 2>&1 || qm status "$NEW_ID" >/dev/null 2>&1; then
    log "Error: $ENTITY_TYPE with ID $NEW_ID already exists."
    exit 1
fi
log "New $ENTITY_TYPE ID: $NEW_ID"

# Detect configuration
debug_log "Reading config file for $ENTITY_TYPE $CURRENT_ID"
if [ "$ENTITY_TYPE" = "CT" ]; then
    CONFIG_FILE="/etc/pve/lxc/$CURRENT_ID.conf"
else
    CONFIG_FILE="/etc/pve/qemu-server/$CURRENT_ID.conf"
fi
if [ ! -f "$CONFIG_FILE" ]; then
    log "Error: Configuration file $CONFIG_FILE not found."
    exit 2
fi

# Extract storage
debug_log "Extracting storage from $CONFIG_FILE"
if [ "$ENTITY_TYPE" = "CT" ]; then
    CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
else
    # For VMs, get the first disk storage (e.g., scsi0, ide0)
    CONTAINER_STORAGE=$(grep -E "^(scsi|ide|sata|virtio)[0-9]+:" "$CONFIG_FILE" | head -n 1 | awk -F: '{print $2}' | cut -d',' -f1 | awk '{print $1}')
fi
if [ -z "$CONTAINER_STORAGE" ]; then
    log "Error: Could not detect storage from $CONFIG_FILE."
    exit 2
fi
debug_log "Detected storage: $CONTAINER_STORAGE"

# Verify storage exists
debug_log "Verifying storage $CONTAINER_STORAGE with 'pvesm status'"
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    log "Error: Storage '$CONTAINER_STORAGE' not found."
    exit 2
fi
log "Detected storage: $CONTAINER_STORAGE"

# Function to check available disk space (in bytes)
check_disk_space() {
    local storage="$1"
    local required_space="$2"
    local custom_path="$3"  # Optional: path to use if provided
    log "Checking disk space for $storage..."
    debug_log "Starting disk space check for storage=$storage, required_space=$required_space bytes"
    local storage_type=$(pvesm status | grep "^$storage" | awk '{print $2}')
    debug_log "Storage type: $storage_type"
    debug_log "pvesm status output: $(pvesm status | grep "^$storage")"
    local storage_info=$(pvesm get "$storage" --human-readable false 2>/dev/null)
    local pvesm_get_exit=$?
    debug_log "pvesm get exit code: $pvesm_get_exit, output: $storage_info"
    local available_space=""

    # Determine the storage path
    local storage_path=""
    if [ -n "$custom_path" ]; then
        debug_log "Using custom path provided: $custom_path"
        storage_path="$custom_path"
    else
        storage_path=$(echo "$storage_info" | grep '^path' | awk '{print $2}')
        if [ -z "$storage_path" ]; then
            if [ "$storage_type" = "nfs" ]; then
                debug_log "NFS storage detected, attempting to get path from mount table"
                storage_path=$(grep "$storage" /proc/mounts | awk '{print $2}' | head -n 1)
                debug_log "NFS mountpoint from /proc/mounts: $storage_path"
            elif [ "$storage_type" = "dir" ]; then
                debug_log "Dir storage detected, checking if it's a custom backup directory or ZFS dataset"
                # Check if the storage name matches a backup directory pattern (e.g., backup-<timestamp>)
                if [[ "$storage" =~ ^backup-[0-9]+$ ]]; then
                    # Try to get the path from pvesm get, but if it fails, we should have the custom path
                    storage_path=$(pvesm get "$storage" --human-readable false 2>/dev/null | grep '^path' | awk '{print $2}')
                    debug_log "Custom backup directory path from pvesm get: $storage_path"
                    if [ -z "$storage_path" ]; then
                        log "Error: Could not retrieve path for custom backup directory '$storage'."
                        return 1
                    fi
                else
                    # Check for a ZFS dataset
                    local zfs_list=$(zfs list -H -o name 2>/dev/null)
                    local dataset=$(echo "$zfs_list" | grep -E "(rpool|local-zfs-2)/backup(-[0-9]+)?$" | head -n 1)
                    if [ -n "$dataset" ]; then
                        debug_log "Found potential ZFS dataset for storage $storage: $dataset"
                        local mountpoint=$(zfs get -p -H -o value mountpoint "$dataset" 2>/dev/null)
                        local zfs_get_exit=$?
                        debug_log "zfs get mountpoint exit code: $zfs_get_exit, output: $mountpoint"
                        if [ $zfs_get_exit -eq 0 ] && [ "$mountpoint" != "none" ] && [ -n "$mountpoint" ]; then
                            storage_path="$mountpoint"
                            debug_log "Using ZFS dataset mountpoint: $storage_path"
                            if [ ! -d "$storage_path" ]; then
                                debug_log "Mountpoint $storage_path does not exist, attempting to mount"
                                zfs mount "$dataset" 2>/dev/null
                                local zfs_mount_exit=$?
                                debug_log "zfs mount exit code: $zfs_mount_exit"
                                if [ $zfs_mount_exit -ne 0 ]; then
                                    log "Error: Could not mount ZFS dataset '$dataset' for storage '$storage'."
                                    return 1
                                fi
                            fi
                        fi
                    else
                        debug_log "No matching ZFS dataset found, trying generic path"
                        storage_path="/$(echo "$storage" | tr '-' '/')"
                        debug_log "Trying generic path: $storage_path"
                    fi
                fi
            fi
        fi
    fi

    if [ -z "$storage_path" ] || [ ! -d "$storage_path" ]; then
        log "Error: Invalid or inaccessible storage path for '$storage'."
        return 1
    fi

    debug_log "Storage path: $storage_path"
    debug_log "Running: df --block-size=1 --output=avail $storage_path"
    available_space=$(df --block-size=1 --output=avail "$storage_path" | tail -n 1)
    local df_exit=$?
    debug_log "df exit code: $df_exit, output: $available_space"
    if [ $df_exit -ne 0 ] || [ -z "$available_space" ] || ! [[ "$available_space" =~ ^[0-9]+$ ]]; then
        log "Error: Could not determine available space for storage '$storage'."
        return 1
    fi
    debug_log "Storage path: $storage_path, available space: $available_space bytes"

    debug_log "Comparing available_space=$available_space with required_space=$required_space"
    if [ "$available_space" -lt "$required_space" ]; then
        log "Insufficient disk space on storage '$storage'."
        log "Required: $((required_space / 1024 / 1024)) MB, Available: $((available_space / 1024 / 1024)) MB"
        # Attempt to adjust ZFS quotas if applicable
        if [ "$storage_type" = "dir" ] || [ "$storage_type" = "zfs" ] || [ "$storage_type" = "zfspool" ]; then
            local zfs_list=$(zfs list -H -o name 2>/dev/null)
            local dataset=$(echo "$zfs_list" | grep -E "(rpool|local-zfs-2)/backup(-[0-9]+)?$" | head -n 1)
            if [ -n "$dataset" ]; then
                debug_log "Checking ZFS quotas for dataset $dataset"
                local dataset_quota=$(zfs get -p -H -o value quota "$dataset" 2>/dev/null)
                local dataset_refquota=$(zfs get -p -H -o value refquota "$dataset" 2>/dev/null)
                debug_log "Dataset quota: $dataset_quota, refquota: $dataset_refquota"
                # Calculate needed quota (required_space + 10% buffer)
                local needed_quota=$((required_space + required_space / 10))
                local needed_quota_mb=$((needed_quota / 1024 / 1024))
                # Check parent pool space
                local parent_pool=$(echo "$dataset" | cut -d'/' -f1)
                local pool_available=$(zfs get -p -H -o value available "$parent_pool" 2>/dev/null)
                debug_log "Parent pool $parent_pool available space: $pool_available bytes"
                if [ -n "$pool_available" ] && [ "$pool_available" -gt "$needed_quota" ]; then
                    if [ "$dataset_quota" != "none" ] && [ -n "$dataset_quota" ] && [ "$dataset_quota" -ne 0 ]; then
                        log "Adjusting quota on $dataset to $needed_quota_mb MB"
                        zfs set quota=${needed_quota_mb}M "$dataset" 2>/dev/null
                        local quota_set_exit=$?
                        debug_log "zfs set quota exit code: $quota_set_exit"
                    fi
                    if [ "$dataset_refquota" != "none" ] && [ -n "$dataset_refquota" ] && [ "$dataset_refquota" -ne 0 ]; then
                        log "Adjusting refquota on $dataset to $needed_quota_mb MB"
                        zfs set refquota=${needed_quota_mb}M "$dataset" 2>/dev/null
                        local refquota_set_exit=$?
                        debug_log "zfs set refquota exit code: $refquota_set_exit"
                    fi
                    # Recheck available space after adjustment
                    available_space=$(df --block-size=1 --output=avail "$storage_path" | tail -n 1)
                    debug_log "Rechecked available space after quota adjustment: $available_space bytes"
                else
                    debug_log "Parent pool $parent_pool does not have enough space to adjust quota"
                fi
            fi
        fi
        if [ "$available_space" -lt "$required_space" ]; then
            return 1
        fi
    fi
    log "Sufficient disk space on storage '$storage': $((available_space / 1024 / 1024)) MB available"
    return 0
}

# Function to wait for storage readiness
wait_for_storage() {
    local storage="$1"
    local path="$2"
    local max_attempts=5
    local attempt=1
    local sleep_time=1

    debug_log "Waiting for storage $storage to be ready at path $path"
    while [ $attempt -le $max_attempts ]; do
        debug_log "Attempt $attempt: Checking if storage $storage is ready"
        local storage_info=$(pvesm get "$storage" --human-readable false 2>/dev/null)
        local pvesm_get_exit=$?
        debug_log "pvesm get exit code: $pvesm_get_exit, output: $storage_info"
        local retrieved_path=$(echo "$storage_info" | grep '^path' | awk '{print $2}')
        if [ $pvesm_get_exit -eq 0 ] && [ -n "$retrieved_path" ] && [ -d "$retrieved_path" ]; then
            debug_log "Storage $storage is ready with path $retrieved_path"
            return 0
        fi
        debug_log "Storage $storage not ready yet, sleeping for $sleep_time seconds"
        sleep $sleep_time
        attempt=$((attempt + 1))
    done

    debug_log "Storage $storage not ready after $max_attempts attempts, using custom path $path"
    if [ -d "$path" ]; then
        return 0
    else
        log "Error: Storage $storage path $path is not accessible after waiting."
        return 1
    fi
}

# Function to configure backup storage
configure_backup_storage() {
    debug_log "Configuring backup storage for $ENTITY_TYPE $CURRENT_ID on $CONTAINER_STORAGE"

    # First, try to create a backup location within the same storage as the CT/VM
    debug_log "Attempting to create a backup location within $CONTAINER_STORAGE"
    local container_storage_type=$(pvesm status | grep "^$CONTAINER_STORAGE" | awk '{print $2}')
    debug_log "Container storage type: $container_storage_type"

    local timestamp=$(date +%s)
    local backup_storage_name="backup-$timestamp"
    local backup_storage_created=0
    local backup_path=""

    if [ "$container_storage_type" = "zfs" ] || [ "$container_storage_type" = "zfspool" ]; then
        debug_log "Creating a new ZFS dataset for backups in $CONTAINER_STORAGE"
        local zfs_pool=$(pvesm get "$CONTAINER_STORAGE" --human-readable false 2>/dev/null | grep '^pool' | awk '{print $2}')
        if [ -z "$zfs_pool" ]; then
            zfs_pool=$(zfs list -H -o name 2>/dev/null | grep -v '/backup' | head -n 1)
        fi
        if [ -n "$zfs_pool" ]; then
            local backup_dataset="backup-$timestamp"
            local full_dataset="$zfs_pool/$backup_dataset"
            debug_log "Attempting to create ZFS dataset $full_dataset"
            zfs create "$full_dataset" 2>/dev/null
            local zfs_create_exit=$?
            debug_log "zfs create exit code: $zfs_create_exit"
            if [ $zfs_create_exit -eq 0 ]; then
                debug_log "Configuring ZFS dataset as directory storage: $backup_storage_name"
                pvesm add dir "$backup_storage_name" --path "/$full_dataset" --content backup --is_mountpoint yes 2>/dev/null
                local pvesm_add_exit=$?
                debug_log "pvesm add $backup_storage_name exit code: $pvesm_add_exit"
                if [ $pvesm_add_exit -eq 0 ]; then
                    BACKUP_STORAGE="$backup_storage_name"
                    backup_storage_created=1
                    backup_path="/$full_dataset"
                    wait_for_storage "$BACKUP_STORAGE" "$backup_path"
                    if [ $? -eq 0 ]; then
                        check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE" "$backup_path"
                        local space_check_exit=$?
                        if [ $space_check_exit -eq 0 ]; then
                            debug_log "Successfully configured $BACKUP_STORAGE for backups within $CONTAINER_STORAGE"
                            return 0
                        else
                            debug_log "New backup storage $BACKUP_STORAGE does not have sufficient space"
                            pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                            zfs destroy "$full_dataset" 2>/dev/null
                            BACKUP_STORAGE=""
                            backup_storage_created=0
                            backup_path=""
                        fi
                    else
                        pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                        zfs destroy "$full_dataset" 2>/dev/null
                        BACKUP_STORAGE=""
                        backup_storage_created=0
                        backup_path=""
                    fi
                else
                    zfs destroy "$full_dataset" 2>/dev/null
                fi
            fi
        fi
    elif [ "$container_storage_type" = "nfs" ] || [ "$container_storage_type" = "dir" ]; then
        debug_log "Attempting to create a backup subdirectory in $CONTAINER_STORAGE"
        local storage_path=$(pvesm get "$CONTAINER_STORAGE" --human-readable false 2>/dev/null | grep '^path' | awk '{print $2}')
        if [ -z "$storage_path" ] && [ "$container_storage_type" = "nfs" ]; then
            storage_path=$(grep "$CONTAINER_STORAGE" /proc/mounts | awk '{print $2}' | head -n 1)
        fi
        if [ -z "$storage_path" ] && [ "$container_storage_type" = "dir" ]; then
            local zfs_list=$(zfs list -H -o name 2>/dev/null)
            local dataset=$(echo "$zfs_list" | grep -E "(rpool|local-zfs-2)/backup(-[0-9]+)?$" | head -n 1)
            if [ -n "$dataset" ]; then
                local mountpoint=$(zfs get -p -H -o value mountpoint "$dataset" 2>/dev/null)
                if [ -n "$mountpoint" ] && [ "$mountpoint" != "none" ]; then
                    storage_path="$mountpoint"
                    if [ ! -d "$storage_path" ]; then
                        zfs mount "$dataset" 2>/dev/null
                    fi
                fi
            else
                storage_path="/$(echo "$CONTAINER_STORAGE" | tr '-' '/')"
            fi
        fi
        if [ -n "$storage_path" ] && [ -d "$storage_path" ]; then
            local backup_dir="backup-$timestamp"
            backup_path="$storage_path/$backup_dir"
            debug_log "Creating backup directory $backup_path"
            mkdir -p "$backup_path" 2>/dev/null
            local mkdir_exit=$?
            debug_log "mkdir exit code: $mkdir_exit"
            if [ $mkdir_exit -eq 0 ]; then
                # Verify directory exists
                if [ -d "$backup_path" ]; then
                    debug_log "Backup directory $backup_path created successfully"
                else
                    debug_log "Backup directory $backup_path does not exist after creation"
                    return 1
                fi
                debug_log "Configuring backup directory as storage: $backup_storage_name"
                pvesm add dir "$backup_storage_name" --path "$backup_path" --content backup --is_mountpoint no 2>/dev/null
                local pvesm_add_exit=$?
                debug_log "pvesm add $backup_storage_name exit code: $pvesm_add_exit"
                if [ $pvesm_add_exit -eq 0 ]; then
                    BACKUP_STORAGE="$backup_storage_name"
                    backup_storage_created=1
                    wait_for_storage "$BACKUP_STORAGE" "$backup_path"
                    if [ $? -eq 0 ]; then
                        check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE" "$backup_path"
                        local space_check_exit=$?
                        if [ $space_check_exit -eq 0 ]; then
                            debug_log "Successfully configured $BACKUP_STORAGE for backups within $CONTAINER_STORAGE"
                            return 0
                        else
                            debug_log "New backup storage $BACKUP_STORAGE does not have sufficient space"
                            pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                            rm -rf "$backup_path" 2>/dev/null
                            BACKUP_STORAGE=""
                            backup_storage_created=0
                            backup_path=""
                        fi
                    else
                        pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                        rm -rf "$backup_path" 2>/dev/null
                        BACKUP_STORAGE=""
                        backup_storage_created=0
                        backup_path=""
                    fi
                else
                    rm -rf "$backup_path" 2>/dev/null
                fi
            fi
        fi
    fi

    # If we can't create a backup location in CONTAINER_STORAGE, fall back to other storages
    debug_log "Could not configure backup storage in $CONTAINER_STORAGE, falling back to other storages"
    local other_storages=$(pvesm status | grep -v "^$CONTAINER_STORAGE" | grep "active" | awk '{print $1}')
    debug_log "Other available storages: $other_storages"
    for storage in $other_storages; do
        debug_log "Trying backup storage: $storage"
        local storage_type=$(pvesm status | grep "^$storage" | awk '{print $2}')
        if [ "$storage_type" = "nfs" ] || [ "$storage_type" = "dir" ]; then
            # For NFS and dir storages, create a subdirectory
            local sub_storage_path=$(pvesm get "$storage" --human-readable false 2>/dev/null | grep '^path' | awk '{print $2}')
            if [ -z "$sub_storage_path" ] && [ "$storage_type" = "nfs" ]; then
                sub_storage_path=$(grep "$storage" /proc/mounts | awk '{print $2}' | head -n 1)
            fi
            if [ -z "$sub_storage_path" ] && [ "$storage_type" = "dir" ]; then
                local zfs_list=$(zfs list -H -o name 2>/dev/null)
                local dataset=$(echo "$zfs_list" | grep -E "(rpool|local-zfs-2)/backup(-[0-9]+)?$" | head -n 1)
                if [ -n "$dataset" ]; then
                    local mountpoint=$(zfs get -p -H -o value mountpoint "$dataset" 2>/dev/null)
                    if [ -n "$mountpoint" ] && [ "$mountpoint" != "none" ]; then
                        sub_storage_path="$mountpoint"
                        if [ ! -d "$sub_storage_path" ]; then
                            zfs mount "$dataset" 2>/dev/null
                        fi
                    fi
                else
                    sub_storage_path="/$(echo "$storage" | tr '-' '/')"
                fi
            fi
            if [ -n "$sub_storage_path" ] && [ -d "$sub_storage_path" ]; then
                local sub_backup_dir="backup-$timestamp"
                local sub_backup_path="$sub_storage_path/$sub_backup_dir"
                debug_log "Creating backup directory $sub_backup_path in $storage"
                mkdir -p "$sub_backup_path" 2>/dev/null
                local mkdir_exit=$?
                debug_log "mkdir exit code: $mkdir_exit"
                if [ $mkdir_exit -eq 0 ]; then
                    # Verify directory exists
                    if [ -d "$sub_backup_path" ]; then
                        debug_log "Backup directory $sub_backup_path created successfully"
                    else
                        debug_log "Backup directory $sub_backup_path does not exist after creation"
                        continue
                    fi
                    local sub_backup_storage_name="backup-$timestamp"
                    debug_log "Configuring backup directory as storage: $sub_backup_storage_name"
                    pvesm add dir "$sub_backup_storage_name" --path "$sub_backup_path" --content backup --is_mountpoint no 2>/dev/null
                    local pvesm_add_exit=$?
                    debug_log "pvesm add $sub_backup_storage_name exit code: $pvesm_add_exit"
                    if [ $pvesm_add_exit -eq 0 ]; then
                        BACKUP_STORAGE="$sub_backup_storage_name"
                        backup_storage_created=1
                        wait_for_storage "$BACKUP_STORAGE" "$sub_backup_path"
                        if [ $? -eq 0 ]; then
                            check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE" "$sub_backup_path"
                            local space_check_exit=$?
                            if [ $space_check_exit -eq 0 ]; then
                                debug_log "Successfully configured $BACKUP_STORAGE for backups within $storage"
                                return 0
                            else
                                debug_log "New backup storage $BACKUP_STORAGE does not have sufficient space"
                                pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                                rm -rf "$sub_backup_path" 2>/dev/null
                                BACKUP_STORAGE=""
                                backup_storage_created=0
                            fi
                        else
                            pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                            rm -rf "$sub_backup_path" 2>/dev/null
                            BACKUP_STORAGE=""
                            backup_storage_created=0
                        fi
                    else
                        rm -rf "$sub_backup_path" 2>/dev/null
                    fi
                fi
            fi
        elif [ "$storage_type" = "zfs" ] || [ "$storage_type" = "zfspool" ]; then
            # For ZFS storages, create a new dataset
            local zfs_pool=$(pvesm get "$storage" --human-readable false 2>/dev/null | grep '^pool' | awk '{print $2}')
            if [ -z "$zfs_pool" ]; then
                zfs_pool=$(zfs list -H -o name 2>/dev/null | grep -v '/backup' | head -n 1)
            fi
            if [ -n "$zfs_pool" ]; then
                local backup_dataset="backup-$timestamp"
                local full_dataset="$zfs_pool/$backup_dataset"
                debug_log "Attempting to create ZFS dataset $full_dataset"
                zfs create "$full_dataset" 2>/dev/null
                local zfs_create_exit=$?
                debug_log "zfs create exit code: $zfs_create_exit"
                if [ $zfs_create_exit -eq 0 ]; then
                    local backup_storage_name="backup-$timestamp"
                    debug_log "Configuring ZFS dataset as directory storage: $backup_storage_name"
                    pvesm add dir "$backup_storage_name" --path "/$full_dataset" --content backup --is_mountpoint yes 2>/dev/null
                    local pvesm_add_exit=$?
                    debug_log "pvesm add $backup_storage_name exit code: $pvesm_add_exit"
                    if [ $pvesm_add_exit -eq 0 ]; then
                        BACKUP_STORAGE="$backup_storage_name"
                        backup_storage_created=1
                        backup_path="/$full_dataset"
                        wait_for_storage "$BACKUP_STORAGE" "$backup_path"
                        if [ $? -eq 0 ]; then
                            check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE" "$backup_path"
                            local space_check_exit=$?
                            if [ $space_check_exit -eq 0 ]; then
                                debug_log "Successfully configured $BACKUP_STORAGE for backups within $storage"
                                return 0
                            else
                                pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                                zfs destroy "$full_dataset" 2>/dev/null
                                BACKUP_STORAGE=""
                                backup_storage_created=0
                                backup_path=""
                            fi
                        else
                            pvesm remove "$BACKUP_STORAGE" 2>/dev/null
                            zfs destroy "$full_dataset" 2>/dev/null
                            BACKUP_STORAGE=""
                            backup_storage_created=0
                            backup_path=""
                        fi
                    else
                        zfs destroy "$full_dataset" 2>/dev/null
                    fi
                fi
            fi
        fi
    done

    log "Error: Could not configure a storage for backups with sufficient space."
    exit 2
}

# Estimate disk size (try actual usage first, then config, then default)
debug_log "Estimating disk size for $ENTITY_TYPE $CURRENT_ID"
CONTAINER_DISK=$(pvesm list "$CONTAINER_STORAGE" | grep -E "(lxc|vm)/$CURRENT_ID/" | awk '{print $2}' | head -n 1)
if [ -n "$CONTAINER_DISK" ]; then
    REQUIRED_SPACE=$CONTAINER_DISK
    debug_log "Estimated disk size from pvesm: $((REQUIRED_SPACE / 1024 / 1024)) MB"
else
    if [ "$ENTITY_TYPE" = "CT" ]; then
        CONTAINER_SIZE=$(grep '^rootfs:' "$CONFIG_FILE" | grep -oP 'size=\K[^,]+' | head -n 1)
    else
        # Sum all disk sizes for VMs (e.g., size=32G)
        CONTAINER_SIZE=$(grep -E '^(scsi|ide|sata|virtio)[0-9]+:' "$CONFIG_FILE" | grep -oP 'size=\K[0-9]+[GM]' | awk '{sum += ($1 ~ /G/ ? $1*1024 : $1)} END {print sum}')
    fi
    if [ -n "$CONTAINER_SIZE" ]; then
        case "$CONTAINER_SIZE" in
            *G) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'G'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024 * 1024)) ;;
            *M) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'M'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024 * 1024)) ;;
            *K) REQUIRED_SPACE=$(echo "$CONTAINER_SIZE" | tr -d 'K'); REQUIRED_SPACE=$((REQUIRED_SPACE * 1024)) ;;
            *) REQUIRED_SPACE=$((CONTAINER_SIZE * 1024 * 1024)) ;; # Assume MB if no unit
        esac
        debug_log "Estimated disk size from config: $((REQUIRED_SPACE / 1024 / 1024)) MB"
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
if [ $? -ne 0 ]; then
    log "Error: Source storage $CONTAINER_STORAGE does not have sufficient space for backup."
    exit 2
fi

# Configure backup storage
configure_backup_storage

# Check disk space for backup storage
debug_log "Checking disk space for backup storage $BACKUP_STORAGE"
check_disk_space "$BACKUP_STORAGE" "$REQUIRED_SPACE"
if [ $? -ne 0 ]; then
    log "Error: Backup storage $BACKUP_STORAGE does not have sufficient space after configuration."
    exit 2
fi

# Check if the CT is unprivileged (only for CTs)
UNPRIVILEGED=""
if [ "$ENTITY_TYPE" = "CT" ]; then
    debug_log "Checking if CT $CURRENT_ID is unprivileged"
    if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
        UNPRIVILEGED="--unprivileged"
        log "Detected unprivileged container. Will use --unprivileged flag for restore."
        debug_log "Unprivileged container detected, setting UNPRIVILEGED=$UNPRIVILEGED"
    fi
fi

# Stop the CT/VM if running
debug_log "Checking status of $ENTITY_TYPE $CURRENT_ID"
if [ "$ENTITY_TYPE" = "CT" ]; then
    STATUS=$(pct status "$CURRENT_ID" 2>/dev/null)
    if echo "$STATUS" | grep -q "status: running"; then
        log "Stopping container $CURRENT_ID..."
        debug_log "Attempting to stop CT $CURRENT_ID"
        pct stop "$CURRENT_ID" || {
            log "Error: Failed to stop container $CURRENT_ID."
            exit 2
        }
        debug_log "Stopped CT $CURRENT_ID"
    else
        log "Container $CURRENT_ID is already stopped (status: $STATUS)."
        debug_log "CT $CURRENT_ID already stopped: $STATUS"
    fi
else
    STATUS=$(qm status "$CURRENT_ID" 2>/dev/null)
    if echo "$STATUS" | grep -q "status: running"; then
        log "Stopping virtual machine $CURRENT_ID..."
        debug_log "Attempting to stop VM $CURRENT_ID"
        qm stop "$CURRENT_ID" || {
            log "Error: Failed to stop virtual machine $CURRENT_ID."
            exit 2
        }
        debug_log "Stopped VM $CURRENT_ID"
    else
        log "Virtual machine $CURRENT_ID is already stopped (status: $STATUS)."
        debug_log "VM $CURRENT_ID already stopped: $STATUS"
    fi
fi

# Check for existing backup or create a new one
log "Searching for existing backup for $ENTITY_TYPE $CURRENT_ID..."
debug_log "Searching backups in $BACKUP_STORAGE with 'pvesm list'"
if [ "$ENTITY_TYPE" = "CT" ]; then
    BACKUP_FILE=$(pvesm list "$BACKUP_STORAGE" | grep "vzdump-lxc-$CURRENT_ID-" | awk '{print $1}' | head -n 1)
else
    BACKUP_FILE=$(pvesm list "$BACKUP_STORAGE" | grep "vzdump-qemu-$CURRENT_ID-" | awk '{print $1}' | head -n 1)
fi
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
    debug_log "Creating new backup with vzdump for $ENTITY_TYPE $CURRENT_ID"
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    debug_log "vzdump exit status: $VZDUMP_STATUS"
    if [ $VZDUMP_STATUS -ne 0 ]; then
        log "Error: Backup failed for $ENTITY_TYPE $CURRENT_ID."
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
if [ $? -ne 0 ]; then
    log "Error: Source storage $CONTAINER_STORAGE does not have sufficient space for restore."
    exit 2
fi

# Restore the CT/VM with the new ID
log "Restoring $ENTITY_TYPE as $NEW_ID..."
debug_log "Restoring $ENTITY_TYPE $NEW_ID from $BACKUP_FILE"
if [ "$ENTITY_TYPE" = "CT" ]; then
    pct restore "$NEW_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
        log "Error: Failed to restore container as $NEW_ID. Old container $CURRENT_ID preserved."
        debug_log "Restore failed for CT $NEW_ID"
        exit 2
    }
else
    qmrestore "$BACKUP_FILE" "$NEW_ID" --storage "$CONTAINER_STORAGE" || {
        log "Error: Failed to restore virtual machine as $NEW_ID. Old virtual machine $CURRENT_ID preserved."
        debug_log "Restore failed for VM $NEW_ID"
        exit 2
    }
fi
debug_log "Restored $ENTITY_TYPE $NEW_ID"

# Start the new CT/VM
log "Starting $ENTITY_TYPE $NEW_ID..."
debug_log "Starting $ENTITY_TYPE $NEW_ID"
if [ "$ENTITY_TYPE" = "CT" ]; then
    pct start "$NEW_ID" || {
        log "Error: Failed to start container $NEW_ID. Old container $CURRENT_ID preserved."
        debug_log "Start failed for CT $NEW_ID"
        exit 2
    }
else
    qm start "$NEW_ID" || {
        log "Error: Failed to start virtual machine $NEW_ID. Old virtual machine $CURRENT_ID preserved."
        debug_log "Start failed for VM $NEW_ID"
        exit 2
    }
fi
debug_log "Started $ENTITY_TYPE $NEW_ID"

# Verify the CT/VM is running
debug_log "Verifying $ENTITY_TYPE $NEW_ID is running"
if [ "$ENTITY_TYPE" = "CT" ]; then
    if pct status "$NEW_ID" | grep -q "status: running"; then
        log "New container $NEW_ID is running."
        debug_log "Verified CT $NEW_ID is running"
    else
        log "Error: Container $NEW_ID restored but not running. Old container $CURRENT_ID preserved."
        log "Check logs with 'journalctl -u pve*'."
        debug_log "CT $NEW_ID not running"
        exit 2
    fi
else
    if qm status "$NEW_ID" | grep -q "status: running"; then
        log "New virtual machine $NEW_ID is running."
        debug_log "Verified VM $NEW_ID is running"
    else
        log "Error: Virtual machine $NEW_ID restored but not running. Old virtual machine $CURRENT_ID preserved."
        log "Check logs with 'journalctl -u pve*'."
        debug_log "VM $NEW_ID not running"
        exit 2
    fi
fi

# Delete the original CT/VM
log "Deleting original $ENTITY_TYPE $CURRENT_ID..."
debug_log "Deleting $ENTITY_TYPE $CURRENT_ID"
if [ "$ENTITY_TYPE" = "CT" ]; then
    pct destroy "$CURRENT_ID" || {
        log "Warning: Failed to delete original container $CURRENT_ID. New container $NEW_ID is running."
        debug_log "Failed to delete CT $CURRENT_ID"
        exit 2
    }
else
    qm destroy "$CURRENT_ID" || {
        log "Warning: Failed to delete original virtual machine $CURRENT_ID. New virtual machine $NEW_ID is running."
        debug_log "Failed to delete VM $CURRENT_ID"
        exit 2
    }
fi
debug_log "Deleted $ENTITY_TYPE $CURRENT_ID"

# Final success message
log "Success: $ENTITY_TYPE ID changed from $CURRENT_ID to $NEW_ID and is running."
debug_log "Operation completed successfully"

# Optional cleanup (commented out)
# log "Cleaning up backup file $BACKUP_FILE..."
# rm -f "$BACKUP_FILE"
# debug_log "Cleaned up backup: $BACKUP_FILE"

exit 0
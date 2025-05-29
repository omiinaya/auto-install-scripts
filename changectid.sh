#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Features an interactive whiptail menu for container selection, styled like community-scripts/ProxmoxVE
# Falls back to text menu if whiptail fails, validates new CT ID
# Usage: ./change_ct_id.sh

# Colors and emojis for community-scripts/ProxmoxVE style
BLUE='\e[34m'
YELLOW='\e[33m'
RED='\e[31m'
GREEN='\e[32m'
CYAN='\e[36m'
WHITE='\e[97m'
CL='\e[0m'
CHECK="${GREEN}✅${CL}"
CROSS="${RED}❌${CL}"
INFO="${CYAN}ℹ️${CL}"
GEAR="${YELLOW}⚙️${CL}"
ID_EMOJI="${CYAN}🆔${CL}"

# Debugging function
debug() {
    echo -e "${INFO} ${CYAN}DEBUG: $1${CL}" >&2
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${CROSS} ${RED}This script must be run as root.${CL}"
    exit 1
fi

# Check if Proxmox tools are available
if ! command -v pct >/dev/null 2>&1 || ! command -v vzdump >/dev/null 2>&1; then
    echo -e "${CROSS} ${RED}Proxmox tools (pct or vzdump) not found. Is this a Proxmox system?${CL}"
    exit 1
fi

# Define backup storage
BACKUP_STORAGE="local"
BACKUP_DIR="/var/lib/vz/dump"

# Check if backup storage exists
if ! pvesm status | grep -q "^$BACKUP_STORAGE"; then
    echo -e "${CROSS} ${RED}Backup storage '$BACKUP_STORAGE' not found.${CL}"
    exit 1
fi

# Get list of containers
debug "Fetching container list..."
CONTAINERS=()
CT_IDS=$(pct list 2>/dev/null | awk 'NR>1 {print $1}')
if [ -z "$CT_IDS" ]; then
    debug "No containers found via pct list."
    echo -e "${CROSS} ${RED}No containers found. Check Proxmox configuration.${CL}"
    exit 1
fi

for CT_ID in $CT_IDS; do
    if [ -f "/etc/pve/lxc/$CT_ID.conf" ]; then
        CT_NAME=$(grep -E "^hostname:" "/etc/pve/lxc/$CT_ID.conf" | awk '{print $2}' | head -n 1)
        CT_NAME=${CT_NAME:-"Unnamed"}
        CT_STATUS=$(pct status "$CT_ID" 2>/dev/null | grep -o "status:.*" | awk '{print $2}' || echo "Unknown")
        CONTAINERS+=("$CT_ID" "$CT_NAME (Status: $CT_STATUS)")
        debug "Found container: ID=$CT_ID, Name=$CT_NAME, Status=$CT_STATUS"
    else
        debug "Config file missing for CT $CT_ID"
    fi
done

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    debug "No valid containers with config files found."
    echo -e "${CROSS} ${RED}No valid containers found. Check /etc/pve/lxc/*.conf.${CL}"
    exit 1
fi

# Check if whiptail is installed and functional
WHIPTAIL_AVAILABLE=0
if command -v whiptail >/dev/null 2>&1; then
    # Test whiptail with a simple dialog
    whiptail --msgbox "Testing whiptail..." 8 40 2>/dev/null && WHIPTAIL_AVAILABLE=1
fi

if [ $WHIPTAIL_AVAILABLE -eq 0 ]; then
    debug "Whiptail not available or failed. Installing or using text fallback..."
    if command -v apt-get >/dev/null 2>&1; then
        echo -e "${INFO} ${CYAN}Installing whiptail...${CL}"
        apt-get update && apt-get install -y whiptail && WHIPTAIL_AVAILABLE=1 || {
            echo -e "${CROSS} ${YELLOW}Failed to install whiptail. Using text-based menu.${CL}"
        }
    fi
fi

# Select container
if [ $WHIPTAIL_AVAILABLE -eq 1 ]; then
    debug "Displaying whiptail menu with ${#CONTAINERS[@]} options"
    CURRENT_CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "${GEAR} Select Container to Change ID" \
        --radiolist "Choose a container:" 15 60 8 \
        "${CONTAINERS[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$CURRENT_CT_ID" ]; then
        debug "Whiptail container selection canceled or failed"
        echo -e "${CROSS} ${YELLOW}Container selection canceled.${CL}"
        exit 0
    fi
else
    debug "Using text-based container selection"
    echo -e "${INFO} ${CYAN}Available containers:${CL}"
    for ((i=0; i<${#CONTAINERS[@]}; i+=2)); do
        echo "[$((i/2 + 1))] ${CONTAINERS[i]}: ${CONTAINERS[i+1]}"
    done
    while true; do
        read -p "Enter the number of the container to select (1-$(( ${#CONTAINERS[@]}/2 ))): " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le $(( ${#CONTAINERS[@]}/2 )) ]; then
            CURRENT_CT_ID=${CONTAINERS[$(( (CHOICE-1)*2 ))]}
            break
        fi
        echo -e "${CROSS} ${RED}Invalid choice. Enter a number between 1 and $(( ${#CONTAINERS[@]}/2 )).${CL}"
    done
fi
echo -e "${CHECK} ${GREEN}Selected container: $CURRENT_CT_ID${CL}"

# Get container storage from configuration
CONFIG_FILE="/etc/pve/lxc/$CURRENT_CT_ID.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${CROSS} ${RED}Configuration file $CONFIG_FILE not found.${CL}"
    exit 1
fi

CONTAINER_STORAGE=$(grep '^rootfs:' "$CONFIG_FILE" | awk -F: '{print $2}' | awk '{print $1}')
if [ -z "$CONTAINER_STORAGE" ]; then
    echo -e "${CROSS} ${RED}Could not detect container storage from $CONFIG_FILE.${CL}"
    exit 1
fi

# Verify container storage exists
if ! pvesm status | grep -q "^$CONTAINER_STORAGE"; then
    echo -e "${CROSS} ${RED}Container storage '$CONTAINER_STORAGE' not found.${CL}"
    exit 1
fi
echo -e "${CHECK} ${GREEN}Detected container storage: $CONTAINER_STORAGE${CL}"

# Check if the container is unprivileged
UNPRIVILEGED=""
if grep -q "unprivileged: 1" "$CONFIG_FILE"; then
    UNPRIVILEGED="--unprivileged"
    echo -e "${CHECK} ${GREEN}Detected unprivileged container. Will use --unprivileged flag for restore.${CL}"
fi

# Prompt for new CT ID
if [ $WHIPTAIL_AVAILABLE -eq 1 ]; then
    debug "Displaying whiptail input for new CT ID"
    while true; do
        NEW_CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
            --title "${ID_EMOJI} Enter New Container ID" \
            --inputbox "Enter the new CT ID (positive integer, not in use):" 10 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            debug "Whiptail new CT ID input canceled"
            echo -e "${CROSS} ${YELLOW}New CT ID input canceled.${CL}"
            exit 0
        fi
        if ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
            whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "${CROSS} Invalid Input" \
                --msgbox "CT ID must be a positive integer." 8 60
            continue
        fi
        if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
            whiptail --backtitle "Proxmox VE Helper Scripts" \
                --title "${CROSS} ID In Use" \
                --msgbox "CT ID $NEW_CT_ID is already in use. Choose another." 8 60
            continue
        fi
        break
    done
else
    debug "Using text-based input for new CT ID"
    while true; do
        read -p "Enter the new CT ID (positive integer, not in use): " NEW_CT_ID
        if ! [[ "$NEW_CT_ID" =~ ^[0-9]+$ ]]; then
            echo -e "${CROSS} ${RED}CT ID must be a positive integer.${CL}"
            continue
        fi
        if pct status "$NEW_CT_ID" >/dev/null 2>&1; then
            echo -e "${CROSS} ${RED}CT ID $NEW_CT_ID is already in use. Choose another.${CL}"
            continue
        fi
        break
    done
fi
echo -e "${CHECK} ${GREEN}New CT ID: $NEW_CT_ID${CL}"

# Stop the container if running
echo -e "${INFO} ${CYAN}Checking container $CURRENT_CT_ID status...${CL}"
STATUS=$(pct status "$CURRENT_CT_ID" 2>/dev/null)
if echo "$STATUS" | grep -q "status: running"; then
    echo -e "${INFO} ${CYAN}Stopping container $CURRENT_CT_ID...${CL}"
    pct stop "$CURRENT_CT_ID" || {
        echo -e "${CROSS} ${RED}Failed to stop container $CURRENT_CT_ID.${CL}"
        exit 1
    }
else
    echo -e "${CHECK} ${GREEN}Container $CURRENT_CT_ID is already stopped (status: $STATUS).${CL}"
fi

# Check for existing backup or create a new one
echo -e "${INFO} ${CYAN}Searching for existing backup for CT $CURRENT_CT_ID...${CL}"
BACKUP_FILE=$(ls -t "$BACKUP_DIR/vzdump-lxc-$CURRENT_CT_ID-"*.tar.zst 2>/dev/null | head -n 1)
if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    echo -e "${CHECK} ${GREEN}Found existing backup: $BACKUP_FILE${CL}"
else
    echo -e "${INFO} ${CYAN}No existing backup found. Checking permissions and path...${CL}"
    ls -l "$BACKUP_DIR" 2>/dev/null || echo -e "${CROSS} ${RED}Cannot access $BACKUP_DIR${CL}"
    echo -e "${INFO} ${CYAN}Creating new backup of container $CURRENT_CT_ID...${CL}"
    VZDUMP_OUTPUT=$(vzdump "$CURRENT_CT_ID" --compress zstd --storage "$BACKUP_STORAGE" --mode snapshot 2>&1)
    VZDUMP_STATUS=$?
    if [ $VZDUMP_STATUS -ne 0 ]; then
        echo -e "${CROSS} ${RED}Backup failed for container $CURRENT_CT_ID.${CL}"
        echo "$VZDUMP_OUTPUT"
        exit 1
    fi
    BACKUP_FILE=$(echo "$VZDUMP_OUTPUT" | grep -oP "creating vzdump archive '\K[^']+" | head -n 1)
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${CROSS} ${RED}No backup file found after vzdump. Expected in $BACKUP_DIR.${CL}"
        ls -l "$BACKUP_DIR" 2>/dev/null
        exit 1
    fi
    echo -e "${CHECK} ${GREEN}New backup created: $BACKUP_FILE${CL}"
fi

# Delete the original container
echo -e "${INFO} ${CYAN}Deleting original container $CURRENT_CT_ID...${CL}"
pct destroy "$CURRENT_CT_ID" || {
    echo -e "${CROSS} ${RED}Failed to delete container $CURRENT_CT_ID.${CL}"
    exit 1
}

# Restore the container with the new CT ID
echo -e "${INFO} ${CYAN}Restoring container as $NEW_CT_ID...${CL}"
pct restore "$NEW_CT_ID" "$BACKUP_FILE" --storage "$CONTAINER_STORAGE" $UNPRIVILEGED || {
    echo -e "${CROSS} ${RED}Failed to restore container as $NEW_CT_ID.${CL}"
    exit 1
}

# Start the new container
echo -e "${INFO} ${CYAN}Starting container $NEW_CT_ID...${CL}"
pct start "$NEW_CT_ID" || {
    echo -e "${INFO} ${CYAN}Failed to start container $NEW_CT_ID.${CL}"
    exit 1
}

# Verify the container is running
if pct status "$NEW_CT_ID" | grep -q "status: running"; then
    echo -e "${CHECK} ${GREEN}Success: Container ID changed from $CURRENT_CT_ID to $NEW_CT_ID and is running.${CL}"
else
    echo -e "${CROSS} ${RED}Warning: Container $NEW_CT_ID restored but not running. Check logs with 'journalctl -u pve*'.${CL}"
    exit 1
fi

# Optional cleanup (commented out)
# echo -e "${INFO} ${CYAN}Cleaning up backup file $BACKUP_FILE...${CL}"
# rm -f "$BACKUP_FILE"

exit 0
#!/bin/bash
# Script to change the CT ID of a Proxmox LXC container using backup and restore
# Features an interactive whiptail menu for container selection, styled like community-scripts/ProxmoxVE
# Dynamically finds or creates backups, validates new CT ID
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

# Check if whiptail is installed
if ! command -v whiptail >/dev/null 2>&1; then
    echo -e "${INFO} ${CYAN}Installing whiptail...${CL}"
    apt-get update && apt-get install -y whiptail || {
        echo -e "${CROSS} ${RED}Failed to install whiptail.${CL}"
        exit 1
    }
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
CONTAINERS=()
while read -r CT_ID; do
    if [ -f "/etc/pve/lxc/$CT_ID.conf" ]; then
        CT_NAME=$(grep -E "^hostname:" "/etc/pve/lxc/$CT_ID.conf" | awk '{print $2}' | head -n 1)
        CT_NAME=${CT_NAME:-"Unnamed"}
        CT_STATUS=$(pct status "$CT_ID" 2>/dev/null | grep -o "status:.*" | awk '{print $2}' || echo "Unknown")
        CONTAINERS+=("$CT_ID" "$CT_NAME (Status: $CT_STATUS)")
    fi
done < <(pct list | awk 'NR>1 {print $1}')

if [ ${#CONTAINERS[@]} -eq 0 ]; then
    echo -e "${CROSS} ${RED}No containers found.${CL}"
    exit 1
fi

# Select container using whiptail (styled like community-scripts/ProxmoxVE)
CURRENT_CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
    --title "${GEAR} Select Container to Change ID" \
    --radiolist "Choose a container:" 15 60 8 \
    "${CONTAINERS[@]}" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ] || [ -z "$CURRENT_CT_ID" ]; then
    echo -e "${CROSS} ${YELLOW}Container selection canceled.${CL}"
    exit 0
fi

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

# Prompt for new CT ID using whiptail
while true; do
    NEW_CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
        --title "${ID_EMOJI} Enter New Container ID" \
        --inputbox "Enter the new CT ID (positive integer, not in use):" 10 60 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
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
    echo -e "${CROSS} ${RED}Failed to start container $NEW_CT_ID.${CL}"
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
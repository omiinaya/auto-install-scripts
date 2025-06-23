#!/bin/bash

# Script to fix ComfyUI systemd service with correct user and paths

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Function to ask yes/no questions and keep asking until valid response
ask_yes_no() {
    local prompt="$1"
    local default="$2"  # "y" or "n"
    local response
    
    while true; do
        if [ "$default" = "y" ]; then
            read -p "$prompt (Y/n): " -n 1 -r response
        else
            read -p "$prompt (y/N): " -n 1 -r response
        fi
        echo
        
        # Handle empty response (just pressed Enter)
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) warn "Please answer yes (y) or no (n).";;
        esac
    done
}

# Check root access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges. Please run with sudo access."
    fi
}

# Stop the current service
stop_service() {
    log "Stopping ComfyUI service..."
    
    if systemctl is-active --quiet comfyui; then
        sudo systemctl stop comfyui
        log "ComfyUI service stopped"
    else
        info "ComfyUI service is not running"
    fi
}

# Verify ComfyUI installation
verify_installation() {
    log "Verifying ComfyUI installation..."
    
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    if [ ! -d "$USER_HOME/comfy" ]; then
        error "ComfyUI installation not found at $USER_HOME/comfy"
    fi
    
    if [ ! -d "$USER_HOME/comfy-env" ]; then
        error "ComfyUI virtual environment not found at $USER_HOME/comfy-env"
    fi
    
    if [ ! -f "$USER_HOME/launch_comfyui.sh" ]; then
        error "Launch script not found at $USER_HOME/launch_comfyui.sh"
    fi
    
    if [ ! -x "$USER_HOME/launch_comfyui.sh" ]; then
        warn "Launch script is not executable, fixing..."
        chmod +x "$USER_HOME/launch_comfyui.sh"
    fi
    
    log "ComfyUI installation verified"
}

# Fix launcher script if it has incorrect argument format
fix_launcher_script() {
    log "Checking launcher script format..."
    
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    LAUNCHER_SCRIPT="$USER_HOME/launch_comfyui.sh"
    
    # Check if launcher script has the old incorrect format
    if grep -q "comfy launch --listen" "$LAUNCHER_SCRIPT" 2>/dev/null; then
        warn "Found incorrect argument format in launcher script, fixing..."
        
        # Backup the original
        cp "$LAUNCHER_SCRIPT" "$LAUNCHER_SCRIPT.backup"
        
        # Fix the argument format
        sed -i 's/comfy launch --listen 0\.0\.0\.0/comfy launch -- --listen 0.0.0.0/g' "$LAUNCHER_SCRIPT"
        
        log "Launcher script argument format fixed"
        info "Backup saved as: $LAUNCHER_SCRIPT.backup"
    elif grep -q "comfy launch -- --listen" "$LAUNCHER_SCRIPT" 2>/dev/null; then
        log "Launcher script already has correct argument format"
    else
        info "Launcher script format check completed"
    fi
}

# Create new service file
create_service() {
    log "Creating new ComfyUI systemd service..."
    
    SERVICE_FILE="/etc/systemd/system/comfyui.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    # Check if we're fixing a root installation
    if [[ "$CURRENT_USER" == "root" ]]; then
        warn "You're running as root. The service will use root paths."
        info "For better security, consider reinstalling ComfyUI as a regular user."
    fi
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=ComfyUI Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/launch_comfyui.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=comfyui

[Install]
WantedBy=multi-user.target
EOF

    log "New systemd service file created"
    info "Service will execute: $USER_HOME/launch_comfyui.sh"
}

# Reload and start service
reload_service() {
    log "Reloading systemd and starting ComfyUI service..."
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable the service
    sudo systemctl enable comfyui
    
    # Start the service
    if sudo systemctl start comfyui; then
        log "ComfyUI service started successfully"
    else
        error "Failed to start ComfyUI service"
    fi
    
    # Wait a moment for service to stabilize
    sleep 3
    
    # Check service status
    if systemctl is-active --quiet comfyui; then
        log "ComfyUI service is running successfully!"
        info "You can check the status with: sudo systemctl status comfyui"
        info "You can view logs with: sudo journalctl -u comfyui -f"
        info "ComfyUI should be accessible at:"
        echo "    Local: http://localhost:8188"
        echo "    Network: http://$(hostname -I | awk '{print $1}'):8188"
    else
        warn "Service may not be running properly."
        info "Check status with: sudo systemctl status comfyui"
        info "Check logs with: sudo journalctl -u comfyui -n 20"
        info "Try running the launcher manually to test: ~/launch_comfyui.sh"
    fi
}

# Main function
main() {
    echo "=================================="
    log "ComfyUI Service Fix Script"
    echo "=================================="
    echo
    info "This script will fix the ComfyUI systemd service"
    info "It will stop the current service and recreate it with correct paths"
    echo
    
    if ! ask_yes_no "Do you want to continue?" "y"; then
        info "Operation cancelled."
        exit 0
    fi
    
    check_sudo
    verify_installation
    fix_launcher_script
    stop_service
    create_service
    reload_service
    
    echo
    echo "=================================="
    log "ComfyUI Service Fix Complete!"
    echo "=================================="
    echo
    info "Service management commands:"
    echo "  sudo systemctl start comfyui     : Start the service"
    echo "  sudo systemctl stop comfyui      : Stop the service"
    echo "  sudo systemctl restart comfyui   : Restart the service"
    echo "  sudo systemctl status comfyui    : Check service status"
    echo "  sudo journalctl -u comfyui -f    : View service logs"
    echo
    info "ComfyUI should be accessible at:"
    echo "  Local: http://localhost:8188"
    echo "  Network: http://your-server-ip:8188"
}

# Run main function
main "$@" 
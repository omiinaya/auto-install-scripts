#!/bin/bash

# Quick fix for ComfyUI launcher script
# This fixes the --listen argument issue

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log "Fixing ComfyUI launcher script..."

LAUNCHER_SCRIPT="$HOME/launch_comfyui.sh"

if [ ! -f "$LAUNCHER_SCRIPT" ]; then
    error "Launcher script not found at $LAUNCHER_SCRIPT"
fi

# Backup the original
cp "$LAUNCHER_SCRIPT" "$LAUNCHER_SCRIPT.backup"
info "Created backup at $LAUNCHER_SCRIPT.backup"

# Create the fixed launcher script
cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# ComfyUI Launcher Script
# This script activates the virtual environment and launches ComfyUI

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

VENV_DIR="$HOME/comfy-env"
COMFY_DIR="$HOME/comfy"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Virtual environment not found at $VENV_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Check if ComfyUI directory exists
if [ ! -d "$COMFY_DIR" ]; then
    echo -e "${RED}ComfyUI directory not found at $COMFY_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to ComfyUI directory
cd "$COMFY_DIR"

echo -e "${GREEN}Starting ComfyUI with network access...${NC}"
echo -e "${GREEN}Access ComfyUI locally at: http://localhost:8188${NC}"
echo -e "${GREEN}Access ComfyUI from network at: http://$(hostname -I | awk '{print $1}'):8188${NC}"
echo -e "${GREEN}Press Ctrl+C to stop ComfyUI${NC}"
echo

# Launch ComfyUI directly with Python (not through comfy-cli)
# ComfyUI main.py supports all the standard arguments
python main.py --listen 0.0.0.0 --port 8188 "$@"
EOF

# Make sure it's executable
chmod +x "$LAUNCHER_SCRIPT"

log "Launcher script fixed successfully!"

# Restart the systemd service if it exists
if systemctl is-enabled comfyui.service >/dev/null 2>&1; then
    info "Restarting ComfyUI systemd service..."
    sudo systemctl restart comfyui.service
    sleep 2
    
    # Check status
    if systemctl is-active comfyui.service >/dev/null 2>&1; then
        log "ComfyUI service is now running successfully!"
    else
        warn "Service may still have issues. Check with: journalctl -u comfyui"
    fi
else
    info "No systemd service found. You can start ComfyUI manually with: $LAUNCHER_SCRIPT"
fi

log "Fix completed!" 
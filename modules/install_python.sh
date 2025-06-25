#!/bin/bash

# Python Installation Module for Debian 12 (Proxmox Container)
# This module contains the exact Python installation code from install_comfyui.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check for and install sudo first if not present
ensure_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        log "Installing sudo..."
        apt update
        apt install -y sudo
    fi
}

# Install Python and related tools (EXACT COPY from install_comfyui.sh)
install_python() {
    log "Installing Python and related tools..."
    
    ensure_sudo
    
    # Install Python 3.11 (Debian 12 default) and pip
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-full \
        python3-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    info "Python version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.9+
    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)"; then
        log "Python version is sufficient (3.9+)"
    else
        error "Python version is too old. ComfyUI requires Python 3.9 or higher."
    fi
    
    # Skip global pip upgrade due to externally-managed-environment
    # We'll upgrade pip inside the virtual environment instead
    info "Skipping global pip upgrade (will upgrade in virtual environment)"
}

# Main function for standalone usage
main() {
    if [ $# -eq 0 ]; then
        echo "Python Installation Module"
        echo "Usage: $0"
        echo
        echo "This module installs Python and related tools exactly as in install_comfyui.sh"
        exit 1
    fi
    
    case "$1" in
        *)
            install_python
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
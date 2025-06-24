#!/bin/bash

# Standalone NVIDIA Drivers Installer for Debian 12 (Proxmox Container)
# This script installs NVIDIA drivers with CUDA support

set -e  # Exit on any error

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

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "This script should not be run as root. Please run as a regular user with sudo privileges."
        if ! ask_yes_no "Do you want to continue anyway?" "y"; then
            exit 1
        fi
    fi
}

# Check system compatibility
check_system() {
    log "Checking system compatibility..."
    
    # Check if running on Debian
    if ! grep -q "Debian" /etc/os-release; then
        warn "This script is designed for Debian 12. Your system:"
        cat /etc/os-release | grep PRETTY_NAME
        if ! ask_yes_no "Do you want to continue anyway?" "y"; then
            exit 1
        fi
    fi
    
    # Check Debian version
    DEBIAN_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    if [ "$DEBIAN_VERSION" != "12" ]; then
        warn "This script is optimized for Debian 12. You are running Debian $DEBIAN_VERSION"
        if ! ask_yes_no "Do you want to continue anyway?" "y"; then
            exit 1
        fi
    fi
    
    info "System check passed: Debian $DEBIAN_VERSION"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
}

# Install basic dependencies
install_basic_deps() {
    log "Installing basic dependencies..."
    sudo apt install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        ca-certificates
}

# Install NVIDIA drivers for Proxmox container
install_nvidia_drivers() {
    log "Installing NVIDIA drivers for Proxmox container..."
    
    # Check if NVIDIA drivers are already installed
    if command -v nvidia-smi >/dev/null 2>&1; then
        info "NVIDIA drivers appear to be already installed:"
        nvidia-smi --version 2>/dev/null || true
        if ! ask_yes_no "Do you want to reinstall NVIDIA drivers?" "y"; then
            log "Skipping NVIDIA driver installation"
            return 0
        fi
    fi
    
    # Add NVIDIA CUDA repository
    info "Adding NVIDIA CUDA repository..."
    curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    
    # Update package list
    sudo apt update
    
    # Install NVIDIA drivers
    info "Installing NVIDIA drivers..."
    sudo apt -V install -y nvidia-driver-cuda nvidia-kernel-dkms
    
    # Reconfigure NVIDIA kernel DKMS
    info "Reconfiguring NVIDIA kernel DKMS..."
    sudo dpkg-reconfigure nvidia-kernel-dkms
    
    # Clean up
    rm -f cuda-keyring_1.1-1_all.deb
    
    log "NVIDIA drivers installed successfully"
}

# Test NVIDIA installation
test_nvidia() {
    log "Testing NVIDIA installation..."
    
    # Test nvidia-smi
    if command -v nvidia-smi >/dev/null 2>&1; then
        info "nvidia-smi is available:"
        nvidia-smi --version
        
        # Try to get GPU information
        info "GPU information:"
        nvidia-smi -L || warn "Could not list GPUs (this is normal in some container environments)"
    else
        warn "nvidia-smi not found. Installation may have failed."
        return 1
    fi
    
    # Check for NVIDIA kernel modules
    info "Checking NVIDIA kernel modules:"
    lsmod | grep nvidia || warn "NVIDIA kernel modules not loaded (may require reboot)"
    
    log "NVIDIA driver test completed"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "NVIDIA Drivers Installation Complete!"
    echo "=================================="
    echo
    info "Installation Summary:"
    echo "  - NVIDIA drivers with CUDA support installed"
    echo "  - Repository: NVIDIA CUDA repository for Debian 12"
    echo "  - Packages: nvidia-driver-cuda, nvidia-kernel-dkms"
    echo
    info "Next Steps:"
    echo "  1. Reboot your system if this is the first NVIDIA driver installation"
    echo "  2. Test with: nvidia-smi"
    echo "  3. For CUDA development, run the CUDA/nvcc installer script"
    echo
    info "Verification Commands:"
    echo "  nvidia-smi --version    : Check driver version"
    echo "  nvidia-smi -L          : List GPUs"
    echo "  lsmod | grep nvidia     : Check kernel modules"
    echo
    if [ -f "/var/log/nvidia-installer.log" ]; then
        info "Installation logs available at: /var/log/nvidia-installer.log"
    fi
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "NVIDIA Drivers Installer for Debian 12"
    echo "=================================="
    echo
    info "This script will install NVIDIA drivers with CUDA support"
    info "Designed for Debian 12 (Proxmox containers)"
    echo
    
    if ! ask_yes_no "Do you want to continue with the NVIDIA driver installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi
    
    check_root
    check_system
    update_system
    install_basic_deps
    install_nvidia_drivers
    test_nvidia
    print_instructions
}

# Run main function
main "$@" 
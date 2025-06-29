#!/bin/bash
set -e

# NVIDIA Drivers Installation Module - Simplified
# No questions, just install drivers

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Install NVIDIA drivers
install_nvidia_drivers() {
    log "Installing NVIDIA drivers..."
    
    # Update system
    apt update && apt upgrade -y
    
    # Install basic dependencies
    apt install -y \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        ca-certificates
    
    # Add NVIDIA CUDA repository
    info "Adding NVIDIA CUDA repository..."
    curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    apt update
    
    # Install NVIDIA drivers
    info "Installing NVIDIA drivers with CUDA support..."
    apt install -y nvidia-driver-cuda nvidia-kernel-dkms
    
    # Reconfigure NVIDIA kernel DKMS
    dpkg-reconfigure nvidia-kernel-dkms
    
    # Clean up
    rm -f cuda-keyring_1.1-1_all.deb
    
    # Verify installation
    if command -v nvidia-smi >/dev/null 2>&1; then
        info "NVIDIA drivers installed successfully"
        nvidia-smi --version
    else
        error "NVIDIA driver installation failed"
    fi
    
    log "NVIDIA drivers installation completed"
}

# Main function
main() {
    install_nvidia_drivers
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
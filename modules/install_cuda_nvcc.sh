#!/bin/bash
set -e

# CUDA Toolkit Installation Module - Simplified
# This module installs a specified version of the CUDA toolkit.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Logging Functions ---
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    # No longer exiting to allow apt to handle the error
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# --- Main Installation Function ---
install_cuda_nvcc() {
    local requested_version="$1"

    if [ -z "$requested_version" ]; then
        error "No CUDA version specified."
        return 1
    fi

    local cuda_version_dash
    cuda_version_dash=$(echo "$requested_version" | tr '.' '-')

    log "Starting installation for CUDA toolkit version $requested_version"

    # 1. Update system and setup CUDA repository
    apt-get update
    if ! apt-cache policy | grep -q "developer.download.nvidia.com"; then
        info "Adding NVIDIA CUDA repository..."
        # The keyring method is more robust
        curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
        if ! dpkg -i cuda-keyring_1.1-1_all.deb; then
            error "Failed to install CUDA keyring."
            rm -f cuda-keyring_1.1-1_all.deb
            return 1
        fi
        apt-get update
        rm -f cuda-keyring_1.1-1_all.deb
    fi

    # 2. Install CUDA toolkit packages
    info "Attempting to install CUDA toolkit packages for version $requested_version..."
    if ! apt-get install -y --allow-downgrades \
        "cuda-toolkit-${cuda_version_dash}" \
        "cuda-nvcc-${cuda_version_dash}"; then
        error "Failed to install CUDA toolkit for version $requested_version."
        warn "Please check if the version is available in the NVIDIA repository for your system."
        return 1
    fi

    # 3. Configure environment
    info "Configuring CUDA environment..."
    local cuda_path="/usr/local/cuda-${requested_version}"
    
    if [ ! -d "$cuda_path" ]; then
        error "CUDA installation directory not found at $cuda_path"
        return 1
    fi

    # Create system-wide profile script
    cat > /etc/profile.d/cuda.sh << EOF
export CUDA_HOME="${cuda_path}"
export PATH="\$CUDA_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="\$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
EOF

    # Source the new environment for the current session
    source /etc/profile.d/cuda.sh

    # 4. Verify installation
    if command -v nvcc &> /dev/null; then
        log "CUDA toolkit $requested_version installation completed successfully."
        info "Active nvcc version: $(nvcc --version | grep 'release')"
    else
        error "nvcc command not found after installation."
        return 1
    fi
}

# This allows the script to be run directly for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ -z "$1" ]; then
        echo "Usage: $0 <cuda-version>"
        exit 1
    fi
    install_cuda_nvcc "$1"
fi 
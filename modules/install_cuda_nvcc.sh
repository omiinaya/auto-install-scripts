#!/bin/bash
set -e

# CUDA Toolkit Installation Module - Simplified with Auto-Detection
# Usage: ./install_cuda_nvcc.sh [version]
# Default version: Auto-detected from nvidia-smi, fallback to 12.6
# Example: ./install_cuda_nvcc.sh 12.4

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Detect CUDA version from nvidia-smi
detect_cuda_version() {
    if command -v nvidia-smi >/dev/null 2>&1; then
        # Get CUDA version from nvidia-smi output
        DETECTED_VERSION=$(nvidia-smi | grep -o "CUDA Version: [0-9]\+\.[0-9]\+" | cut -d' ' -f3)
        if [ -n "$DETECTED_VERSION" ]; then
            info "Detected CUDA version from nvidia-smi: $DETECTED_VERSION"
            echo "$DETECTED_VERSION"
        else
            warn "Could not parse CUDA version from nvidia-smi output"
            echo "12.6"
        fi
    else
        warn "nvidia-smi not found, using fallback version"
        echo "12.6"
    fi
}

# Parse version argument or auto-detect
if [ -n "$1" ]; then
    CUDA_VERSION="$1"
    info "Using specified CUDA version: $CUDA_VERSION"
else
    CUDA_VERSION=$(detect_cuda_version)
    info "Using auto-detected CUDA version: $CUDA_VERSION"
fi

CUDA_VERSION_DASH=$(echo "$CUDA_VERSION" | tr '.' '-')

log "Installing CUDA toolkit version $CUDA_VERSION"

# Install CUDA toolkit
install_cuda_toolkit() {
    log "Installing CUDA toolkit $CUDA_VERSION and nvcc compiler..."
    
    # Update system
    apt update
    
    # Setup CUDA repository if not already present
    if ! apt-cache policy | grep -q "developer.download.nvidia.com"; then
        info "Adding NVIDIA CUDA repository..."
        curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        apt update
        rm -f cuda-keyring_1.1-1_all.deb
    fi
    
    # Install CUDA toolkit for specified version
    info "Installing CUDA toolkit $CUDA_VERSION..."
    apt install -y \
        cuda-toolkit-${CUDA_VERSION_DASH} \
        cuda-compiler-${CUDA_VERSION_DASH} \
        cuda-nvcc-${CUDA_VERSION_DASH} \
        cuda-libraries-dev-${CUDA_VERSION_DASH} \
        cuda-command-line-tools-${CUDA_VERSION_DASH}
    
    # Configure CUDA environment
    info "Configuring CUDA environment..."
    
    # Find nvcc location
    NVCC_PATH=""
    for path in /usr/local/cuda-${CUDA_VERSION}/bin/nvcc /usr/local/cuda/bin/nvcc; do
        if [ -f "$path" ]; then
            NVCC_PATH="$path"
            break
        fi
    done
    
    # If not found in standard locations, search for it
    if [ -z "$NVCC_PATH" ]; then
        NVCC_PATH=$(find /usr -name nvcc -type f 2>/dev/null | head -1)
    fi
    
    if [ -z "$NVCC_PATH" ]; then
        error "nvcc not found after installation"
    fi
    
    # Create global symlink
    ln -sf "$NVCC_PATH" /usr/local/bin/nvcc
    
    # Set up CUDA environment
    CUDA_HOME=$(dirname $(dirname "$NVCC_PATH"))
    
    # Create system-wide CUDA environment
    cat > /etc/profile.d/cuda.sh << EOF
export PATH="$CUDA_HOME/bin:\$PATH"
export CUDA_HOME="$CUDA_HOME"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
EOF
    
    # Add to /etc/environment
    echo "CUDA_HOME=\"$CUDA_HOME\"" >> /etc/environment
    
    # Source the environment
    source /etc/profile.d/cuda.sh
    
    # Verify installation
    if command -v nvcc >/dev/null 2>&1; then
        info "CUDA $CUDA_VERSION installation successful"
        nvcc --version | head -1
    else
        error "CUDA installation failed - nvcc not available"
    fi
    
    log "CUDA toolkit $CUDA_VERSION installation completed"
}

# Main function
main() {
    install_cuda_toolkit
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
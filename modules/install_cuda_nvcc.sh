#!/bin/bash

# Standalone CUDA Toolkit and nvcc Installer for Debian 12
# This script installs CUDA development tools including nvcc compiler

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

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update
}

# Install CUDA repository if not already present
setup_cuda_repository() {
    log "Setting up CUDA repository..."
    
    # Check if CUDA repository is already configured
    if apt-cache policy | grep -q "developer.download.nvidia.com"; then
        info "NVIDIA CUDA repository already configured"
        return 0
    fi
    
    # Add NVIDIA CUDA repository
    info "Adding NVIDIA CUDA repository..."
    curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt update
    
    # Clean up
    rm -f cuda-keyring_1.1-1_all.deb
    
    log "CUDA repository configured successfully"
}

# Install CUDA toolkit and nvcc compiler
install_cuda_toolkit() {
    log "Installing CUDA toolkit and nvcc compiler..."
    
    # Check if nvcc is already available
    if command -v nvcc >/dev/null 2>&1; then
        info "nvcc already available at: $(which nvcc)"
        nvcc --version | head -1
        if ! ask_yes_no "Do you want to reinstall CUDA toolkit?" "y"; then
            log "Skipping CUDA toolkit installation"
            return 0
        fi
    fi
    
    info "Installing CUDA development packages..."
    
    # Install comprehensive CUDA development packages
    # Try multiple package combinations for maximum compatibility
    
    # Primary CUDA packages
    sudo apt install -y \
        cuda-toolkit-12-6 \
        cuda-compiler-12-6 \
        cuda-nvcc-12-6 \
        cuda-toolkit-config-common \
        cuda-runtime-12-6 \
        cuda-drivers || warn "Some primary CUDA packages could not be installed"
    
    # Additional development packages
    sudo apt install -y \
        cuda-libraries-dev-12-6 \
        cuda-command-line-tools-12-6 \
        cuda-minimal-build-12-6 || warn "Some additional CUDA packages could not be installed"
    
    # If primary packages failed, try alternative versions
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Primary packages failed, trying CUDA 12.4..."
        sudo apt install -y \
            cuda-toolkit-12-4 \
            cuda-compiler-12-4 \
            cuda-nvcc-12-4 || warn "CUDA 12.4 packages failed"
    fi
    
    # If still no nvcc, try generic packages
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Trying generic CUDA packages..."
        sudo apt install -y \
            cuda-toolkit \
            cuda-nvcc \
            cuda-compiler \
            libcuda1 \
            libcudart12 || warn "Generic CUDA packages failed"
    fi
    
    # Last resort: nvidia-cuda-toolkit
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Trying nvidia-cuda-toolkit as last resort..."
        sudo apt install -y nvidia-cuda-toolkit || warn "nvidia-cuda-toolkit not available"
    fi
    
    log "CUDA toolkit installation completed"
}

# Configure nvcc and CUDA environment
configure_cuda_environment() {
    log "Configuring CUDA environment..."
    
    # Refresh PATH to pick up newly installed binaries
    export PATH="/usr/bin:/usr/local/bin:/usr/local/cuda/bin:/usr/local/cuda-12/bin:/usr/local/cuda-12.6/bin:/usr/local/cuda-12.4/bin:/usr/local/cuda-12.9/bin:$PATH"
    hash -r
    
    # Search for nvcc in common locations
    info "Searching for nvcc in the system..."
    NVCC_LOCATION=""
    
    # Check common CUDA installation paths
    for cuda_path in /usr/local/cuda-12.9/bin/nvcc /usr/local/cuda-12.6/bin/nvcc /usr/local/cuda-12.4/bin/nvcc /usr/local/cuda-12/bin/nvcc /usr/local/cuda/bin/nvcc; do
        if [ -f "$cuda_path" ]; then
            NVCC_LOCATION="$cuda_path"
            info "Found nvcc at: $NVCC_LOCATION"
            break
        fi
    done
    
    # If not found in common locations, search broadly
    if [ -z "$NVCC_LOCATION" ]; then
        NVCC_LOCATION=$(find /usr -name nvcc -type f 2>/dev/null | head -1)
        if [ -n "$NVCC_LOCATION" ]; then
            info "Found nvcc at: $NVCC_LOCATION"
        fi
    fi
    
    # Set up nvcc globally if found
    if [ -n "$NVCC_LOCATION" ]; then
        # Create symlink in /usr/local/bin (which is in everyone's PATH)
        sudo ln -sf "$NVCC_LOCATION" /usr/local/bin/nvcc
        info "Created global symlink: /usr/local/bin/nvcc -> $NVCC_LOCATION"
        
        # Also create symlinks for other CUDA tools if they exist
        NVCC_DIR=$(dirname "$NVCC_LOCATION")
        for tool in nvprof nsight-compute nsight-systems; do
            if [ -f "$NVCC_DIR/$tool" ]; then
                sudo ln -sf "$NVCC_DIR/$tool" "/usr/local/bin/$tool"
                info "Created symlink: /usr/local/bin/$tool"
            fi
        done
        
        # Set up CUDA environment variables
        CUDA_HOME=$(dirname "$NVCC_DIR")
        
        # Create system-wide CUDA environment configuration
        sudo tee /etc/profile.d/cuda.sh > /dev/null << EOF
# CUDA tools PATH and environment variables (added by CUDA installer)
export PATH="$NVCC_DIR:\$PATH"
export CUDA_HOME="$CUDA_HOME"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
EOF
        
        info "Created /etc/profile.d/cuda.sh for system-wide CUDA environment"
        info "CUDA_HOME set to: $CUDA_HOME"
        
        # Also set up environment variables in /etc/environment for systemd services
        if ! grep -q "CUDA_HOME" /etc/environment 2>/dev/null; then
            echo "CUDA_HOME=\"$CUDA_HOME\"" | sudo tee -a /etc/environment > /dev/null
            info "Added CUDA_HOME to /etc/environment"
        fi
        
        log "CUDA environment configured successfully"
    else
        warn "Could not find nvcc anywhere in the system"
        warn "CUDA development tools may not be properly installed"
        return 1
    fi
}

# Test CUDA installation
test_cuda_installation() {
    log "Testing CUDA installation..."
    
    # Source the CUDA environment
    if [ -f "/etc/profile.d/cuda.sh" ]; then
        source /etc/profile.d/cuda.sh
    fi
    
    # Test nvcc
    if command -v nvcc >/dev/null 2>&1; then
        info "nvcc successfully configured at: $(which nvcc)"
        info "CUDA Compiler version:"
        nvcc --version
        
        # Test CUDA_HOME
        if [ -n "$CUDA_HOME" ] && [ -d "$CUDA_HOME" ]; then
            info "CUDA_HOME is set to: $CUDA_HOME"
            if [ -f "$CUDA_HOME/lib64/libcudart.so" ]; then
                info "CUDA runtime library found"
            else
                warn "CUDA runtime library not found at expected location"
            fi
        else
            warn "CUDA_HOME not set or directory doesn't exist"
        fi
        
        # Test compilation (simple test)
        info "Testing CUDA compilation..."
        cat > /tmp/test_cuda.cu << 'EOF'
#include <stdio.h>
#include <cuda_runtime.h>

__global__ void hello() {
    printf("Hello from GPU!\n");
}

int main() {
    printf("CUDA Test Program\n");
    int deviceCount;
    cudaError_t error = cudaGetDeviceCount(&deviceCount);
    if (error == cudaSuccess) {
        printf("Found %d CUDA device(s)\n", deviceCount);
    } else {
        printf("CUDA Error: %s\n", cudaGetErrorString(error));
    }
    return 0;
}
EOF
        
        if nvcc /tmp/test_cuda.cu -o /tmp/test_cuda 2>/dev/null; then
            info "CUDA compilation test successful"
            /tmp/test_cuda || warn "CUDA runtime test failed (GPU may not be available)"
        else
            warn "CUDA compilation test failed"
        fi
        
        # Clean up test files
        rm -f /tmp/test_cuda.cu /tmp/test_cuda
        
        log "CUDA installation test completed successfully!"
        return 0
    else
        error "nvcc not found after installation. Installation failed."
        return 1
    fi
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "CUDA Toolkit Installation Complete!"
    echo "=================================="
    echo
    info "Installation Summary:"
    echo "  - CUDA toolkit and nvcc compiler installed"
    echo "  - Global nvcc symlink created in /usr/local/bin"
    echo "  - System-wide CUDA environment configured"
    echo "  - CUDA_HOME environment variable set"
    echo
    info "Environment Files Created:"
    echo "  - /etc/profile.d/cuda.sh (shell environment)"
    echo "  - /etc/environment (systemd services)"
    echo
    info "Verification Commands:"
    echo "  nvcc --version          : Check CUDA compiler version"
    echo "  echo \$CUDA_HOME        : Check CUDA_HOME variable"
    echo "  which nvcc             : Check nvcc location"
    echo
    info "Usage:"
    echo "  - nvcc is now globally available"
    echo "  - CUDA environment is automatically loaded"
    echo "  - Restart shell or run: source /etc/profile.d/cuda.sh"
    echo
    info "For Python/ML development:"
    echo "  - PyTorch: pip install torch --index-url https://download.pytorch.org/whl/cu124"
    echo "  - TensorFlow: pip install tensorflow[and-cuda]"
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "CUDA Toolkit and nvcc Installer for Debian 12"
    echo "=================================="
    echo
    info "This script will install CUDA development tools including:"
    echo "  - CUDA toolkit"
    echo "  - nvcc compiler"
    echo "  - CUDA libraries and headers"
    echo "  - Global environment configuration"
    echo
    
    if ! ask_yes_no "Do you want to continue with the CUDA installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi
    
    update_system
    setup_cuda_repository
    install_cuda_toolkit
    configure_cuda_environment
    test_cuda_installation
    print_instructions
}

# Run main function
main "$@" 
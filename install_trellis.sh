#!/bin/bash

# TRELLIS Installer Script for Debian 12 (Proxmox Container)
# https://github.com/microsoft/TRELLIS
# This script automates the installation of TRELLIS and its dependencies using modular components.

set -e  # Exit on any error

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

# Update system packages
update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
}

# Install basic dependencies
install_basic_deps() {
    log "Installing basic dependencies..."
    apt install -y \
        sudo \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        unzip \
        vim \
        htop \
        screen \
        tmux \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender-dev \
        ffmpeg
}

# Install NVIDIA drivers using module
install_nvidia_drivers() {
    log "Installing NVIDIA drivers using module..."
    NVIDIA_INSTALLER_URL="${NVIDIA_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_nvidia_drivers.sh}"
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    if curl -fSsl -o install_nvidia_drivers.sh "$NVIDIA_INSTALLER_URL"; then
        chmod +x install_nvidia_drivers.sh
        ./install_nvidia_drivers.sh
        log "NVIDIA drivers installation completed"
    else
        error "Failed to download NVIDIA driver installer."
    fi
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Install CUDA toolkit using module
install_cuda() {
    log "Installing CUDA toolkit using module..."
    CUDA_INSTALLER_URL="${CUDA_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_cuda_nvcc.sh}"
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    if curl -fSsl -o install_cuda_nvcc.sh "$CUDA_INSTALLER_URL"; then
        chmod +x install_cuda_nvcc.sh
        ./install_cuda_nvcc.sh
        log "CUDA toolkit installation completed"
    else
        error "Failed to download CUDA installer."
    fi
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Install Miniconda if not present
install_miniconda() {
    if command -v conda >/dev/null 2>&1 || [ -d "$HOME/miniconda" ]; then
        info "Conda is already installed."
    else
        log "Installing Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
        bash /tmp/miniconda.sh -b -p $HOME/miniconda
        # Add Miniconda to PATH and initialize conda in both ~/.bashrc and ~/.profile
        for f in "$HOME/.bashrc" "$HOME/.profile"; do
            echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> "$f"
            echo 'if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then' >> "$f"
            echo '    . "$HOME/miniconda/etc/profile.d/conda.sh"' >> "$f"
            echo 'fi' >> "$f"
        done
        log "Miniconda installed and initialized. Please restart your shell or run: source ~/.bashrc"
    fi
    # Always make conda available in the current session
    export PATH="$HOME/miniconda/bin:$PATH"
    if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda/etc/profile.d/conda.sh"
    fi
    # Install system Python using the module (download from URL)
    PYTHON_INSTALLER_URL="${PYTHON_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_python.sh}"
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    if curl -fSsl -o install_python.sh "$PYTHON_INSTALLER_URL"; then
        chmod +x install_python.sh
        ./install_python.sh install
        log "System Python installation completed"
    else
        error "Failed to download Python installer module."
    fi
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Clone TRELLIS repo with submodules
clone_trellis() {
    log "Cloning TRELLIS repository with submodules..."
    if [ -d "$HOME/TRELLIS" ]; then
        warn "TRELLIS directory already exists at $HOME/TRELLIS"
        return 0
    fi
    git clone --recurse-submodules https://github.com/microsoft/TRELLIS.git $HOME/TRELLIS
    log "TRELLIS cloned to $HOME/TRELLIS"
}

# Run TRELLIS setup script
run_trellis_setup() {
    log "Running TRELLIS setup.sh with recommended options..."
    cd $HOME/TRELLIS
    # Create conda env with Python 3.10 if not already present
    if ! conda env list | grep -q "trellis"; then
        conda create -y -n trellis python=3.10
    fi
    conda activate trellis
    # Use --new-env to create a new conda env, and install all recommended dependencies
    bash -c ". ./setup.sh --new-env --basic --xformers --flash-attn --diffoctreerast --spconv --mipgaussian --kaolin --nvdiffrast"
    log "TRELLIS setup complete. Activate the environment with: conda activate trellis"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "TRELLIS Installation Complete!"
    echo "=================================="
    echo
    info "To activate the TRELLIS environment:"
    echo "  conda activate trellis"
    echo
    info "To run TRELLIS demos or training, see the official repo:"
    echo "  https://github.com/microsoft/TRELLIS"
    echo
    info "For more setup options, run:"
    echo "  cd ~/TRELLIS && ./setup.sh --help"
    echo
}

main() {
    echo "=================================="
    log "TRELLIS Installer for Debian 12"
    echo "=================================="
    echo
    info "This script will install TRELLIS and all required dependencies."
    info "Installation location: $HOME/TRELLIS"
    echo
    update_system
    install_basic_deps
    install_nvidia_drivers
    install_cuda
    install_miniconda
    clone_trellis
    run_trellis_setup
    print_instructions
}

main "$@" 
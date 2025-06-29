#!/bin/bash
# FramePack Linux Installer Script for Debian 12
# This script installs FramePack with NVIDIA GPU support.
# It is designed to be non-interactive and fail on any error.

set -e

# --- Configuration ---
PYTHON_VERSION="3.10"
CUDA_VERSION="12.6"
FRAMEPACK_DIR="$HOME/FramePack"
VENV_DIR="$HOME/framepack-env"

# --- Modules ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

source "$MODULES_DIR/install_nvidia_drivers.sh"
source "$MODULES_DIR/install_cuda_nvcc.sh"
source "$MODULES_DIR/install_python.sh"

# --- Logging ---
log() {
    echo "--- $1 ---"
}

# 1. Update system and install basic dependencies
log "Updating system packages and installing dependencies"
apt-get update
apt-get install -y git curl wget build-essential software-properties-common apt-transport-https ca-certificates gnupg lsb-release unzip vim htop screen tmux ffmpeg libsm6 libxext6 libxrender-dev libglib2.0-0 libgl1-mesa-glx

# 2. Install NVIDIA Drivers
log "Installing NVIDIA Drivers"
install_nvidia_drivers

# 3. Install Python
log "Installing Python $PYTHON_VERSION"
install_python "$PYTHON_VERSION"

# 4. Install CUDA
log "Installing CUDA $CUDA_VERSION"
install_cuda_nvcc "$CUDA_VERSION"

# 5. Create FramePack Workspace
log "Setting up FramePack workspace at $FRAMEPACK_DIR"
rm -rf "$FRAMEPACK_DIR"
git clone https://github.com/lllyasviel/FramePack.git "$FRAMEPACK_DIR"
cd "$FRAMEPACK_DIR"

# 6. Create and activate Python virtual environment
log "Creating Python virtual environment at $VENV_DIR"
rm -rf "$VENV_DIR"
python$PYTHON_VERSION -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# 7. Install Python dependencies
log "Installing Python dependencies for FramePack"
pip install --upgrade pip
pip install -r requirements.txt
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 8. Run setup
log "Running FramePack setup"
python setup.py develop

echo "FramePack installation completed successfully."
echo "To use FramePack, activate the virtual environment:"
echo "source $VENV_DIR/bin/activate"
echo "Then navigate to the directory:"
echo "cd $FRAMEPACK_DIR"
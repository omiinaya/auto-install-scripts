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
source "$MODULES_DIR/install_nvidia_drivers.sh"
install_nvidia_drivers

# 3. Install Python
log "Installing Python $PYTHON_VERSION"
source "$MODULES_DIR/install_python.sh"
install_python "$PYTHON_VERSION"

# 4. Install CUDA
log "Installing CUDA $CUDA_VERSION"
source "$MODULES_DIR/install_cuda_nvcc.sh"
install_cuda_nvcc "$CUDA_VERSION"

# 5. Create FramePack Workspace
log "Setting up FramePack workspace at $FRAMEPACK_DIR"
# The pyenv installation process corrupts the PATH, so we must redefine it
# to include the shims for the python executable to be found.
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"
rm -rf "$FRAMEPACK_DIR"
git clone https://github.com/lllyasviel/FramePack.git "$FRAMEPACK_DIR"
cd "$FRAMEPACK_DIR"

# 6. Create and activate Python virtual environment
log "Creating Python virtual environment at $VENV_DIR"
rm -rf "$VENV_DIR"
python${PYTHON_VERSION} -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# 7. Install Python dependencies
log "Installing Python dependencies for FramePack"
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt

# Install optional performance libraries
log "Installing performance optimization libraries..."
pip install xformers flash-attn sage-attention==1.0.6

# 8. Create Launcher Script
log "Creating launcher script at $HOME/launch_framepack.sh"
LAUNCHER_SCRIPT="$HOME/launch_framepack.sh"

cat > "$LAUNCHER_SCRIPT" << EOF
#!/bin/bash
# FramePack Launcher Script

echo "--- Starting FramePack ---"

# Activate Python virtual environment
source "$VENV_DIR/bin/activate"

# Navigate to the application directory
cd "$FRAMEPACK_DIR"

# Launch the Gradio demo and make it accessible over the network
echo "Launching Gradio demo on all network interfaces..."
python demo_gradio.py --server 0.0.0.0
EOF

chmod +x "$LAUNCHER_SCRIPT"

# 9. Create and enable systemd service
log "Creating systemd service to run FramePack on startup"
SERVICE_FILE="/etc/systemd/system/framepack.service"
CURRENT_USER=$(whoami)

# Using sudo to write the service file
sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=FramePack Gradio Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$FRAMEPACK_DIR
ExecStart=/bin/bash $LAUNCHER_SCRIPT
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

log "Reloading systemd and enabling the FramePack service"
sudo systemctl daemon-reload
sudo systemctl enable framepack.service

echo "FramePack installation completed successfully."
echo "To use FramePack manually:"
echo "1. Activate the virtual environment: source $VENV_DIR/bin/activate"
echo "2. Navigate to the directory: cd $FRAMEPACK_DIR"
echo "3. Run the application: python demo_gradio.py"
echo
echo "--- Systemd Service Information ---"
echo "A service has been created to start FramePack automatically on boot."
echo "You can manage it with these commands:"
echo " - Start now: sudo systemctl start framepack.service"
echo " - Stop:      sudo systemctl stop framepack.service"
echo " - Status:    sudo systemctl status framepack.service"
echo " - Logs:      sudo journalctl -u framepack.service -f"
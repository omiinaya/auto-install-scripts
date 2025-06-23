#!/bin/bash

# ComfyUI Linux Installer Script for Debian 12 (Proxmox Container)
# This script installs ComfyUI with NVIDIA GPU support

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
        if ! ask_yes_no "Do you want to continue anyway?" "n"; then
            exit 1
        fi
    fi
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
        tmux
}

# Install Python and related tools
install_python() {
    log "Installing Python and related tools..."
    
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

# Install NVIDIA drivers for Proxmox container
install_nvidia_drivers() {
    log "Installing NVIDIA drivers for Proxmox container..."
    
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
    sudo dpkg-reconfigure nvidia-kernel-dkms
    
    # Clean up
    rm -f cuda-keyring_1.1-1_all.deb
    
    log "NVIDIA drivers installed successfully"
}

# Create virtual environment
create_venv() {
    log "Creating Python virtual environment..."
    
    # Create comfy-env directory in user's home
    VENV_DIR="$HOME/comfy-env"
    
    if [ -d "$VENV_DIR" ]; then
        warn "Virtual environment already exists at $VENV_DIR"
        if ask_yes_no "Do you want to remove it and create a new one?" "n"; then
            rm -rf "$VENV_DIR"
        else
            info "Using existing virtual environment"
            return 0
        fi
    fi
    
    python3 -m venv "$VENV_DIR"
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip in virtual environment
    pip install --upgrade pip setuptools wheel
    
    log "Virtual environment created at $VENV_DIR"
}

# Install comfy-cli
install_comfy_cli() {
    log "Installing comfy-cli..."
    
    # Ensure we're in the virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Install comfy-cli
    pip install comfy-cli
    
    # Enable command completion (optional)
    comfy --install-completion || warn "Could not install command completion"
    
    log "comfy-cli installed successfully"
}

# Install ComfyUI
install_comfyui() {
    log "Installing ComfyUI..."
    
    # Ensure we're in the virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Create ComfyUI workspace directory
    COMFY_DIR="$HOME/comfy"
    
    if [ -d "$COMFY_DIR" ]; then
        warn "ComfyUI directory already exists at $COMFY_DIR"
        if ask_yes_no "Do you want to remove it and install fresh?" "n"; then
            rm -rf "$COMFY_DIR"
        else
            info "Using existing ComfyUI installation"
            return 0
        fi
    fi
    
    # Install ComfyUI using comfy-cli
    comfy --workspace="$COMFY_DIR" install
    
    log "ComfyUI installed successfully at $COMFY_DIR"
}

# Install PyTorch with CUDA support
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA support..."
    
    # Ensure we're in the virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Install PyTorch with CUDA 12.4 support
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    
    log "PyTorch with CUDA support installed"
}

# Install additional dependencies
install_additional_deps() {
    log "Installing additional Python packages..."
    
    # Ensure we're in the virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Install commonly needed packages
    pip install \
        numpy \
        opencv-python \
        pillow \
        requests \
        tqdm \
        psutil \
        scipy \
        matplotlib
    
    log "Additional dependencies installed"
}

# Create launcher script
create_launcher() {
    log "Creating launcher script..."
    
    LAUNCHER_SCRIPT="$HOME/launch_comfyui.sh"
    
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

# Launch ComfyUI with network access by default
# Use -- to pass arguments to the underlying ComfyUI process
comfy launch -- --listen 0.0.0.0 "$@"
EOF

    # Make the launcher script executable
    if chmod +x "$LAUNCHER_SCRIPT"; then
        log "Launcher script created and made executable at $LAUNCHER_SCRIPT"
    else
        warn "Failed to make launcher script executable. You may need to run: chmod +x $LAUNCHER_SCRIPT"
    fi
}

# Create systemd service (optional)
create_systemd_service() {
    log "Creating systemd service for ComfyUI..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run ComfyUI automatically?" "n"; then
        return 0
    fi
    
    SERVICE_FILE="/etc/systemd/system/comfyui.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=ComfyUI Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/launch_comfyui.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable comfyui.service
    
    log "Systemd service created. You can start it with: sudo systemctl start comfyui"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Activate virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Test Python imports
    info "Testing Python imports..."
    python3 -c "import torch; print(f'PyTorch version: {torch.__version__}')"
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
    
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)"; then
        log "CUDA is available and working!"
    else
        warn "CUDA is not available. GPU acceleration may not work."
    fi
    
    # Test comfy-cli
    info "Testing comfy-cli..."
    comfy --version
    
    log "Installation test completed successfully!"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "ComfyUI Installation Complete!"
    echo "=================================="
    echo
    info "To start ComfyUI:"
    echo "  1. Run: $HOME/launch_comfyui.sh"
    echo "  2. Or manually:"
    echo "     source $HOME/comfy-env/bin/activate"
    echo "     cd $HOME/comfy"
    echo "     comfy launch"
    echo
    info "ComfyUI will be accessible at:"
    echo "  Local access: http://localhost:8188"
    echo "  Network access: http://your-server-ip:8188"
    echo
    info "Common launch options:"
    echo "  --cpu                 : Use CPU only"
    echo "  --lowvram            : Low VRAM mode"
    echo "  --port 8080          : Use different port"
    echo "  --listen 127.0.0.1   : Restrict to local access only"
    echo
    info "Useful commands:"
    echo "  comfy model download --url <model_url> --relative-path models/checkpoints"
    echo "  comfy launch --background  : Run in background"
    echo "  comfy stop            : Stop background instance"
    echo
    if [ -f "/etc/systemd/system/comfyui.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start comfyui    : Start service"
        echo "  sudo systemctl stop comfyui     : Stop service"
        echo "  sudo systemctl status comfyui   : Check status"
    fi
    echo
    warn "Remember to download models before using ComfyUI!"
    echo "You can download models from Hugging Face or other sources."
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "ComfyUI Linux Installer"
    echo "=================================="
    echo
    info "This script will install ComfyUI with NVIDIA GPU support on Debian 12"
    info "Installation location: $HOME/comfy"
    info "Virtual environment: $HOME/comfy-env"
    echo
    
    if ! ask_yes_no "Do you want to continue with the installation?" "n"; then
        info "Installation cancelled."
        exit 0
    fi
    
    check_root
    update_system
    install_basic_deps
    install_python
    install_nvidia_drivers
    create_venv
    install_comfy_cli
    install_comfyui
    install_pytorch_cuda
    install_additional_deps
    create_launcher
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
#!/bin/bash

# Stable Diffusion WebUI Linux Installer Script for Debian 12 (Proxmox Container)
# This script installs AUTOMATIC1111's Stable Diffusion WebUI with NVIDIA GPU support

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
    apt update && apt upgrade -y
}

# Install basic dependencies
install_basic_deps() {
    log "Installing basic dependencies..."
    
    # Check for and install sudo first if not present
    if ! command -v sudo >/dev/null 2>&1; then
        log "Installing sudo..."
        apt update
        apt install -y sudo
    fi
    
    apt install -y \
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

    # Install google-perftools for TCMalloc support
    log "Installing google-perftools (TCMalloc) for improved memory usage..."
    sudo apt-get install -y google-perftools
}

# Install Python using standalone module
install_python() {
    log "Installing Python using standalone module..."
    
    # Download and run the standalone Python installer
    info "Downloading Python installer from GitHub..."
    
    # You can set PYTHON_INSTALLER_URL environment variable to use a custom URL
    PYTHON_INSTALLER_URL="${PYTHON_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_python.sh}"
    
    # Create temporary directory for the installer
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download and source the installer script
    if curl -fSsl -o install_python.sh "$PYTHON_INSTALLER_URL"; then
        chmod +x install_python.sh
        info "Running Python installer (default version for FramePack compatibility)..."
        info "Note: FramePack recommends Python 3.10, but Python 3.11 (Debian 12 default) is compatible"
        
        # Source the script to use its functions
        source ./install_python.sh
        
        # Call the function directly
        install_python
        
        log "Python installation completed"
    else
        error "Failed to download Python installer from GitHub. Please check your internet connection or install Python manually."
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Install NVIDIA drivers using standalone module
install_nvidia_drivers() {
    log "Installing NVIDIA drivers using standalone module..."
    
    # Download and run the standalone NVIDIA driver installer
    info "Downloading NVIDIA driver installer from GitHub..."
    
    # You can set NVIDIA_INSTALLER_URL environment variable to use a custom URL
    NVIDIA_INSTALLER_URL="${NVIDIA_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_nvidia_drivers.sh}"
    
    # Create temporary directory for the installer
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download and execute the installer script
    if curl -fSsl -o install_nvidia_drivers.sh "$NVIDIA_INSTALLER_URL"; then
        chmod +x install_nvidia_drivers.sh
        info "Running NVIDIA driver installer..."
        ./install_nvidia_drivers.sh
        log "NVIDIA drivers installation completed"
    else
        error "Failed to download NVIDIA driver installer from GitHub. Please check your internet connection or install NVIDIA drivers manually."
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Install CUDA toolkit and nvcc using standalone module
install_nvcc() {
    log "Installing CUDA toolkit and nvcc using standalone module..."
    
    # Download and run the standalone CUDA installer
    info "Downloading CUDA installer from GitHub..."
    
    # You can set CUDA_INSTALLER_URL environment variable to use a custom URL
    CUDA_INSTALLER_URL="${CUDA_INSTALLER_URL:-https://raw.githubusercontent.com/omiinaya/install-scripts/refs/heads/main/modules/install_cuda_nvcc.sh}"
    
    # Create temporary directory for the installer
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Download and execute the installer script
    if curl -fSsl -o install_cuda_nvcc.sh "$CUDA_INSTALLER_URL"; then
        chmod +x install_cuda_nvcc.sh
        info "Running CUDA installer..."
        ./install_cuda_nvcc.sh
        log "CUDA toolkit installation completed"
    else
        error "Failed to download CUDA installer from GitHub. Please check your internet connection or install CUDA toolkit manually."
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Create virtual environment
create_venv() {
    log "Creating Python virtual environment..."
    
    # Create sd-env directory in user's home
    VENV_DIR="$HOME/sd-env"
    
    if [ -d "$VENV_DIR" ]; then
        warn "Virtual environment already exists at $VENV_DIR"
        if ask_yes_no "Do you want to remove it and create a new one?" "y"; then
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

# Clone Stable Diffusion WebUI repository
clone_sd_webui() {
    log "Cloning Stable Diffusion WebUI repository..."
    
    # Create Stable Diffusion workspace directory
    SD_DIR="$HOME/stable-diffusion-webui"
    
    if [ -d "$SD_DIR" ]; then
        warn "Stable Diffusion WebUI directory already exists at $SD_DIR"
        if ask_yes_no "Do you want to remove it and clone fresh?" "y"; then
            rm -rf "$SD_DIR"
        else
            info "Using existing Stable Diffusion WebUI installation"
            return 0
        fi
    fi
    
    # Clone the repository
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$SD_DIR"
    
    log "Stable Diffusion WebUI cloned successfully to $SD_DIR"
}

# Install PyTorch with CUDA support
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA support..."
    
    # Ensure we're in the virtual environment
    source "$HOME/sd-env/bin/activate"
    
    # Install PyTorch with CUDA 12.4 support
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
    
    log "PyTorch with CUDA support installed"
}

# Create launcher script
create_launcher() {
    log "Creating launcher script..."
    
    LAUNCHER_SCRIPT="$HOME/launch_sd.sh"
    
    cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# Stable Diffusion WebUI Launcher Script
# This script activates the virtual environment and launches Stable Diffusion WebUI

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

VENV_DIR="$HOME/sd-env"
SD_DIR="$HOME/stable-diffusion-webui"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Virtual environment not found at $VENV_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Check if Stable Diffusion directory exists
if [ ! -d "$SD_DIR" ]; then
    echo -e "${RED}Stable Diffusion WebUI directory not found at $SD_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to Stable Diffusion directory
cd "$SD_DIR"

echo -e "${GREEN}Starting Stable Diffusion WebUI with network access...${NC}"
echo -e "${GREEN}Access WebUI locally at: http://localhost:7860${NC}"
echo -e "${GREEN}Access WebUI from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${BLUE}Note: Models will be downloaded automatically on first run${NC}"
echo -e "${GREEN}Press Ctrl+C to stop Stable Diffusion WebUI${NC}"
echo

# Launch Stable Diffusion WebUI with common options
./webui.sh \
    --xformers \
    --listen \
    --enable-insecure-extension-access \
    --api \
    "$@"
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
    log "Creating systemd service for Stable Diffusion WebUI..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run Stable Diffusion WebUI automatically?" "y"; then
        return 0
    fi
    
    SERVICE_FILE="/etc/systemd/system/sd-webui.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Stable Diffusion WebUI Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME/stable-diffusion-webui
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/bash $USER_HOME/stable-diffusion-webui/webui.sh -f --xformers --listen --enable-insecure-extension-access --api
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sd-webui.service
    
    log "Systemd service created. You can start it with: sudo systemctl start sd-webui"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Activate virtual environment
    source "$HOME/sd-env/bin/activate"
    
    # Test Python imports
    info "Testing Python imports..."
    python3 -c "import torch; print(f'PyTorch version: {torch.__version__}')"
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
    
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)"; then
        log "CUDA is available and working!"
    else
        warn "CUDA is not available. GPU acceleration may not work."
    fi
    
    log "Installation test completed successfully!"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "Stable Diffusion WebUI Installation Complete!"
    echo "=================================="
    echo
    info "To start Stable Diffusion WebUI:"
    echo "  1. Run: $HOME/launch_sd.sh"
    echo "  2. Or manually:"
    echo "     source $HOME/sd-env/bin/activate"
    echo "     cd $HOME/stable-diffusion-webui"
    echo "     ./webui.sh"
    echo
    info "WebUI will be accessible at:"
    echo "  Local access: http://localhost:7860"
    echo "  Network access: http://your-server-ip:7860"
    echo
    info "Common launch options:"
    echo "  --xformers           : Enable xformers for better performance"
    echo "  --listen            : Allow network access"
    echo "  --api               : Enable API"
    echo "  --lowvram           : Low VRAM mode"
    echo "  --medvram           : Medium VRAM mode"
    echo
    if [ -f "/etc/systemd/system/sd-webui.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start sd-webui    : Start service"
        echo "  sudo systemctl stop sd-webui     : Stop service"
        echo "  sudo systemctl status sd-webui   : Check status"
    fi
    echo
    warn "Important Notes:"
    echo "  • First launch will download models (may take 1+ hours)"
    echo "  • Default model is not included - download from CivitAI or Hugging Face"
    echo "  • Recommended: Download models to models/Stable-diffusion/"
    echo "  • Extensions can be installed from the WebUI"
    echo
    info "For more information and documentation, visit:"
    echo "  https://github.com/AUTOMATIC1111/stable-diffusion-webui/wiki"
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "Stable Diffusion WebUI Linux Installer"
    echo "=================================="
    echo
    info "This script will install AUTOMATIC1111's Stable Diffusion WebUI on Debian 12"
    info "Installation location: $HOME/stable-diffusion-webui"
    info "Virtual environment: $HOME/sd-env"
    echo
    info "Features:"
    echo "  • Text-to-Image generation"
    echo "  • Image-to-Image modification"
    echo "  • Inpainting and Outpainting"
    echo "  • Model management and merging"
    echo "  • Extension system"
    echo "  • API access"
    echo
    
    if ! ask_yes_no "Do you want to continue with the installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi
    
    update_system
    install_basic_deps
    install_python
    install_nvidia_drivers
    install_nvcc
    create_venv
    clone_sd_webui
    install_pytorch_cuda
    create_launcher
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
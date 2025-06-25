#!/bin/bash

# FramePack Linux Installer Script for Debian 12 (Proxmox Container)
# This script installs FramePack with NVIDIA GPU support

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
        ffmpeg \
        libsm6 \
        libxext6 \
        libxrender-dev \
        libglib2.0-0 \
        libgl1-mesa-glx
}

# Install Python and related tools
install_python() {
    log "Installing Python and related tools..."
    
    # Install Python 3.10 specifically (FramePack recommends Python 3.10)
    sudo apt install -y \
        python3.10 \
        python3.10-pip \
        python3.10-venv \
        python3.10-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Create symlinks if needed
    if ! command -v python3.10 >/dev/null 2>&1; then
        error "Python 3.10 is not available. FramePack requires Python 3.10."
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3.10 --version | cut -d' ' -f2)
    info "Python version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.10
    if python3.10 -c "import sys; exit(0 if sys.version_info >= (3, 10) and sys.version_info < (3, 11) else 1)"; then
        log "Python 3.10 is available"
    else
        error "FramePack requires Python 3.10 specifically."
    fi
    
    info "Python 3.10 installation completed"
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
    
    # Create framepack-env directory in user's home
    VENV_DIR="$HOME/framepack-env"
    
    if [ -d "$VENV_DIR" ]; then
        warn "Virtual environment already exists at $VENV_DIR"
        if ask_yes_no "Do you want to remove it and create a new one?" "y"; then
            rm -rf "$VENV_DIR"
        else
            info "Using existing virtual environment"
            return 0
        fi
    fi
    
    python3.10 -m venv "$VENV_DIR"
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip in virtual environment
    pip install --upgrade pip setuptools wheel
    
    log "Virtual environment created at $VENV_DIR"
}

# Clone FramePack repository
clone_framepack() {
    log "Cloning FramePack repository..."
    
    # Create FramePack workspace directory
    FRAMEPACK_DIR="$HOME/FramePack"
    
    if [ -d "$FRAMEPACK_DIR" ]; then
        warn "FramePack directory already exists at $FRAMEPACK_DIR"
        if ask_yes_no "Do you want to remove it and clone fresh?" "y"; then
            rm -rf "$FRAMEPACK_DIR"
        else
            info "Using existing FramePack installation"
            return 0
        fi
    fi
    
    # Clone the repository
    git clone https://github.com/lllyasviel/FramePack.git "$FRAMEPACK_DIR"
    
    log "FramePack cloned successfully to $FRAMEPACK_DIR"
}

# Install PyTorch with CUDA support
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA support..."
    
    # Ensure we're in the virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Install PyTorch with CUDA 12.6 support (as specified in FramePack instructions)
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
    
    log "PyTorch with CUDA support installed"
}

# Install FramePack requirements
install_framepack_requirements() {
    log "Installing FramePack requirements..."
    
    # Ensure we're in the virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Change to FramePack directory
    cd "$HOME/FramePack"
    
    # Install requirements from requirements.txt
    pip install -r requirements.txt
    
    log "FramePack requirements installed"
}

# Install optional attention kernels
install_optional_attention() {
    log "Installing optional attention kernels..."
    
    if ask_yes_no "Do you want to install xformers for better performance?" "y"; then
        # Ensure we're in the virtual environment
        source "$HOME/framepack-env/bin/activate"
        
        info "Installing xformers..."
        pip install xformers
        log "xformers installed successfully"
    fi
    
    if ask_yes_no "Do you want to install sage-attention? (may affect results slightly)" "n"; then
        # Ensure we're in the virtual environment
        source "$HOME/framepack-env/bin/activate"
        
        info "Installing sage-attention..."
        pip install sageattention==1.0.6
        log "sage-attention installed successfully"
        warn "Note: sage-attention may influence results, though the influence is minimal"
    fi
}

# Create launcher script
create_launcher() {
    log "Creating launcher script..."
    
    LAUNCHER_SCRIPT="$HOME/launch_framepack.sh"
    
    cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# FramePack Launcher Script
# This script activates the virtual environment and launches FramePack

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

VENV_DIR="$HOME/framepack-env"
FRAMEPACK_DIR="$HOME/FramePack"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Virtual environment not found at $VENV_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Check if FramePack directory exists
if [ ! -d "$FRAMEPACK_DIR" ]; then
    echo -e "${RED}FramePack directory not found at $FRAMEPACK_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to FramePack directory
cd "$FRAMEPACK_DIR"

echo -e "${GREEN}Starting FramePack with network access...${NC}"
echo -e "${GREEN}Access FramePack locally at: http://localhost:7860${NC}"
echo -e "${GREEN}Access FramePack from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${BLUE}Note: Models will be downloaded automatically on first run (30GB+)${NC}"
echo -e "${GREEN}Press Ctrl+C to stop FramePack${NC}"
echo

# Launch FramePack with network access by default
# Pass any additional arguments to the script
python demo_gradio.py --listen 0.0.0.0 "$@"
EOF

    # Make the launcher script executable
    if chmod +x "$LAUNCHER_SCRIPT"; then
        log "Launcher script created and made executable at $LAUNCHER_SCRIPT"
    else
        warn "Failed to make launcher script executable. You may need to run: chmod +x $LAUNCHER_SCRIPT"
    fi
}

# Create F1 launcher script
create_f1_launcher() {
    log "Creating F1 launcher script..."
    
    F1_LAUNCHER_SCRIPT="$HOME/launch_framepack_f1.sh"
    
    cat > "$F1_LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# FramePack F1 Launcher Script
# This script activates the virtual environment and launches FramePack F1

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

VENV_DIR="$HOME/framepack-env"
FRAMEPACK_DIR="$HOME/FramePack"

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Virtual environment not found at $VENV_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Check if FramePack directory exists
if [ ! -d "$FRAMEPACK_DIR" ]; then
    echo -e "${RED}FramePack directory not found at $FRAMEPACK_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Change to FramePack directory
cd "$FRAMEPACK_DIR"

echo -e "${GREEN}Starting FramePack F1 with network access...${NC}"
echo -e "${GREEN}Access FramePack F1 locally at: http://localhost:7860${NC}"
echo -e "${GREEN}Access FramePack F1 from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${BLUE}Note: F1 model features more dynamic movements and reverse generation${NC}"
echo -e "${GREEN}Press Ctrl+C to stop FramePack F1${NC}"
echo

# Launch FramePack F1 with network access by default
# Pass any additional arguments to the script
python demo_gradio_f1.py --listen 0.0.0.0 "$@"
EOF

    # Make the F1 launcher script executable
    if chmod +x "$F1_LAUNCHER_SCRIPT"; then
        log "F1 launcher script created and made executable at $F1_LAUNCHER_SCRIPT"
    else
        warn "Failed to make F1 launcher script executable. You may need to run: chmod +x $F1_LAUNCHER_SCRIPT"
    fi
}

# Create systemd service (optional)
create_systemd_service() {
    log "Creating systemd service for FramePack..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run FramePack automatically?" "y"; then
        return 0
    fi
    
    SERVICE_FILE="/etc/systemd/system/framepack.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=FramePack Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/launch_framepack.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable framepack.service
    
    log "Systemd service created. You can start it with: sudo systemctl start framepack"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Activate virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Test Python imports
    info "Testing Python imports..."
    python3.10 -c "import torch; print(f'PyTorch version: {torch.__version__}')"
    python3.10 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
    
    if python3.10 -c "import torch; exit(0 if torch.cuda.is_available() else 1)"; then
        log "CUDA is available and working!"
    else
        warn "CUDA is not available. GPU acceleration may not work."
    fi
    
    # Test FramePack dependencies
    info "Testing FramePack dependencies..."
    cd "$HOME/FramePack"
    python3.10 -c "import diffusers; print(f'Diffusers version: {diffusers.__version__}')"
    python3.10 -c "import transformers; print(f'Transformers version: {transformers.__version__}')"
    python3.10 -c "import gradio; print(f'Gradio version: {gradio.__version__}')"
    
    log "Installation test completed successfully!"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "FramePack Installation Complete!"
    echo "=================================="
    echo
    info "To start FramePack:"
    echo "  1. Run: $HOME/launch_framepack.sh"
    echo "  2. For F1 model: $HOME/launch_framepack_f1.sh"
    echo "  3. Or manually:"
    echo "     source $HOME/framepack-env/bin/activate"
    echo "     cd $HOME/FramePack"
    echo "     python demo_gradio.py --listen 0.0.0.0"
    echo
    info "FramePack will be accessible at:"
    echo "  Local access: http://localhost:7860"
    echo "  Network access: http://your-server-ip:7860"
    echo
    info "Common launch options:"
    echo "  --share              : Create public Gradio link"
    echo "  --port 8080          : Use different port"
    echo "  --server 127.0.0.1   : Restrict to local access only"
    echo
    info "System Requirements:"
    echo "  • NVIDIA GPU: RTX 30XX/40XX/50XX series (6GB+ VRAM)"
    echo "  • Memory: 32GB+ RAM recommended (64GB for best performance)"
    echo "  • Storage: 50GB+ free space for models"
    echo
    info "Model Information:"
    echo "  • Models download automatically on first run (30GB+)"
    echo "  • Generation speed: ~1.5-2.5s per frame on RTX 4090"
    echo "  • Can generate up to 120 seconds of video (3600 frames)"
    echo
    if [ -f "/etc/systemd/system/framepack.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start framepack    : Start service"
        echo "  sudo systemctl stop framepack     : Stop service"
        echo "  sudo systemctl status framepack   : Check status"
    fi
    echo
    warn "Important Notes:"
    echo "  • First launch will download models (may take 1+ hours)"
    echo "  • FramePack generates videos progressively frame-by-frame"
    echo "  • Use concise, motion-focused prompts for best results"
    echo "  • Example: 'The girl dances gracefully, with clear movements, full of charm.'"
    echo
    info "For more examples and documentation, visit:"
    echo "  https://github.com/lllyasviel/FramePack"
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "FramePack Linux Installer"
    echo "=================================="
    echo
    info "This script will install FramePack with NVIDIA GPU support on Debian 12"
    info "Installation location: $HOME/FramePack"
    info "Virtual environment: $HOME/framepack-env"
    echo
    info "FramePack is a next-frame prediction model for video generation"
    info "It can generate up to 120 seconds of video with just 6GB VRAM"
    echo
    
    if ! ask_yes_no "Do you want to continue with the installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi
    
    check_root
    update_system
    install_basic_deps
    install_python
    install_nvidia_drivers
    install_nvcc
    create_venv
    clone_framepack
    install_pytorch_cuda
    install_framepack_requirements
    install_optional_attention
    create_launcher
    create_f1_launcher
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
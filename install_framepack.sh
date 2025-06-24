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
    sudo apt update && sudo apt upgrade -y
}

# Install basic dependencies
install_basic_deps() {
    log "Installing basic dependencies..."
    
    # First install sudo if not present (required for all subsequent operations)
    if ! command -v sudo >/dev/null 2>&1; then
        log "Installing sudo..."
        apt update
        apt install -y sudo
    fi
    
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
        tmux \
        pciutils
}

# Install Python 3.10 specifically (FramePack requirement)
install_python() {
    log "Installing Python 3.10 and related tools..."
    
    # Install Python 3.10 and related packages
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
        error "Python version is too old. FramePack requires Python 3.9 or higher."
    fi
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
    
    # Create framepack-env directory in user's home
    VENV_DIR="$HOME/framepack-env"
    
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

# Setup CUDA environment variables
setup_cuda_environment() {
    log "Setting up CUDA environment variables..."
    
    # Find CUDA installation path
    CUDA_PATH=""
    for path in /usr/local/cuda-12.6 /usr/local/cuda-12 /usr/local/cuda /opt/cuda; do
        if [ -d "$path" ]; then
            CUDA_PATH="$path"
            break
        fi
    done
    
    if [ -z "$CUDA_PATH" ]; then
        warn "CUDA installation not found in standard locations"
        info "Installing CUDA toolkit..."
        sudo apt install -y nvidia-cuda-toolkit cuda-toolkit-12-6 || warn "Could not install CUDA toolkit"
        
        # Try to find CUDA again
        for path in /usr/local/cuda-12.6 /usr/local/cuda-12 /usr/local/cuda /opt/cuda; do
            if [ -d "$path" ]; then
                CUDA_PATH="$path"
                break
            fi
        done
    fi
    
    if [ -n "$CUDA_PATH" ]; then
        info "Found CUDA at: $CUDA_PATH"
        
        # Set environment variables for current session
        export CUDA_HOME="$CUDA_PATH"
        export CUDA_ROOT="$CUDA_PATH"
        export PATH="$CUDA_PATH/bin:$PATH"
        export LD_LIBRARY_PATH="$CUDA_PATH/lib64:$LD_LIBRARY_PATH"
        
        # Add to user's bashrc for persistence
        if ! grep -q "CUDA_HOME" "$HOME/.bashrc"; then
            info "Adding CUDA environment variables to ~/.bashrc"
            cat >> "$HOME/.bashrc" << EOF

# CUDA Environment Variables (added by FramePack installer)
export CUDA_HOME="$CUDA_PATH"
export CUDA_ROOT="$CUDA_PATH"
export PATH="$CUDA_PATH/bin:\$PATH"
export LD_LIBRARY_PATH="$CUDA_PATH/lib64:\$LD_LIBRARY_PATH"
EOF
        fi
        
        log "CUDA environment variables configured"
    else
        warn "Could not locate CUDA installation. Some features may not work."
    fi
}

# Install PyTorch with CUDA 12.6 support (FramePack requirement)
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA 12.6 support..."
    
    # Ensure we're in the virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Ensure pip is available
    if ! command -v pip >/dev/null 2>&1; then
        python -m ensurepip --default-pip
        pip install --upgrade pip
    fi
    
    # Install PyTorch with CUDA 12.6 support (as specified in FramePack docs)
    # Install all three together to avoid version conflicts
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
    
    log "PyTorch with CUDA 12.6 support installed"
}

# Clone and setup FramePack
install_framepack() {
    log "Installing FramePack..."
    
    # Ensure we're in the virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Create FramePack workspace directory
    FRAMEPACK_DIR="$HOME/framepack"
    
    if [ -d "$FRAMEPACK_DIR" ]; then
        warn "FramePack directory already exists at $FRAMEPACK_DIR"
        if ask_yes_no "Do you want to remove it and install fresh?" "n"; then
            rm -rf "$FRAMEPACK_DIR"
        else
            info "Using existing FramePack installation"
            cd "$FRAMEPACK_DIR"
            git pull origin main || warn "Could not update existing installation"
            return 0
        fi
    fi
    
    # Clone FramePack repository
    git clone https://github.com/lllyasviel/FramePack.git "$FRAMEPACK_DIR"
    cd "$FRAMEPACK_DIR"
    
    # Install FramePack requirements
    pip install -r requirements.txt
    
    log "FramePack installed successfully at $FRAMEPACK_DIR"
}

# Install optional attention kernels
install_attention_kernels() {
    log "Installing optional attention kernels..."
    
    # Ensure we're in the virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    if ask_yes_no "Do you want to install sage-attention for better performance? (may affect results slightly)" "y"; then
        info "Installing sage-attention..."
        pip install sageattention==1.0.6 || warn "Failed to install sage-attention, continuing without it"
    fi
    
    if ask_yes_no "Do you want to install xformers for memory efficiency?" "y"; then
        info "Installing xformers..."
        pip install xformers || warn "Failed to install xformers, continuing without it"
    fi
    
    if ask_yes_no "Do you want to install flash-attention?" "n"; then
        info "Installing flash-attention..."
        
        # Check if CUDA environment is properly set
        if [ -z "$CUDA_HOME" ]; then
            warn "CUDA_HOME not set. Setting up CUDA environment first..."
            # Source bashrc to get CUDA variables
            source "$HOME/.bashrc" 2>/dev/null || true
        fi
        
        # Install with proper CUDA environment
        CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}" \
        pip install flash-attn --no-build-isolation || warn "Failed to install flash-attention, continuing without it"
    fi
}

# Create launcher scripts
create_launchers() {
    log "Creating launcher scripts..."
    
    # Main GUI launcher
    LAUNCHER_SCRIPT="$HOME/launch_framepack.sh"
    
    cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# FramePack Launcher Script
# This script activates the virtual environment and launches FramePack

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VENV_DIR="$HOME/framepack-env"
FRAMEPACK_DIR="$HOME/framepack"

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

echo -e "${GREEN}Starting FramePack GUI...${NC}"
echo -e "${GREEN}Access FramePack at: http://localhost:7860${NC}"
echo -e "${GREEN}Access from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${GREEN}Press Ctrl+C to stop FramePack${NC}"
echo -e "${YELLOW}Note: First run will download 30GB+ of models from HuggingFace${NC}"
echo

# Launch FramePack with network access and custom arguments
python demo_gradio.py --share --server_name 0.0.0.0 "$@"
EOF

    # F1 model launcher
    LAUNCHER_F1_SCRIPT="$HOME/launch_framepack_f1.sh"
    
    cat > "$LAUNCHER_F1_SCRIPT" << 'EOF'
#!/bin/bash

# FramePack F1 Launcher Script
# This script activates the virtual environment and launches FramePack F1

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VENV_DIR="$HOME/framepack-env"
FRAMEPACK_DIR="$HOME/framepack"

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

echo -e "${GREEN}Starting FramePack F1 GUI...${NC}"
echo -e "${GREEN}Access FramePack F1 at: http://localhost:7860${NC}"
echo -e "${GREEN}Access from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${GREEN}Press Ctrl+C to stop FramePack${NC}"
echo -e "${YELLOW}Note: First run will download models from HuggingFace${NC}"
echo

# Launch FramePack F1 with network access and custom arguments
python demo_gradio_f1.py --share --server_name 0.0.0.0 "$@"
EOF

    # Make the launcher scripts executable
    if chmod +x "$LAUNCHER_SCRIPT" && chmod +x "$LAUNCHER_F1_SCRIPT"; then
        log "Launcher scripts created and made executable:"
        info "  Main GUI: $LAUNCHER_SCRIPT"
        info "  F1 Model: $LAUNCHER_F1_SCRIPT"
    else
        warn "Failed to make launcher scripts executable. You may need to run:"
        warn "  chmod +x $LAUNCHER_SCRIPT"
        warn "  chmod +x $LAUNCHER_F1_SCRIPT"
    fi
}

# Create systemd service (optional)
create_systemd_service() {
    log "Creating systemd service for FramePack..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run FramePack automatically?" "n"; then
        return 0
    fi
    
    # Ask which version to run as service
    echo "Which FramePack version should run as a service?"
    echo "1) Main FramePack (demo_gradio.py)"
    echo "2) FramePack F1 (demo_gradio_f1.py)"
    read -p "Choose (1 or 2): " -n 1 -r service_choice
    echo
    
    case "$service_choice" in
        1)
            SERVICE_SCRIPT="launch_framepack.sh"
            SERVICE_NAME="framepack"
            SERVICE_DESC="FramePack Main"
            ;;
        2)
            SERVICE_SCRIPT="launch_framepack_f1.sh"
            SERVICE_NAME="framepack-f1"
            SERVICE_DESC="FramePack F1"
            ;;
        *)
            warn "Invalid choice, skipping systemd service creation"
            return 0
            ;;
    esac
    
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=$SERVICE_DESC Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/$SERVICE_SCRIPT
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME.service"
    
    log "Systemd service created. You can start it with: sudo systemctl start $SERVICE_NAME"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Activate virtual environment
    source "$HOME/framepack-env/bin/activate"
    
    # Test Python imports
    info "Testing Python imports..."
    python3 -c "import torch; print(f'PyTorch version: {torch.__version__}')"
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
    
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)"; then
        log "CUDA is available and working!"
        
        # Test GPU memory if possible
        python3 -c "
import torch
if torch.cuda.is_available():
    gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
    print(f'GPU Memory: {gpu_memory:.1f} GB')
    if gpu_memory < 6:
        print('WARNING: Less than 6GB GPU memory detected')
    else:
        print('GPU memory check passed')
"
    else
        warn "CUDA is not available. GPU acceleration may not work."
    fi
    
    # Test basic imports from FramePack requirements
    info "Testing FramePack dependencies..."
    cd "$HOME/framepack"
    python3 -c "
try:
    import gradio
    import diffusers
    import transformers
    print('Core dependencies imported successfully')
except ImportError as e:
    print(f'Import error: {e}')
    exit(1)
" || warn "Some dependencies may not be installed correctly"
    
    log "Installation test completed!"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "FramePack Installation Complete!"
    echo "=================================="
    echo
    info "FramePack has been installed successfully!"
    echo
    info "To start FramePack:"
    echo "  Main GUI: $HOME/launch_framepack.sh"
    echo "  F1 Model: $HOME/launch_framepack_f1.sh"
    echo
    info "Or manually:"
    echo "  source $HOME/framepack-env/bin/activate"
    echo "  cd $HOME/framepack"
    echo "  python demo_gradio.py --share --server_name 0.0.0.0"
    echo "  python demo_gradio_f1.py --share --server_name 0.0.0.0"
    echo
    info "FramePack will be accessible at:"
    echo "  Local access: http://localhost:7860"
    echo "  Network access: http://your-server-ip:7860"
    echo
    info "Common launch options:"
    echo "  --port 8080          : Use different port"
    echo "  --server_name 127.0.0.1 : Restrict to local access only"
    echo "  --share              : Create public Gradio link"
    echo
    if [ -f "/etc/systemd/system/framepack.service" ] || [ -f "/etc/systemd/system/framepack-f1.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start framepack     : Start main service"
        echo "  sudo systemctl start framepack-f1  : Start F1 service"
        echo "  sudo systemctl stop framepack      : Stop main service"
        echo "  sudo systemctl status framepack    : Check main status"
    fi
    echo
    warn "IMPORTANT NOTES:"
    echo "• First run will download 30GB+ of models from HuggingFace"
    echo "• Requires at least 6GB GPU memory for optimal performance"
    echo "• RTX 30XX/40XX/50XX series GPUs are recommended"
    echo "• Generation speed: ~2.5 sec/frame (RTX 4090), 4-8x slower on laptops"
    echo "• You'll see frames generate progressively (next-frame prediction)"
    echo "• Use TeaCache for faster preview, disable for highest quality"
    echo
    info "GPU Requirements Check:"
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -n1 || echo "GPU info not available"
    else
        echo "Run 'nvidia-smi' after reboot to check GPU status"
    fi
    echo
    info "For help and examples, visit: https://github.com/lllyasviel/FramePack"
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "FramePack Linux Installer"
    echo "=================================="
    echo
    info "This script will install FramePack with NVIDIA GPU support on Debian 12"
    info "Installation location: $HOME/framepack"
    info "Virtual environment: $HOME/framepack-env"
    echo
    info "Requirements:"
    echo "• NVIDIA RTX 30XX/40XX/50XX series GPU"
    echo "• At least 6GB GPU memory"
    echo "• 30GB+ free disk space for models"
    echo "• Debian 12 with sudo privileges"
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
    setup_cuda_environment
    create_venv
    install_pytorch_cuda
    install_framepack
    install_attention_kernels
    create_launchers
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
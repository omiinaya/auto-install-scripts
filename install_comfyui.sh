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

# Install nvcc compiler
install_nvcc() {
    log "Ensuring nvcc compiler is installed..."
    
    # Check if nvcc is already available
    if command -v nvcc >/dev/null 2>&1; then
        info "nvcc already available at: $(which nvcc)"
        nvcc --version | head -1
        return 0
    fi
    
    info "nvcc not found, installing CUDA development tools..."
    
    # Install comprehensive CUDA development packages
    sudo apt update
    
    # First try the standard CUDA packages that should be available
    info "Attempting to install CUDA toolkit packages..."
    sudo apt install -y \
        cuda-toolkit-12-6 \
        cuda-compiler-12-6 \
        cuda-nvcc-12-6 \
        cuda-toolkit-config-common \
        cuda-runtime-12-6 \
        cuda-drivers || warn "Some primary CUDA packages could not be installed"
    
    # If that fails, try installing the full CUDA toolkit
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Primary packages failed, trying full CUDA installation..."
        sudo apt install -y cuda || warn "Full CUDA installation failed"
    fi
    
    # If still no nvcc, try alternative approaches
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Trying alternative CUDA package names..."
        sudo apt install -y \
            cuda-toolkit \
            cuda-nvcc \
            cuda-compiler \
            libcuda1 \
            libcudart12 || warn "Alternative CUDA packages failed"
    fi
    
    # Last resort: try to install from nvidia-cuda-toolkit if available
    if ! command -v nvcc >/dev/null 2>&1; then
        info "Trying nvidia-cuda-toolkit as last resort..."
        sudo apt install -y nvidia-cuda-toolkit || warn "nvidia-cuda-toolkit not available"
    fi
    
    # Refresh PATH to pick up newly installed binaries
    export PATH="/usr/bin:/usr/local/bin:/usr/local/cuda/bin:/usr/local/cuda-12/bin:/usr/local/cuda-12.6/bin:/usr/local/cuda-12.9/bin:$PATH"
    hash -r
    
    # Search for nvcc in common locations (both /usr and /usr/local)
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
        
        # Add the CUDA bin directory to system PATH permanently
        CUDA_HOME=$(dirname "$NVCC_DIR")
        sudo tee /etc/profile.d/cuda.sh > /dev/null << EOF
# CUDA tools PATH (added by ComfyUI installer)
export PATH="$NVCC_DIR:\$PATH"
export CUDA_HOME="$CUDA_HOME"
export LD_LIBRARY_PATH="$CUDA_HOME/lib64:\$LD_LIBRARY_PATH"
EOF
        info "Created /etc/profile.d/cuda.sh for system-wide CUDA environment"
        info "CUDA_HOME set to: $CUDA_HOME"
        
        # Verify the symlink works
        if command -v nvcc >/dev/null 2>&1; then
            log "nvcc successfully configured at: $(which nvcc)"
            nvcc --version | head -1
        else
            warn "nvcc symlink created but not immediately available"
            info "Run 'source /etc/profile.d/cuda.sh' or restart your shell"
        fi
    else
        warn "Could not find nvcc anywhere in the system"
        warn "CUDA development tools may not be properly installed"
        info "You may need to install CUDA toolkit manually"
    fi
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
    
    # Check if comfy-cli is installed
    pip list | grep comfy

    # If not installed, install it
    pip install comfy-cli

    # Test the command
    comfy --version
    
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

# Verify and fix comfy-cli installation
verify_comfy_cli() {
    log "Verifying comfy-cli installation..."
    
    # Activate virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Check if comfy command works
    if command -v comfy >/dev/null 2>&1; then
        info "comfy-cli is working correctly"
        comfy --version
        return 0
    fi
    
    warn "comfy command not found, attempting to fix..."
    
    # Try to install/reinstall comfy-cli
    info "Installing comfy-cli..."
    if pip install comfy-cli; then
        info "comfy-cli installed successfully"
    else
        warn "Failed to install comfy-cli via pip"
        return 1
    fi
    
    # Test again
    if command -v comfy >/dev/null 2>&1; then
        log "comfy-cli is now working!"
        comfy --version
        return 0
    else
        warn "comfy command still not available after installation"
        info "You may need to restart your shell or check your PATH"
        return 1
    fi
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
    
    # Verify comfy-cli
    verify_comfy_cli
    
    log "Installation test completed successfully!"
}

# Download essential models
download_essential_models() {
    log "Downloading essential models..."
    
    if ! ask_yes_no "Do you want to download essential models (SD 1.5, SDXL, VAE)? This will take several GB of space." "y"; then
        info "Skipping model download. You can download models manually later."
        return 0
    fi
    
    # Activate virtual environment
    source "$HOME/comfy-env/bin/activate"
    
    # Create model directories
    mkdir -p "$HOME/comfy/models/checkpoints"
    mkdir -p "$HOME/comfy/models/vae"
    
    cd "$HOME/comfy/models/checkpoints"
    
    # Download SD 1.5 (the one causing the error)
    info "Downloading Stable Diffusion 1.5..."
    if wget -O v1-5-pruned-emaonly-fp16.safetensors https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors; then
        log "SD 1.5 downloaded successfully"
    else
        warn "Failed to download SD 1.5 model"
    fi
    
    # Download SDXL Base (optional)
    if ask_yes_no "Do you want to download SDXL Base model? (6.6GB)" "n"; then
        info "Downloading SDXL Base..."
        if wget -O sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors; then
            log "SDXL Base downloaded successfully"
        else
            warn "Failed to download SDXL Base model"
        fi
    fi
    
    # Download VAE
    cd "$HOME/comfy/models/vae"
    info "Downloading VAE model..."
    if wget -O vae-ft-mse-840000-ema-pruned.safetensors https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors; then
        log "VAE model downloaded successfully"
    else
        warn "Failed to download VAE model"
    fi
    
    log "Model download completed!"
    info "Models are stored in: $HOME/comfy/models/"
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
    install_nvcc
    create_venv
    install_comfy_cli
    install_comfyui
    install_pytorch_cuda
    install_additional_deps
    create_launcher
    create_systemd_service
    test_installation
    download_essential_models
    print_instructions
}

# Run main function
main "$@" 
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

# Set up CUDA environment variables globally
setup_cuda_environment() {
    # Check if CUDA is already in PATH
    if command -v nvcc >/dev/null 2>&1; then
        info "CUDA already available in PATH"
        return 0
    fi
    
    # Try to find CUDA installation and add to PATH
    local cuda_found=false
    for cuda_path in /usr/local/cuda-12.4 /usr/local/cuda-11.8 /usr/local/cuda-12.2 /usr/local/cuda; do
        if [ -f "$cuda_path/bin/nvcc" ]; then
            info "Found CUDA at: $cuda_path"
            export PATH="$cuda_path/bin:$PATH"
            export CUDA_HOME="$cuda_path"
            export LD_LIBRARY_PATH="$cuda_path/lib64:$LD_LIBRARY_PATH"
            cuda_found=true
            break
        fi
    done
    
    if [ "$cuda_found" = false ]; then
        warn "No CUDA installation found in common locations"
        warn "CUDA toolkit may need to be installed separately"
    else
        info "CUDA environment variables set:"
        info "  CUDA_HOME: $CUDA_HOME"
        info "  PATH: CUDA bin directory added"
        info "  LD_LIBRARY_PATH: CUDA lib64 directory added"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended for Stable Diffusion WebUI installation."
        warn "This can cause permission issues and conflicts with conda/pip."
        echo
        info "Recommended approach:"
        echo "  1. Create a regular user: adduser sdwebui"
        echo "  2. Add to sudo group: usermod -aG sudo sdwebui"
        echo "  3. Switch to user: su - sdwebui"
        echo "  4. Run this script as the regular user"
        echo
        if ! ask_yes_no "Do you want to continue as root anyway? (NOT recommended)" "n"; then
            exit 1
        fi
        warn "Continuing as root - you may encounter permission issues later."
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt update && sudo apt upgrade -y
}

# Check and install sudo if missing
check_and_install_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        warn "sudo is not installed. Installing sudo first..."
        
        # Check if we're running as root
        if [[ $EUID -eq 0 ]]; then
            # We're root, can install directly
            apt update
            apt install -y sudo
            log "sudo installed successfully"
        else
            # We're not root and don't have sudo - need manual intervention
            error "sudo is not installed and you're not running as root."
            echo "Please run one of the following commands first:"
            echo "  1. As root: apt update && apt install -y sudo"
            echo "  2. Using su: su -c 'apt update && apt install -y sudo'"
            echo "Then add your user to the sudo group:"
            echo "  usermod -aG sudo \$(whoami)"
            echo "Log out and log back in, then run this script again."
            exit 1
        fi
    else
        info "sudo is already installed"
    fi
}

# Install essential system packages
install_essential_packages() {
    log "Installing essential system packages..."
    sudo apt install -y \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common
}

# Install basic dependencies
install_basic_deps() {
    log "Installing basic development dependencies..."
    sudo apt install -y \
        git \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        unzip \
        zip \
        tar \
        gzip \
        vim \
        nano \
        htop \
        screen \
        tmux \
        tree \
        rsync \
        openssh-client \
        locales
}

# Install system libraries required for Stable Diffusion WebUI
install_system_libraries() {
    log "Installing system libraries for Stable Diffusion WebUI..."
    sudo apt install -y \
        libblas-dev \
        liblapack-dev \
        libatlas-base-dev \
        gfortran \
        libffi-dev \
        libssl-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        libgl1-mesa-glx \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender-dev \
        libgomp1 \
        libgcc-s1 \
        libc6-dev \
        zlib1g-dev \
        libglib2.0-0 \
        libgperftools0
}

# Install multimedia and graphics libraries
install_graphics_libs() {
    log "Installing graphics and multimedia libraries..."
    sudo apt install -y \
        libopencv-dev \
        python3-opencv \
        libjpeg-dev \
        libpng-dev \
        libtiff-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libv4l-dev \
        libxvidcore-dev \
        libx264-dev \
        libgtk2.0-dev \
        libatlas-base-dev \
        libgstreamer1.0-dev \
        libgstreamer-plugins-base1.0-dev \
        ffmpeg
}

# Install Python 3.10 (required for Stable Diffusion WebUI)
install_python() {
    log "Installing Python 3.10..."
    
    # Check if Python 3.10 is already installed
    if command -v python3.10 >/dev/null 2>&1; then
        info "Python 3.10 is already installed"
        return 0
    fi
    
    # Add deadsnakes PPA for Python 3.10
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update
    
    # Install Python 3.10 and pip
    sudo apt install -y python3.10 python3.10-venv python3.10-dev python3-pip
    
    # Create symlink for python3.10 as python3
    if [ ! -f /usr/bin/python3.10 ]; then
        error "Python 3.10 installation failed"
        exit 1
    fi
    
    # Install pip for Python 3.10
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10
    
    log "Python 3.10 installed successfully"
}

# Install NVIDIA drivers and CUDA
install_nvidia_drivers() {
    log "Checking NVIDIA GPU and drivers..."
    
    # Check if NVIDIA GPU is present
    if ! lspci | grep -i nvidia >/dev/null 2>&1; then
        warn "No NVIDIA GPU detected. Stable Diffusion WebUI may run on CPU only."
        if ! ask_yes_no "Continue with CPU-only installation?" "y"; then
            exit 1
        fi
        return 0
    fi
    
    info "NVIDIA GPU detected"
    
    # Check if NVIDIA drivers are already installed
    if command -v nvidia-smi >/dev/null 2>&1; then
        info "NVIDIA drivers already installed"
        nvidia-smi
        return 0
    fi
    
    if ask_yes_no "Install NVIDIA drivers and CUDA toolkit?" "y"; then
        log "Installing NVIDIA drivers and CUDA toolkit..."
        
        # Add NVIDIA repository
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
        sudo dpkg -i cuda-keyring_1.1-1_all.deb
        sudo apt update
        
        # Install CUDA toolkit and drivers
        sudo apt install -y cuda-toolkit-12-4 nvidia-driver-535
        
        # Install cuDNN
        sudo apt install -y libcudnn8
        
        log "NVIDIA drivers and CUDA toolkit installed"
        info "Please reboot your system after installation"
        
        if ask_yes_no "Reboot now?" "n"; then
            sudo reboot
        fi
    else
        warn "Skipping NVIDIA driver installation. Stable Diffusion WebUI may not work optimally."
    fi
}

# Install Miniconda
install_conda() {
    log "Installing Miniconda..."
    
    if [ -d "$HOME/miniconda3" ]; then
        warn "Miniconda already installed at $HOME/miniconda3"
        if ask_yes_no "Reinstall Miniconda?" "n"; then
            rm -rf "$HOME/miniconda3"
        else
            return 0
        fi
    fi
    
    # Download and install Miniconda
    MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
    MINICONDA_SCRIPT="$HOME/miniconda3.sh"
    
    wget -O "$MINICONDA_SCRIPT" "$MINICONDA_URL"
    bash "$MINICONDA_SCRIPT" -b -p "$HOME/miniconda3"
    rm "$MINICONDA_SCRIPT"
    
    # Initialize conda for this shell session
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    
    # Configure conda
    conda config --set auto_activate_base false
    conda config --set channel_priority strict
    
    log "Miniconda installed successfully"
}

# Create conda environment for Stable Diffusion WebUI
create_conda_env() {
    log "Creating conda environment for Stable Diffusion WebUI..."
    
    ENV_NAME="sdwebui"
    
    # Initialize conda for this shell session
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    
    # Remove existing environment if it exists
    if conda env list | grep -q "^$ENV_NAME "; then
        warn "Conda environment '$ENV_NAME' already exists"
        if ask_yes_no "Remove existing environment and create fresh?" "n"; then
            conda env remove -n "$ENV_NAME" -y
        else
            info "Using existing environment"
            return 0
        fi
    fi
    
    # Create environment with Python 3.10
    log "Creating conda environment with Python 3.10..."
    conda create -n "$ENV_NAME" python=3.10 -y
    
    # Activate environment and install essential packages
    conda activate "$ENV_NAME"
    
    # Install essential conda packages
    log "Installing essential conda packages..."
    conda install -c conda-forge -y \
        pip \
        setuptools \
        wheel \
        numpy \
        scipy \
        matplotlib \
        pillow \
        opencv \
        scikit-image \
        imageio \
        tqdm \
        pyyaml \
        requests \
        psutil \
        packaging \
        cython
    
    log "Conda environment '$ENV_NAME' created successfully with Python 3.10"
}

# Helper function to run commands in the sdwebui conda environment
run_in_sdwebui_env() {
    local cmd="$1"
    export PATH="$HOME/miniconda3/bin:$PATH"
    
    # Detect CUDA installation
    local cuda_vars=""
    if [ -d "/usr/local/cuda-12.4/bin" ]; then
        cuda_vars="export PATH='/usr/local/cuda-12.4/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.4'; export LD_LIBRARY_PATH='/usr/local/cuda-12.4/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-11.8/bin" ]; then
        cuda_vars="export PATH='/usr/local/cuda-11.8/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-11.8'; export LD_LIBRARY_PATH='/usr/local/cuda-11.8/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-12.2/bin" ]; then
        cuda_vars="export PATH='/usr/local/cuda-12.2/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.2'; export LD_LIBRARY_PATH='/usr/local/cuda-12.2/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda/bin" ]; then
        cuda_vars="export PATH='/usr/local/cuda/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda'; export LD_LIBRARY_PATH='/usr/local/cuda/lib64:\$LD_LIBRARY_PATH';"
    fi
    
    # Use conda run to execute commands in the environment
    conda run -n sdwebui bash -c "
        $cuda_vars
        export PYTHONPATH='$HOME/stable-diffusion-webui:\$PYTHONPATH'
        $cmd
    "
}

# Clone Stable Diffusion WebUI repository
clone_sdwebui() {
    log "Cloning Stable Diffusion WebUI repository..."
    
    SDWEBUI_DIR="$HOME/stable-diffusion-webui"
    
    if [ -d "$SDWEBUI_DIR" ]; then
        warn "Stable Diffusion WebUI directory already exists at $SDWEBUI_DIR"
        if ask_yes_no "Do you want to remove it and clone fresh?" "n"; then
            rm -rf "$SDWEBUI_DIR"
        else
            info "Using existing Stable Diffusion WebUI repository"
            cd "$SDWEBUI_DIR"
            git pull origin master
            return 0
        fi
    fi
    
    # Clone the repository
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$SDWEBUI_DIR"
    
    log "Stable Diffusion WebUI repository cloned successfully at $SDWEBUI_DIR"
}

# Install PyTorch with CUDA support
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA support..."
    
    # Install pip in conda environment
    log "Installing pip in conda environment..."
    conda run -n sdwebui conda install -c conda-forge pip -y
    
    # Verify pip is now available
    if ! conda run -n sdwebui which pip >/dev/null 2>&1; then
        error "Failed to install pip in conda environment"
        exit 1
    fi
    
    info "pip is available at: $(conda run -n sdwebui which pip)"
    
    # Upgrade pip and install PyTorch
    log "Upgrading pip and installing PyTorch..."
    run_in_sdwebui_env "pip install --upgrade pip setuptools wheel"
    
    # Install PyTorch with CUDA support
    log "Installing PyTorch with CUDA support..."
    run_in_sdwebui_env "pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121"
    
    # Verify PyTorch CUDA installation
    log "Verifying PyTorch CUDA installation..."
    run_in_sdwebui_env "python -c 'import torch; print(f\"PyTorch version: {torch.__version__}\"); print(f\"CUDA available: {torch.cuda.is_available()}\"); print(f\"CUDA version: {torch.version.cuda}\")'"
    
    log "PyTorch with CUDA support installed"
}

# Install Stable Diffusion WebUI dependencies
install_sdwebui_deps() {
    log "Installing Stable Diffusion WebUI dependencies..."
    
    cd "$HOME/stable-diffusion-webui"
    
    # Install requirements
    log "Installing Python requirements..."
    run_in_sdwebui_env "pip install -r requirements.txt"
    
    # Install additional useful packages
    log "Installing additional packages..."
    run_in_sdwebui_env "pip install xformers accelerate transformers diffusers"
    
    log "Stable Diffusion WebUI dependencies installed successfully"
}

# Create launcher scripts
create_launcher() {
    log "Creating launcher scripts..."
    
    # Create main launcher
    LAUNCHER_SCRIPT="$HOME/launch_sdwebui.sh"
    
    cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# Stable Diffusion WebUI Launcher Script

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONDA_DIR="$HOME/miniconda3"
SDWEBUI_DIR="$HOME/stable-diffusion-webui"

# Check if directories exist
if [ ! -d "$CONDA_DIR" ]; then
    echo -e "${RED}Miniconda not found at $CONDA_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

if [ ! -d "$SDWEBUI_DIR" ]; then
    echo -e "${RED}Stable Diffusion WebUI directory not found at $SDWEBUI_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Add conda to PATH and activate environment
export PATH="$CONDA_DIR/bin:$PATH"
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate sdwebui

# Change to Stable Diffusion WebUI directory
cd "$SDWEBUI_DIR"

# Set environment variables for better performance
export COMMANDLINE_ARGS="--listen --enable-insecure-extension-access --xformers"

echo -e "${GREEN}Starting Stable Diffusion WebUI...${NC}"
echo -e "${GREEN}Access locally at: http://localhost:7860${NC}"
echo -e "${GREEN}Access from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${GREEN}Press Ctrl+C to stop${NC}"
echo

# Launch Stable Diffusion WebUI
python launch.py
EOF

    # Create launcher with specific options
    LAUNCHER_OPTIONS="$HOME/launch_sdwebui_options.sh"
    
    cat > "$LAUNCHER_OPTIONS" << 'EOF'
#!/bin/bash

# Stable Diffusion WebUI Launcher with Options

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONDA_DIR="$HOME/miniconda3"
SDWEBUI_DIR="$HOME/stable-diffusion-webui"

# Check directories
if [ ! -d "$CONDA_DIR" ] || [ ! -d "$SDWEBUI_DIR" ]; then
    echo -e "${RED}Required directories not found. Please run the installer script first.${NC}"
    exit 1
fi

# Add conda to PATH and activate environment
export PATH="$CONDA_DIR/bin:$PATH"
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate sdwebui
cd "$SDWEBUI_DIR"

# Default arguments
ARGS="--listen --enable-insecure-extension-access"

# Add xformers for better performance if available
if python -c "import xformers" 2>/dev/null; then
    ARGS="$ARGS --xformers"
    echo -e "${GREEN}xformers available - enabling for better performance${NC}"
fi

# Add additional arguments if provided
if [ $# -gt 0 ]; then
    ARGS="$ARGS $@"
fi

echo -e "${GREEN}Starting Stable Diffusion WebUI with arguments: $ARGS${NC}"
echo -e "${GREEN}Access at: http://localhost:7860${NC}"
echo

# Launch with arguments
python launch.py $ARGS
EOF

    # Make launcher scripts executable
    chmod +x "$LAUNCHER_SCRIPT" "$LAUNCHER_OPTIONS"
    
    log "Launcher scripts created:"
    info "  Main launcher: $LAUNCHER_SCRIPT"
    info "  Options launcher: $LAUNCHER_OPTIONS"
}

# Create systemd service (optional)
create_systemd_service() {
    log "Creating systemd service for Stable Diffusion WebUI..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run Stable Diffusion WebUI automatically?" "n"; then
        return 0
    fi
    
    SERVICE_FILE="/etc/systemd/system/sdwebui.service"
    
    # Get absolute paths
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
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/launch_sdwebui.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=sdwebui

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable sdwebui.service
    
    log "Systemd service created. You can start it with: sudo systemctl start sdwebui"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Ensure conda is in PATH and activate environment
    export PATH="$HOME/miniconda3/bin:$PATH"
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate sdwebui
    
    # Change to Stable Diffusion WebUI directory
    cd "$HOME/stable-diffusion-webui"
    
    # Test Python imports
    info "Testing Python imports..."
    python -c "import torch; print(f'PyTorch version: {torch.__version__}')" || warn "PyTorch import failed"
    python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')" || warn "CUDA test failed"
    
    # Test Stable Diffusion WebUI imports
    info "Testing Stable Diffusion WebUI imports..."
    python -c "import modules.scripts; print('Stable Diffusion WebUI imports successful')" || warn "Stable Diffusion WebUI import failed"
    
    if python -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
        log "CUDA is available and working!"
    else
        warn "CUDA is not available. GPU acceleration may not work."
    fi
    
    log "Installation test completed!"
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "Stable Diffusion WebUI Installation Complete!"
    echo "=================================="
    echo
    info "To start Stable Diffusion WebUI:"
    echo "  1. Basic launch: $HOME/launch_sdwebui.sh"
    echo "  2. With options: $HOME/launch_sdwebui_options.sh"
    echo
    info "Stable Diffusion WebUI will be accessible at:"
    echo "  Local access: http://localhost:7860"
    echo "  Network access: http://your-server-ip:7860"
    echo
    info "Manual activation commands:"
    echo "  export PATH=\"$HOME/miniconda3/bin:\$PATH\""
    echo "  source \"$HOME/miniconda3/etc/profile.d/conda.sh\""
    echo "  conda activate sdwebui"
    echo "  cd $HOME/stable-diffusion-webui"
    echo "  python launch.py --listen"
    echo
    info "Common launch options:"
    echo "  --listen : Allow network access"
    echo "  --xformers : Better memory efficiency (if available)"
    echo "  --medvram : For GPUs with 4-8GB VRAM"
    echo "  --lowvram : For GPUs with 2-4GB VRAM"
    echo "  --cpu : Force CPU-only mode"
    echo "  --api : Enable API access"
    echo
    info "Model downloads:"
    echo "  Place model files in: $HOME/stable-diffusion-webui/models/Stable-diffusion/"
    echo "  Recommended models:"
    echo "    - Stable Diffusion 1.5: https://huggingface.co/runwayml/stable-diffusion-v1-5"
    echo "    - Stable Diffusion 2.1: https://huggingface.co/stabilityai/stable-diffusion-2-1"
    echo "    - Stable Diffusion XL: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0"
    echo
    info "Extensions:"
    echo "  Extensions are automatically installed in: $HOME/stable-diffusion-webui/extensions/"
    echo "  Popular extensions:"
    echo "    - ControlNet: https://github.com/Mikubill/sd-webui-controlnet"
    echo "    - LoRA: Built-in support"
    echo "    - Textual Inversion: Built-in support"
    echo
    if [ -f "/etc/systemd/system/sdwebui.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start sdwebui    : Start service"
        echo "  sudo systemctl stop sdwebui     : Stop service"
        echo "  sudo systemctl status sdwebui   : Check status"
    fi
    echo
    warn "Important notes:"
    echo "  - First launch may take time to download models"
    echo "  - Recommended: At least 8GB GPU memory for optimal performance"
    echo "  - For better results, use high-quality models and proper prompts"
    echo "  - Check the wiki for advanced features and troubleshooting"
    echo
    info "Troubleshooting:"
    echo "  - If CUDA errors occur, check NVIDIA driver installation"
    echo "  - If out of memory, use --medvram or --lowvram flags"
    echo "  - Check logs in the web UI or with: journalctl -u sdwebui -f"
    echo
}

# Main installation function
main() {
    echo "=================================="
    log "Stable Diffusion WebUI Linux Installer"
    echo "=================================="
    echo
    info "This script will install AUTOMATIC1111's Stable Diffusion WebUI with NVIDIA GPU support on Debian 12"
    info "Installation location: $HOME/stable-diffusion-webui"
    info "Conda environment: $HOME/miniconda3/envs/sdwebui"
    echo
    info "Stable Diffusion WebUI is a powerful web interface for Stable Diffusion that supports:"
    echo "  - Text-to-image generation"
    echo "  - Image-to-image generation"
    echo "  - Inpainting and outpainting"
    echo "  - Extensions and custom scripts"
    echo "  - LoRA, Textual Inversion, and ControlNet"
    echo "  - Multiple model support"
    echo "  - Web-based user interface"
    echo
    warn "System requirements:"
    echo "  - Debian 12 Linux system"
    echo "  - NVIDIA GPU with 4GB+ VRAM (recommended 8GB+)"
    echo "  - 20GB+ free disk space"
    echo "  - Internet connection for downloads"
    echo
    
    if ! ask_yes_no "Do you want to continue with the installation?" "y"; then
        info "Installation cancelled."
        exit 0
    fi
    
    check_and_install_sudo
    check_root
    setup_cuda_environment
    update_system
    install_essential_packages
    install_basic_deps
    install_system_libraries
    install_graphics_libs
    install_python
    install_nvidia_drivers
    install_conda
    create_conda_env
    clone_sdwebui
    install_pytorch_cuda
    install_sdwebui_deps
    create_launcher
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
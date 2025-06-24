#!/bin/bash

# TRELLIS Linux Installer Script for Debian 12 (Proxmox Container)
# This script installs TRELLIS 3D generation model with NVIDIA GPU support

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
        warn "Running as root is not recommended for TRELLIS installation."
        warn "This can cause permission issues and conflicts with conda/pip."
        echo
        info "Recommended approach:"
        echo "  1. Create a regular user: adduser trellis"
        echo "  2. Add to sudo group: usermod -aG sudo trellis"
        echo "  3. Switch to user: su - trellis"
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

# Install essential system packages (often missing in minimal Debian 12)
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
        locales \
        util-linux
}

# Install system libraries required for TRELLIS
install_system_libraries() {
    log "Installing system libraries for TRELLIS..."
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
        zlib1g-dev
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
        ffmpeg \
        libavutil-dev \
        libpostproc-dev \
        libeigen3-dev \
        libglfw3-dev \
        libglew-dev \
        freeglut3-dev
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
        python3-distutils \
        python3-numpy \
        python3-scipy \
        python3-matplotlib \
        python3-pil \
        python3-requests \
        python3-six \
        python3-yaml \
        python3-psutil \
        pipx \
        cython3
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    info "Python version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.8+
    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 8) else 1)"; then
        log "Python version is sufficient (3.8+)"
    else
        error "Python version is too old. TRELLIS requires Python 3.8 or higher."
    fi
    
    # Skip global pip upgrade due to externally-managed-environment
    info "Skipping global pip upgrade (will upgrade in virtual environment)"
}

# Install NVIDIA drivers and CUDA toolkit for Proxmox container
install_nvidia_drivers() {
    if ! ask_yes_no "Do you want to install NVIDIA drivers and CUDA toolkit?" "y"; then
        warn "Skipping NVIDIA driver installation. GPU acceleration will not be available."
        return 0
    fi
    
    log "Installing NVIDIA drivers and CUDA toolkit for Proxmox container..."
    
    # Add NVIDIA CUDA repository
    info "Adding NVIDIA CUDA repository..."
    curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    
    # Update package list
    sudo apt update
    
    # Install NVIDIA drivers
    info "Installing NVIDIA drivers..."
    sudo apt -V install -y nvidia-driver-cuda nvidia-kernel-dkms
    
    # Install CUDA toolkit (needed for nvcc and development)
    info "Installing CUDA toolkit..."
    sudo apt install -y \
        cuda-toolkit-12-4 \
        cuda-compiler-12-4 \
        cuda-libraries-dev-12-4 \
        cuda-driver-dev-12-4
    
    # Note: cuDNN and NCCL are not available in NVIDIA repository for Debian 12
    # These will be installed via conda/pip in the Python environment instead
    info "Skipping cuDNN and NCCL system packages (not available for Debian 12)"
    warn "cuDNN and NCCL will be installed via conda/pip in the Python environment"
    
    # Reconfigure NVIDIA kernel DKMS
    sudo dpkg-reconfigure nvidia-kernel-dkms
    
    # Set up CUDA environment globally
    info "Setting up CUDA environment..."
    echo 'export PATH="/usr/local/cuda-12.4/bin:$PATH"' | sudo tee -a /etc/environment
    echo 'export CUDA_HOME="/usr/local/cuda-12.4"' | sudo tee -a /etc/environment
    echo 'export LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH"' | sudo tee -a /etc/environment
    
    # Create symlink for default CUDA
    if [ ! -L "/usr/local/cuda" ]; then
        sudo ln -sf /usr/local/cuda-12.4 /usr/local/cuda
    fi
    
    # Clean up
    rm -f cuda-keyring_1.1-1_all.deb
    
    log "NVIDIA drivers and CUDA toolkit installed successfully"
    info "CUDA_HOME will be set to: /usr/local/cuda-12.4"
    info "You may need to restart or source /etc/environment for global changes"
}

# Install Conda
install_conda() {
    log "Installing Miniconda..."
    
    CONDA_DIR="$HOME/miniconda3"
    
    if [ -d "$CONDA_DIR" ]; then
        warn "Miniconda already exists at $CONDA_DIR"
        if ask_yes_no "Do you want to remove it and install fresh?" "n"; then
            rm -rf "$CONDA_DIR"
        else
            info "Using existing Miniconda installation"
            return 0
        fi
    fi
    
    # Download and install Miniconda
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p "$CONDA_DIR"
    rm miniconda.sh
    
    # Initialize conda
    "$CONDA_DIR/bin/conda" init bash
    
    # Add conda to PATH for current session
    export PATH="$CONDA_DIR/bin:$PATH"
    
    # Update conda
    conda update -n base -c defaults conda -y
    
    log "Miniconda installed successfully at $CONDA_DIR"
}

# Create virtual environment
create_conda_env() {
    log "Creating Conda environment for TRELLIS..."
    
    # Ensure conda is in PATH
    export PATH="$HOME/miniconda3/bin:$PATH"
    
    ENV_NAME="trellis"
    
    # Check if environment already exists
    if conda env list | grep -q "^$ENV_NAME "; then
        warn "Conda environment '$ENV_NAME' already exists"
        if ask_yes_no "Do you want to remove it and create a new one?" "y"; then
            conda env remove -n "$ENV_NAME" -y
        else
            info "Using existing conda environment"
            # Initialize conda for this shell session
            source "$HOME/miniconda3/etc/profile.d/conda.sh"
            # Still verify it has the right Python version
            conda activate "$ENV_NAME"
            ACTUAL_PYTHON_VERSION=$(python --version)
            if [[ ! "$ACTUAL_PYTHON_VERSION" == *"3.10"* ]]; then
                error "Existing environment has wrong Python version: $ACTUAL_PYTHON_VERSION"
                error "Removing and recreating..."
                conda deactivate
                conda env remove -n "$ENV_NAME" -y
            else
                log "Existing environment verified with Python 3.10"
                return 0
            fi
        fi
    fi
    
    # Force Python 3.10 installation with multiple attempts
    info "Creating conda environment with Python 3.10..."
    
    # Initialize conda for this shell session
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    
    # Method 1: Try explicit Python 3.10
    log "Attempt 1: Creating environment with python=3.10"
    if conda create -n "$ENV_NAME" python=3.10 -y; then
        conda activate "$ENV_NAME"
        ACTUAL_PYTHON_VERSION=$(python --version)
        info "Created environment with: $ACTUAL_PYTHON_VERSION"
        
        if [[ "$ACTUAL_PYTHON_VERSION" == *"3.10"* ]]; then
            log "Successfully created Python 3.10 environment"
        else
            warn "Wrong Python version, trying method 2..."
            conda deactivate
            conda env remove -n "$ENV_NAME" -y
            
            # Method 2: Try with explicit version constraint
            log "Attempt 2: Creating environment with python=3.10.*"
            if conda create -n "$ENV_NAME" python=3.10.* -y; then
                conda activate "$ENV_NAME"
                ACTUAL_PYTHON_VERSION=$(python --version)
                info "Created environment with: $ACTUAL_PYTHON_VERSION"
                
                if [[ ! "$ACTUAL_PYTHON_VERSION" == *"3.10"* ]]; then
                    conda deactivate
                    conda env remove -n "$ENV_NAME" -y
                    
                    # Method 3: Force with conda-forge channel
                    log "Attempt 3: Creating environment with conda-forge channel"
                    conda create -n "$ENV_NAME" -c conda-forge python=3.10 -y
                    conda activate "$ENV_NAME"
                    ACTUAL_PYTHON_VERSION=$(python --version)
                    info "Created environment with: $ACTUAL_PYTHON_VERSION"
                    
                    if [[ ! "$ACTUAL_PYTHON_VERSION" == *"3.10"* ]]; then
                        error "All methods failed to create Python 3.10 environment"
                        error "Your conda installation may need updating"
                        error "Try: conda update conda"
                        exit 1
                    fi
                fi
            else
                error "Failed to create conda environment"
                exit 1
            fi
        fi
    else
        error "Failed to create conda environment"
        exit 1
    fi
    
    # Verify final environment
    FINAL_ENV=$(conda info --envs | grep '*' | awk '{print $1}')
    FINAL_PYTHON=$(python --version)
    FINAL_PATH=$(which python)
    
    log "Final environment verification:"
    info "  Environment: $FINAL_ENV"
    info "  Python: $FINAL_PYTHON"
    info "  Path: $FINAL_PATH"
    
    if [[ "$FINAL_ENV" != "$ENV_NAME" ]] || [[ ! "$FINAL_PYTHON" == *"3.10"* ]]; then
        error "Environment verification failed!"
        exit 1
    fi
    
    # Install essential conda packages for Python 3.10
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

# Helper function to run commands in the trellis conda environment
run_in_trellis_env() {
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
    # This avoids shell activation issues
    conda run -n trellis bash -c "
        $cuda_vars
        export PYTHONPATH='$HOME/TRELLIS:\$PYTHONPATH'
        export SPCONV_ALGO='native'
        export CUDA_LAUNCH_BLOCKING=1
        export PATH='$HOME/miniconda3/envs/trellis/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH'
        $cmd
    "
}

# Helper function to verify trellis environment exists and has correct Python
verify_trellis_env() {
    export PATH="$HOME/miniconda3/bin:$PATH"
    
    # Check if the environment exists
    if ! conda env list | grep -q "^trellis "; then
        error "Trellis conda environment not found!"
        error "Available environments:"
        conda env list
        exit 1
    fi
    
    # Check Python version in the environment
    PYTHON_VERSION=$(conda run -n trellis python --version 2>/dev/null || echo "unknown")
    PYTHON_PATH=$(conda run -n trellis which python 2>/dev/null || echo "unknown")
    
    if [[ ! "$PYTHON_VERSION" == *"3.10"* ]]; then
        error "Trellis environment has wrong Python version!"
        error "Expected: Python 3.10.x"
        error "Got: $PYTHON_VERSION"
        error "Python path: $PYTHON_PATH"
        exit 1
    fi
    
    log "Trellis environment verified: $PYTHON_VERSION at $PYTHON_PATH"
}

# Clone TRELLIS repository
clone_trellis() {
    log "Cloning TRELLIS repository..."
    
    TRELLIS_DIR="$HOME/TRELLIS"
    
    if [ -d "$TRELLIS_DIR" ]; then
        warn "TRELLIS directory already exists at $TRELLIS_DIR"
        if ask_yes_no "Do you want to remove it and clone fresh?" "n"; then
            rm -rf "$TRELLIS_DIR"
        else
            info "Using existing TRELLIS repository"
            cd "$TRELLIS_DIR"
            git submodule update --init --recursive
            return 0
        fi
    fi
    
    # Clone with submodules
    git clone --recurse-submodules https://github.com/microsoft/TRELLIS.git "$TRELLIS_DIR"
    
    log "TRELLIS repository cloned successfully at $TRELLIS_DIR"
}

# Verify CUDA installation
verify_cuda_installation() {
    log "Verifying CUDA installation..."
    
    # Check if nvcc is available
    if command -v nvcc >/dev/null 2>&1; then
        NVCC_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
        info "Found nvcc version: $NVCC_VERSION"
    else
        warn "nvcc not found in PATH. Checking common locations..."
        
        # Check common CUDA paths
        local cuda_found=false
        for cuda_path in /usr/local/cuda-12.4 /usr/local/cuda-11.8 /usr/local/cuda-12.2 /usr/local/cuda; do
            if [ -f "$cuda_path/bin/nvcc" ]; then
                info "Found nvcc at: $cuda_path/bin/nvcc"
                NVCC_VERSION=$($cuda_path/bin/nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
                info "NVCC version: $NVCC_VERSION"
                cuda_found=true
                break
            fi
        done
        
        if [ "$cuda_found" = false ]; then
            warn "CUDA toolkit not found in common locations!"
            warn "This might be because:"
            warn "  1. CUDA toolkit is not installed"
            warn "  2. CUDA is installed in a non-standard location"
            warn "  3. CUDA installation is incomplete"
            echo
            info "Checking if CUDA packages are installed..."
            if dpkg -l | grep -q cuda; then
                info "CUDA packages found in system:"
                dpkg -l | grep cuda | head -10
            else
                warn "No CUDA packages found in system"
            fi
            echo
            warn "TRELLIS will continue installation, but CUDA compilation may fail."
            warn "You may need to install CUDA toolkit manually:"
            echo "  sudo apt install cuda-toolkit-12-4"
            echo "  or run the script again and choose 'y' when asked about NVIDIA drivers."
        fi
    fi
    
    # Check CUDA_HOME
    if [ -z "$CUDA_HOME" ]; then
        warn "CUDA_HOME not set globally. Will set per-command."
    else
        info "CUDA_HOME: $CUDA_HOME"
    fi
    
    log "CUDA verification completed"
}

# Install PyTorch with CUDA support
install_pytorch_cuda() {
    log "Installing PyTorch with CUDA support..."
    
    # Verify environment exists and has correct Python version
    verify_trellis_env
    
    # Verify CUDA is available
    verify_cuda_installation
    
    # Show environment info
    info "Using conda environment: trellis"
    info "Python version: $(conda run -n trellis python --version)"
    info "Python path: $(conda run -n trellis which python)"
    
    # Ensure pip is installed and available in the conda environment
    log "Installing pip in conda environment..."
    conda run -n trellis conda install -c conda-forge pip -y
    
    # Verify pip is now available
    if ! conda run -n trellis which pip >/dev/null 2>&1; then
        error "Failed to install pip in conda environment"
        exit 1
    fi
    
    info "pip is available at: $(conda run -n trellis which pip)"
    
    # Upgrade pip in conda environment
    log "Upgrading pip and setuptools..."
    run_in_trellis_env "$HOME/miniconda3/envs/trellis/bin/pip install --upgrade pip setuptools wheel"
    
    # Install compatible PyTorch version (2.5.1 instead of 2.6.0 for better compatibility)
    log "Installing PyTorch 2.5.1 with CUDA 12.4 support for better package compatibility..."
    run_in_trellis_env "$HOME/miniconda3/envs/trellis/bin/pip install torch==2.5.1+cu124 torchvision==0.20.1+cu124 torchaudio==2.5.1+cu124 --index-url https://download.pytorch.org/whl/cu124"
    
    # Verify PyTorch CUDA installation
    log "Verifying PyTorch CUDA installation..."
    run_in_trellis_env "python -c 'import torch; print(f\"PyTorch version: {torch.__version__}\"); print(f\"CUDA available: {torch.cuda.is_available()}\"); print(f\"CUDA version: {torch.version.cuda}\")'"
    
    log "PyTorch with CUDA support installed"
}

# Set permanent CUDA environment variables in conda environment
setup_cuda_env_vars() {
    log "Setting up CUDA environment variables in conda environment..."
    
    # Determine CUDA path
    local cuda_path=""
    if [ -d "/usr/local/cuda-12.4/bin" ]; then
        cuda_path="/usr/local/cuda-12.4"
        info "Using CUDA 12.4"
    elif [ -d "/usr/local/cuda-11.8/bin" ]; then
        cuda_path="/usr/local/cuda-11.8"
        info "Using CUDA 11.8"
    elif [ -d "/usr/local/cuda-12.2/bin" ]; then
        cuda_path="/usr/local/cuda-12.2"
        info "Using CUDA 12.2"
    elif [ -d "/usr/local/cuda/bin" ]; then
        cuda_path="/usr/local/cuda"
        info "Using default CUDA installation"
    else
        error "No CUDA installation found!"
        error "Please install CUDA toolkit first: sudo apt install cuda-toolkit-12-4"
        exit 1
    fi
    
    # Create conda environment activation script to set CUDA variables
    local env_vars_dir="$HOME/miniconda3/envs/trellis/etc/conda/activate.d"
    local env_vars_script="$env_vars_dir/cuda_env_vars.sh"
    
    # Create activation directory if it doesn't exist
    mkdir -p "$env_vars_dir"
    
    # Create script to set CUDA environment variables
    cat > "$env_vars_script" << EOF
#!/bin/bash
# CUDA environment variables for TRELLIS
export CUDA_HOME="$cuda_path"
export PATH="$cuda_path/bin:\$PATH"
export LD_LIBRARY_PATH="$cuda_path/lib64:\$LD_LIBRARY_PATH"
export CUDA_LAUNCH_BLOCKING=1
export SPCONV_ALGO='native'
EOF
    
    chmod +x "$env_vars_script"
    
    # Also create deactivation script
    local deactivate_dir="$HOME/miniconda3/envs/trellis/etc/conda/deactivate.d"
    local deactivate_script="$deactivate_dir/cuda_env_vars.sh"
    
    mkdir -p "$deactivate_dir"
    
    cat > "$deactivate_script" << EOF
#!/bin/bash
# Remove CUDA environment variables when deactivating TRELLIS environment
unset CUDA_HOME
# Note: We don't unset PATH and LD_LIBRARY_PATH as they might be used by other applications
EOF
    
    chmod +x "$deactivate_script"
    
    log "CUDA environment variables configured for conda environment"
    info "CUDA_HOME: $cuda_path"
    info "PATH: $cuda_path/bin (added)"
    info "LD_LIBRARY_PATH: $cuda_path/lib64 (added)"
}

# Install TRELLIS dependencies
install_trellis_deps() {
    log "Installing TRELLIS dependencies..."
    
    # Verify environment exists and has correct Python version
    verify_trellis_env
    
    # Set up CUDA environment variables permanently
    setup_cuda_env_vars
    
    # Define CUDA environment variables for this session
    local cuda_path=""
    local cuda_env_vars=""
    if [ -d "/usr/local/cuda-12.4/bin" ]; then
        cuda_path="/usr/local/cuda-12.4"
        cuda_env_vars="export PATH='/usr/local/cuda-12.4/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.4'; export LD_LIBRARY_PATH='/usr/local/cuda-12.4/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-11.8/bin" ]; then
        cuda_path="/usr/local/cuda-11.8"
        cuda_env_vars="export PATH='/usr/local/cuda-11.8/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-11.8'; export LD_LIBRARY_PATH='/usr/local/cuda-11.8/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-12.2/bin" ]; then
        cuda_path="/usr/local/cuda-12.2"
        cuda_env_vars="export PATH='/usr/local/cuda-12.2/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.2'; export LD_LIBRARY_PATH='/usr/local/cuda-12.2/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda/bin" ]; then
        cuda_path="/usr/local/cuda"
        cuda_env_vars="export PATH='/usr/local/cuda/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda'; export LD_LIBRARY_PATH='/usr/local/cuda/lib64:\$LD_LIBRARY_PATH';"
    fi
    
    info "Using conda environment: trellis"
    info "Python version: $(conda run -n trellis python --version)"
    info "Python path: $(conda run -n trellis which python)"
    info "CUDA path: $cuda_path"
    
    # Verify CUDA environment is properly set
    log "Verifying CUDA environment in conda environment..."
    run_in_trellis_env "echo 'CUDA_HOME:' \$CUDA_HOME && echo 'nvcc version:' && nvcc --version 2>/dev/null || echo 'nvcc not found'" || warn "nvcc not found in conda environment, but CUDA_HOME is set"
    
    # Additional CUDA verification
    log "Additional CUDA verification..."
    run_in_trellis_env "echo 'Checking CUDA installation...' && ls -la \$CUDA_HOME/bin/nvcc 2>/dev/null || echo 'nvcc not found at expected location'"
    run_in_trellis_env "echo 'Checking CUDA libraries...' && ls -la \$CUDA_HOME/lib64/libcuda* 2>/dev/null | head -5 2>/dev/null || echo 'CUDA libraries not found'"
    
    # Check if CUDA toolkit is actually installed on the system
    log "Checking system CUDA toolkit installation..."
    if ! command -v nvcc >/dev/null 2>&1; then
        warn "CUDA toolkit (nvcc) not found on system level"
        info "Checking for CUDA packages..."
        if dpkg -l | grep -q "cuda-toolkit"; then
            info "CUDA toolkit packages are installed:"
            dpkg -l | grep "cuda-toolkit" | head -3
            warn "CUDA toolkit is installed but nvcc is not in system PATH"
            info "This might be a PATH issue. The installation will continue but some CUDA compilation may fail."
        else
            warn "CUDA toolkit packages are not installed"
            info "You may need to install CUDA toolkit: sudo apt install cuda-toolkit-12-4"
            info "The installation will continue but CUDA compilation will likely fail."
        fi
    else
        info "CUDA toolkit found on system level: $(which nvcc)"
    fi
    
    # Make setup script executable
    run_in_trellis_env "cd '$HOME/TRELLIS' && chmod +x setup.sh"
    
    # Install dependencies using the setup script step by step (in conda environment)
    info "Installing basic dependencies..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --basic"
    
    info "Installing xformers (compatible version for PyTorch 2.5.1)..."
    # Install specific xformers version compatible with PyTorch 2.5.1
    run_in_trellis_env "$HOME/miniconda3/envs/trellis/bin/pip install xformers==0.0.28.post3 --no-deps"
    # Also try the original setup script in case there are additional dependencies
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --xformers" || warn "Setup script xformers step failed, but compatible version already installed"
    
    info "Installing flash-attn..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --flash-attn" || warn "Flash-attn installation failed, continuing with other dependencies"
    
    info "Installing diffoctreerast..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --diffoctreerast" || warn "Diffoctreerast installation failed, continuing with other dependencies"
    
    info "Installing spconv..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --spconv" || warn "Spconv installation failed, continuing with other dependencies"
    
    info "Installing mip-splatting..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --mipgaussian" || warn "Mip-splatting installation failed, continuing with other dependencies"
    
    info "Installing kaolin (compatible version for PyTorch 2.5.1)..."
    # Install kaolin using pip with compatible PyTorch version
    run_in_trellis_env "$HOME/miniconda3/envs/trellis/bin/pip install kaolin==0.17.0 -f https://nvidia-kaolin.s3.us-east-2.amazonaws.com/torch-2.5.1_cu124.html" || warn "Kaolin installation failed, trying alternative method"
    # Also try the original setup script in case there are additional dependencies
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --kaolin" || warn "Setup script kaolin step failed, but compatible version already installed"
    
    info "Installing nvdiffrast..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --nvdiffrast" || warn "Nvdiffrast installation failed, continuing with other dependencies"
    
    info "Installing demo dependencies..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --demo" || warn "Demo dependencies installation failed, continuing with other dependencies"
    
    # Install additional Python packages that might be needed (in conda environment)
    info "Installing additional Python packages..."
    run_in_trellis_env "$HOME/miniconda3/envs/trellis/bin/pip install gradio transformers diffusers accelerate safetensors huggingface-hub trimesh pyopengl moderngl imageio-ffmpeg av decord"
    
    # Install cuDNN via conda (since it's not available as system package on Debian 12)
    info "Installing cuDNN via conda..."
    run_in_trellis_env "$HOME/miniconda3/bin/conda install -c conda-forge cudnn -y" || warn "cuDNN conda installation failed, but may not be strictly required"
    
    log "TRELLIS dependencies installed successfully"
}

# Retry installation of CUDA-dependent packages
retry_cuda_dependent_installations() {
    log "Retrying installation of CUDA-dependent packages..."
    
    # Check if CUDA toolkit is now available
    if ! command -v nvcc >/dev/null 2>&1; then
        warn "CUDA toolkit still not available, skipping CUDA-dependent package retry"
        return 0
    fi
    
    info "CUDA toolkit is available, retrying failed installations..."
    
    # Set up CUDA environment variables
    local cuda_env_vars=""
    if [ -d "/usr/local/cuda-12.4/bin" ]; then
        cuda_env_vars="export PATH='/usr/local/cuda-12.4/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.4'; export LD_LIBRARY_PATH='/usr/local/cuda-12.4/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-11.8/bin" ]; then
        cuda_env_vars="export PATH='/usr/local/cuda-11.8/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-11.8'; export LD_LIBRARY_PATH='/usr/local/cuda-11.8/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda-12.2/bin" ]; then
        cuda_env_vars="export PATH='/usr/local/cuda-12.2/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda-12.2'; export LD_LIBRARY_PATH='/usr/local/cuda-12.2/lib64:\$LD_LIBRARY_PATH';"
    elif [ -d "/usr/local/cuda/bin" ]; then
        cuda_env_vars="export PATH='/usr/local/cuda/bin:\$PATH'; export CUDA_HOME='/usr/local/cuda'; export LD_LIBRARY_PATH='/usr/local/cuda/lib64:\$LD_LIBRARY_PATH';"
    fi
    
    # Retry flash-attn installation
    info "Retrying flash-attn installation..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --flash-attn" || warn "Flash-attn installation still failed"
    
    # Retry spconv installation
    info "Retrying spconv installation..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --spconv" || warn "Spconv installation still failed"
    
    # Retry mip-splatting installation
    info "Retrying mip-splatting installation..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --mipgaussian" || warn "Mip-splatting installation still failed"
    
    # Retry nvdiffrast installation
    info "Retrying nvdiffrast installation..."
    run_in_trellis_env "cd '$HOME/TRELLIS' && $cuda_env_vars source setup.sh --nvdiffrast" || warn "Nvdiffrast installation still failed"
    
    log "CUDA-dependent package retry completed"
}

# Create launcher script
create_launcher() {
    log "Creating launcher scripts..."
    
    # Create main launcher for web demo
    LAUNCHER_SCRIPT="$HOME/launch_trellis.sh"
    
    cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash

# TRELLIS Launcher Script
# This script activates the conda environment and launches TRELLIS web demo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

CONDA_DIR="$HOME/miniconda3"
TRELLIS_DIR="$HOME/TRELLIS"

# Check if conda environment exists
if [ ! -d "$CONDA_DIR" ]; then
    echo -e "${RED}Miniconda not found at $CONDA_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Check if TRELLIS directory exists
if [ ! -d "$TRELLIS_DIR" ]; then
    echo -e "${RED}TRELLIS directory not found at $TRELLIS_DIR${NC}"
    echo "Please run the installer script first."
    exit 1
fi

# Add conda to PATH and initialize
export PATH="$CONDA_DIR/bin:$PATH"
source "$CONDA_DIR/etc/profile.d/conda.sh"

# Activate conda environment
conda activate trellis

# Change to TRELLIS directory
cd "$TRELLIS_DIR"

# Set environment variables
export SPCONV_ALGO='native'
export CUDA_LAUNCH_BLOCKING=1

# Set CUDA paths if available
if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
    export CUDA_HOME="/usr/local/cuda"
fi

echo -e "${GREEN}Starting TRELLIS Web Demo...${NC}"
echo -e "${GREEN}Access TRELLIS locally at: http://localhost:7860${NC}"
echo -e "${GREEN}Access TRELLIS from network at: http://$(hostname -I | awk '{print $1}'):7860${NC}"
echo -e "${GREEN}Press Ctrl+C to stop TRELLIS${NC}"
echo -e "${BLUE}Note: First launch may take longer due to model downloads${NC}"
echo

# Launch TRELLIS web demo with network access
python app.py --server_name 0.0.0.0 --server_port 7860 "$@"
EOF

    # Create text-to-3D launcher
    TEXT_LAUNCHER="$HOME/launch_trellis_text.sh"
    
    cat > "$TEXT_LAUNCHER" << 'EOF'
#!/bin/bash

# TRELLIS Text-to-3D Launcher Script

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

CONDA_DIR="$HOME/miniconda3"
TRELLIS_DIR="$HOME/TRELLIS"

# Check directories
if [ ! -d "$CONDA_DIR" ] || [ ! -d "$TRELLIS_DIR" ]; then
    echo -e "${RED}Required directories not found. Please run the installer script first.${NC}"
    exit 1
fi

# Add conda to PATH and activate environment
export PATH="$CONDA_DIR/bin:$PATH"
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate trellis
cd "$TRELLIS_DIR"

# Set environment variables
export SPCONV_ALGO='native'
export CUDA_LAUNCH_BLOCKING=1

# Set CUDA paths if available
if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
    export CUDA_HOME="/usr/local/cuda"
fi

echo -e "${GREEN}Starting TRELLIS Text-to-3D Web Demo...${NC}"
echo -e "${GREEN}Access at: http://localhost:7860${NC}"
echo

# Launch text-to-3D demo
python app_text.py --server_name 0.0.0.0 --server_port 7860 "$@"
EOF

    # Create example runner script
    EXAMPLE_SCRIPT="$HOME/run_trellis_example.sh"
    
    cat > "$EXAMPLE_SCRIPT" << 'EOF'
#!/bin/bash

# TRELLIS Example Runner Script

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

CONDA_DIR="$HOME/miniconda3"
TRELLIS_DIR="$HOME/TRELLIS"

# Check directories
if [ ! -d "$CONDA_DIR" ] || [ ! -d "$TRELLIS_DIR" ]; then
    echo -e "${RED}Required directories not found. Please run the installer script first.${NC}"
    exit 1
fi

# Add conda to PATH and activate environment
export PATH="$CONDA_DIR/bin:$PATH"
source "$CONDA_DIR/etc/profile.d/conda.sh"
conda activate trellis
cd "$TRELLIS_DIR"

# Set environment variables
export SPCONV_ALGO='native'
export CUDA_LAUNCH_BLOCKING=1

# Set CUDA paths if available
if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
    export CUDA_HOME="/usr/local/cuda"
fi

echo -e "${GREEN}Running TRELLIS example...${NC}"
echo

# Run example
python example.py "$@"
EOF

    # Make launcher scripts executable
    if chmod +x "$LAUNCHER_SCRIPT" "$TEXT_LAUNCHER" "$EXAMPLE_SCRIPT"; then
        log "Launcher scripts created and made executable:"
        info "  Main web demo: $LAUNCHER_SCRIPT"
        info "  Text-to-3D demo: $TEXT_LAUNCHER"
        info "  Example runner: $EXAMPLE_SCRIPT"
    else
        warn "Failed to make launcher scripts executable. You may need to run: chmod +x ~/launch_trellis*.sh ~/run_trellis_example.sh"
    fi
}

# Create systemd service (optional)
create_systemd_service() {
    log "Creating systemd service for TRELLIS..."
    
    if ! ask_yes_no "Do you want to create a systemd service to run TRELLIS automatically?" "n"; then
        return 0
    fi
    
    SERVICE_FILE="/etc/systemd/system/trellis.service"
    
    # Get absolute paths (resolve $HOME properly)
    CURRENT_USER=$(whoami)
    USER_HOME=$(eval echo ~$CURRENT_USER)
    
    info "Creating systemd service for user: $CURRENT_USER"
    info "Using home directory: $USER_HOME"
    
    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=TRELLIS 3D Generation Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
ExecStart=$USER_HOME/launch_trellis.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=trellis

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable trellis.service
    
    log "Systemd service created. You can start it with: sudo systemctl start trellis"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    # Ensure conda is in PATH and activate environment
    export PATH="$HOME/miniconda3/bin:$PATH"
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate trellis
    
    # Change to TRELLIS directory
    cd "$HOME/TRELLIS"
    
    # Set environment variables
    export SPCONV_ALGO='native'
    
    # Test Python imports
    info "Testing Python imports..."
    python3 -c "import torch; print(f'PyTorch version: {torch.__version__}')" || warn "PyTorch import failed"
    python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')" || warn "CUDA test failed"
    
    # Test TRELLIS imports
    info "Testing TRELLIS imports..."
    python3 -c "from trellis.pipelines import TrellisImageTo3DPipeline; print('TRELLIS imports successful')" || warn "TRELLIS import failed"
    
    if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
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
    log "TRELLIS Installation Complete!"
    echo "=================================="
    echo
    info "To start TRELLIS:"
    echo "  1. Web Demo (Image-to-3D): $HOME/launch_trellis.sh"
    echo "  2. Text-to-3D Demo: $HOME/launch_trellis_text.sh"
    echo "  3. Run Examples: $HOME/run_trellis_example.sh"
    echo
    info "TRELLIS will be accessible at:"
    echo "  Local access: http://localhost:7860"
    echo "  Network access: http://your-server-ip:7860"
    echo
    info "Manual activation commands:"
    echo "  export PATH=\"$HOME/miniconda3/bin:\$PATH\""
    echo "  source \"$HOME/miniconda3/etc/profile.d/conda.sh\""
    echo "  conda activate trellis"
    echo "  cd $HOME/TRELLIS"
    echo "  export SPCONV_ALGO='native'"
    echo "  python app.py"
    echo
    info "Available models (will download automatically on first use):"
    echo "  - TRELLIS-image-large (1.2B params) - Best for image-to-3D"
    echo "  - TRELLIS-text-base (342M params) - Text-to-3D"
    echo "  - TRELLIS-text-large (1.1B params) - Text-to-3D"
    echo "  - TRELLIS-text-xlarge (2.0B params) - Text-to-3D"
    echo
    info "Environment variables:"
    echo "  SPCONV_ALGO='native' - Faster for single runs"
    echo "  ATTN_BACKEND='flash-attn' - Default attention backend"
    echo "  CUDA_LAUNCH_BLOCKING=1 - Better error reporting"
    echo
    info "Output formats supported:"
    echo "  - 3D Gaussians (.ply files)"
    echo "  - Radiance Fields"
    echo "  - Meshes (.glb files)"
    echo "  - Video previews (.mp4)"
    echo
    if [ -f "/etc/systemd/system/trellis.service" ]; then
        info "Systemd service commands:"
        echo "  sudo systemctl start trellis    : Start service"
        echo "  sudo systemctl stop trellis     : Stop service"
        echo "  sudo systemctl status trellis   : Check status"
    fi
    echo
    warn "Important notes:"
    echo "  - First run may take time to download models (several GB)"
    echo "  - Recommended: At least 16GB GPU memory for optimal performance"
    echo "  - For better results, use high-quality input images"
    echo "  - Text-to-3D works better with detailed prompts"
    echo
    info "Troubleshooting:"
    echo "  - If CUDA errors occur, check NVIDIA driver installation"
    echo "  - If out of memory, reduce generation steps or use smaller models"
    echo "  - Check logs with: journalctl -u trellis -f (for systemd service)"
    echo
}

# Check CUDA toolkit installation status
check_cuda_toolkit() {
    log "Checking CUDA toolkit installation status..."
    
    # Check if CUDA toolkit packages are installed
    local cuda_packages_installed=false
    if dpkg -l | grep -q "cuda-toolkit"; then
        info "CUDA toolkit packages found:"
        dpkg -l | grep "cuda-toolkit" | head -5
        cuda_packages_installed=true
    fi
    
    # Check if nvcc is available
    local nvcc_available=false
    if command -v nvcc >/dev/null 2>&1; then
        info "nvcc is available in PATH"
        nvcc_available=true
    else
        warn "nvcc is not available in PATH"
    fi
    
    # Check common CUDA installation paths
    local cuda_paths_found=()
    for cuda_path in /usr/local/cuda-12.4 /usr/local/cuda-11.8 /usr/local/cuda-12.2 /usr/local/cuda; do
        if [ -d "$cuda_path" ] && [ -f "$cuda_path/bin/nvcc" ]; then
            cuda_paths_found+=("$cuda_path")
            info "Found CUDA installation at: $cuda_path"
        fi
    done
    
    if [ ${#cuda_paths_found[@]} -eq 0 ]; then
        warn "No CUDA installations found in common locations"
    fi
    
    # Provide recommendations
    if [ "$nvcc_available" = false ] && [ "$cuda_packages_installed" = false ]; then
        warn "CUDA toolkit appears to be missing or incomplete"
        echo
        info "To install CUDA toolkit, you can:"
        echo "  1. Run this script again and choose 'y' when asked about NVIDIA drivers"
        echo "  2. Install manually: sudo apt install cuda-toolkit-12-4"
        echo "  3. Download from NVIDIA website: https://developer.nvidia.com/cuda-downloads"
        echo
        warn "TRELLIS will continue installation, but CUDA compilation may fail."
        warn "Some packages may need to be compiled from source without CUDA support."
    elif [ "$nvcc_available" = false ] && [ "$cuda_packages_installed" = true ]; then
        warn "CUDA packages are installed but nvcc is not in PATH"
        info "This might be a PATH issue. CUDA_HOME will be set during installation."
    fi
    
    log "CUDA toolkit check completed"
}

# Install missing CUDA toolkit components
install_cuda_toolkit_components() {
    log "Installing missing CUDA toolkit components..."
    
    # Check if CUDA toolkit is already installed
    if command -v nvcc >/dev/null 2>&1; then
        info "CUDA toolkit already available"
        return 0
    fi
    
    # Check what CUDA packages are installed
    local cuda_packages=$(dpkg -l | grep cuda | grep -v "^rc" | wc -l)
    if [ "$cuda_packages" -gt 0 ]; then
        info "Found $cuda_packages CUDA packages installed"
        dpkg -l | grep cuda | grep -v "^rc" | head -5
    fi
    
    # Install CUDA toolkit if not present
    if ! dpkg -l | grep -q "cuda-toolkit"; then
        warn "CUDA toolkit not found. Installing..."
        
        # Add NVIDIA repository if not already added
        if [ ! -f "/etc/apt/sources.list.d/cuda.list" ]; then
            info "Adding NVIDIA CUDA repository..."
            curl -fSsl -O https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
            sudo dpkg -i cuda-keyring_1.1-1_all.deb
            rm -f cuda-keyring_1.1-1_all.deb
            sudo apt update
        fi
        
        # Install CUDA toolkit
        info "Installing CUDA toolkit..."
        sudo apt install -y \
            cuda-toolkit-12-4 \
            cuda-compiler-12-4 \
            cuda-libraries-dev-12-4 \
            cuda-driver-dev-12-4
        
        # Set up environment variables
        info "Setting up CUDA environment variables..."
        echo 'export PATH="/usr/local/cuda-12.4/bin:$PATH"' | sudo tee -a /etc/environment
        echo 'export CUDA_HOME="/usr/local/cuda-12.4"' | sudo tee -a /etc/environment
        echo 'export LD_LIBRARY_PATH="/usr/local/cuda-12.4/lib64:$LD_LIBRARY_PATH"' | sudo tee -a /etc/environment
        
        # Create symlink for default CUDA
        if [ ! -L "/usr/local/cuda" ]; then
            sudo ln -sf /usr/local/cuda-12.4 /usr/local/cuda
        fi
        
        log "CUDA toolkit installed successfully"
    else
        info "CUDA toolkit packages are installed"
        
        # Check if nvcc is available
        if ! command -v nvcc >/dev/null 2>&1; then
            warn "nvcc not found in PATH, checking common locations..."
            
            # Find CUDA installation
            for cuda_path in /usr/local/cuda-12.4 /usr/local/cuda-11.8 /usr/local/cuda-12.2 /usr/local/cuda; do
                if [ -f "$cuda_path/bin/nvcc" ]; then
                    info "Found nvcc at: $cuda_path/bin/nvcc"
                    # Add to PATH for current session
                    export PATH="$cuda_path/bin:$PATH"
                    export CUDA_HOME="$cuda_path"
                    export LD_LIBRARY_PATH="$cuda_path/lib64:$LD_LIBRARY_PATH"
                    
                    # Add to system environment
                    echo "export PATH=\"$cuda_path/bin:\$PATH\"" | sudo tee -a /etc/environment
                    echo "export CUDA_HOME=\"$cuda_path\"" | sudo tee -a /etc/environment
                    echo "export LD_LIBRARY_PATH=\"$cuda_path/lib64:\$LD_LIBRARY_PATH\"" | sudo tee -a /etc/environment
                    break
                fi
            done
        fi
    fi
    
    # Verify installation
    if command -v nvcc >/dev/null 2>&1; then
        NVCC_VERSION=$(nvcc --version | grep "release" | awk '{print $6}' | cut -c2-)
        log "CUDA toolkit verified: nvcc version $NVCC_VERSION"
    else
        warn "CUDA toolkit installation may be incomplete"
        warn "Some CUDA-dependent packages may fail to compile"
    fi
}

# Install additional CUDA development dependencies
install_cuda_dev_deps() {
    log "Installing additional CUDA development dependencies..."
    
    sudo apt install -y \
        gcc-12 \
        g++-12 \
        make \
        cmake \
        ninja-build \
        pkg-config \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        freeglut3-dev \
        libxrandr-dev \
        libxinerama-dev \
        libxcursor-dev \
        libxi-dev \
        libxext-dev \
        libxfixes-dev \
        libxrender-dev \
        libxss-dev \
        libxxf86vm-dev \
        libxrandr-dev \
        libasound2-dev \
        libpulse-dev \
        libdbus-1-dev \
        libudev-dev \
        libevdev-dev \
        libmtdev-dev \
        libts-dev \
        libxkbcommon-dev \
        libdrm-dev \
        libgbm-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev \
        libvulkan-dev \
        vulkan-tools \
        vulkan-validationlayers \
        libvulkan1 \
        libglvnd0 \
        libgl1 \
        libglx0 \
        libegl1 \
        libgles2 \
        libglvnd-dev \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libgles2-mesa-dev
}

# Main installation function
main() {
    echo "=================================="
    log "TRELLIS Linux Installer"
    echo "=================================="
    echo
    info "This script will install TRELLIS 3D generation model with NVIDIA GPU support on Debian 12"
    info "Installation location: $HOME/TRELLIS"
    info "Conda environment: $HOME/miniconda3/envs/trellis"
    echo
    info "TRELLIS is Microsoft's large-scale 3D asset generation model that supports:"
    echo "  - High-quality image-to-3D generation"
    echo "  - Text-to-3D generation"
    echo "  - Multiple output formats (Gaussians, Radiance Fields, Meshes)"
    echo "  - GLB/PLY/MP4 export capabilities"
    echo "  - Web-based user interface"
    echo
    warn "System requirements:"
    echo "  - Debian 12 Linux system"
    echo "  - NVIDIA GPU with 16GB+ VRAM (recommended)"
    echo "  - 50GB+ free disk space"
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
    install_cuda_toolkit_components
    install_cuda_dev_deps
    install_conda
    create_conda_env
    clone_trellis
    check_cuda_toolkit
    install_pytorch_cuda
    install_trellis_deps
    retry_cuda_dependent_installations
    create_launcher
    create_systemd_service
    test_installation
    print_instructions
}

# Run main function
main "$@" 
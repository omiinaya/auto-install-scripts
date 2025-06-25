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
    
    # Ensure conda is properly initialized
    if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
        source "$HOME/miniconda/etc/profile.d/conda.sh"
    fi
    
    # Initialize conda for the current shell and fix any syntax errors
    if command -v conda >/dev/null 2>&1; then
        conda init bash
        # Fix bashrc syntax errors if they exist
        if ! bash -n ~/.bashrc 2>/dev/null; then
            warn "Syntax error detected in ~/.bashrc, fixing now..."
            # Create a backup
            cp ~/.bashrc ~/.bashrc.backup.$(date +%s)
            # Fix common syntax issues caused by conda init conflicts
            # Remove duplicate or malformed conda initialization blocks
            awk '
            /# >>> conda initialize >>>/ { in_conda=1; print; next }
            /# <<< conda initialize <<</ { in_conda=0; print; next }
            in_conda && seen_conda { next }
            in_conda { seen_conda=1 }
            !in_conda { print }
            ' ~/.bashrc > ~/.bashrc.tmp && mv ~/.bashrc.tmp ~/.bashrc
            
            # Test the fix
            if bash -n ~/.bashrc 2>/dev/null; then
                log "Fixed ~/.bashrc syntax errors"
            else
                # If still broken, restore from backup and create minimal working version
                warn "Complex syntax errors detected, creating clean ~/.bashrc"
                cp ~/.bashrc.backup.$(date +%s | tail -1) ~/.bashrc.broken
                cat > ~/.bashrc << 'EOF'
# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH
EOF
                # Re-run conda init on the clean bashrc
                conda init bash
                log "Created clean ~/.bashrc and re-initialized conda"
            fi
        fi
        # Now source the fixed bashrc
        source ~/.bashrc || warn "Failed to source ~/.bashrc after fixing"
    fi
    
    # Create conda env with Python 3.10 if not already present
    if ! conda env list | grep -q "trellis"; then
        log "Creating trellis conda environment..."
        conda create -y -n trellis python=3.10
    fi
    
    # Use source instead of bash -c to run setup in the current shell context
    log "Activating trellis environment and running setup..."
    source "$HOME/miniconda/etc/profile.d/conda.sh"
    conda activate trellis
    
    # Run setup with error handling - use bash instead of source to avoid return statement issues
    if [ -f "./setup.sh" ]; then
        log "Running TRELLIS setup script..."
        bash ./setup.sh --new-env --basic --xformers --flash-attn --diffoctreerast --spconv --mipgaussian --kaolin --nvdiffrast || {
            warn "Setup script encountered some issues, but continuing..."
        }
    else
        error "setup.sh not found in TRELLIS directory"
    fi

    # Always activate trellis environment before pip/python commands
    if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
        source "$HOME/miniconda/etc/profile.d/conda.sh"
    fi
    conda activate trellis

    # Check if torch is importable
    if ! python -c "import torch" 2>/dev/null; then
        log "PyTorch not found, installing torch, torchvision, torchaudio..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || warn "Manual PyTorch installation failed"
        # After installing torch, re-run the optional dependency setup
        log "Re-running setup.sh for optional dependencies after torch install..."
        bash ./setup.sh --xformers --flash-attn --kaolin --nvdiffrast --diffoctreerast --mipgaussian --vox2seq --spconv || warn "Optional dependency setup failed"
    fi
    # Print torch version for verification
    python -c "import torch; print('PyTorch version:', torch.__version__)" || warn "PyTorch is still not importable after install!"
    
    log "TRELLIS setup complete. Activate the environment with: conda activate trellis"
}

# Fix post-installation issues
fix_post_install() {
    log "Fixing common post-installation issues..."
    
    # Create a separate conda activation script for convenience
    cat > "$HOME/.conda_trellis_init" << 'EOF'
#!/bin/bash
# TRELLIS conda initialization script
if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
    source "$HOME/miniconda/etc/profile.d/conda.sh"
    # Uncomment the next line to auto-activate trellis environment
    # conda activate trellis
fi
EOF
    
    # Add source command to bashrc if not already present
    if [ -f "$HOME/.bashrc" ] && ! grep -q ".conda_trellis_init" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Source TRELLIS conda initialization" >> "$HOME/.bashrc"
        echo "[ -f ~/.conda_trellis_init ] && source ~/.conda_trellis_init" >> "$HOME/.bashrc"
        log "Added TRELLIS conda initialization to ~/.bashrc"
    fi
}

# Print final instructions
print_instructions() {
    echo
    echo "=================================="
    log "TRELLIS Installation Complete!"
    echo "=================================="
    echo
    info "IMPORTANT: Please restart your shell or run:"
    echo "  source ~/.bashrc"
    echo
    info "Then activate the TRELLIS environment with:"
    echo "  conda activate trellis"
    echo
    info "If you encounter 'conda: command not found', run:"
    echo "  source ~/miniconda/etc/profile.d/conda.sh"
    echo "  conda init bash"
    echo "  source ~/.bashrc"
    echo
    info "To test the installation:"
    echo "  cd ~/TRELLIS"
    echo "  conda activate trellis"
    echo "  python -c \"import torch; print('PyTorch version:', torch.__version__)\""
    echo
    info "To run TRELLIS demos or training, see the official repo:"
    echo "  https://github.com/microsoft/TRELLIS"
    echo
    info "For additional setup options, run:"
    echo "  cd ~/TRELLIS && source ./setup.sh --help"
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
    fix_post_install
    print_instructions
}

main "$@"
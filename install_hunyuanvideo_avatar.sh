#!/bin/bash
set -e

# --- Configuration ---
# Set the installation directory for HunyuanVideo-Avatar
INSTALL_DIR="$HOME/HunyuanVideo-Avatar"
# Get the absolute path of the modules directory from the current script's location
MODULES_DIR="$(dirname "$(realpath "$0")")/modules"

echo "HunyuanVideo-Avatar will be installed in: $INSTALL_DIR"
echo "Modules will be used from: $MODULES_DIR"

# --- Installation ---

# Ensure git is installed
sudo apt-get update
sudo apt-get install -y git sudo wget

# 1. Clone HunyuanVideo-Avatar repository into the target directory
echo "Cloning HunyuanVideo-Avatar repository..."
if [ ! -d "$INSTALL_DIR" ]; then
  git clone https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# 2. Install Python (using repo module)
echo "Installing Python 3.10 using pyenv..."
bash "$MODULES_DIR/install_python.sh" 3.10

# 3. Install NVIDIA drivers (using repo module)
echo "Installing NVIDIA drivers..."
bash "$MODULES_DIR/install_nvidia_drivers.sh"

# 4. Install CUDA (using repo module)
echo "Installing CUDA 12.4..."
bash "$MODULES_DIR/install_cuda_nvcc.sh" 12.4

# Helper function to initialize conda properly
initialize_conda() {
    # Set conda paths
    CONDA_BASE="$HOME/miniconda3"
    
    # Add conda to PATH if not already there
    if [[ ":$PATH:" != *":$CONDA_BASE/bin:"* ]]; then
        export PATH="$CONDA_BASE/bin:$PATH"
    fi
    
    # Initialize conda for bash with fallback
    if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
        source "$CONDA_BASE/etc/profile.d/conda.sh"
    else
        eval "$($CONDA_BASE/bin/conda shell.bash hook)"
    fi
}

# 5. Install Miniconda if not present
if ! command -v conda &> /dev/null; then
    echo "Installing Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda3
    rm miniconda.sh
    
    # Initialize conda
    initialize_conda
    conda init bash
    
    # Reload bash profile
    source ~/.bashrc || true
else
    echo "Conda already installed"
    initialize_conda
fi

# 6. Create conda environment
echo "Creating conda environment 'HunyuanVideo-Avatar'..."
conda create -n HunyuanVideo-Avatar python=3.10.9 -y

# 7. Activate environment and install dependencies in a subshell for robustness
echo "Activating environment and installing dependencies..."
(
    source "$HOME/miniconda3/etc/profile.d/conda.sh"
    conda activate HunyuanVideo-Avatar

    # Install PyTorch with CUDA 12.4 support
    echo "Installing PyTorch..."
    conda install pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=12.4 -c pytorch -c nvidia -y

    # 8. Install pip dependencies
    echo "Installing pip dependencies from requirements.txt..."
    python -m pip install -r requirements.txt

    # 9. Install flash attention v2 for acceleration
    echo "Installing flash attention v2..."
    python -m pip install ninja
    python -m pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3
)

echo "HunyuanVideo-Avatar installation completed successfully in $INSTALL_DIR!"
echo "To use the environment, run:"
echo "cd $INSTALL_DIR"
echo "source ~/.bashrc"
echo "conda activate HunyuanVideo-Avatar"
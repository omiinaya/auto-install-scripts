#!/bin/bash
set -e

# Ensure git is installed
apt-get update
apt-get install -y git sudo wget

# 1. Clone HunyuanVideo-Avatar repository
if [ ! -d "HunyuanVideo-Avatar" ]; then
  git clone https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar.git
fi
cd HunyuanVideo-Avatar

# 2. Install Python (using repo module)
cd ../modules
bash install_python.sh 3.10
cd ../HunyuanVideo-Avatar

# 3. Install NVIDIA drivers (using repo module)
cd ../modules
bash install_nvidia_drivers.sh
cd ../HunyuanVideo-Avatar

# 4. Install CUDA (using repo module)
cd ../modules
bash install_cuda_nvcc.sh 12.4
cd ../HunyuanVideo-Avatar

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
echo "Creating conda environment..."
conda create -n HunyuanVideo-Avatar python=3.10.9 -y

# 7. Activate environment and install dependencies
echo "Activating environment and installing PyTorch with CUDA 12.4..."
conda activate HunyuanVideo-Avatar

# Install PyTorch with CUDA 12.4 support
conda install pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=12.4 -c pytorch -c nvidia -y

# 8. Install pip dependencies
echo "Installing pip dependencies..."
python -m pip install -r requirements.txt

# 9. Install flash attention v2 for acceleration
echo "Installing flash attention v2..."
python -m pip install ninja
python -m pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3

echo "HunyuanVideo-Avatar installation completed successfully!"
echo "To use the environment, run: conda activate HunyuanVideo-Avatar"

# On the Linux system where you ran the installation:
source ~/.bashrc
# OR
export PATH="$HOME/miniconda3/bin:$PATH"
source "$HOME/miniconda3/etc/profile.d/conda.sh"

# Then try:
conda activate HunyuanVideo-Avatar 
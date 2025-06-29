#!/bin/bash
set -e

# Ensure git is installed
sudo apt-get update
sudo apt-get install -y git sudo wget

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
bash install_cuda_nvcc.sh 11.8
cd ../HunyuanVideo-Avatar

# Helper function to initialize conda properly
initialize_conda() {
    # Set conda paths
    CONDA_BASE="$HOME/miniconda3"
    
    # Add conda to PATH if not already there
    if [[ ":$PATH:" != *":$CONDA_BASE/bin:"* ]]; then
        export PATH="$CONDA_BASE/bin:$PATH"
    fi
    
    # Initialize conda for bash
    if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
        source "$CONDA_BASE/etc/profile.d/conda.sh"
    else
        echo "Warning: conda.sh not found, using fallback initialization"
        eval "$($CONDA_BASE/bin/conda shell.bash hook)"
    fi
}

# 5. Install Miniconda if not present
if ! command -v conda >/dev/null 2>&1; then
    echo "Installing Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda3
    rm miniconda.sh
    
    # Initialize conda immediately after installation
    initialize_conda
    
    # Initialize conda for future shell sessions
    $HOME/miniconda3/bin/conda init bash
    
    echo "Miniconda installed and initialized"
else
    echo "Conda already installed"
    # Still initialize conda for this session
    initialize_conda
fi

# 6. Create and activate conda environment
CONDA_ENV=HunyuanVideo-Avatar

# Ensure conda is properly initialized before creating environment
initialize_conda

# Check if environment already exists
if conda env list | grep -q "^$CONDA_ENV "; then
    echo "Conda environment '$CONDA_ENV' already exists"
else
    echo "Creating conda environment '$CONDA_ENV'..."
    conda create -y -n $CONDA_ENV python=3.10.9
fi

# Activate the environment
echo "Activating conda environment '$CONDA_ENV'..."
conda activate $CONDA_ENV

# Verify we're in the correct environment
echo "Current conda environment: $(conda info --envs | grep '*' | awk '{print $1}')"

# 7. Install PyTorch and dependencies (CUDA 11.8 by default)
echo "Installing PyTorch with CUDA 11.8 support..."
conda install -y pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=11.8 -c pytorch -c nvidia

# 8. Install pip requirements
echo "Upgrading pip and installing requirements..."
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

# 9. Install flash-attention v2 and ninja
echo "Installing flash-attention v2 and ninja..."
python -m pip install ninja
python -m pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3

# 10. Install huggingface-cli for model downloads
echo "Installing huggingface-hub CLI..."
python -m pip install "huggingface_hub[cli]"

# 11. Download model weights
echo "Downloading HunyuanVideo-Avatar model weights..."
cd weights
huggingface-cli download tencent/HunyuanVideo-Avatar --local-dir ./
cd ..

# 12. Create optimized launcher script
echo "Creating launcher script..."
cat > launch_hunyuanvideo_avatar.sh << 'EOF'
#!/bin/bash

# HunyuanVideo-Avatar Optimized Launcher
# This script sets up memory optimization and launches the application

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}Starting HunyuanVideo-Avatar...${NC}"

# Helper function to initialize conda properly
initialize_conda() {
    CONDA_BASE="$HOME/miniconda3"
    
    # Add conda to PATH if not already there
    if [[ ":$PATH:" != *":$CONDA_BASE/bin:"* ]]; then
        export PATH="$CONDA_BASE/bin:$PATH"
    fi
    
    # Initialize conda for bash
    if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
        source "$CONDA_BASE/etc/profile.d/conda.sh"
    else
        echo -e "${RED}Warning: conda.sh not found, using fallback initialization${NC}"
        eval "$($CONDA_BASE/bin/conda shell.bash hook)"
    fi
}

# Initialize and activate conda environment
initialize_conda

if ! conda env list | grep -q "HunyuanVideo-Avatar"; then
    echo -e "${RED}Error: HunyuanVideo-Avatar conda environment not found!${NC}"
    echo "Please run the installation script first."
    exit 1
fi

echo -e "${BLUE}Activating conda environment...${NC}"
conda activate HunyuanVideo-Avatar

# Verify we're in the correct environment
CURRENT_ENV=$(conda info --envs | grep '*' | awk '{print $1}')
if [ "$CURRENT_ENV" != "HunyuanVideo-Avatar" ]; then
    echo -e "${RED}Error: Failed to activate HunyuanVideo-Avatar environment${NC}"
    echo "Current environment: $CURRENT_ENV"
    exit 1
fi

echo -e "${GREEN}Successfully activated environment: $CURRENT_ENV${NC}"

# Set memory optimization environment variables
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export CUDA_VISIBLE_DEVICES=0

# Kill any existing Python processes to free GPU memory
echo -e "${BLUE}Clearing GPU memory...${NC}"
sudo pkill -f python || true
sleep 2

# Navigate to project directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${GREEN}Starting HunyuanVideo-Avatar...${NC}"
echo -e "${GREEN}Access the interface at: http://localhost:8080${NC}"
echo -e "${BLUE}Press Ctrl+C to stop${NC}"
echo

# Launch the Gradio server
if [ -f "./scripts/run_gradio.sh" ]; then
    bash ./scripts/run_gradio.sh
else
    echo -e "${RED}Error: run_gradio.sh not found in ./scripts/${NC}"
    echo "Please ensure you're running this from the HunyuanVideo-Avatar directory"
    exit 1
fi
EOF

# Make launcher executable
chmod +x launch_hunyuanvideo_avatar.sh

# 13. Print completion message
echo
echo "=================================================="
echo "Installation complete!"
echo
echo "To run HunyuanVideo-Avatar:"
echo "   cd $(pwd)"
echo "   bash ./launch_hunyuanvideo_avatar.sh"
echo
echo "The launcher will:"
echo "- Initialize and activate the conda environment"
echo "- Clear GPU memory automatically"
echo "- Set memory optimization flags"
echo "- Start the Gradio interface on http://localhost:8080"
echo
echo "For more usage, see: https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar"
echo "=================================================="
echo 
#!/bin/bash
set -e

# Ensure git is installed
sudo apt-get update
sudo apt-get install -y git sudo

# 1. Clone HunyuanVideo-Avatar repository
if [ ! -d "HunyuanVideo-Avatar" ]; then
  git clone https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar.git
fi
cd HunyuanVideo-Avatar

# 2. Install Python (using repo module)
cd ../modules
bash install_python.sh
cd ../HunyuanVideo-Avatar

# 3. Install NVIDIA drivers (using repo module)
cd ../modules
bash install_nvidia_drivers.sh
cd ../HunyuanVideo-Avatar

# 4. Install CUDA (using repo module)
cd ../modules
bash install_cuda_nvcc.sh
cd ../HunyuanVideo-Avatar

# 5. Install Miniconda if not present
if ! command -v conda >/dev/null 2>&1; then
    echo "Installing Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda3
    rm miniconda.sh
    export PATH="$HOME/miniconda3/bin:$PATH"
    eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
    conda init bash
    source ~/.bashrc
else
    echo "Conda already installed"
fi

# 6. Create and activate conda environment
CONDA_ENV=HunyuanVideo-Avatar
conda create -y -n $CONDA_ENV python=3.10.9
source $(conda info --base)/etc/profile.d/conda.sh
conda activate $CONDA_ENV

# 7. Install PyTorch and dependencies (CUDA 11.8 by default)
conda install -y pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=11.8 -c pytorch -c nvidia

# 8. Install pip requirements
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

# 9. Install flash-attention v2 and ninja
python -m pip install ninja
python -m pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3

# 10. Install huggingface-cli for model downloads
python -m pip install "huggingface_hub[cli]"

# 11. Download model weights
echo "Downloading HunyuanVideo-Avatar model weights..."
cd weights
huggingface-cli download tencent/HunyuanVideo-Avatar --local-dir ./
cd ..

# 12. Create optimized launcher script
cat > launch_hunyuanvideo_avatar.sh << 'EOF'
#!/bin/bash

# HunyuanVideo-Avatar Optimized Launcher
# This script sets up memory optimization and launches the application

# Activate conda environment
source ~/miniconda3/etc/profile.d/conda.sh
conda activate HunyuanVideo-Avatar

# Set memory optimization environment variables
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export CUDA_VISIBLE_DEVICES=0

# Kill any existing Python processes to free GPU memory
echo "Clearing GPU memory..."
sudo pkill -f python || true
sleep 2

# Navigate to project directory
cd ~/auto-install-scripts/HunyuanVideo-Avatar

echo "Starting HunyuanVideo-Avatar..."
echo "Access the interface at: http://localhost:8080"
echo "Press Ctrl+C to stop"

# Launch the Gradio server
bash ./scripts/run_gradio.sh
EOF

# Make launcher executable
chmod +x launch_hunyuanvideo_avatar.sh

# 13. Print completion message
echo "\n=================================================="
echo "Installation complete!"
echo "\nTo run HunyuanVideo-Avatar:"
echo "   bash ~/auto-install-scripts/HunyuanVideo-Avatar/launch_hunyuanvideo_avatar.sh"
echo "\nThe launcher will:"
echo "- Clear GPU memory automatically"
echo "- Set memory optimization flags"
echo "- Start the Gradio interface on http://localhost:8080"
echo "\nFor more usage, see: https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar"
echo "==================================================\n" 
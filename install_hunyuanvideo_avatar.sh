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

# 5. Create and activate conda environment
CONDA_ENV=HunyuanVideo-Avatar
conda create -y -n $CONDA_ENV python=3.10.9
source $(conda info --base)/etc/profile.d/conda.sh
conda activate $CONDA_ENV

# 6. Install PyTorch and dependencies (CUDA 11.8 by default)
conda install -y pytorch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 pytorch-cuda=11.8 -c pytorch -c nvidia

# 7. Install pip requirements
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

# 8. Install flash-attention v2 and ninja
python -m pip install ninja
python -m pip install git+https://github.com/Dao-AILab/flash-attention.git@v2.6.3

# 9. Print instructions for model weights and running the app
echo "\n=================================================="
echo "Installation complete!"
echo "\nNext steps:"
echo "1. Download the pretrained model weights as described in the HunyuanVideo-Avatar README."
echo "2. To run the Gradio server:"
echo "   cd HunyuanVideo-Avatar"
echo "   bash ./scripts/run_gradio.sh"
echo "\nFor more usage, see: https://github.com/Tencent-Hunyuan/HunyuanVideo-Avatar"
echo "==================================================\n" 
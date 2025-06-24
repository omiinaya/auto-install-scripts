#!/bin/bash

# Quick fix for flash-attention version conflict
# Run this to fix the current FramePack installation

echo "Fixing flash-attention version conflict..."

# Activate the FramePack environment
source "$HOME/framepack-env/bin/activate"

# Set up CUDA environment
export CUDA_HOME="/usr/local/cuda-12.9"
export PATH="/usr/local/cuda-12.9/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda-12.9/lib64:$LD_LIBRARY_PATH"

echo "Uninstalling incompatible flash-attention 2.8.0.post2..."
pip uninstall -y flash-attn

echo "Installing compatible flash-attention version (2.7.1-2.7.4)..."
CUDA_HOME="/usr/local/cuda-12.9" pip install "flash-attn>=2.7.1,<=2.7.4" --no-build-isolation

echo "Flash-attention version fix complete!"
echo "You can now run FramePack:"
echo "  $HOME/launch_framepack.sh" 
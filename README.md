# AI Model Installation Scripts for Debian 12 (Proxmox Container)

This repository contains comprehensive installation scripts for popular AI models with NVIDIA GPU support, specifically designed for Debian 12 systems running in Proxmox containers.

## Available Installation Scripts

### 1. ComfyUI Installer (`install_comfyui.sh`)
- **Purpose**: Node-based UI for Stable Diffusion workflows
- **Features**: Advanced workflow creation, custom nodes, ComfyUI-Manager
- **Best for**: Power users who want fine-grained control over image generation

### 2. TRELLIS Installer (`install_trellis.sh`)
- **Purpose**: Microsoft's 3D asset generation model
- **Features**: Image-to-3D, Text-to-3D, multiple output formats (Gaussians, Meshes, GLB)
- **Best for**: 3D content creation and asset generation

### 3. Stable Diffusion WebUI Installer (`install_sd_webui.sh`)
- **Purpose**: AUTOMATIC1111's web interface for Stable Diffusion
- **Features**: Text-to-image, image-to-image, inpainting, extensions, LoRA support
- **Best for**: Traditional Stable Diffusion workflows with web interface

## Features

All scripts provide:
- **Complete dependency installation** for fresh Debian 12 systems
- **NVIDIA GPU support** with proper CUDA drivers for Proxmox containers
- **Conda environment management** for isolated installations
- **Automatic model installation** using official methods
- **PyTorch with CUDA support** for GPU acceleration
- **Launcher scripts** for easy startup
- **Optional systemd services** for automatic startup
- **Installation testing** to verify everything works
- **Robust error handling** and user-friendly prompts

## Prerequisites

- Debian 12 system (tested on Proxmox containers)
- NVIDIA GPU passed through to the container
- User account with sudo privileges
- Internet connection for downloading packages
- Sufficient disk space (20-50GB depending on model)

## Quick Installation

### ComfyUI
```bash
wget https://raw.githubusercontent.com/your-repo/install-scripts/main/install_comfyui.sh
chmod +x install_comfyui.sh
./install_comfyui.sh
```

### TRELLIS
```bash
wget https://raw.githubusercontent.com/your-repo/install-scripts/main/install_trellis.sh
chmod +x install_trellis.sh
./install_trellis.sh
```

### Stable Diffusion WebUI
```bash
wget https://raw.githubusercontent.com/your-repo/install-scripts/main/install_sd_webui.sh
chmod +x install_sd_webui.sh
./install_sd_webui.sh
```

## What Gets Installed

### System Packages (All Scripts)
- Python 3.10/3.11 with pip, venv, and development tools
- Git, curl, wget, build-essential, cmake, ninja-build
- NVIDIA CUDA drivers and kernel modules
- Graphics libraries (OpenCV, FFmpeg, etc.)
- Additional utilities (vim, htop, screen, tmux)

### Python Packages (Conda Environment)
- PyTorch with CUDA support
- Model-specific packages and dependencies
- Common ML libraries (numpy, opencv-python, pillow, etc.)

### Installation Locations
- **ComfyUI**: `~/comfy/` with virtual environment `~/comfy-env/`
- **TRELLIS**: `~/TRELLIS/` with conda environment `~/miniconda3/envs/trellis`
- **Stable Diffusion WebUI**: `~/stable-diffusion-webui/` with conda environment `~/miniconda3/envs/sdwebui`

## Usage

### ComfyUI
```bash
# Start ComfyUI
~/launch_comfyui.sh

# Access at: http://localhost:8188
```

### TRELLIS
```bash
# Start TRELLIS web demo
~/launch_trellis.sh

# Start text-to-3D demo
~/launch_trellis_text.sh

# Access at: http://localhost:7860
```

### Stable Diffusion WebUI
```bash
# Start with basic options
~/launch_sdwebui.sh

# Start with custom options
~/launch_sdwebui_options.sh --medvram --api

# Access at: http://localhost:7860
```

## Model Recommendations

### ComfyUI Models
- **Stable Diffusion 1.5**: https://huggingface.co/runwayml/stable-diffusion-v1-5
- **Stable Diffusion XL**: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0
- **SDXL Turbo**: https://huggingface.co/stabilityai/sdxl-turbo

### TRELLIS Models
- **TRELLIS-image-large**: 1.2B parameters for image-to-3D
- **TRELLIS-text-base**: 342M parameters for text-to-3D
- **TRELLIS-text-large**: 1.1B parameters for text-to-3D

### Stable Diffusion WebUI Models
- **Stable Diffusion 1.5**: https://huggingface.co/runwayml/stable-diffusion-v1-5
- **Stable Diffusion 2.1**: https://huggingface.co/stabilityai/stable-diffusion-2-1
- **Stable Diffusion XL**: https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0

## System Requirements

### Minimum Requirements
- **GPU**: NVIDIA GPU with 4GB+ VRAM
- **RAM**: 8GB+ system RAM
- **Storage**: 20GB+ free space
- **OS**: Debian 12 (Proxmox container recommended)

### Recommended Requirements
- **GPU**: NVIDIA GPU with 8GB+ VRAM (16GB+ for TRELLIS)
- **RAM**: 16GB+ system RAM
- **Storage**: 50GB+ free space
- **OS**: Debian 12 with GPU passthrough

## Troubleshooting

### Common Issues

#### GPU Not Detected
```bash
# Check GPU passthrough
nvidia-smi

# Test CUDA in Python
python -c "import torch; print(torch.cuda.is_available())"
```

#### Port Conflicts
- **ComfyUI**: Default port 8188, change with `--port 8080`
- **TRELLIS**: Default port 7860, change in launcher script
- **Stable Diffusion WebUI**: Default port 7860, change with `--port 8080`

#### Memory Issues
- **ComfyUI**: Use `--lowvram` flag
- **TRELLIS**: Reduce generation steps or use smaller models
- **Stable Diffusion WebUI**: Use `--medvram` or `--lowvram` flags

#### Permission Issues
Ensure your user has sudo privileges and can write to the home directory.

### Getting Help

1. **Check the logs**: Each script provides detailed logging
2. **Test installation**: All scripts include installation testing
3. **Verify CUDA**: Ensure NVIDIA drivers are properly installed
4. **Check disk space**: Ensure sufficient free space for models

## Updating

### ComfyUI
```bash
source ~/comfy-env/bin/activate
cd ~/comfy
comfy update
```

### TRELLIS
```bash
cd ~/TRELLIS
git pull origin main
```

### Stable Diffusion WebUI
```bash
cd ~/stable-diffusion-webui
git pull origin master
```

## Uninstalling

### ComfyUI
```bash
rm -rf ~/comfy ~/comfy-env ~/launch_comfyui.sh
```

### TRELLIS
```bash
rm -rf ~/TRELLIS ~/miniconda3/envs/trellis ~/launch_trellis*.sh ~/run_trellis_example.sh
```

### Stable Diffusion WebUI
```bash
rm -rf ~/stable-diffusion-webui ~/miniconda3/envs/sdwebui ~/launch_sdwebui*.sh
```

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve these installation scripts.

## License

These scripts are provided as-is for educational and personal use. Please respect the licenses of the individual AI models and tools being installed. 
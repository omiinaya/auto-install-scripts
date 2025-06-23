# ComfyUI Linux Installer for Debian 12 (Proxmox Container)

This script provides a comprehensive installation of ComfyUI with NVIDIA GPU support specifically designed for Debian 12 systems running in Proxmox containers.

## Features

- **Complete dependency installation** for fresh Debian 12 systems
- **NVIDIA GPU support** with proper CUDA drivers for Proxmox containers
- **Virtual environment setup** to isolate ComfyUI installation
- **Automatic ComfyUI installation** using the official comfy-cli tool
- **PyTorch with CUDA support** for GPU acceleration
- **Launcher script** for easy ComfyUI startup
- **Optional systemd service** for automatic startup
- **Installation testing** to verify everything works

## Prerequisites

- Debian 12 system (tested on Proxmox containers)
- NVIDIA GPU passed through to the container
- User account with sudo privileges
- Internet connection for downloading packages

## Installation

1. **Download the installer script:**
   ```bash
   wget https://your-server.com/install_comfyui.sh
   # or
   curl -O https://your-server.com/install_comfyui.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x install_comfyui.sh
   ```

3. **Run the installer:**
   ```bash
   ./install_comfyui.sh
   ```

The script will:
- Update your system packages
- Install all necessary dependencies (Python, Git, build tools, etc.)
- Install NVIDIA drivers and CUDA support
- Create a Python virtual environment
- Install ComfyUI using comfy-cli
- Install PyTorch with CUDA support
- Create a launcher script
- Optionally create a systemd service
- Test the installation

## What Gets Installed

### System Packages
- Python 3.11+ with pip, venv, and development tools
- Git, curl, wget, build-essential
- NVIDIA CUDA drivers and kernel modules
- Additional utilities (vim, htop, screen, tmux)

### Python Packages (in virtual environment)
- comfy-cli (official ComfyUI management tool)
- PyTorch with CUDA 12.4 support
- ComfyUI and ComfyUI-Manager
- Common dependencies (numpy, opencv-python, pillow, etc.)

### Installation Locations
- **ComfyUI**: `~/comfy/`
- **Virtual Environment**: `~/comfy-env/`
- **Launcher Script**: `~/launch_comfyui.sh`
- **Systemd Service**: `/etc/systemd/system/comfyui.service` (optional)

## Usage

### Starting ComfyUI

**Option 1: Using the launcher script (recommended)**
```bash
~/launch_comfyui.sh
```

**Option 2: Manual launch**
```bash
source ~/comfy-env/bin/activate
cd ~/comfy
comfy launch
```

**Option 3: Using systemd service (if installed)**
```bash
sudo systemctl start comfyui
```

### Accessing ComfyUI
- **Local access**: http://localhost:8188
- **Network access**: http://your-server-ip:8188 (enabled by default)

### Common Launch Options

```bash
# Use different port
~/launch_comfyui.sh -- --port 8080

# Low VRAM mode (for GPUs with limited memory)
~/launch_comfyui.sh -- --lowvram

# CPU-only mode (if GPU issues)
~/launch_comfyui.sh -- --cpu

# Restrict to local access only (disable network access)
~/launch_comfyui.sh -- --listen 127.0.0.1

# Background mode
source ~/comfy-env/bin/activate
comfy launch --background
```

### Managing Models

```bash
# Activate virtual environment first
source ~/comfy-env/bin/activate

# Download a model
comfy model download --url https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned.safetensors --relative-path models/checkpoints

# List installed models
ls ~/comfy/models/checkpoints/
```

### Systemd Service Management (if installed)

```bash
# Start ComfyUI service
sudo systemctl start comfyui

# Stop ComfyUI service
sudo systemctl stop comfyui

# Check service status
sudo systemctl status comfyui

# View service logs
sudo journalctl -u comfyui -f
```

## Troubleshooting

### GPU Not Detected
If CUDA is not working:
1. Verify GPU passthrough in Proxmox
2. Check NVIDIA driver installation:
   ```bash
   nvidia-smi
   ```
3. Test CUDA in Python:
   ```bash
   source ~/comfy-env/bin/activate
   python3 -c "import torch; print(torch.cuda.is_available())"
   ```

### Port Already in Use
If port 8188 is busy:
```bash
~/launch_comfyui.sh -- --port 8080
```

### Memory Issues
For low VRAM GPUs:
```bash
~/launch_comfyui.sh -- --lowvram
```

### Permission Issues
Ensure your user has sudo privileges and can write to the home directory.

### Network Access Issues
Network access is enabled by default. To disable it and restrict to local access only:
```bash
~/launch_comfyui.sh -- --listen 127.0.0.1
```

## Updating ComfyUI

```bash
source ~/comfy-env/bin/activate
cd ~/comfy
comfy update
```

## Uninstalling

To remove ComfyUI:
```bash
# Remove directories
rm -rf ~/comfy ~/comfy-env

# Remove launcher script
rm ~/launch_comfyui.sh

# Remove systemd service (if installed)
sudo systemctl stop comfyui
sudo systemctl disable comfyui
sudo rm /etc/systemd/system/comfyui.service
sudo systemctl daemon-reload
```

## Support

For issues specific to this installer script, check:
1. That you're running on Debian 12
2. That your user has sudo privileges
3. That the NVIDIA GPU is properly passed through in Proxmox
4. That you have sufficient disk space (at least 10GB recommended)

For ComfyUI-specific issues, refer to the [official ComfyUI documentation](https://github.com/comfyanonymous/ComfyUI).

## Script Details

The installer performs these steps in order:
1. System package updates
2. Basic dependency installation
3. Python and development tools setup
4. NVIDIA driver installation (Proxmox-specific)
5. Virtual environment creation
6. Comfy-CLI installation
7. ComfyUI installation
8. PyTorch with CUDA installation
9. Additional Python packages
10. Launcher script creation
11. Optional systemd service setup
12. Installation verification

The entire process typically takes 10-30 minutes depending on your system and internet connection. 
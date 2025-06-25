# AI Installation Scripts

A collection of modular installation scripts for AI/ML applications, designed specifically for Debian 12 (Proxmox Containers). These scripts automate the setup of various AI tools with NVIDIA GPU support.

## Features

- **Modular Design**: Common dependencies (Python, NVIDIA, CUDA) are separated into reusable modules
- **Interactive Installation**: User-friendly prompts and colored output for better UX
- **Comprehensive Setup**: Handles all aspects from system updates to application launch
- **Container-Optimized**: Specifically designed for Debian 12 Proxmox containers
- **Systemd Integration**: Optional systemd service creation for automatic startup
- **Testing & Verification**: Built-in installation testing and environment verification

## Supported Applications

### ComfyUI
- Web UI for Stable Diffusion with a node-based interface
- Includes comfy-cli for command-line operations
- Automatic model management and download support
- Configurable for different VRAM usage modes

### FramePack
- Next-frame prediction model for video generation
- Supports up to 120 seconds of video generation
- Includes both standard and F1 models
- Optimized for 6GB+ VRAM GPUs

## Module Structure

```
install-scripts/
├── install_comfyui.sh      # ComfyUI installation script
├── install_framepack.sh    # FramePack installation script
└── modules/
    ├── install_python.sh       # Python environment setup
    ├── install_nvidia_drivers.sh   # NVIDIA driver installation
    └── install_cuda_nvcc.sh    # CUDA toolkit and compiler setup
```

## Installation

1. Clone the repository:
```bash
git clone https://github.com/omiinaya/install-scripts.git
cd install-scripts
```

2. Make scripts executable:
```bash
chmod +x *.sh modules/*.sh
```

3. Run the desired installation script:
```bash
# For ComfyUI
./install_comfyui.sh

# For FramePack
./install_framepack.sh
```

## Environment Variables

The scripts support customization through environment variables:

- `PYTHON_INSTALLER_URL`: Custom URL for Python installer module
- `NVIDIA_INSTALLER_URL`: Custom URL for NVIDIA driver installer module
- `CUDA_INSTALLER_URL`: Custom URL for CUDA toolkit installer module

## Common Operations

### ComfyUI

Start the service:
```bash
# Using launcher script
~/launch_comfyui.sh

# Using systemd (if enabled)
sudo systemctl start comfyui
```

Access the UI:
- Local: http://localhost:8188
- Network: http://your-server-ip:8188

### FramePack

Start the service:
```bash
# Standard model
~/launch_framepack.sh

# F1 model (more dynamic movements)
~/launch_framepack_f1.sh

# Using systemd (if enabled)
sudo systemctl start framepack
```

Access the UI:
- Local: http://localhost:7860
- Network: http://your-server-ip:7860

## Features

### Automated Setup
- System package updates
- Basic dependency installation
- Python environment configuration
- NVIDIA driver installation
- CUDA toolkit setup
- Virtual environment creation
- Application-specific dependencies
- Launcher script generation
- Optional systemd service creation

### Safety Features
- Error checking and validation
- Installation testing
- Environment verification
- Backup prompts for existing installations
- Detailed logging and error messages

### User Experience
- Colored output for better readability
- Interactive yes/no prompts
- Progress indicators
- Detailed installation instructions
- Post-installation usage guide

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [FramePack](https://github.com/lllyasviel/FramePack)
- NVIDIA for CUDA and GPU support 
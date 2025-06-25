# Open Source Awesome AI

[![Awesome](https://img.shields.io/badge/Awesome-blue.svg)](https://github.com/sindresorhus/awesome)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian 12](https://img.shields.io/badge/Platform-Debian%2012-informational)](https://www.debian.org/)
[![GPU Support](https://img.shields.io/badge/GPU-NVIDIA-green)](https://www.nvidia.com/)

Self-hosting is the practice of running applications on your own server(s) instead of relying on SaaS providers. This list features modular, automated installation scripts for popular AI/ML tools, optimized for **Debian 12 (Proxmox containers)** with NVIDIA GPU support.

> **Modular, robust, and container-optimized AI/ML installer scripts for your own hardware.**

--------------------

## Table of Contents

- [Software](#software)
  - [Generative AI & ML](#generative-ai--ml)
  - [Modules](#modules)
- [Usage](#usage)
- [Features](#features)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)
- [External Links](#external-links)

--------------------

## Software

### Generative AI & ML

**[`^        back to top        ^`](#awesome-selfhosted-ai)**

- **[ComfyUI](https://github.com/comfyanonymous/ComfyUI)**  
  *Node-based Stable Diffusion Web UI with comfy-cli, automatic model management, and VRAM optimization.*  
  `Shell` `Stable Diffusion` `WebUI` `GPU`  
  **Install:** `./install_comfyui.sh`

- **[FramePack](https://github.com/lllyasviel/FramePack)**  
  *Next-frame prediction for video generation (standard & F1 models, up to 120s, 6GB+ VRAM).*  
  `Shell` `Video` `ML` `GPU`  
  **Install:** `./install_framepack.sh`

- **[Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)**  
  *Popular web interface for Stable Diffusion: text2img, img2img, inpainting, extensions, API, systemd, root support, TCMalloc.*  
  `Shell` `Stable Diffusion` `WebUI` `API` `GPU`  
  **Install:** `./install_stablediffusion.sh`

- **[TRELLIS (Microsoft)](https://github.com/microsoft/trellis)**  
  *3D generative model setup via official conda-based installer. GPU-accelerated, container-friendly.*  
  `Shell` `3D` `ML` `Conda` `GPU`  
  **Install:** `./install_trellis.sh`

--------------------

### Modules

**[`^        back to top        ^`](#awesome-selfhosted-ai)**

- **install_python.sh**  
  *Installs and configures Python (version specified per app).*  
  `Shell` `Python`
- **install_nvidia_drivers.sh**  
  *Installs NVIDIA GPU drivers for Debian 12.*  
  `Shell` `NVIDIA` `GPU`
- **install_cuda_nvcc.sh**  
  *Installs CUDA toolkit and NVCC compiler.*  
  `Shell` `CUDA` `GPU`

--------------------

## Usage

1. **Clone the repository:**
   ```bash
   git clone https://github.com/omiinaya/install-scripts.git
   cd install-scripts
   ```
2. **Make scripts executable:**
   ```bash
   chmod +x *.sh modules/*.sh
   ```
3. **Run the desired installer:**
   ```bash
   # ComfyUI
   ./install_comfyui.sh
   # FramePack
   ./install_framepack.sh
   # Stable Diffusion WebUI
   ./install_stablediffusion.sh
   # TRELLIS
   ./install_trellis.sh
   ```

### Stable Diffusion WebUI (AUTOMATIC1111) Service
- Systemd service (`sd-webui.service`) runs as root with `-f` flag, API and network enabled.
- Control the service:
  ```bash
  sudo systemctl start sd-webui
  sudo systemctl stop sd-webui
  sudo systemctl status sd-webui
  ```
- Access: [http://your-server-ip:7860](http://your-server-ip:7860)
- Command: `bash webui.sh -f --xformers --listen --enable-insecure-extension-access --api`
- TCMalloc (google-perftools) is installed for improved memory usage.

### ComfyUI & FramePack
- Launcher scripts and systemd services are created by the installers.
- Access ComfyUI: [http://your-server-ip:8188](http://your-server-ip:8188)
- Access FramePack: [http://your-server-ip:7860](http://your-server-ip:7860)

--------------------

## Features

- **Modular Design:** Reusable modules for Python, NVIDIA, CUDA, etc.
- **Container-Optimized:** Designed for Debian 12 Proxmox containers.
- **Systemd Integration:** Optional service creation for auto-start.
- **GPU Support:** Full NVIDIA and CUDA stack setup.
- **Interactive UX:** Colored output, prompts, and progress indicators.
- **Safety:** Error checking, validation, and backup prompts.
- **Customizable:** Environment variables for custom module URLs.

--------------------

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

--------------------

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

--------------------

## Acknowledgments

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [FramePack](https://github.com/lllyasviel/FramePack)
- [Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
- [TRELLIS](https://github.com/microsoft/trellis)
- NVIDIA for CUDA and GPU support

--------------------

## External Links

- [Debian 12](https://www.debian.org/)
- [Proxmox VE](https://www.proxmox.com/)
- [NVIDIA CUDA](https://developer.nvidia.com/cuda-zone)
- [Awesome-Selfhosted](https://github.com/awesome-selfhosted/awesome-selfhosted) 
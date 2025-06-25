# Auto Install Scripts

[![Awesome](https://img.shields.io/badge/Awesome-blue.svg)](https://github.com/sindresorhus/awesome)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Debian 12](https://img.shields.io/badge/Platform-Debian%2012-informational)](https://www.debian.org/)
[![GPU Support](https://img.shields.io/badge/GPU-NVIDIA-green)](https://www.nvidia.com/)

Self-hosting is the practice of running applications on your own server(s) instead of relying on SaaS providers. This list features modular, automated installation scripts for popular AI/ML tools, optimized for **Debian 12 (Proxmox containers)** with NVIDIA GPU support.

> **Modular, robust, and container-optimized installer scripts for your own hardware.**

--------------------

## Table of Contents

- [Software](#software)
  - [AI Automation](#ai-automation)
  - [3D Generation](#3d-generation)
  - [Video Generation](#video-generation)
  - [Image Generation](#image-generation)
- [Usage](#usage)
- [Features](#features)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)
- [External Links](#external-links)

--------------------

## Software

### AI Automation

**[`^        back to top        ^`](#auto-install-scripts)**

- **[ComfyUI](https://github.com/comfyanonymous/ComfyUI)**  
  *AI automation and workflow orchestration for Stable Diffusion and related models. Node-based Web UI, comfy-cli, automatic model management, VRAM optimization.*  
  `Shell` `Automation` `Stable Diffusion` `WebUI` `GPU`  
  **Install:** `./install_comfyui.sh`

### 3D Generation

**[`^        back to top        ^`](#auto-install-scripts)**

- **[TRELLIS (Microsoft)](https://github.com/microsoft/trellis)**  
  *Generate 3D assets using a GPU-accelerated, container-friendly pipeline. Official conda-based installer.*  
  `Shell` `3D` `ML` `Conda` `GPU`  
  **Install:** `./install_trellis.sh`

### Video Generation

**[`^        back to top        ^`](#auto-install-scripts)**

- **[FramePack](https://github.com/lllyasviel/FramePack)**  
  *Generate next-frame prediction videos (standard & F1 models, up to 120s, 6GB+ VRAM).*  
  `Shell` `Video` `ML` `GPU`  
  **Install:** `./install_framepack.sh`

### Image Generation

**[`^        back to top        ^`](#auto-install-scripts)**

- **[Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)**  
  *Generate images with Stable Diffusion: text2img, img2img, inpainting, extensions, API, systemd, root support, TCMalloc.*  
  `Shell` `Stable Diffusion` `WebUI` `API` `GPU`  
  **Install:** `./install_stablediffusion.sh`

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
   # TRELLIS
   ./install_trellis.sh
   # FramePack
   ./install_framepack.sh
   # Stable Diffusion WebUI
   ./install_stablediffusion.sh
   # ComfyUI
   ./install_comfyui.sh
   ```

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

- [TRELLIS](https://github.com/microsoft/trellis)
- [FramePack](https://github.com/lllyasviel/FramePack)
- [Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- NVIDIA for CUDA and GPU support

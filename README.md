# 🛠️ AI Self-Hosted Install Scripts

A curated collection of modular, automated install scripts for popular self-hosted AI/ML tools on Debian 12 (Proxmox containers). Each script sets up GPU acceleration, dependencies, and systemd services for seamless, production-ready deployment.

---

## 📚 Table of Contents
- [Supported Applications](#supported-applications)
- [Reusable Modules](#reusable-modules)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgments](#acknowledgments)

---

## 🚀 Supported Applications

### [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
> **Node-based Stable Diffusion Web UI**
- **Features:** Modern, modular workflow UI for Stable Diffusion. Model management, VRAM modes, CLI, and more.
- **Requirements:** NVIDIA GPU (6GB+), Debian 12, 32GB+ RAM recommended.
- **Quickstart:**
  ```bash
  ./install_comfyui.sh
  # Then: ~/launch_comfyui.sh or systemctl start comfyui
  # Access: http://localhost:8188
  ```

---

### [FramePack](https://github.com/lllyasviel/FramePack)
> **Next-frame video generation AI**
- **Features:** Generate up to 120s of video, F1 model for dynamic motion, optimized for 6GB+ VRAM.
- **Requirements:** NVIDIA GPU (6GB+), Debian 12, 32GB+ RAM recommended.
- **Quickstart:**
  ```bash
  ./install_framepack.sh
  # Then: ~/launch_framepack.sh or systemctl start framepack
  # Access: http://localhost:7860
  ```

---

### [Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
> **The most popular SD web interface**
- **Features:** Text2img, img2img, inpainting, extensions, API, root/systemd support, TCMalloc for memory.
- **Requirements:** NVIDIA GPU (6GB+), Debian 12, 32GB+ RAM recommended, TCMalloc auto-installed.
- **Quickstart:**
  ```bash
  ./install_stablediffusion.sh
  # Service: systemctl start sd-webui
  # Access: http://localhost:7860
  ```

---

### [TRELLIS (Microsoft)](https://github.com/microsoft/TRELLIS)
> **Scalable, versatile 3D generation (CVPR'25 Spotlight)**
- **Features:** 3D latent diffusion, multi-GPU, conda-based, CUDA 11.8/12.2, modular install.
- **Requirements:** NVIDIA GPU (16GB+), Debian 12, Miniconda (auto-installed), CUDA 11.8/12.2.
- **Quickstart:**
  ```bash
  ./install_trellis.sh
  # Then: conda activate trellis
  # See repo for usage
  ```

---

## 🧩 Reusable Modules

- `modules/install_python.sh` — Python 3.x, venv, pipx
- `modules/install_nvidia_drivers.sh` — NVIDIA drivers (Debian 12)
- `modules/install_cuda_nvcc.sh` — CUDA toolkit & nvcc

All app installers use these modules for consistent, reliable setup.

---

## 🖥️ System Requirements
- **OS:** Debian 12 (Bookworm, Proxmox container recommended)
- **GPU:** NVIDIA (6GB+ for most, 16GB+ for TRELLIS)
- **RAM:** 32GB+ recommended
- **Storage:** 50GB+ free (models)
- **Network:** Internet access for downloads

---

## ⚡ Installation
1. **Clone this repo:**
   ```bash
   git clone https://github.com/omiinaya/install-scripts.git
   cd install-scripts
   chmod +x *.sh modules/*.sh
   ```
2. **Run the installer for your app:**
   ```bash
   ./install_comfyui.sh           # or
   ./install_framepack.sh         # or
   ./install_stablediffusion.sh   # or
   ./install_trellis.sh
   ```
3. **Follow the post-install instructions for each app.**

---

## 🤝 Contributing
- PRs welcome! Add new apps, improve modules, or suggest features.
- See [CONTRIBUTING.md](CONTRIBUTING.md) if available.

---

## 📄 License
MIT — see [LICENSE](LICENSE)

---

## 🙏 Acknowledgments
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [FramePack](https://github.com/lllyasviel/FramePack)
- [Stable Diffusion WebUI (AUTOMATIC1111)](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
- [TRELLIS (Microsoft)](https://github.com/microsoft/TRELLIS)
- NVIDIA, PyTorch, and the open-source community 
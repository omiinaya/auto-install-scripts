#!/bin/bash

# Python Installation Module for Debian 12 (Proxmox Container)
# This module provides functions to install different Python versions

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check for and install sudo first if not present
ensure_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        log "Installing sudo..."
        apt update
        apt install -y sudo
    fi
}

# Install Python 3 (default version - typically 3.11 on Debian 12)
install_python3_default() {
    log "Installing Python 3 (default version) and related tools..."
    
    ensure_sudo
    
    # Install Python 3 (default) and pip
    sudo apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-full \
        python3-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
    info "Python version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.9+
    if python3 -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)"; then
        log "Python version is sufficient (3.9+)"
    else
        error "Python version is too old. Requires Python 3.9 or higher."
    fi
    
    # Skip global pip upgrade due to externally-managed-environment
    # We'll upgrade pip inside virtual environments instead
    info "Skipping global pip upgrade (will upgrade in virtual environment)"
    
    log "Python 3 (default) installation completed"
}

# Install Python 3.10 specifically
install_python310() {
    log "Installing Python 3.10 specifically and related tools..."
    
    ensure_sudo
    
    # Install Python 3.10 specifically
    sudo apt install -y \
        python3.10 \
        python3.10-pip \
        python3.10-venv \
        python3.10-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Verify Python 3.10 is available
    if ! command -v python3.10 >/dev/null 2>&1; then
        error "Python 3.10 is not available. Please check your system's package repositories."
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3.10 --version | cut -d' ' -f2)
    info "Python 3.10 version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.10
    if python3.10 -c "import sys; exit(0 if sys.version_info >= (3, 10) and sys.version_info < (3, 11) else 1)"; then
        log "Python 3.10 is available and working"
    else
        error "Python 3.10 verification failed."
    fi
    
    info "Python 3.10 installation completed"
}

# Install Python 3.11 specifically
install_python311() {
    log "Installing Python 3.11 specifically and related tools..."
    
    ensure_sudo
    
    # Install Python 3.11 specifically
    sudo apt install -y \
        python3.11 \
        python3.11-pip \
        python3.11-venv \
        python3.11-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Verify Python 3.11 is available
    if ! command -v python3.11 >/dev/null 2>&1; then
        error "Python 3.11 is not available. Please check your system's package repositories."
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3.11 --version | cut -d' ' -f2)
    info "Python 3.11 version: $PYTHON_VERSION"
    
    # Ensure we have Python 3.11
    if python3.11 -c "import sys; exit(0 if sys.version_info >= (3, 11) and sys.version_info < (3, 12) else 1)"; then
        log "Python 3.11 is available and working"
    else
        error "Python 3.11 verification failed."
    fi
    
    info "Python 3.11 installation completed"
}

# Install Python 3.12 specifically
install_python312() {
    log "Installing Python 3.12 specifically and related tools..."
    
    ensure_sudo
    
    # Python 3.12 might not be available in default Debian 12 repos
    # Try to install from backports or alternative sources
    
    # First try default repositories
    if sudo apt install -y python3.12 python3.12-pip python3.12-venv python3.12-dev 2>/dev/null; then
        log "Python 3.12 installed from default repositories"
    else
        warn "Python 3.12 not available in default repositories"
        info "Attempting to install from deadsnakes PPA alternative..."
        
        # Install dependencies for adding repositories
        sudo apt install -y software-properties-common
        
        # Add deadsnakes PPA equivalent or compile from source
        warn "Python 3.12 installation may require manual setup on Debian 12"
        error "Python 3.12 is not readily available. Consider using Python 3.10 or 3.11 instead."
    fi
    
    # Install common tools
    sudo apt install -y \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Verify Python 3.12 is available
    if ! command -v python3.12 >/dev/null 2>&1; then
        error "Python 3.12 is not available after installation attempt."
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3.12 --version | cut -d' ' -f2)
    info "Python 3.12 version: $PYTHON_VERSION"
    
    log "Python 3.12 installation completed"
}

# Create virtual environment with specified Python version
create_python_venv() {
    local python_cmd="$1"
    local venv_path="$2"
    local venv_name="$3"
    
    if [ -z "$python_cmd" ] || [ -z "$venv_path" ] || [ -z "$venv_name" ]; then
        error "Usage: create_python_venv <python_command> <venv_path> <venv_name>"
    fi
    
    log "Creating Python virtual environment with $python_cmd..."
    
    # Full path to virtual environment
    FULL_VENV_PATH="$venv_path/$venv_name"
    
    if [ -d "$FULL_VENV_PATH" ]; then
        warn "Virtual environment already exists at $FULL_VENV_PATH"
        read -p "Do you want to remove it and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$FULL_VENV_PATH"
        else
            info "Using existing virtual environment"
            return 0
        fi
    fi
    
    # Verify Python command exists
    if ! command -v "$python_cmd" >/dev/null 2>&1; then
        error "Python command '$python_cmd' not found. Please install it first."
    fi
    
    # Create the virtual environment
    "$python_cmd" -m venv "$FULL_VENV_PATH"
    
    # Activate virtual environment and upgrade pip
    source "$FULL_VENV_PATH/bin/activate"
    pip install --upgrade pip setuptools wheel
    deactivate
    
    log "Virtual environment created at $FULL_VENV_PATH"
    info "To activate: source $FULL_VENV_PATH/bin/activate"
}

# Function to determine which Python version to install based on requirements
install_python_for_app() {
    local app_name="$1"
    local min_version="$2"
    local max_version="$3"
    local preferred_version="$4"
    
    log "Installing Python for $app_name..."
    info "Requirements: Min: $min_version, Max: $max_version, Preferred: $preferred_version"
    
    case "$preferred_version" in
        "3.10")
            install_python310
            ;;
        "3.11")
            install_python311
            ;;
        "3.12")
            install_python312
            ;;
        "default"|"")
            install_python3_default
            ;;
        *)
            warn "Unknown Python version '$preferred_version', installing default"
            install_python3_default
            ;;
    esac
}

# Main function for standalone usage
main() {
    if [ $# -eq 0 ]; then
        echo "Python Installation Module"
        echo "Usage: $0 <command> [options]"
        echo
        echo "Commands:"
        echo "  default          - Install Python 3 (default system version)"
        echo "  3.10             - Install Python 3.10 specifically"
        echo "  3.11             - Install Python 3.11 specifically"
        echo "  3.12             - Install Python 3.12 specifically"
        echo "  venv <python_cmd> <path> <name> - Create virtual environment"
        echo
        echo "Examples:"
        echo "  $0 default"
        echo "  $0 3.10"
        echo "  $0 venv python3.10 /home/user myproject-env"
        exit 1
    fi
    
    case "$1" in
        "default")
            install_python3_default
            ;;
        "3.10")
            install_python310
            ;;
        "3.11")
            install_python311
            ;;
        "3.12")
            install_python312
            ;;
        "venv")
            if [ $# -ne 4 ]; then
                error "Usage: $0 venv <python_command> <venv_path> <venv_name>"
            fi
            create_python_venv "$2" "$3" "$4"
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
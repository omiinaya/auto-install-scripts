#!/bin/bash
set -e

# Python Installation Module - Using pyenv for Version Management
# Usage: ./install_python.sh [version]
# Default version: Auto-detected latest available, fallback to 3.11
# Example: ./install_python.sh 3.10

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Install system dependencies for pyenv
install_pyenv_dependencies() {
    log "Installing pyenv dependencies..."
    
    # Update package list
    apt update
    
    # Install build dependencies for Python compilation
    apt install -y \
        make \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        wget \
        curl \
        llvm \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        git
    
    info "pyenv dependencies installed successfully"
}

# Install pyenv
install_pyenv() {
    log "Installing pyenv..."

    # The pyenv installer script fails if the ~/.pyenv directory already exists.
    # We will check for the directory's existence and assume pyenv is installed if found.
    if [ -d "$HOME/.pyenv" ]; then
        info "pyenv directory found at '$HOME/.pyenv'. Skipping installation."
        return 0
    fi

    info "pyenv not found, proceeding with installation."
    # Install pyenv using the official installer
    curl https://pyenv.run | bash
    
    # Add pyenv to shell profile for future sessions
    SHELL_PROFILE=""
    if [ -f "$HOME/.bashrc" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        SHELL_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.profile" ]; then
        SHELL_PROFILE="$HOME/.profile"
    fi
    
    if [ -n "$SHELL_PROFILE" ]; then
        info "Adding pyenv to $SHELL_PROFILE"
        
        # Ensure the configuration is not duplicated
        if ! grep -q 'PYENV_ROOT' "$SHELL_PROFILE"; then
            cat >> "$SHELL_PROFILE" << 'EOF'

# --- pyenv configuration ---
# The following lines were automatically added by an installation script.
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init --path)"
fi
# --- end pyenv configuration ---
EOF
        fi
    fi
    
    log "pyenv installed successfully"
}

# Initialize pyenv in the current script session
init_pyenv() {
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"
    
    if ! command -v pyenv >/dev/null 2>&1; then
        error "pyenv not found after installation. Please check the installation and PATH."
    fi
}

# Get the latest available Python version for a major.minor version
get_latest_python_version() {
    local major_minor="$1"
    
    # List available versions and filter for the requested major.minor
    pyenv install --list | grep -E "^\s*${major_minor}\.[0-9]+$" | tail -1 | tr -d ' '
}

# Detect the best Python version to install
detect_python_version() {
    info "Detecting best Python version to install..."
    
    # Try versions in order of preference
    for version in "3.12" "3.11" "3.10" "3.9"; do
        local latest=$(get_latest_python_version "$version")
        if [ -n "$latest" ]; then
            info "Latest available Python version for $version: $latest"
            echo "$latest"
            return 0
        fi
    done
    
    warn "Could not detect available Python versions, using fallback"
    echo "3.11.0"
}

# Install Python version using pyenv
install_python_version() {
    local version="$1"
    
    log "Installing Python $version using pyenv..."
    
    # Check if version is already installed
    if pyenv versions | grep -q "$version"; then
        info "Python $version is already installed"
    else
        info "Compiling Python $version (this may take several minutes)..."
        pyenv install "$version"
    fi
    
    # Set as global default
    pyenv global "$version"
    
    # Verify installation
    local installed_version=$(python --version 2>&1 | cut -d' ' -f2)
    log "Python version set: $installed_version"
    
    # Upgrade pip
    info "Upgrading pip..."
    python -m pip install --upgrade pip
    
    # Install essential packages
    info "Installing essential Python packages..."
    python -m pip install \
        setuptools \
        wheel \
        virtualenv \
        pipenv
    
    log "Python $version installation completed successfully"
}

# Create a project-specific virtual environment
create_project_venv() {
    local project_name="$1"
    local python_version="$2"
    
    if [ -z "$project_name" ]; then
        info "No project name specified, skipping virtual environment creation"
        return 0
    fi
    
    log "Creating virtual environment for project: $project_name"
    
    # Create virtual environment using pyenv
    if ! pyenv virtualenvs | grep -q "$project_name"; then
        pyenv virtualenv "$python_version" "$project_name"
        info "Virtual environment '$project_name' created"
    else
        info "Virtual environment '$project_name' already exists"
    fi
    
    # Instructions for activating the environment
    info "To activate this environment later, run:"
    info "  pyenv activate $project_name"
    info "To deactivate, run:"
    info "  pyenv deactivate"
}

# Main installation function
install_python() {
    log "Starting Python installation with pyenv..."
    
    # Parse arguments
    local requested_version="$1"
    local project_name="$2"
    
    # Install system dependencies
    install_pyenv_dependencies
    
    # Install pyenv
    install_pyenv

    # Initialize pyenv for current session without corrupting the shell state
    init_pyenv
    
    # Determine Python version to install
    local python_version
    if [ -n "$requested_version" ]; then
        # Check if it's a major.minor version, get the latest patch version
        if [[ "$requested_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            python_version=$(get_latest_python_version "$requested_version")
            if [ -z "$python_version" ]; then
                warn "No Python $requested_version versions available, trying exact version"
                python_version="$requested_version"
            fi
        else
            python_version="$requested_version"
        fi
        info "Using requested Python version: $python_version"
    else
        python_version=$(detect_python_version)
        info "Using auto-detected Python version: $python_version"
    fi
    
    # Install the Python version
    install_python_version "$python_version"
    
    # Create project virtual environment if requested
    if [ -n "$project_name" ]; then
        create_project_venv "$project_name" "$python_version"
    fi
    
    # Print usage information
    echo
    info "Python installation completed!"
    info "Installed Python version: $(python --version)"
    info "Python location: $(which python)"
    echo
    info "pyenv commands:"
    info "  pyenv versions        - List installed Python versions"
    info "  pyenv global <version> - Set global Python version"
    info "  pyenv local <version>  - Set local Python version for current directory"
    info "  pyenv virtualenv <version> <name> - Create virtual environment"
    info "  pyenv activate <name>  - Activate virtual environment"
    echo
    info "To use pyenv in new shell sessions, restart your shell or run:"
    info "  source ~/.bashrc"
}

# If script is run directly (not sourced), call the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    PYTHON_VERSION="${1:-}"
    PROJECT_NAME="${2:-}"
    
    # Override with environment variable if set
    if [ -n "${PYTHON_VERSION:-}" ]; then
        PYTHON_VERSION="$PYTHON_VERSION"
    fi
    
    install_python "$PYTHON_VERSION" "$PROJECT_NAME"
fi 
#!/bin/bash
set -e

# Python Installation Module - Simplified with Version Support
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

# Detect latest available Python version
detect_python_version() {
    # Update package list first
    apt update >/dev/null 2>&1
    
    # Check for available Python versions in order of preference
    for version in 3.12 3.11 3.10 3.9; do
        if apt-cache show python${version} >/dev/null 2>&1; then
            info "Latest available Python version: $version"
            echo "$version"
            return 0
        fi
    done
    
    # Fallback to 3.11 if nothing found
    warn "Could not detect available Python versions, using fallback"
    echo "3.11"
}

# Parse version argument or auto-detect
if [ -n "$1" ]; then
    PYTHON_VERSION="$1"
    info "Using specified Python version: $PYTHON_VERSION"
else
    PYTHON_VERSION=$(detect_python_version)
    info "Using auto-detected Python version: $PYTHON_VERSION"
fi

log "Installing Python $PYTHON_VERSION and related tools"

# Install Python and tools
install_python() {
    log "Installing Python $PYTHON_VERSION and related tools..."
    
    # Update package list
    apt update
    
    # Install Python version-specific packages
    info "Installing Python $PYTHON_VERSION and essential tools..."
    apt install -y \
        sudo \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-pip \
        python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-full \
        python${PYTHON_VERSION}-dev \
        python3-setuptools \
        python3-wheel \
        pipx
    
    # Create python3 symlink if it doesn't exist or points to wrong version
    if ! command -v python3 >/dev/null 2>&1 || ! python3 --version | grep -q "$PYTHON_VERSION"; then
        info "Creating python3 symlink for Python $PYTHON_VERSION..."
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1
    fi
    
    # Verify Python version
    INSTALLED_VERSION=$(python3 --version | cut -d' ' -f2)
    log "Python version installed: $INSTALLED_VERSION"
    
    # Check if Python is 3.9+
    if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)"; then
        error "Python version is too old. Requires Python 3.9 or higher."
    fi
    
    log "Python $PYTHON_VERSION installation completed"
}

# Main function
main() {
    install_python
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 
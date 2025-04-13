#!/bin/bash
# proton-manager.sh - Utility to manage Proton-GE versions
# Usage: proton-manager.sh [list|install|use] [version]

set -e

COMPAT_DIR="/home/steam/.steam/root/compatibilitytools.d"
STEAM_USER_HOME="/home/steam"

# Ensure the compatibilitytools directory exists
mkdir -p "$COMPAT_DIR"

# List available versions from GitHub API
list_available_versions() {
  echo "Fetching available Proton-GE versions..."
  curl -s "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases" | \
    jq -r '.[].tag_name' | sort -V
}

# List installed versions
list_installed_versions() {
  echo "Installed Proton-GE versions:"
  find "$COMPAT_DIR" -maxdepth 1 -type d -name "GE-Proton*" | \
    sed "s|$COMPAT_DIR/||" | sort -V
}

# Install a specific version
install_version() {
  local VERSION="$1"
  
  if [ -z "$VERSION" ]; then
    echo "Error: No version specified."
    echo "Usage: proton-manager.sh install GE-Proton8-2"
    return 1
  fi
  
  # Check if already installed
  if [ -d "$COMPAT_DIR/$VERSION" ]; then
    echo "Version $VERSION is already installed."
    return 0
  fi
  
  echo "Installing Proton-GE version: $VERSION..."
  
  # Create temporary directory
  local TEMP_DIR=$(mktemp -d)
  cd "$TEMP_DIR"
  
  # Download and extract
  local URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$VERSION/$VERSION.tar.gz"
  if curl -L "$URL" -o "$VERSION.tar.gz"; then
    tar xzf "$VERSION.tar.gz" -C "$COMPAT_DIR/"
    echo "Successfully installed $VERSION to $COMPAT_DIR/$VERSION"
    
    # Create symbolic link to make it the default version
    use_version "$VERSION"
  else
    echo "Error: Failed to download $VERSION"
    return 1
  fi
  
  # Clean up
  rm -rf "$TEMP_DIR"
}

# Set a specific version as the default
use_version() {
  local VERSION="$1"
  
  if [ -z "$VERSION" ]; then
    echo "Error: No version specified."
    echo "Usage: proton-manager.sh use GE-Proton8-2"
    return 1
  fi
  
  # Check if installed
  if [ ! -d "$COMPAT_DIR/$VERSION" ]; then
    echo "Error: Version $VERSION is not installed."
    echo "Available versions:"
    list_installed_versions
    return 1
  fi
  
  # Update .bashrc to set PROTON_PATH
  sed -i '/^export PROTON_PATH=/d' "$STEAM_USER_HOME/.bashrc"
  echo "export PROTON_PATH=$COMPAT_DIR/$VERSION/proton" >> "$STEAM_USER_HOME/.bashrc"
  
  # Set for current session
  export PROTON_PATH="$COMPAT_DIR/$VERSION/proton"
  
  echo "Now using Proton-GE version: $VERSION"
  echo "PROTON_PATH=$PROTON_PATH"
}

# Show help message
show_help() {
  echo "Usage: proton-manager.sh [command] [version]"
  echo ""
  echo "Commands:"
  echo "  list             List installed Proton-GE versions"
  echo "  available        List available Proton-GE versions from GitHub"
  echo "  install [ver]    Install specified Proton-GE version"
  echo "  use [ver]        Set specified version as default"
  echo ""
  echo "Examples:"
  echo "  proton-manager.sh available"
  echo "  proton-manager.sh install GE-Proton8-2"
  echo "  proton-manager.sh use GE-Proton8-2"
}

# Main logic
case "$1" in
  list)
    list_installed_versions
    ;;
  available)
    list_available_versions
    ;;
  install)
    install_version "$2"
    ;;
  use)
    use_version "$2"
    ;;
  *)
    show_help
    ;;
esac
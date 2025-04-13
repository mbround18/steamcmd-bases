#!/bin/bash
# Proton initialization script
set -Eeuo pipefail

# Skip if no Proton installation is found
COMPAT_DIR="/home/steam/.steam/root/compatibilitytools.d"
if [ ! -d "$COMPAT_DIR" ] || [ -z "$(find "$COMPAT_DIR" -maxdepth 1 -type d -name "GE-Proton*" 2>/dev/null)" ]; then
    echo "🎮 No Proton installation detected, skipping Proton initialization"
    exit 0
fi

echo "🎮 Initializing Proton environment..."

# Find the latest Proton installation
PROTON_DIR=$(find "$COMPAT_DIR" -maxdepth 1 -type d -name "GE-Proton*" | sort -V | tail -n 1)
PROTON_VERSION=$(basename "$PROTON_DIR")
export PROTON_PATH="${PROTON_DIR}/proton"

# Set default Proton environment variables if not already set
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH:-/home/steam/.steam/steam}
export STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-/home/steam/.proton}
export WINEPREFIX=${WINEPREFIX:-/home/steam/.proton/pfx}

echo "🔍 Using Proton version: $PROTON_VERSION"
echo "🔍 Proton path: $PROTON_PATH"

# Initialize Proton prefix if it doesn't exist
if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "🏗️ Creating new Proton prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    # Run a simple command to initialize the prefix
    "$PROTON_PATH" run /bin/true || echo "⚠️ Proton prefix initialization failed, but continuing..."
fi

# Set up Xvfb if needed for graphical applications
if [ -z "${DISPLAY:-}" ] && command -v Xvfb &> /dev/null; then
    export DISPLAY=:99
    Xvfb :99 -screen 0 1024x768x16 &
    echo "🖥️ Started Xvfb on display $DISPLAY"
    # Store the PID for later cleanup
    echo "$!" > /tmp/xvfb.pid
    export SDL_VIDEODRIVER=x11
fi

# Set persistent environment variables in profile
if [ "$(id -u)" = "1000" ]; then
    echo "🔧 Setting persistent Proton environment variables"
    echo "export PROTON_PATH=$PROTON_PATH" >> /home/steam/.bashrc
    echo "export STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH" >> /home/steam/.bashrc
    echo "export STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH" >> /home/steam/.bashrc
    echo "export WINEPREFIX=$WINEPREFIX" >> /home/steam/.bashrc
    echo "export DISPLAY=${DISPLAY:-:0}" >> /home/steam/.bashrc
    echo "export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-x11}" >> /home/steam/.bashrc
fi

echo "✅ Proton initialization complete"
#!/bin/bash
# Proton initialization script
# Initializes Proton environment with proper version detection and idempotency
set -Eeuo pipefail

# Source dependency management library
# shellcheck source=/opt/steamcmd-bases/lib/deps.sh
source "${STEAMCMD_BASES_LIB:-/opt/steamcmd-bases/lib}/deps.sh"

# Skip if no Proton installation is found
if ! is_proton_installed; then
    echo "🎮 No Proton installation detected, skipping Proton initialization"
    exit 0
fi

echo "🎮 Initializing Proton environment..."

# Detect Proton installation
PROTON_PATH=$(detect_proton_version)
export PROTON_PATH="${PROTON_PATH}/proton"

# Get version information
PROTON_VERSION=$(get_proton_version_string)

# Set default Proton environment variables if not already set
export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH:-/home/steam/.steam/steam}
export STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-/home/steam/.proton}
export WINEPREFIX=${WINEPREFIX:-/home/steam/.proton/pfx}

echo "🔍 Using Proton version: ${PROTON_VERSION}"
echo "🔍 Proton path: ${PROTON_PATH%/proton}"

# Set up Xvfb before touching Proton at all - it creates a Vulkan instance
# (DXVK) even for a no-op prefix init below, and that fails immediately
# without a display, regardless of whether a game is actually running.
if [ -z "${DISPLAY:-}" ] && command -v Xvfb &> /dev/null; then
    export DISPLAY=:99
    Xvfb :99 -screen 0 1024x768x16 &
    echo "🖥️ Started Xvfb on display $DISPLAY"
    # Store the PID for later cleanup
    echo "$!" > /tmp/xvfb.pid
    export SDL_VIDEODRIVER=x11
fi

# Initialize Proton prefix if it doesn't exist (idempotent)
if [ ! -d "$WINEPREFIX" ] || [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo "🏗️ Creating new Proton prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    # Run a simple command to initialize the prefix
    "${PROTON_PATH}" run /bin/true || echo "⚠️ Proton prefix initialization failed, but continuing..."
else
    echo "✓ Proton prefix already initialized"
fi

# Persist environment variables so they reach the container's main process
# (see persist_env in deps.sh) as well as interactive steam shells
persist_env PROTON_PATH "${PROTON_PATH}"
persist_env STEAM_COMPAT_CLIENT_INSTALL_PATH "${STEAM_COMPAT_CLIENT_INSTALL_PATH}"
persist_env STEAM_COMPAT_DATA_PATH "${STEAM_COMPAT_DATA_PATH}"
persist_env WINEPREFIX "${WINEPREFIX}"
persist_env DISPLAY "${DISPLAY:-:0}"
persist_env SDL_VIDEODRIVER "${SDL_VIDEODRIVER:-x11}"

echo "✅ Proton initialization complete"
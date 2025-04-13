#!/bin/bash
# proton-run.sh - A utility script to simplify running applications with Proton
# Usage: proton-run.sh [path/to/executable.exe] [arguments]

set -e

# Check if an executable was provided
if [ -z "$1" ]; then
  echo "Usage: proton-run.sh [path/to/executable.exe] [arguments]"
  echo "Example: proton-run.sh /home/steam/Steam/steamapps/common/mygame/Game.exe -server"
  exit 1
fi

EXECUTABLE="$1"
shift
ARGS=("$@")

# Ensure Proton environment is properly set
if [ -z "$PROTON_PATH" ]; then
  # Find the latest Proton installation
  PROTON_DIR=$(find /home/steam/.steam/root/compatibilitytools.d -maxdepth 1 -type d -name "GE-Proton*" | sort -V | tail -n 1)
  if [ -z "$PROTON_DIR" ]; then
    echo "Error: No Proton installation found. Please ensure Proton is installed."
    exit 1
  fi
  export PROTON_PATH="${PROTON_DIR}/proton"
  echo "Automatically selected Proton: ${PROTON_PATH}"
fi

# Ensure Steam compat variables are set
if [ -z "$STEAM_COMPAT_CLIENT_INSTALL_PATH" ]; then
  export STEAM_COMPAT_CLIENT_INSTALL_PATH="/home/steam/.steam/steam"
fi

if [ -z "$STEAM_COMPAT_DATA_PATH" ]; then
  export STEAM_COMPAT_DATA_PATH="/home/steam/.proton"
fi

# Ensure Wine prefix is set
if [ -z "$WINEPREFIX" ]; then
  export WINEPREFIX="/home/steam/.proton/pfx"
fi

# Display setup for headless operation
if [ -z "$DISPLAY" ]; then
  export DISPLAY=:99
  export SDL_VIDEODRIVER=x11

  # Check if Xvfb exists and start if needed
  if command -v Xvfb >/dev/null 2>&1; then
    Xvfb :99 -screen 0 1024x768x16 &
    XVFB_PID=$!
    # Give X time to start
    sleep 1
  fi
fi

echo "Running: ${EXECUTABLE} ${ARGS[*]}"
echo "With Proton: ${PROTON_PATH}"

# Run the executable with Proton
"${PROTON_PATH}" run "${EXECUTABLE}" "${ARGS[@]}"

# Clean up Xvfb if we started it
if [ -n "$XVFB_PID" ]; then
  kill $XVFB_PID
fi
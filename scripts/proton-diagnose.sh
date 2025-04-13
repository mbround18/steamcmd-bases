#!/bin/bash
# proton-diagnose.sh - Utility to diagnose Proton environment and issues
# Usage: proton-diagnose.sh [options]

set -e

echo "===== Proton Environment Diagnostics ====="
echo ""

# Check Proton installation
echo "=== Proton Installations ==="
COMPAT_DIR="/home/steam/.steam/root/compatibilitytools.d"
if [ -d "$COMPAT_DIR" ]; then
  PROTON_VERSIONS=$(find "$COMPAT_DIR" -maxdepth 1 -type d -name "GE-Proton*" | sort -V)
  if [ -z "$PROTON_VERSIONS" ]; then
    echo "❌ No Proton installations found in $COMPAT_DIR"
  else
    echo "✅ Found Proton installations:"
    for version in $PROTON_VERSIONS; do
      echo "   - $(basename $version)"
    done
  fi
else
  echo "❌ Compatibility tools directory not found: $COMPAT_DIR"
fi

# Check Proton path
echo -e "\n=== Proton Path ==="
if [ -n "$PROTON_PATH" ]; then
  echo "PROTON_PATH = $PROTON_PATH"
  if [ -f "$PROTON_PATH" ]; then
    echo "✅ Proton binary exists"
  else
    echo "❌ Proton binary not found at $PROTON_PATH"
  fi
else
  echo "❌ PROTON_PATH environment variable not set"
fi

# Check Steam environment
echo -e "\n=== Steam Environment ==="
REQUIRED_VARS=(
  "STEAM_COMPAT_CLIENT_INSTALL_PATH"
  "STEAM_COMPAT_DATA_PATH"
  "WINEPREFIX"
)

for var in "${REQUIRED_VARS[@]}"; do
  if [ -n "${!var}" ]; then
    echo "$var = ${!var}"
    if [ -d "${!var}" ]; then
      echo "✅ Directory exists"
    else
      echo "❌ Directory does not exist"
    fi
  else
    echo "❌ $var not set"
  fi
done

# Check Wine prefix
echo -e "\n=== Wine Prefix ==="
if [ -n "$WINEPREFIX" ]; then
  if [ -d "$WINEPREFIX" ]; then
    echo "✅ Wine prefix exists at $WINEPREFIX"
    if [ -f "$WINEPREFIX/system.reg" ]; then
      echo "✅ Wine registry found"
    else
      echo "❌ Wine registry not found, prefix may be incomplete"
    fi
  else
    echo "❌ Wine prefix directory does not exist"
  fi
else
  echo "❌ WINEPREFIX not set"
fi

# Check display configuration
echo -e "\n=== Display Configuration ==="
if [ -n "$DISPLAY" ]; then
  echo "DISPLAY = $DISPLAY"
  if pgrep -f "Xvfb $DISPLAY" > /dev/null; then
    echo "✅ Xvfb running on $DISPLAY"
  else
    echo "❌ No Xvfb instance running on $DISPLAY"
  fi
else
  echo "❌ DISPLAY environment variable not set"
fi

# Check required libraries
echo -e "\n=== Required Libraries ==="
LIBRARIES=(
  "/usr/lib/i386-linux-gnu/libncurses.so.5"
  "/usr/lib/x86_64-linux-gnu/libncurses.so.5"
  "/usr/lib/i386-linux-gnu/libcurl.so.4"
  "/usr/lib/x86_64-linux-gnu/libvulkan.so.1"
  "/home/steam/.steam/sdk64/steamclient.so"
)

for lib in "${LIBRARIES[@]}"; do
  if [ -f "$lib" ] || [ -L "$lib" ]; then
    echo "✅ Found: $lib"
  else
    echo "❌ Missing: $lib (may not be required for all games)"
  fi
done

# Check Steam runtime
echo -e "\n=== Steam Runtime ==="
if [ -d "/home/steam/.steam/steam/steamapps/common/SteamLinuxRuntime" ]; then
  echo "✅ Steam Linux Runtime is installed"
else
  echo "⚠️ Steam Linux Runtime is not installed (not critical for all games)"
fi

# Print summary
echo -e "\n=== Environment Summary ==="
echo "USER: $(whoami)"
echo "HOME: $HOME"
echo "PATH: $PATH"

echo -e "\n=== Additional Environment Variables ==="
env | grep -E 'STEAM|WINE|PROTON|SDL|DISPLAY|DBUS|XDG'

# Create a test Wine prefix if requested
if [ "$1" = "--init-prefix" ]; then
  echo -e "\n=== Initializing Wine Prefix ==="
  if [ -z "$WINEPREFIX" ]; then
    export WINEPREFIX="/home/steam/.proton/pfx"
  fi
  
  if [ -d "$WINEPREFIX" ]; then
    echo "⚠️ Wine prefix already exists at $WINEPREFIX"
    read -p "Do you want to recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rm -rf "$WINEPREFIX"
    else
      echo "Skipping prefix initialization"
      exit 0
    fi
  fi
  
  if [ -n "$PROTON_PATH" ] && [ -f "$PROTON_PATH" ]; then
    echo "Creating a fresh Wine prefix using Proton..."
    "$PROTON_PATH" run /bin/true
    echo "✅ Wine prefix initialized at $WINEPREFIX"
  else
    echo "❌ Cannot initialize Wine prefix: PROTON_PATH not properly set"
  fi
fi

echo -e "\n=== Diagnostics Complete ==="
echo "For problems, check the wiki at: https://github.com/GloriousEggroll/proton-ge-custom/wiki"
#!/bin/bash
# Wine initialization script
set -Eeuo pipefail

# Skip this script if Wine is not installed
if ! command -v wine &> /dev/null; then
    echo "🍷 Wine not detected, skipping Wine initialization"
    exit 0
fi

echo "🍷 Initializing Wine environment..."

# Set default Wine environment variables if not already set
export WINEARCH=${WINEARCH:-win64}
export WINEDEBUG=${WINEDEBUG:-fixme-all}
export WINEPREFIX=${WINEPREFIX:-/home/steam/.wine}

# Create Wine prefix if it doesn't exist
if [ ! -d "$WINEPREFIX" ]; then
    echo "🏗️ Creating new Wine prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    # Run a simple command to initialize the prefix
    wine wineboot --init || echo "⚠️ Wine prefix initialization failed, but continuing..."
fi

# Set persistent environment variables in profile
if [ "$(id -u)" = "1000" ]; then
    echo "🔧 Setting persistent Wine environment variables"
    echo "export WINEARCH=${WINEARCH}" >> /home/steam/.bashrc
    echo "export WINEDEBUG=${WINEDEBUG}" >> /home/steam/.bashrc
    echo "export WINEPREFIX=${WINEPREFIX}" >> /home/steam/.bashrc
fi

echo "✅ Wine initialization complete"
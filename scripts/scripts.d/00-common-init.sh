#!/bin/bash
# Common initialization script for all SteamCMD images
set -Eeuo pipefail

echo "🔧 Running common initialization tasks..."

# Create data directories if they don't exist
mkdir -p /home/steam/data
mkdir -p /home/steam/logs

# Make sure SteamCMD is ready (non-interactive test launch)
if [ "$(id -u)" = "1000" ]; then
    echo "📦 Ensuring SteamCMD is properly initialized..."
    steamcmd +quit > /dev/null 2>&1 || echo "⚠️ SteamCMD initialization failed, but continuing..."
fi

# Set appropriate permissions
chown -R steam:steam /home/steam || echo "⚠️ Permissions setting failed, but continuing..."

echo "✅ Common initialization complete"
#!/bin/bash
# Wine initialization script
# Initializes Wine environment with proper version detection and idempotency
set -Eeuo pipefail

# Source dependency management library
# shellcheck source=/opt/steamcmd-bases/lib/deps.sh
source "${STEAMCMD_BASES_LIB:-/opt/steamcmd-bases/lib}/deps.sh"

# Skip this script if Wine is not installed
if ! is_wine_installed; then
    echo "🍷 Wine not detected, skipping Wine initialization"
    exit 0
fi

echo "🍷 Initializing Wine environment..."
echo "🍷 Detected: $(detect_wine_version)"

# Set default Wine environment variables if not already set
export WINEARCH=${WINEARCH:-win64}
export WINEDEBUG=${WINEDEBUG:-fixme-all}
export WINEPREFIX=${WINEPREFIX:-$(get_wine_prefix)}

# Create Wine prefix if it doesn't exist (idempotent)
if ! is_wine_prefix_valid; then
    echo "🏗️ Creating new Wine prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"
    # Run a simple command to initialize the prefix
    wine wineboot --init || echo "⚠️ Wine prefix initialization failed, but continuing..."
else
    echo "✓ Wine prefix already initialized"
fi

# Persist environment variables so they reach the container's main process
# (see persist_env in deps.sh) as well as interactive steam shells
persist_env WINEARCH "${WINEARCH}"
persist_env WINEDEBUG "${WINEDEBUG}"
persist_env WINEPREFIX "${WINEPREFIX}"

echo "✅ Wine initialization complete"
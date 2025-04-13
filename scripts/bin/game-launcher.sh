#!/bin/bash
# game-launcher.sh - Unified game/server launcher for both Wine and Proton environments
# Usage: game-launcher.sh [--proton|--wine] [--appid APPID] [--install] PATH_TO_EXE [ARGS...]

set -Eeuo pipefail

# Default values
USE_PROTON="auto"  # auto, yes, no
APPID=""
INSTALL=false
EXECUTABLE=""
ARGS=()
GAME_DIR="/home/steam/game"  # Default install directory

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proton)
            USE_PROTON="yes"
            shift
            ;;
        --wine)
            USE_PROTON="no"
            shift
            ;;
        --appid)
            APPID="$2"
            shift 2
            ;;
        --install)
            INSTALL=true
            shift
            ;;
        *)
            EXECUTABLE="$1"
            shift
            ARGS=("$@")
            break
            ;;
    esac
done

# Validate required arguments
if [ -z "$EXECUTABLE" ]; then
    echo "Usage: game-launcher.sh [--proton|--wine] [--appid APPID] [--install] PATH_TO_EXE [ARGS...]"
    echo ""
    echo "Options:"
    echo "  --proton       Force using Proton"
    echo "  --wine         Force using Wine"
    echo "  --appid APPID  Steam App ID (for installation)"
    echo "  --install      Install/update the application before launching"
    echo ""
    echo "Examples:"
    echo "  game-launcher.sh --appid 1161040 --install --proton /home/steam/game/server.exe -port 28015"
    exit 1
fi

# Install/Update if requested
if [ "$INSTALL" = true ] && [ -n "$APPID" ]; then
    echo "📥 Installing/updating Steam AppID: $APPID to $GAME_DIR"
    
    # Create game directory if it doesn't exist
    mkdir -p "$GAME_DIR"
    
    # Check if we should force Windows platform type
    if [ "$USE_PROTON" = "yes" ] || [ "$USE_PROTON" = "auto" ] && command -v proton-run &>/dev/null; then
        PLATFORM_FLAG="+@sSteamCmdForcePlatformType windows"
    else
        PLATFORM_FLAG=""
    fi
    
    # Run the installation with force_install_dir to ensure consistent location
    steamcmd $PLATFORM_FLAG +login anonymous +force_install_dir "$GAME_DIR" +app_update "$APPID" validate +quit
    
    echo "✅ Installation/update completed to $GAME_DIR"
fi

# Detect execution environment if set to auto
if [ "$USE_PROTON" = "auto" ]; then
    if command -v proton-run &>/dev/null && [ -n "$PROTON_PATH" ]; then
        USE_PROTON="yes"
    elif command -v wine &>/dev/null; then
        USE_PROTON="no"
    else
        echo "❌ Neither Proton nor Wine is available. Cannot run Windows executables."
        exit 1
    fi
fi

# Check if the executable exists
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Executable not found: $EXECUTABLE"
    exit 1
fi

# Launch the application
echo "🚀 Launching: $EXECUTABLE ${ARGS[*]}"

if [ "$USE_PROTON" = "yes" ]; then
    echo "🎮 Using Proton"
    if command -v proton-run &>/dev/null; then
        proton-run "$EXECUTABLE" "${ARGS[@]}"
    else
        echo "❌ proton-run script not found"
        exit 1
    fi
else
    echo "🍷 Using Wine"
    wine "$EXECUTABLE" "${ARGS[@]}"
fi
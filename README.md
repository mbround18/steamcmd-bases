# SteamCMD Docker Base Images

[![Docker Release](https://github.com/mbround18/steamcmd-bases/actions/workflows/deployer.yaml/badge.svg)](https://github.com/mbround18/steamcmd-bases/actions/workflows/deployer.yaml)
[![Docker Pulls](https://img.shields.io/docker/pulls/mbround18/steamcmd.svg?style=flat-square)](https://hub.docker.com/r/mbround18/steamcmd)

This repository provides a set of Docker base images for running SteamCMD, with specialized versions for running Windows games through Wine and Proton.

## Available Images

Three Docker images are available from this repository:

1. **mbround18/steamcmd** - Base SteamCMD image for Linux-native games and applications
2. **mbround18/steamcmd-wine** - SteamCMD with Wine for basic Windows game support
3. **mbround18/steamcmd-proton** - SteamCMD with GloriousEggroll's Proton-GE for enhanced Windows game compatibility

## Image Tags

- `latest`: The most recent build from the main branch
- `[git-sha]`: Specific version tagged with the Git commit SHA

## Usage in Dockerfiles

### Basic SteamCMD (Linux Games)

```dockerfile
FROM mbround18/steamcmd:latest

# Install a Linux game
RUN steamcmd +login anonymous \
    +app_update 896660 validate \
    +quit

# Run the game
CMD ["/home/steam/Steam/steamapps/common/mygame/run.sh"]
```

### Using Wine for Windows Games

```dockerfile
FROM mbround18/steamcmd-wine:latest

# Install a Windows game
RUN steamcmd +@sSteamCmdForcePlatformType windows \
    +login anonymous \
    +app_update 896660 validate \
    +quit

# Set up game directory
ENV WINEDEBUG=-all
ENV WINEARCH=win64

# Run the game with Wine
CMD ["wine", "/home/steam/Steam/steamapps/common/mygame/Game.exe"]
```

### Using Proton for Windows Games

```dockerfile
FROM mbround18/steamcmd-proton:latest

# Install a Windows game
RUN steamcmd +login anonymous \
    +app_update 896660 validate \
    +quit

# Define game directory
ENV GAME_DIR=/home/steam/Steam/steamapps/common/mygame
ENV WINEPREFIX=/home/steam/.proton/pfx

# Set up Proton environment variables
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/steam/.steam/steam
ENV STEAM_COMPAT_DATA_PATH=/home/steam/.proton

# Run the game with Proton
CMD ["bash", "-c", "${PROTON_PATH} run ${GAME_DIR}/Game.exe -args"]
```

## Running Windows Games with Proton

Proton offers better compatibility for modern Windows games compared to standard Wine. The `mbround18/steamcmd-proton` image includes the latest GloriousEggroll Proton-GE custom build.

### Key Environment Variables

- `PROTON_PATH`: Path to the Proton binary (automatically set)
- `STEAM_COMPAT_CLIENT_INSTALL_PATH`: Steam installation path (already set)
- `STEAM_COMPAT_DATA_PATH`: Proton prefix location (already set to `/home/steam/.proton`)
- `WINEPREFIX`: Wine prefix location (should be set to `/home/steam/.proton/pfx` for consistency)

### Example: Running a Windows Game Server with Proton

```dockerfile
FROM mbround18/steamcmd-proton:latest

# Install game
RUN steamcmd +login anonymous +app_update 123456 validate +quit

# Game-specific environment variables
ENV SERVER_DIR=/home/steam/Steam/steamapps/common/mygame
ENV WINEPREFIX=/home/steam/.proton/pfx
ENV WINEDLLOVERRIDES="xaudio2_7=n,b"

# Create a startup script
RUN echo '#!/bin/bash \n\
${PROTON_PATH} run ${SERVER_DIR}/Server.exe -server -port=28015 \
' > /home/steam/start_server.sh && chmod +x /home/steam/start_server.sh

# Start the server
CMD ["/home/steam/start_server.sh"]
```

## Script System

These Docker images include a modular script system to make configuration and game management easier.

### Directory Structure

- `/opt/steamcmd-bases/scripts.d/*` - Automatically executed initialization scripts
- `/opt/steamcmd-bases/bin/*` - Utility scripts that can be manually called
- `/opt/steamcmd-bases/entrypoint.sh` - Main entrypoint that orchestrates everything

### Standardized Game Directory

All games installed using the provided utilities will be placed in `/home/steam/game` by default. This provides a consistent location for game files across containers.

### Available Utility Scripts

#### game-launcher

A unified script for launching games with either Wine or Proton:

```bash
# Install and run a game (automatically detects Wine or Proton)
game-launcher --appid 1161040 --install /home/steam/game/server.exe -port 28015

# Force using Proton
game-launcher --proton --appid 1161040 --install /home/steam/game/server.exe -port 28015
```

#### proton-run

Simplified interface for running executables with Proton:

```bash
proton-run /home/steam/game/server.exe -port 28015
```

#### proton-manager

Utility for managing multiple Proton versions:

```bash
# List available Proton versions from GitHub
proton-manager available

# Install a specific Proton version
proton-manager install GE-Proton8-2

# Switch to using a specific Proton version
proton-manager use GE-Proton8-2

# List installed versions
proton-manager list
```

#### proton-diagnose

Utility for troubleshooting Proton environments:

```bash
# Run diagnostics
proton-diagnose

# Initialize a fresh Wine prefix
proton-diagnose --init-prefix
```

## Extending with Custom Scripts

You can add your own initialization scripts or utilities to extend these images:

```dockerfile
FROM mbround18/steamcmd-proton:latest

# Add a custom initialization script (will run on container start)
COPY --chmod=755 my-custom-init.sh /opt/steamcmd-bases/scripts.d/50-my-custom-init.sh

# Add a custom utility
COPY --chmod=755 my-utility.sh /opt/steamcmd-bases/bin/my-utility
RUN ln -sf /opt/steamcmd-bases/bin/my-utility /usr/local/bin/my-utility
```

### Script Execution Order

Scripts in `/opt/steamcmd-bases/scripts.d/` are executed alphabetically on container startup. The included scripts follow this pattern:

- `00-common-init.sh` - Basic setup for all images
- `10-wine-init.sh` - Wine-specific initialization (Wine and Proton images)
- `20-proton-init.sh` - Proton-specific initialization (Proton images)
- `99-cleanup.sh` - Sets up cleanup handlers for container shutdown

## Advanced Configuration

### Using a Specific Proton Version

If you need a specific version of Proton-GE:

```dockerfile
FROM mbround18/steamcmd-proton:latest

# Download and install specific Proton version (if needed)
RUN mkdir -p /tmp/proton-ge \
    && cd /tmp/proton-ge \
    && curl -sL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton7-38/GE-Proton7-38.tar.gz" -o proton.tar.gz \
    && tar xzf proton.tar.gz -C /home/steam/.steam/root/compatibilitytools.d/ \
    && rm -rf /tmp/proton-ge

# Update PROTON_PATH to use the specific version
ENV PROTON_PATH=/home/steam/.steam/root/compatibilitytools.d/GE-Proton7-38/proton
```

### Using winetricks

The images include winetricks for installing additional components:

```dockerfile
FROM mbround18/steamcmd-wine:latest

# Use winetricks to install additional components
RUN winetricks --unattended dxvk vcrun2019
```

### Display Support

For games requiring a display (even for headless servers):

```dockerfile
FROM mbround18/steamcmd-proton:latest

# Install X virtual framebuffer (already included in the proton image)
ENV DISPLAY=:99
ENV SDL_VIDEODRIVER=x11

# Start Xvfb in the background when container starts
CMD Xvfb :99 -screen 0 1024x768x16 & \
    ${PROTON_PATH} run ${GAME_DIR}/Game.exe
```

## Troubleshooting

### Common Issues

1. **Missing libraries**: Some games may require additional libraries

   ```dockerfile
   RUN apt-get update && apt-get install -y \
       libgdiplus libsdl2-2.0-0 libvulkan1 libvulkan-dev
   ```

2. **Proton prefix issues**: Try creating a fresh prefix

   ```dockerfile
   RUN rm -rf /home/steam/.proton/pfx && \
       ${PROTON_PATH} run /bin/true
   ```

3. **32-bit application support**: Ensure 32-bit libraries are installed

   ```dockerfile
   RUN dpkg --add-architecture i386 && \
       apt-get update && \
       apt-get install -y libc6:i386 libstdc++6:i386
   ```

## Building the Images

To build the images locally:

```bash
make docker-build
```

To push the images:

```bash
make docker-push
```

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

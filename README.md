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

#### dockerify

A single tool for installing, running, and troubleshooting Wine/Proton (see [crates/dockerify](crates/dockerify)) - it replaces the old `proton-run`/`proton-manager`/`proton-diagnose` shell scripts:

```bash
# Install Wine or a specific/latest Proton-GE version
dockerify install wine
dockerify install proton --version GE-Proton9-20   # or --version latest

# Run an executable (auto-detects Wine vs Proton, preferring Proton)
dockerify run /home/steam/game/server.exe -port 28015
dockerify run --wine /opt/steamcmd-bases/bin/test-exe.exe --verbose
dockerify run --proton /opt/steamcmd-bases/bin/test-exe.exe --json

# Manage installed Proton-GE versions
dockerify proton list                    # installed versions
dockerify proton available               # versions on GitHub
dockerify proton use GE-Proton8-2        # switch the "current" symlink

# Diagnose the environment (installations, env vars, display, libraries)
dockerify diagnose
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

# Install a specific Proton-GE version and repoint "current" at it
RUN dockerify install proton --version GE-Proton7-38
```

`PROTON_PATH` stays pointed at `.../compatibilitytools.d/current/proton`, so no `ENV` override is needed.

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

Images are built with [`docker buildx bake`](https://docs.docker.com/build/bake/) via `docker-bake.hcl`, which defines the `base`, `wine`, and `proton` targets and their registry cache config in one place (used for both local builds and `--push`).

To build all three images locally (also builds the Rust `test-exe` binary first, since the `wine`/`proton` targets `COPY` it in):

```bash
make docker-build
```

To build a single target directly:

```bash
cargo build --release
docker buildx bake proton --load
```

To pin an exact GE-Proton release instead of whatever is newest on GitHub at build time:

```bash
PROTON_VERSION=GE-Proton9-20 docker buildx bake proton --load
```

To push the images (and cache) to the registry:

```bash
make docker-push
```

## System Management & Version Control (v2.0+)

This repository now includes enhanced dependency management and cross-platform testing to ensure reliability across Windows, Linux, and macOS environments.

### Core Features

- **Explicit Version Management**: OS, Wine, Proton, and SteamCMD versions are explicitly managed and detectable
- **Dependency Library**: Shell library (`scripts/lib/deps.sh`) provides functions for detecting and validating all components
- **Idempotent Scripts**: All initialization scripts can be safely run multiple times
- **Cross-Platform Testing**: Rust-based test executable validates functionality on Windows Server, Linux, and macOS
- **Multi-Stage Docker**: Efficient layer reuse across three image variants

### Key Maxims

1. **Always manage OS/Wine/Proton versions explicitly** - Every environment has detectable versions
2. **Dependency detection over assumption** - Always check before assuming tools are installed
3. **Idempotency** - Scripts must be safe to run repeatedly
4. **Cross-platform validation** - Test on real Windows, Linux, and macOS platforms
5. **Graceful degradation** - Non-critical failures don't block container startup
6. **Persistent environment** - Configuration survives across restarts
7. **Shared library design** - Common logic in `scripts/lib/deps.sh`
8. **Explicit user context** - All operations run as steam:1000 user

See [docs/maxims.md](docs/maxims.md) for full details.

### Architecture

The repository is organized as:

```text
.
├── crates/
│   └── test-exe/              # Rust binary for cross-platform testing
│       └── src/main.rs        # Test executable (Windows/Linux/Mac)
├── scripts/
│   ├── lib/
│   │   └── deps.sh            # Dependency management library
│   ├── bin/
│   │   └── dockerify run /opt/steamcmd-bases/bin/test-exe.exe       # Wine/Proton test wrapper
│   └── scripts.d/
│       ├── 00-common-init.sh  # Common initialization
│       ├── 10-wine-init.sh    # Wine environment setup
│       ├── 20-proton-init.sh  # Proton environment setup
│       └── 99-cleanup.sh      # Cleanup handlers
├── .github/workflows/
│   └── test-compatibility.yml # Multi-platform CI/CD tests
├── docs/
│   ├── maxims.md              # Design principles
│   └── architecture.md        # Technical architecture
└── Dockerfile                 # Multi-stage container build
```

See [docs/architecture.md](docs/architecture.md) for detailed technical design.

### Development: Building Test Executable

The Rust binary is used to validate Wine/Proton installations across platforms.

#### Local Development

```bash
# Build for your current platform
cargo build --release

# Test the binary locally
./target/release/test-exe --json
./target/release/test-exe --verbose

# See all options
./target/release/test-exe --help
```

#### Cross-Compilation (All Platforms)

Install cross-compilation tool:

```bash
cargo install cross
```

Build for all targets:

```bash
# Linux (native)
cargo build --release --target x86_64-unknown-linux-gnu

# Windows
cross build --release --target x86_64-pc-windows-gnu

# macOS
cross build --release --target x86_64-apple-darwin
```

Binaries are output to `target/*/release/test-exe*`

#### Integration with Docker

Before building Docker images, build the Linux test executable:

```bash
cargo build --release --target x86_64-unknown-linux-gnu
```

This binary is automatically copied into Docker images during build.

### Testing: Multi-Platform Validation

#### Local Testing

Test on your current system:

```bash
# Test directly
./target/release/test-exe --json

# Test through Wine (if installed)
wine ./target/release/test-exe --verbose
```

#### Docker Testing

Test inside containers:

```bash
# Build image (compose.yaml only runs pre-built images; see "Building the Images" above)
cargo build --release && docker buildx bake wine --load

# Run tests in container
docker compose run steamcmd-wine dockerify run /opt/steamcmd-bases/bin/test-exe.exe --json
```

#### CI/CD Testing (GitHub Actions)

The `.github/workflows/test-compatibility.yml` automatically:

1. **Builds** test-exe for Windows, Linux, and macOS
2. **Tests** on each platform (native execution)
3. **Tests** through Wine/Proton when available
4. **Builds** all Docker images
5. **Reports** compatibility matrix

Push to GitHub to trigger tests, or manually run:

```bash
gh workflow run test-compatibility.yml
```

### Dependency Management

All initialization scripts use the centralized `deps.sh` library for version detection and management.

#### Checking System Status

In containers or local environments:

```bash
# Source the library
source scripts/lib/deps.sh

# Check what's installed
detect_wine_version
detect_proton_version
get_os_type
get_os_version

# Check if components are valid
is_wine_installed && echo "Wine found"
is_proton_installed && echo "Proton found"
is_wine_prefix_valid && echo "Wine prefix initialized"

# Print summary
print_deps_summary
```

#### Installing Components

The library provides installation functions for different platforms:

```bash
# Install Wine on Debian/Ubuntu
install_wine_debian "stable"

# Install Wine on macOS
install_wine_macos

# Install Proton-GE
install_proton_ge "latest"
```

#### Custom Initialization

To add custom dependency management:

1. Edit `scripts/lib/deps.sh` to add detection/installation functions
2. Create new init script in `scripts/scripts.d/` (use numeric prefix for ordering)
3. Source `deps.sh` and use functions
4. Copy script into Dockerfile if container-based

See [docs/maxims.md#implementation-guidelines](docs/maxims.md#implementation-guidelines) for examples.

### Diagnostics & Troubleshooting

#### Verify Installation

```bash
# Check all components
source scripts/lib/deps.sh
print_deps_summary
```

#### Run Diagnostics in Container

```bash
docker compose run steamcmd-proton dockerify diagnose
```

#### Test Wine/Proton Compatibility

```bash
# Direct test
docker compose run steamcmd-wine dockerify run /opt/steamcmd-bases/bin/test-exe.exe --json

# With verbose output
docker compose run steamcmd-wine dockerify run --wine /opt/steamcmd-bases/bin/test-exe.exe --verbose

# Force Proton (skip Wine)
docker compose run steamcmd-proton dockerify run --proton /opt/steamcmd-bases/bin/test-exe.exe --json
```

#### Check Environment Variables

```bash
# In container, after initialization
docker compose run steamcmd-wine env | grep WINE

# Check persisted variables
docker compose run steamcmd-wine cat /home/steam/.bashrc
```

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

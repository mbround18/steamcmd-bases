# Architecture Guide

This document describes the high-level architecture of steamcmd-bases v2, which combines Docker containers, shell script libraries, and Rust-based cross-platform testing tools.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    steamcmd-bases Repository                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────┐             │
│  │  Rust Crates     │         │  Shell Scripts   │             │
│  ├──────────────────┤         ├──────────────────┤             │
│  │ test-exe (binary)│         │ deps.sh (lib)    │             │
│  │  - Outputs JSON  │         │ init scripts     │             │
│  │  - Multi-target  │         │ test-wine.sh     │             │
│  │  - Win/Lin/Mac   │         │ proton-*.sh      │             │
│  └──────────────────┘         └──────────────────┘             │
│         ↓                              ↓                         │
│  ┌──────────────────────────────────────────────┐              │
│  │     Docker Images (3 Variants)               │              │
│  ├──────────────────────────────────────────────┤              │
│  │ mbround18/steamcmd:base      (SteamCMD only) │              │
│  │ mbround18/steamcmd:wine      (+ Wine)        │              │
│  │ mbround18/steamcmd:proton    (+ Proton-GE)   │              │
│  └──────────────────────────────────────────────┘              │
│         ↓                                                       │
│  ┌──────────────────────────────────────────────┐              │
│  │  GitHub Actions Test Matrix                  │              │
│  ├──────────────────────────────────────────────┤              │
│  │ Ubuntu 24.04  → Wine + test-exe              │              │
│  │ Windows Server → Native + test-exe           │              │
│  │ macOS Latest  → Wine (optional) + test-exe   │              │
│  └──────────────────────────────────────────────┘              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Rust Workspace (`crates/`)

#### `test-exe` Binary

- **Purpose:** Cross-platform executable for validating Wine/Proton functionality
- **Built Targets:**
  - `x86_64-unknown-linux-gnu` → Linux binary (no extension)
  - `x86_64-pc-windows-gnu` → Windows executable (.exe)
  - `x86_64-apple-darwin` → macOS Mach-O binary
- **Outputs:**
  - Text format: Human-readable with test status indicators
  - JSON format: Structured output with schema validation
- **Dependencies:** serde_json, chrono (minimal)
- **Integration:** Copied into Docker images, used by test-wine.sh wrapper

### 2. Shell Script Library (`scripts/lib/`)

#### `deps.sh`

Core library providing system and dependency management functions:

**OS Detection:**

- `get_os_type()` - Returns: ubuntu, debian, centos, rhel, macos, windows
- `get_os_version()` - Returns: semantic version

**Wine Functions:**

- `detect_wine_version()` - Parses wine --version output
- `is_wine_installed()` - Binary check
- `is_wine_prefix_valid()` - Checks drive_c existence
- `get_wine_prefix()` - Returns WINEPREFIX path
- `install_wine_debian()` - Platform-specific installation
- `install_wine_macos()` - Homebrew integration

**Proton Functions:**

- `detect_proton_version()` - Finds latest GE-Proton directory
- `get_proton_version_string()` - Extracts version number
- `is_proton_installed()` - Binary check
- `install_proton_ge()` - GitHub release download + extraction

**SteamCMD Functions:**

- `is_steamcmd_installed()` - Binary check
- `get_steamcmd_path()` - Returns installation directory
- `validate_steamcmd()` - Runs quick test

**Version Checking:**

- `check_wine_version(min_version)` - Semantic version comparison
- `check_proton_version(min_version)` - Semantic version comparison

**Utilities:**

- `print_deps_summary()` - Formatted system status report

### 3. Initialization Scripts (`scripts/scripts.d/`)

Run in alphabetical order by entrypoint:

**00-common-init.sh** (All images)

- Creates /home/steam/data, /home/steam/logs
- Initializes SteamCMD
- Sets directory permissions

**10-wine-init.sh** (Wine + Proton images)

- Sources deps.sh
- Detects Wine installation via `is_wine_installed()`
- Sets WINEARCH, WINEDEBUG, WINEPREFIX
- Creates Wine prefix with wineboot --init (idempotent)
- Persists environment to ~/.bashrc (idempotent)

**20-proton-init.sh** (Proton image only)

- Sources deps.sh
- Detects Proton via `detect_proton_version()`
- Sets PROTON_PATH, STEAM_COMPAT_* variables
- Creates Proton prefix (idempotent)
- Starts Xvfb for headless display
- Persists environment to ~/.bashrc (idempotent)

**99-cleanup.sh** (Proton image only)

- Registers signal handlers (SIGTERM, SIGINT)
- Terminates Xvfb on container exit
- Cleans temporary files

### 4. Test Wrapper (`scripts/bin/test-wine.sh`)

Orchestrates test-exe execution:

**Modes:**

- `--proton` - Force Proton execution
- `--wine` - Force Wine execution
- `--json` - Structured output (default: text)
- `--verbose` - Detailed diagnostics

**Flow:**

1. Parse arguments
2. Check test executable exists
3. Auto-detect or validate platform (Wine vs Proton)
4. Run test-exe with appropriate platform
5. Validate output format (JSON schema or text regex)
6. Return appropriate exit code

**Integration:** Called during Docker build verification, CI/CD testing

### 5. Docker Multi-Stage Build

#### Stage 1: `steamcmd-base`

- Ubuntu 24.04
- SteamCMD installation
- steam user (UID 1000)
- Base scripts and library

#### Stage 2: `wine-base`

- Extends steamcmd-base
- WineHQ official repository + stable
- Winetricks, cabextract
- Wine init script
- test-wine.sh wrapper
- Pre-built test-exe binary

#### Stage 3: `proton-base`

- Extends wine-base
- Auto-downloads latest Proton-GE from GitHub
- Xvfb for headless display
- Proton init script
- proton-*.sh utility scripts

#### Final Targets

- `base` → minimal SteamCMD
- `wine` → SteamCMD + Wine
- `proton` → SteamCMD + Wine + Proton-GE

### 6. GitHub Actions Workflow (`test-compatibility.yml`)

**Jobs:**

1. **build-test-exe** (Matrix: Linux, Windows, macOS)
   - Builds Rust binary for each target
   - Uses `cross` for non-native targets
   - Uploads as artifacts

2. **test-linux**
   - Downloads Linux binary
   - Runs test-exe natively
   - Installs Wine
   - Runs test-exe through Wine
   - Reports results

3. **test-windows**
   - Downloads Windows binary
   - Runs test-exe natively on Windows Server
   - Validates exit codes

4. **test-macos**
   - Downloads macOS binary
   - Runs test-exe natively
   - Attempts Wine installation via Homebrew
   - Tests through Wine if available

5. **test-docker**
   - Downloads pre-built binary
   - Builds all three Docker images
   - Validates image construction

6. **compatibility-matrix**
   - Aggregate results
   - Generates compatibility table

## Data Flow: Container Startup

```
Container Start
    ↓
docker-entrypoint.sh
    ├─ Print system info
    ├─ Discover scripts.d/* (00-*, 10-*, 20-*, 99-*)
    │
    ├─ Run 00-common-init.sh
    │  ├─ mkdir /home/steam/data, /home/steam/logs
    │  └─ steamcmd +quit (verify)
    │
    ├─ Run 10-wine-init.sh (if wine-base or proton-base)
    │  ├─ source /opt/steamcmd-bases/lib/deps.sh
    │  ├─ is_wine_installed? → continue or skip
    │  ├─ mkdir WINEPREFIX
    │  ├─ wine wineboot --init
    │  └─ echo "export WINEPREFIX=..." >> ~/.bashrc
    │
    ├─ Run 20-proton-init.sh (if proton-base only)
    │  ├─ source /opt/steamcmd-bases/lib/deps.sh
    │  ├─ detect_proton_version()
    │  ├─ mkdir STEAM_COMPAT_DATA_PATH
    │  ├─ proton run /bin/true
    │  ├─ start Xvfb :99 if DISPLAY unset
    │  └─ echo "export PROTON_PATH=..." >> ~/.bashrc
    │
    ├─ Run 99-cleanup.sh (if proton-base only)
    │  └─ trap Xvfb cleanup on signals
    │
    └─ Execute CMD (steamcmd +quit)
```

## Data Flow: Test Execution

```
GitHub Actions: test-compatibility.yml
    ├─ Build test-exe for [Linux, Windows, macOS]
    ├─ Distribute artifacts
    │
    ├─ test-linux:
    │  ├─ ./test-exe --json
    │  │  └─ JSON: {"success":true, "tests":{...}, ...}
    │  ├─ Install Wine
    │  └─ wine ./test-exe --json
    │     └─ (if successful: test-exe ran through Wine)
    │
    ├─ test-windows:
    │  └─ test-exe.exe --json (native)
    │     └─ JSON output on Windows Server
    │
    └─ test-macos:
        ├─ ./test-exe --json (native)
        ├─ brew install wine
        └─ wine ./test-exe --json (if Wine installed)
```

## Deployment Strategy

### Local Development

```bash
# Build Rust binary
cargo build --release

# Test locally
./target/release/test-exe --json

# Build Docker images
docker compose build steamcmd-wine
docker compose build steamcmd-proton

# Test in container
docker compose run steamcmd-wine test-wine.sh --json
```

### CI/CD Pipeline

```bash
# GitHub Actions automatically:
# 1. Builds test-exe for all targets
# 2. Tests on three OSes
# 3. Builds Docker images
# 4. Generates compatibility matrix
```

### Registry Deployment

```bash
# Push to Docker Hub (requires credentials)
docker compose push

# Tags: mbround18/steamcmd:wine-${VERSION}
#       mbround18/steamcmd:proton-${VERSION}
```

## Version Management

### Semantic Versioning

- **Major:** Breaking changes (new dependency requirements)
- **Minor:** New features (additional platforms, tools)
- **Patch:** Fixes (bug fixes, minor updates)

### Component Versions

- **Base OS:** Ubuntu 24.04 (configurable via ARG)
- **Wine:** Latest stable from WineHQ (pinned per build)
- **Proton-GE:** Latest from GloriousEggroll (auto-updated)
- **test-exe:** Crate version (Cargo.toml)
- **Docker images:** Git SHA tag (CI/CD) or explicit version

## Key Design Patterns

### 1. Graceful Degradation

- Init scripts continue on non-critical failures
- Test suite works without Wine/Proton installed
- Missing tools trigger skips, not errors

### 2. Idempotency

- All scripts check for existing state
- Environment variables appended, not overwritten
- Repeated runs are safe

### 3. Library-Based Design

- deps.sh is sourced by multiple scripts
- Functions are unit-testable
- Version detection is centralized

### 4. Docker Multi-Stage

- Reusable steamcmd-base for all images
- Minimal final image size
- Clear dependency hierarchy

### 5. Cross-Platform Testing

- Real execution on target platforms (not emulation)
- Matrix approach for scalability
- Artifact caching for efficiency

## Future Extensions

### Adding Support for New OS

1. Update `get_os_type()` in deps.sh
2. Implement `install_wine_<os>()`
3. Add GitHub Actions job
4. Test on CI/CD

### Adding New Diagnostic Tool

1. Create script in `scripts/bin/`
2. Copy into Docker image
3. Create symlink in /usr/local/bin
4. Document in README

### Migrating to Podman

- Replace docker compose with podman-compose
- No script changes required (POSIX shell compatible)
- Volume mounts work identically

## See Also

- [System Maxims](./maxims.md) - Design principles
- [README.md](../README.md) - User guide
- Dockerfile - Container definitions
- compose.yaml - Service definitions

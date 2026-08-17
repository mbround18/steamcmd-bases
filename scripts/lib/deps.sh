#!/usr/bin/env bash
# shellcheck disable=SC2181
#
# Dependency Management Library
# Provides functions for managing Wine, Proton, SteamCMD, and OS-level dependencies
# Encodes system management maxims: always manage OS/deps/Wine/Proton versions, idempotency, graceful degradation
#
# Usage: source /opt/steamcmd-bases/lib/deps.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# OS Detection Functions
# ============================================================================

# Detect the operating system type
# Returns: ubuntu, debian, centos, rhel, macos, windows
get_os_type() {
    local os_type=""
    
    if [[ -f /etc/os-release ]]; then
        # Linux systems
        source /etc/os-release
        case "${ID}" in
            ubuntu|debian)
                os_type="${ID}"
                ;;
            centos|rhel|fedora)
                os_type="centos"
                ;;
            *)
                os_type="${ID}"
                ;;
        esac
    elif [[ $(uname -s) == "Darwin" ]]; then
        os_type="macos"
    elif [[ $(uname -s) == "MINGW64" ]] || [[ $(uname -s) == "MINGW32" ]]; then
        os_type="windows"
    else
        os_type="unknown"
    fi
    
    echo "${os_type}"
}

# Detect OS version
# Returns: version string (e.g., "22.04", "11.0", "13")
get_os_version() {
    local os_type
    os_type=$(get_os_type)
    
    case "${os_type}" in
        ubuntu|debian)
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                echo "${VERSION_ID}"
            fi
            ;;
        centos|rhel)
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                echo "${VERSION_ID}"
            fi
            ;;
        macos)
            sw_vers -productVersion
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ============================================================================
# Wine Detection Functions
# ============================================================================

# Detect installed Wine version
# Returns: version string or empty if not installed
detect_wine_version() {
    if command -v wine &> /dev/null; then
        wine --version 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Check if Wine is installed
# Returns: 0 if installed, 1 otherwise
is_wine_installed() {
    [[ -n $(detect_wine_version) ]] && return 0 || return 1
}

# Detect Wine prefix location
# Returns: path to Wine prefix
get_wine_prefix() {
    echo "${WINEPREFIX:=/home/steam/.wine}"
}

# Check if Wine prefix exists and is initialized
# Returns: 0 if valid, 1 otherwise
is_wine_prefix_valid() {
    local prefix
    prefix=$(get_wine_prefix)
    [[ -d "${prefix}/drive_c" ]] && return 0 || return 1
}

# ============================================================================
# Proton Detection Functions
# ============================================================================

# Detect installed Proton version
# Returns: path to Proton directory or empty if not installed
detect_proton_version() {
    local proton_path
    local steam_dir="${HOME}/.steam/root"
    local compat_dir="${steam_dir}/compatibilitytools.d"

    # Check PROTON_PATH environment variable first
    if [[ -n "${PROTON_PATH:-}" ]] && [[ -d "${PROTON_PATH}" ]]; then
        echo "${PROTON_PATH}"
        return 0
    fi

    # Respect the "current" symlink maintained by the Dockerfile build and
    # `dockerify install proton`/`dockerify proton use`, so a pinned version
    # isn't silently overridden by whichever GE-Proton* directory sorts highest.
    if [[ -L "${compat_dir}/current" ]] && [[ -d "${compat_dir}/current" ]]; then
        echo "${compat_dir}/current"
        return 0
    fi

    # Fall back to the newest installed Proton-GE
    if [[ -d "${compat_dir}" ]]; then
        proton_path=$(find "${compat_dir}" -maxdepth 1 -type d -name "GE-Proton*" | sort -V | tail -n1)
        if [[ -n "${proton_path}" ]]; then
            echo "${proton_path}"
            return 0
        fi
    fi

    echo ""
    return 1
}

# Check if Proton is installed
# Returns: 0 if installed, 1 otherwise
is_proton_installed() {
    [[ -n $(detect_proton_version) ]] && return 0 || return 1
}

# Get Proton version string (e.g., "8.3", "8.26")
# Returns: version number or empty if not available
get_proton_version_string() {
    local proton_path
    proton_path=$(detect_proton_version)
    
    if [[ -z "${proton_path}" ]]; then
        echo ""
        return 1
    fi

    # Resolve symlinks (e.g. the "current" pointer) so we read the real
    # GE-Proton directory name rather than "current" itself
    proton_path=$(readlink -f "${proton_path}" 2>/dev/null || echo "${proton_path}")

    # Extract version from directory name (e.g., "GE-Proton8.3-1" -> "8.3")
    basename "${proton_path}" | grep -oP 'Proton\K[0-9.]+' || echo ""
}

# ============================================================================
# SteamCMD Detection Functions
# ============================================================================

# Check if SteamCMD is installed
# Returns: 0 if installed, 1 otherwise
is_steamcmd_installed() {
    command -v steamcmd &> /dev/null && return 0 || return 1
}

# Get SteamCMD installation path
# Returns: path to steamcmd directory
get_steamcmd_path() {
    echo "${STEAMCMD_PATH:=/root/.local/share/Steam/steamcmd}"
}

# Validate SteamCMD installation
# Returns: 0 if valid, 1 otherwise
validate_steamcmd() {
    local steamcmd_path
    steamcmd_path=$(get_steamcmd_path)
    
    if [[ ! -f "${steamcmd_path}/steamcmd.sh" ]]; then
        return 1
    fi
    
    # Test SteamCMD can run (quick validation)
    if timeout 10 "${steamcmd_path}/steamcmd.sh" +quit &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Installation Functions (Ubuntu/Debian)
# ============================================================================

# Install Wine on Debian/Ubuntu systems
install_wine_debian() {
    local wine_version="${1:-stable}"
    
    if is_wine_installed; then
        echo -e "${GREEN}✓${NC} Wine already installed: $(detect_wine_version)"
        return 0
    fi
    
    echo -e "${BLUE}→${NC} Installing Wine (${wine_version})..."
    
    # Add WineHQ repository (keyring-based, matches the Dockerfile's approach;
    # apt-key is deprecated/removed on current Debian/Ubuntu releases)
    if ! grep -q "winehq.org" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        sudo mkdir -pm755 /etc/apt/keyrings

        sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || {
            echo -e "${RED}✗${NC} Failed to add Wine GPG key"
            return 1
        }
        sudo chmod 644 /etc/apt/keyrings/winehq-archive.key

        sudo wget -NP /etc/apt/sources.list.d/ "https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -cs)/winehq-$(lsb_release -cs).sources" || {
            echo -e "${RED}✗${NC} Failed to add Wine repository"
            return 1
        }
    fi
    
    # Install Wine
    sudo apt-get update || {
        echo -e "${RED}✗${NC} Failed to update package list"
        return 1
    }
    
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        --install-recommends winehq-stable \
        winetricks cabextract || {
        echo -e "${RED}✗${NC} Failed to install Wine"
        return 1
    }
    
    echo -e "${GREEN}✓${NC} Wine installed: $(detect_wine_version)"
    return 0
}

# Install Proton-GE on Linux systems
install_proton_ge() {
    local version="${1:-latest}"
    
    if is_proton_installed; then
        echo -e "${GREEN}✓${NC} Proton already installed at $(detect_proton_version)"
        return 0
    fi
    
    echo -e "${BLUE}→${NC} Installing Proton-GE (${version})..."
    
    local steam_dir="${HOME}/.steam/root"
    local compat_dir="${steam_dir}/compatibilitytools.d"
    mkdir -p "${compat_dir}"
    
    # Fetch latest release info from GitHub
    local release_url
    if [[ "${version}" == "latest" ]]; then
        release_url=$(curl -s "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases" \
            | grep -i "browser_download_url.*\.tar\.gz" \
            | head -n1 \
            | cut -d'"' -f4)
    else
        # TODO: Handle specific version requests
        release_url=$(curl -s "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases" \
            | grep -i "browser_download_url.*\.tar\.gz" \
            | grep "${version}" \
            | head -n1 \
            | cut -d'"' -f4)
    fi
    
    if [[ -z "${release_url}" ]]; then
        echo -e "${RED}✗${NC} Failed to find Proton-GE release"
        return 1
    fi
    
    # Download and extract
    echo -e "${BLUE}→${NC} Downloading ${release_url##*/}..."
    cd "${compat_dir}" || return 1
    
    if ! curl -L "${release_url}" -o proton.tar.gz; then
        echo -e "${RED}✗${NC} Failed to download Proton-GE"
        return 1
    fi
    
    if ! tar -xzf proton.tar.gz; then
        echo -e "${RED}✗${NC} Failed to extract Proton-GE"
        rm -f proton.tar.gz
        return 1
    fi
    
    rm -f proton.tar.gz
    echo -e "${GREEN}✓${NC} Proton-GE installed at $(detect_proton_version)"
    return 0
}

# ============================================================================
# Installation Functions (macOS)
# ============================================================================

# Install Wine on macOS using Homebrew
install_wine_macos() {
    if is_wine_installed; then
        echo -e "${GREEN}✓${NC} Wine already installed: $(detect_wine_version)"
        return 0
    fi
    
    echo -e "${BLUE}→${NC} Installing Wine (macOS via Homebrew)..."
    
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}✗${NC} Homebrew not installed. Please install from https://brew.sh"
        return 1
    fi
    
    if ! brew install wine; then
        echo -e "${RED}✗${NC} Failed to install Wine via Homebrew"
        return 1
    fi
    
    echo -e "${GREEN}✓${NC} Wine installed: $(detect_wine_version)"
    return 0
}

# ============================================================================
# Version Check Functions
# ============================================================================

# Check if Wine version meets minimum requirement
# Args: minimum_version (e.g., "8.0")
# Returns: 0 if meets requirement, 1 otherwise
check_wine_version() {
    local min_version="${1:?Minimum Wine version required}"
    local current_version
    
    current_version=$(detect_wine_version | grep -oP '\d+\.\d+' || echo "0.0")
    
    # Simple numeric version comparison (8.0 vs 8.5, etc.)
    if (( $(echo "${current_version} >= ${min_version}" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# Check if Proton version meets minimum requirement
# Args: minimum_version (e.g., "8.0")
# Returns: 0 if meets requirement, 1 otherwise
check_proton_version() {
    local min_version="${1:?Minimum Proton version required}"
    local current_version
    
    current_version=$(get_proton_version_string || echo "0.0")
    
    if (( $(echo "${current_version} >= ${min_version}" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Environment Persistence Functions
# ============================================================================

# Persist an environment variable so it is visible to:
#   1. the current shell (export)
#   2. the container's main process, via a runtime env file that
#      entrypoint.sh sources right before `exec "$@"` (init scripts run as
#      separate processes, so a plain `export` here would otherwise be lost
#      by the time the CMD is exec'd)
#   3. interactive `steam` shells, via ~/.bashrc (best-effort convenience)
#
# Usage: persist_env WINEPREFIX /home/steam/.wine
persist_env() {
    local name="$1"
    local value="$2"
    local runtime_env="${STEAMCMD_BASES_RUNTIME_ENV:-}"

    export "${name}=${value}"

    if [[ -n "${runtime_env}" ]]; then
        touch "${runtime_env}" 2>/dev/null || true
        grep -v "^export ${name}=" "${runtime_env}" > "${runtime_env}.tmp" 2>/dev/null || true
        mv "${runtime_env}.tmp" "${runtime_env}" 2>/dev/null || true
        echo "export ${name}=${value}" >> "${runtime_env}"
    fi

    if [[ "$(id -u)" == "1000" ]] && [[ -f /home/steam/.bashrc ]]; then
        sed -i "/^export ${name}=/d" /home/steam/.bashrc
        echo "export ${name}=${value}" >> /home/steam/.bashrc
    fi
}

# ============================================================================
# Summary Functions
# ============================================================================

# Print system dependencies summary
print_deps_summary() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}System Dependencies Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # OS Info
    local os_type os_version
    os_type=$(get_os_type)
    os_version=$(get_os_version)
    echo -e "  OS: ${os_type} ${os_version}"
    echo ""
    
    # SteamCMD
    echo -e "  SteamCMD:"
    if is_steamcmd_installed; then
        echo -e "    ${GREEN}✓${NC} Installed at $(get_steamcmd_path)"
    else
        echo -e "    ${RED}✗${NC} Not installed"
    fi
    echo ""
    
    # Wine
    echo -e "  Wine:"
    if is_wine_installed; then
        echo -e "    ${GREEN}✓${NC} $(detect_wine_version)"
        echo -e "    ${GREEN}✓${NC} Prefix: $(get_wine_prefix)"
        if is_wine_prefix_valid; then
            echo -e "    ${GREEN}✓${NC} Prefix initialized"
        else
            echo -e "    ${YELLOW}⚠${NC} Prefix not initialized"
        fi
    else
        echo -e "    ${RED}✗${NC} Not installed"
    fi
    echo ""
    
    # Proton
    echo -e "  Proton-GE:"
    if is_proton_installed; then
        echo -e "    ${GREEN}✓${NC} $(get_proton_version_string) installed"
        echo -e "    ${GREEN}✓${NC} Path: $(detect_proton_version)"
    else
        echo -e "    ${RED}✗${NC} Not installed"
    fi
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

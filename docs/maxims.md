# System Management Maxims

This document establishes the core principles that guide the steamcmd-bases project architecture and implementation. These maxims ensure reproducibility, reliability, and proper dependency management across Windows, Linux, and macOS environments.

## Core Maxims

### 1. Always Manage OS/Wine/Proton Versions Explicitly

**Principle:** Every environment (Docker container, CI/CD runner, local development) must have explicit, detectable versions of the base OS, Wine, and Proton.

**Implementation:**

- Dockerfile pins Ubuntu version (default: 24.04)
- SteamCMD is installed from official repository (auto-pinned to stable)
- Wine version is specified via WineHQ official repository (winehq-stable)
- Proton-GE version is auto-detected from latest GitHub release or explicitly pinned
- Shell library `deps.sh` provides `detect_wine_version()`, `detect_proton_version()`, `get_os_version()` functions

**Rationale:** Version mismatches cause silent failures. Explicit versioning enables reproducibility and debugging.

### 2. Dependency Detection Over Assumption

**Principle:** Never assume a tool or library is installed. Always detect, validate, and report its presence.

**Implementation:**

- `deps.sh` provides functions for checking installation: `is_wine_installed()`, `is_proton_installed()`, `is_steamcmd_installed()`
- Initialization scripts skip gracefully if dependencies aren't available
- Test executable validates environment before claiming success
- Diagnostic tools (`proton-diagnose.sh`) check every component explicitly

**Rationale:** Silent failures are catastrophic in CI/CD and production. Explicit detection enables graceful degradation.

### 3. Idempotency: Scripts Must Be Safe to Run Repeatedly

**Principle:** Running the same script multiple times must produce the same result without errors or side effects.

**Implementation:**

- All initialization scripts check if setup is already done before modifying state
- `deps.sh` includes idempotent wrappers: `is_wine_prefix_valid()`, checking existing state
- Docker CMD can be repeated without corrupting prefixes
- Environment variables are only appended to `.bashrc` if not already present

**Rationale:** Idempotency enables safe re-runs during debugging, updates, and troubleshooting.

### 4. Cross-Platform Test Validation

**Principle:** Compatibility must be validated through actual execution on target platforms (Windows, Linux, macOS).

**Implementation:**

- Rust-based test executable (`test-exe`) is built for multiple targets:
  - `x86_64-pc-windows-gnu` (Windows Server)
  - `x86_64-unknown-linux-gnu` (Linux/Ubuntu)
  - `x86_64-apple-darwin` (macOS)
- GitHub Actions matrix tests on all three platforms
- Test executable produces predictable JSON and text output for validation
- `test-wine.sh` wrapper runs test through Wine/Proton and validates results

**Rationale:** Real platform testing catches issues that static analysis misses. Emulation is less reliable than native execution.

### 5. Graceful Degradation Over Hard Failures

**Principle:** Non-critical failures should never block container startup or workflow completion.

**Implementation:**

- Init scripts use `continue-on-error` pattern: `command || echo "⚠️ Warning..."`
- Initialization script failures log warnings but allow container to proceed
- Test suite can complete even if Wine/Proton aren't available
- Fallback mechanisms: auto-detect latest Proton, skip Wine init if not installed

**Rationale:** Systems should degrade gracefully rather than crash. Users need partial functionality during failures.

### 6. Environment Variable Persistence

**Principle:** Configuration set during initialization must survive across container restarts and user logins.

**Implementation:**

- Init scripts append to `.bashrc` (not just export in current shell)
- Variables are tagged with comments: `# (managed by steamcmd-bases)`
- Idempotent appends prevent duplicate entries
- PROTON_PATH, WINEPREFIX, etc. are persisted by all init scripts

**Rationale:** Transient environment variables are lost on logout/restart, breaking subsequent commands.

### 7. Shared Library Over Duplication

**Principle:** Common logic must live in a single, sourced library (`deps.sh`) to ensure consistency.

**Implementation:**

- `scripts/lib/deps.sh` contains all detection and validation functions
- All init scripts source this library
- Functions are documented with usage examples
- Library is copied into Docker image at standard path

**Rationale:** Duplicated logic causes bugs and inconsistency. Centralized logic ensures all scripts behave identically.

### 8. Explicit User Context (steam:1000)

**Principle:** All game-related operations run as the `steam` user (UID 1000) with minimal privilege escalation.

**Implementation:**

- Non-root user created in Dockerfile
- Game directories owned by steam:steam
- Sudoers access only for necessary privileged operations
- Prefixes (Wine, Proton) initialized under steam user context

**Rationale:** Security isolation prevents container breaking out. Non-root operation is safer and more portable.

## Implementation Guidelines

### Adding New Dependency Checks

1. Add function to `scripts/lib/deps.sh`:

```bash
is_tool_installed() {
    command -v tool &> /dev/null && return 0 || return 1
}

detect_tool_version() {
    if is_tool_installed; then
        tool --version 2>/dev/null || echo ""
    else
        echo ""
    fi
}
```

2. Use in init scripts:

```bash
source /opt/steamcmd-bases/lib/deps.sh
if ! is_tool_installed; then
    echo "Tool not found, skipping init"
    exit 0
fi
```

### Adding New Platform Support

1. Update `get_os_type()` in `deps.sh` to detect new OS
2. Implement platform-specific install functions:
   - `install_wine_<platform>()`
   - `install_proton_ge_<platform>()`
3. Add GitHub Actions job for new platform (`.github/workflows/test-compatibility.yml`)
4. Update Dockerfile (if container-based) with platform-specific packages

### Testing Changes

1. Test init script idempotency:

```bash
bash ./scripts/scripts.d/10-wine-init.sh
bash ./scripts/scripts.d/10-wine-init.sh  # Should succeed without errors
```

2. Test deps.sh functions:

```bash
source scripts/lib/deps.sh
detect_wine_version
is_wine_installed && echo "✓ Wine found"
```

3. Test on Docker:

```bash
docker compose build steamcmd-wine
docker compose run steamcmd-wine /opt/steamcmd-bases/bin/test-wine.sh --json
```

4. Validate cross-platform (via GitHub Actions):
   - Create PR and watch test-compatibility.yml results

## Version Management Strategy

### SteamCMD

- **Pinning:** Official Ubuntu repository (auto-updates with apt)
- **Detection:** `is_steamcmd_installed()` checks for binary
- **Override:** `STEAMCMD_PATH` environment variable

### Wine

- **Pinning:** WineHQ official stable repository
- **Detection:** `detect_wine_version()` parses `wine --version`
- **Override:** `WINEPREFIX`, `WINEARCH`, `WINEDEBUG` environment variables

### Proton-GE

- **Pinning:** Latest GitHub release from GloriousEggroll (auto-detected on container build)
- **Detection:** `detect_proton_version()` finds `GE-Proton*` directories
- **Override:** `PROTON_PATH` environment variable

### Base OS

- **Pinning:** Dockerfile ARG `UBUNTU_VERSION` (default: 24.04)
- **Override:** Build argument: `docker build --build-arg UBUNTU_VERSION=22.04 ...`

## Troubleshooting

### Script Fails on Multiple Runs

**Root Cause:** Not idempotent (checking for existence or modifying unconditionally)

**Fix:** Add `if [[ ! -d ... ]]` or `if ! grep -q ...` guards before modifications

### Environment Variables Not Persistent

**Root Cause:** Set in shell session, not in `.bashrc`

**Fix:** Append to `/home/steam/.bashrc` inside script

### Wine/Proton Commands Fail

**Root Cause:** Version mismatch or missing dependencies

**Fix:** Run `proton-diagnose.sh` to validate environment

### Docker Build Fails to Find Binary

**Root Cause:** Test executable not pre-built

**Fix:** Run `cargo build --release` before `docker compose build`

## See Also

- [Architecture Guide](./architecture.md) - High-level design overview
- [Development Setup](../README.md#development) - Getting started for contributors
- [Troubleshooting](../README.md#troubleshooting) - Common issues and solutions

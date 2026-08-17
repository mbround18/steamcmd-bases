# Development Guide

This guide walks through contributing to steamcmd-bases, including building, testing, and extending the system.

## Prerequisites

### Required

- Git
- Docker & Docker Compose
- Rust 1.70+ (via rustup)
- Bash 4+

### Optional (for cross-compilation)

- `cross` CLI tool (`cargo install cross`)
- macOS or GitHub Actions for native testing on all platforms

## Local Setup

### 1. Clone and Enter Repository

```bash
git clone https://github.com/mbround18/steamcmd-bases.git
cd steamcmd-bases
```

### 2. Build Rust Test Executable

```bash
# Build for your current platform (Linux)
cargo build --release

# Verify it works
./target/release/test-exe --json
./target/release/test-exe --verbose
```

### 3. Test Shell Library

```bash
# Source the dependency library
source scripts/lib/deps.sh

# Test functions
get_os_type
get_os_version
is_steamcmd_installed

# Print summary
print_deps_summary
```

### 4. Build Docker Images

```bash
# Build all three images
docker compose build

# Or build specific target
docker compose build steamcmd-proton
```

### 5. Test in Container

```bash
# Run test in wine image
docker compose run steamcmd-wine /opt/steamcmd-bases/bin/dockerify run /opt/steamcmd-bases/bin/test-exe.exe --json

# Run test in proton image
docker compose run steamcmd-proton /opt/steamcmd-bases/bin/dockerify run --proton /opt/steamcmd-bases/bin/test-exe.exe --json
```

## Development Workflow

### Making Changes to Shell Scripts

```bash
# Edit script
nano scripts/lib/deps.sh

# Source and test immediately
source scripts/lib/deps.sh
is_wine_installed

# For init scripts, rebuild and test container
docker compose build steamcmd-wine
docker compose run steamcmd-wine bash -c 'source /opt/steamcmd-bases/lib/deps.sh && print_deps_summary'
```

### Making Changes to Rust Code

```bash
# Edit Rust source
nano crates/test-exe/src/main.rs

# Rebuild
cargo build --release

# Test output
./target/release/test-exe --json
./target/release/test-exe --verbose

# For Docker integration, rebuild images
docker compose build
docker compose run steamcmd-wine /opt/steamcmd-bases/bin/test-exe.exe
```

### Testing Idempotency

A core principle is that scripts can be run repeatedly safely:

```bash
# Build image
docker compose build steamcmd-proton

# Run container multiple times, each should succeed
docker compose run steamcmd-proton bash -c '/opt/steamcmd-bases/scripts.d/10-wine-init.sh && /opt/steamcmd-bases/scripts.d/10-wine-init.sh'

# Check that environment variables aren't duplicated
docker compose run steamcmd-proton grep -c "WINEARCH" /home/steam/.bashrc
# Should output: 1 (not 2 or more)
```

## Building Across Platforms

### For Windows Targets

Install `cross`:

```bash
cargo install cross
```

Build Windows executable:

```bash
cross build --release --target x86_64-pc-windows-gnu
```

### For macOS Targets

On macOS, use `cross` for other targets:

```bash
cross build --release --target x86_64-apple-darwin
cross build --release --target x86_64-pc-windows-gnu
```

### Build Script (All Targets)

```bash
#!/bin/bash
set -e

echo "Building for all targets..."

# Linux (native)
cargo build --release --target x86_64-unknown-linux-gnu
echo "✓ Linux built"

# Windows
cross build --release --target x86_64-pc-windows-gnu
echo "✓ Windows built"

# macOS
cross build --release --target x86_64-apple-darwin
echo "✓ macOS built"

echo ""
echo "Artifacts:"
ls -lh target/x86_64-unknown-linux-gnu/release/test-exe
ls -lh target/x86_64-pc-windows-gnu/release/test-exe.exe
ls -lh target/x86_64-apple-darwin/release/test-exe

echo ""
echo "All builds complete!"
```

## Testing

### Unit Tests (Shell)

Test individual functions from deps.sh:

```bash
source scripts/lib/deps.sh

# Test detection functions
test_detection() {
    echo "Testing detection functions..."

    # Should work on any system
    OS=$(get_os_type)
    [[ -n "$OS" ]] && echo "✓ get_os_type: $OS" || echo "✗ get_os_type failed"

    # Returns 0 or 1 (exit code)
    is_steamcmd_installed && echo "✓ SteamCMD installed" || echo "✓ SteamCMD not installed"
}

test_detection
```

### Integration Tests (Docker)

Test full container flow:

```bash
# Build and run a container with all init scripts
docker compose run --rm steamcmd-proton bash -c '
    echo "Checking initialization..."
    source /opt/steamcmd-bases/lib/deps.sh

    # All these should work after init scripts
    detect_wine_version
    detect_proton_version
    env | grep -E "(WINE|PROTON|STEAM)"

    echo "✓ Initialization successful"
'
```

### End-to-End Tests (test-exe)

Test the executable through Wine/Proton:

```bash
# In container
docker compose run steamcmd-wine bash -c '
    echo "Testing wine executable execution..."
    wine /opt/steamcmd-bases/bin/test-exe.exe --json | jq .success
    # Should output: true
'
```

### CI/CD Tests (GitHub)

Push to GitHub to trigger workflows:

```bash
git push origin feature-branch
```

Watch `.github/workflows/test-compatibility.yml` results:

- Ubuntu test job
- Windows Server test job
- macOS test job
- Docker build job
- Compatibility matrix report

## Code Quality

### Shell Scripts

Use shellcheck:

```bash
# Install
apt-get install shellcheck  # Ubuntu/Debian
brew install shellcheck     # macOS

# Check scripts
shellcheck scripts/lib/deps.sh
shellcheck scripts/scripts.d/*.sh
```

### Rust Code

```bash
# Check for warnings
cargo clippy --release

# Format code
cargo fmt

# Run tests (if added)
cargo test
```

### Markdown

```bash
# Install markdownlint
npm install -g markdownlint-cli

# Check documentation
markdownlint README.md docs/*.md
```

## Adding New Features

### Adding a New Detection Function

1. Add to `scripts/lib/deps.sh`:

```bash
detect_my_tool_version() {
    if command -v mytool &> /dev/null; then
        mytool --version 2>/dev/null || echo ""
    else
        echo ""
    fi
}

is_my_tool_installed() {
    [[ -n $(detect_my_tool_version) ]] && return 0 || return 1
}
```

2. Test it:

```bash
source scripts/lib/deps.sh
detect_my_tool_version
is_my_tool_installed
```

3. Use in init scripts:

```bash
if is_my_tool_installed; then
    echo "MyTool found: $(detect_my_tool_version)"
else
    echo "MyTool not installed, skipping setup"
fi
```

### Adding a New Init Script

1. Create `scripts/scripts.d/NN-feature-init.sh` (use numeric prefix):

```bash
#!/bin/bash
# Feature initialization script
set -Eeuo pipefail

source "${STEAMCMD_BASES_LIB:-/opt/steamcmd-bases/lib}/deps.sh"

echo "🔧 Initializing my feature..."

if is_my_tool_installed; then
    echo "✓ Feature ready"
else
    echo "⚠️ Feature not available, skipping"
fi
```

2. Copy to Dockerfile:

```dockerfile
COPY --chmod=755 scripts/scripts.d/NN-feature-init.sh /opt/steamcmd-bases/scripts.d/
```

3. Test idempotency:

```bash
docker compose run steamcmd-proton bash -c \
  '/opt/steamcmd-bases/scripts.d/NN-feature-init.sh && /opt/steamcmd-bases/scripts.d/NN-feature-init.sh'
```

### Adding a New Platform Support

1. Update `get_os_type()` in deps.sh to detect OS
2. Implement `install_wine_<platform>()` function
3. Add platform detection to init scripts
4. Add GitHub Actions job to test-compatibility.yml
5. Test on real system (or via CI/CD)

## Documentation

When making changes, update:

- **Code comments**: Explain why, not what
- **Function headers**: Document parameters and return values
- **README.md**: User-facing changes
- **docs/architecture.md**: Technical design changes
- **docs/maxims.md**: Principle updates

## Submitting Changes

1. Create feature branch:

```bash
git checkout -b feature/description
```

2. Make changes and test locally

3. Commit with clear messages:

```bash
git commit -m "feat: add support for new platform

- Add OS detection for NewOS
- Implement Wine installation for NewOS
- Update GitHub Actions to test NewOS"
```

4. Push and create PR:

```bash
git push origin feature/description
```

5. Address CI/CD failures and review feedback

6. Merge when approved

## Debugging

### Enable Verbose Output

```bash
# Docker container with debugging
docker compose run steamcmd-proton bash -x /opt/steamcmd-bases/scripts.d/10-wine-init.sh

# Rust with detailed errors
RUST_BACKTRACE=1 ./target/release/test-exe
```

### Inspect Container State

```bash
# Enter container shell
docker compose run --entrypoint bash steamcmd-proton

# Inside container:
source /opt/steamcmd-bases/lib/deps.sh
print_deps_summary
cat /home/steam/.bashrc
```

### Check Build Logs

```bash
# Full build output
docker compose build --no-cache steamcmd-proton 2>&1 | tee build.log

# Inspect specific layer
docker history mbround18/steamcmd:proton-latest
```

## Performance

### Optimize Rust Builds

Cargo.toml is configured for optimized releases:

```toml
[profile.release]
opt-level = 3
lto = true
codegen-units = 1
```

For faster debug builds during development:

```bash
cargo build  # Uses debug profile (much faster)
./target/debug/test-exe --json
```

### Docker Layer Caching

To improve build times:

1. Put frequently-changing files (scripts) near end of Dockerfile
2. Use `--mount=type=cache` for apt caches
3. Avoid `RUN` commands that invalidate cache

Current Dockerfile uses best practices:

- Stable packages (Ubuntu) → mutable packages (Steam tools) → scripts

## See Also

- [README.md](../README.md) - User guide
- [docs/maxims.md](../docs/maxims.md) - Design principles
- [docs/architecture.md](../docs/architecture.md) - Technical architecture
- [Cargo.toml](../Cargo.toml) - Rust workspace definition
- [Dockerfile](../Dockerfile) - Container definitions

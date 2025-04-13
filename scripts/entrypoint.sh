#!/bin/bash
set -Eeuo pipefail

# ───────────────────────────────────────────────────────────
# SteamCMD Docker Base Entrypoint
# ───────────────────────────────────────────────────────────

echo "──────────────────────────────────────────────────────────"
echo "🚀 SteamCMD Docker Base - $(date)"
echo "──────────────────────────────────────────────────────────"

# System Info
echo "🔹 Hostname: $(hostname)"
echo "🔹 Kernel: $(uname -r)"
echo "🔹 OS: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
if command -v lscpu &> /dev/null; then
    echo "🔹 CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | sed 's/^ *//')"
fi
echo "🔹 Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "🔹 Disk Space: $(df -h / | awk 'NR==2 {print $4}')"
echo "──────────────────────────────────────────────────────────"

# User & Permission Check
echo "👤 Running as user: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo "👥 Groups: $(id -Gn)"

# Check and run initialization scripts
if [ -d "/opt/steamcmd-bases/scripts.d" ]; then
    echo "📜 Running initialization scripts..."
    
    # Find all executable scripts in the directory and sort them
    scripts=$(find /opt/steamcmd-bases/scripts.d -type f -executable | sort)
    
    # Execute each script
    for script in $scripts; do
        script_name=$(basename "$script")
        echo "▶️ Running $script_name"
        
        # Execute the script
        "$script" || {
            echo "❌ Script $script_name failed with exit code $?"
            # Continue despite errors, but log them
            echo "⚠️ Continuing despite error..."
        }
    done
    
    echo "✅ Initialization scripts completed"
else
    echo "ℹ️ No initialization scripts directory found"
fi

# Execute the command passed to docker run
echo "▶️ Executing provided command: $*"
exec "$@"
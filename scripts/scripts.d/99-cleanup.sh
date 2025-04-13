#!/bin/bash
# Cleanup script that's executed last in the initialization sequence
set -Eeuo pipefail

echo "🧹 Setting up cleanup handlers..."

# Register cleanup function to be called on container exit
cleanup() {
    echo "🛑 Container stopping, performing cleanup..."
    
    # Kill Xvfb if it was started
    if [ -f /tmp/xvfb.pid ]; then
        XVFB_PID=$(cat /tmp/xvfb.pid)
        if kill -0 "$XVFB_PID" 2>/dev/null; then
            echo "🖥️ Stopping Xvfb (PID: $XVFB_PID)"
            kill "$XVFB_PID" 2>/dev/null || true
        fi
        rm -f /tmp/xvfb.pid
    fi
    
    # Clean up temporary files
    echo "🗑️ Removing temporary files..."
    find /tmp -type f -name "steam_*" -delete 2>/dev/null || true
    
    echo "✅ Cleanup completed"
}

# Create the exit script
cat > /opt/steamcmd-bases/cleanup.sh << 'EOF'
#!/bin/bash
# This script is designed to be used as a trap handler
# or called manually before container shutdown

# Kill Xvfb if it was started
if [ -f /tmp/xvfb.pid ]; then
    XVFB_PID=$(cat /tmp/xvfb.pid)
    if kill -0 "$XVFB_PID" 2>/dev/null; then
        echo "🖥️ Stopping Xvfb (PID: $XVFB_PID)"
        kill "$XVFB_PID" 2>/dev/null || true
    fi
    rm -f /tmp/xvfb.pid
fi

# Clean up temporary files
echo "🗑️ Removing temporary files..."
find /tmp -type f -name "steam_*" -delete 2>/dev/null || true

echo "✅ Cleanup completed"
EOF

# Make the script executable
chmod +x /opt/steamcmd-bases/cleanup.sh

# Register the cleanup trap if this is executed in the main process
if [ $$ -eq 1 ]; then
    trap cleanup EXIT
fi

echo "✅ Cleanup handlers installed"
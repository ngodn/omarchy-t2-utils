#!/bin/bash
# Install permanent WiFi fix for T2 Macs
# Must be run as root (sudo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

echo "=== T2 Mac WiFi Fix Installer ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Backup existing config if present
if [[ -f /etc/iwd/main.conf ]]; then
    echo "Backing up existing /etc/iwd/main.conf to /etc/iwd/main.conf.bak"
    cp /etc/iwd/main.conf /etc/iwd/main.conf.bak
fi

# Install iwd config
echo "Installing iwd configuration..."
mkdir -p /etc/iwd
cp "$CONFIG_DIR/iwd/main.conf" /etc/iwd/main.conf
echo "✓ Installed /etc/iwd/main.conf"

# Restart iwd to apply changes
echo ""
echo "Restarting iwd service..."
if systemctl restart iwd; then
    echo "✓ iwd service restarted"
else
    echo "✗ Failed to restart iwd (you may need to restart manually)"
fi

# Disable power save immediately
echo ""
echo "Disabling power save on wlan0..."
iw dev wlan0 set power_save off 2>/dev/null || true

echo ""
echo "=== Installation Complete ==="
echo "WiFi power save has been disabled permanently."
echo "If you still experience issues, try connecting to a 5GHz network."

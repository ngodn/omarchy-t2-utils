#!/bin/bash
# Fix WiFi power save issues on T2 Macs (Broadcom BCM4364)
# This script disables WiFi power save which causes intermittent connection drops

set -e

IFACE="${1:-wlan0}"

echo "=== T2 Mac WiFi Power Save Fix ==="
echo ""

# Check if running as root for permanent fix
if [[ $EUID -ne 0 ]]; then
    echo "Note: Run with sudo for permanent fix installation"
    echo ""
fi

# Show current status
echo "Current power save status:"
iw dev "$IFACE" get power_save 2>/dev/null || echo "Could not get power save status"
echo ""

# Disable power save immediately
echo "Disabling power save on $IFACE..."
if iw dev "$IFACE" set power_save off 2>/dev/null; then
    echo "✓ Power save disabled for current session"
else
    echo "✗ Failed to disable power save (may need sudo)"
fi
echo ""

# Show new status
echo "New power save status:"
iw dev "$IFACE" get power_save 2>/dev/null || echo "Could not get power save status"

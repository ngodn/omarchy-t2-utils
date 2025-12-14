#!/bin/bash
# Fix slow boot caused by NetworkManager-wait-online.service
# This service waits for network connectivity before allowing boot to proceed,
# which can add 1+ minutes to boot time if network is slow or unavailable.
# Most desktop users don't need this - it's mainly for servers.

set -e

echo "=== Fix Slow Boot (NetworkManager-wait-online) ==="
echo ""

SERVICE="NetworkManager-wait-online.service"

# Check current status
if ! systemctl is-enabled "$SERVICE" &>/dev/null; then
    echo "Service $SERVICE is already disabled, no fix needed"
    exit 0
fi

echo "Current boot time analysis:"
systemd-analyze blame | grep -E "(NetworkManager-wait|network-online)" | head -5
echo ""

echo "This service is causing slow boot by waiting for network connectivity."
echo "Disabling it will speed up boot time significantly."
echo ""

read -p "Disable $SERVICE? [Y/n] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo "Disabling $SERVICE..."
sudo systemctl disable "$SERVICE"

echo ""
echo "Verifying..."
if ! systemctl is-enabled "$SERVICE" &>/dev/null; then
    echo "Done! $SERVICE has been disabled."
    echo ""
    echo "Your next boot should be significantly faster."
    echo "If you ever need this service again, re-enable it with:"
    echo "  sudo systemctl enable $SERVICE"
else
    echo "Failed to disable service"
    exit 1
fi

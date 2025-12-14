#!/bin/bash
# Fix t2_ncm NetworkManager DHCP issues on T2 Macs
# The internal T2 USB ethernet interface causes endless DHCP timeouts
# because there's no DHCP server on the T2 side.
#
# This script applies the official fix from t2linux wiki:
# https://wiki.t2linux.org/guides/postinstall/

set -e

echo "=== Fix t2_ncm NetworkManager Issue ==="
echo ""

UDEV_RULE="/etc/udev/rules.d/99-network-t2-ncm.rules"
NM_CONF="/etc/NetworkManager/conf.d/99-network-t2-ncm.conf"

# Check if already configured
if [[ -f "$UDEV_RULE" ]] && [[ -f "$NM_CONF" ]]; then
    echo "t2_ncm fix is already applied:"
    echo "  - $UDEV_RULE"
    echo "  - $NM_CONF"
    echo ""
    echo "No changes needed."
    exit 0
fi

# Check if t2_ncm interface exists
if ! ip link show t2_ncm &>/dev/null && ! ip link | grep -q "ac:de:48:00:11:22"; then
    echo "Warning: t2_ncm interface not detected."
    echo "This fix is only needed for Apple T2 Macs."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "This will create two configuration files:"
echo "  1. $UDEV_RULE (udev rule for consistent naming)"
echo "  2. $NM_CONF (disable auto-configuration)"
echo ""
echo "This prevents NetworkManager from trying to get DHCP on the"
echo "internal T2 USB ethernet, which always fails and causes delays."
echo ""

read -p "Apply fix? [Y/n] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Creating udev rule..."
cat <<EOF | sudo tee "$UDEV_RULE"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="ac:de:48:00:11:22", NAME="t2_ncm"
EOF

echo ""
echo "Creating NetworkManager config..."
cat <<EOF | sudo tee "$NM_CONF"
[main]
no-auto-default=t2_ncm
EOF

echo ""
echo "Reloading udev rules..."
sudo udevadm control --reload-rules

echo ""
echo "Restarting NetworkManager..."
sudo systemctl restart NetworkManager

echo ""
echo "Done! t2_ncm will no longer cause DHCP timeout issues."
echo ""
echo "To verify, check that t2_ncm is unmanaged:"
echo "  nmcli device status | grep t2_ncm"

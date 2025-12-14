#!/bin/bash
# Fix yay/paru "libalpm.so.XX not found" error after pacman upgrade
# This rebuilds yay from AUR source to link against the current libalpm version

set -e

echo "=== Fix yay libalpm Library Error ==="
echo ""

# Check if yay is actually broken
if yay --version &>/dev/null; then
    echo "✓ yay is working fine, no fix needed"
    exit 0
fi

echo "yay is broken, rebuilding from AUR source..."
echo ""

# Ensure dependencies are installed
echo "Installing build dependencies..."
sudo pacman -S --needed --noconfirm git base-devel

# Build in temp directory
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

echo ""
echo "Cloning yay from AUR..."
git clone https://aur.archlinux.org/yay.git
cd yay

echo ""
echo "Building and installing yay..."
makepkg -si --noconfirm

# Cleanup
cd /
rm -rf "$BUILD_DIR"

echo ""
echo "Verifying installation..."
if yay --version &>/dev/null; then
    echo "✓ yay is now working!"
    yay --version
else
    echo "✗ yay is still broken, something went wrong"
    exit 1
fi

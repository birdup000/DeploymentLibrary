#!/bin/bash
# Install Krita (Linux)
# Installs Krita via the system package manager.
set -e

echo "Installing Krita..."

if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y krita
elif command -v dnf &>/dev/null; then
    sudo dnf install -y krita
elif command -v yum &>/dev/null; then
    sudo yum install -y krita
elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm krita
elif command -v zypper &>/dev/null; then
    sudo zypper --non-interactive install krita
else
    echo "ERROR: Unsupported package manager. Install Krita manually."
    exit 1
fi

echo "Krita installed successfully."

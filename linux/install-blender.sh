#!/bin/bash
# Install Blender (Linux)
# Installs Blender via the system package manager.
set -e

echo "Installing Blender..."

if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y blender
elif command -v dnf &>/dev/null; then
    sudo dnf install -y blender
elif command -v yum &>/dev/null; then
    sudo yum install -y blender
elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm blender
elif command -v zypper &>/dev/null; then
    sudo zypper --non-interactive install blender
else
    echo "ERROR: Unsupported package manager. Install Blender manually."
    exit 1
fi

echo "Blender installed successfully."

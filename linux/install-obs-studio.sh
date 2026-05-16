#!/bin/bash
# Install OBS Studio (Linux)
# Installs OBS Studio via the system package manager.
set -e

echo "Installing OBS Studio..."

if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y obs-studio
elif command -v dnf &>/dev/null; then
    sudo dnf install -y obs-studio
elif command -v yum &>/dev/null; then
    sudo yum install -y obs-studio
elif command -v pacman &>/dev/null; then
    sudo pacman -Sy --noconfirm obs-studio
elif command -v zypper &>/dev/null; then
    sudo zypper --non-interactive install obs-studio
else
    echo "ERROR: Unsupported package manager. Install OBS Studio manually."
    exit 1
fi

echo "OBS Studio installed successfully."

#!/usr/bin/env bash
set -e

source ./scripts/os_detect.sh

echo "Installing Chezmoi..."

if ! command -v chezmoi &> /dev/null; then
    if [ "${machine}" == "Linux" ] || [ "${machine}" == "Mac" ]; then
        sh -c "$(curl -fsLS get.chezmoi.io)"
        export PATH="./bin:$PATH"
    elif [ "${machine}" == "Windows" ]; then
        if command -v winget &> /dev/null; then
            winget install twpayne.chezmoi
        elif command -v scoop &> /dev/null; then
            scoop install chezmoi
        fi
    fi
else
    echo "Chezmoi is already installed."
fi

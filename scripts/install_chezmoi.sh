#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/os_detect.sh"

echo "Installing Chezmoi..."

if ! command -v chezmoi &> /dev/null; then
    if [ "${machine}" == "Linux" ] || [ "${machine}" == "Mac" ]; then
        CHEZMOI_BINDIR="${HOME}/.local/bin"
        mkdir -p "${CHEZMOI_BINDIR}"
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "${CHEZMOI_BINDIR}"
        export PATH="${CHEZMOI_BINDIR}:$PATH"
        echo "Chezmoi installed to ${CHEZMOI_BINDIR}/chezmoi"
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

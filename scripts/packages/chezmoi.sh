#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command chezmoi; then
    echo "chezmoi is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    mkdir -p "$HOME/.local/bin"
    # Use sh -c pattern (not pipe) — piping drops the -b flag
    sh -c "$(curl -fsSL get.chezmoi.io)" -- -b "$HOME/.local/bin"
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install chezmoi
    elif has_command winget; then
        installer_winget_install twpayne.chezmoi
    else
        echo "Cannot install chezmoi on Windows: scoop or winget required."
        exit 1
    fi
fi
ensure_user_bin_in_path

if has_command chezmoi; then
    echo "chezmoi installed: $(command -v chezmoi)"
else
    echo "WARNING: chezmoi binary not found on PATH after install."
    [[ -x "$HOME/.local/bin/chezmoi" ]] && echo "  File exists at ~/.local/bin/chezmoi but PATH may not include it."
fi

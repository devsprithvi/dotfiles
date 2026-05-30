#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command gh; then
    echo "gh is already installed."
    exit 0
fi

if os_is_macos; then
    installer_brew_install gh
elif os_is_linux; then
    if has_command apt-get; then
        installer_apt_install gh
    elif has_command dnf; then
        installer_dnf_install gh
    elif has_command pacman; then
        installer_pacman_install gh
    elif has_command apk; then
        installer_apk_install gh
    else
        echo "ERROR: No supported package manager found to install gh on Linux." >&2
        exit 1
    fi
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install gh
    elif has_command winget; then
        installer_winget_install GitHub.cli
    else
        echo "Cannot install gh on Windows: scoop or winget required."
        exit 1
    fi
fi

echo "gh installed."

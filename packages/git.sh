#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

# git is typically pre-installed, but we ensure it is available
# and configured at the user level.

if has_command git; then
    echo "git is already installed."
    exit 0
fi

if os_is_macos; then
    # macOS provides git via Xcode Command Line Tools
    xcode-select --install 2>/dev/null || true
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install git
    elif has_command winget; then
        installer_winget_install Git.Git
    else
        echo "Cannot install git on Windows: scoop or winget required."
        exit 1
    fi
elif os_is_linux; then
    if os_distro_like debian; then
        installer_apt_install git
    elif os_distro_like fedora || os_distro_like rhel; then
        installer_dnf_install git
    elif os_distro_like arch; then
        installer_pacman_install git
    elif os_distro_like alpine; then
        installer_apk_install git
    else
        echo "Unknown distro '${OS_DISTRO}'. Cannot install git automatically."
        exit 1
    fi
fi

echo "git installed."

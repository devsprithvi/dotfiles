#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command zsh; then
    echo "zsh is already installed."
    exit 0
fi

# zsh is a system-level shell — it genuinely needs privileged install on Linux.
# On macOS it is pre-installed. On Windows it is not practical.

if os_is_macos; then
    echo "zsh should be pre-installed on macOS."
    exit 0
fi

if os_is_windows; then
    echo "Skipping zsh on Windows."
    exit 0
fi

# Linux — system package, needs sudo
if os_is_linux; then
    if os_distro_like debian; then
        installer_apt_install zsh
    elif os_distro_like fedora || os_distro_like rhel; then
        installer_dnf_install zsh
    elif os_distro_like arch; then
        installer_pacman_install zsh
    elif os_distro_like alpine; then
        installer_apk_install zsh
    else
        echo "Unknown distro '${OS_DISTRO}'. Cannot install zsh automatically."
        exit 1
    fi
fi

if ! has_command zsh; then
    echo "ERROR: Failed to install zsh. Cannot continue."
    exit 1
fi

echo "zsh installed."

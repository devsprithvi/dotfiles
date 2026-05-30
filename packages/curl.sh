#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command curl; then
    echo "curl is already installed."
    exit 0
fi

if os_is_macos; then
    # curl is pre-installed on macOS
    echo "curl should be pre-installed on macOS."
    exit 0
fi

if os_is_windows; then
    echo "curl should be pre-installed on Windows."
    exit 0
fi

# Linux — system package, needs sudo
if os_is_linux; then
    if os_distro_like debian; then
        installer_apt_install curl
    elif os_distro_like fedora || os_distro_like rhel; then
        installer_dnf_install curl
    elif os_distro_like arch; then
        installer_pacman_install curl
    elif os_distro_like alpine; then
        installer_apk_install curl
    else
        echo "Unknown distro '${OS_DISTRO}'. Cannot install curl automatically."
        exit 1
    fi
fi

if ! has_command curl; then
    echo "ERROR: Failed to install curl. Cannot continue."
    exit 1
fi

echo "curl installed."

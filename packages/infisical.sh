#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command infisical; then
    echo "infisical is already installed."
    exit 0
fi

if os_is_macos; then
    installer_brew_install "infisical/get-cli/infisical"
elif os_is_linux; then
    if has_command apt-get; then
        install_from_url "infisical-repo" "https://artifacts-cli.infisical.com/setup.deb.sh"
        _APT_UPDATED="" # Force apt-get update to run again for the new repo
        installer_apt_install infisical
    elif has_command dnf; then
        install_from_url "infisical-repo" "https://artifacts-cli.infisical.com/setup.rpm.sh"
        installer_dnf_install infisical
    elif has_command apk; then
        install_from_url "infisical-repo" "https://artifacts-cli.infisical.com/setup.apk.sh"
        installer_apk_install infisical
    else
        echo "ERROR: No supported package manager found to install infisical on Linux." >&2
        exit 1
    fi
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install infisical
    else
        echo "Cannot install infisical on Windows: scoop required."
        exit 1
    fi
fi

echo "infisical installed."

#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command infisical; then
    echo "infisical is already installed."
else
    if os_is_linux || os_is_macos; then
        install_from_url "infisical" \
            "https://raw.githubusercontent.com/Infisical/infisical/main/scripts/install.sh"
    elif os_is_windows; then
        if has_command scoop; then
            installer_scoop_install infisical
        else
            echo "Cannot install infisical on Windows: scoop required."
            exit 1
        fi
    fi
fi

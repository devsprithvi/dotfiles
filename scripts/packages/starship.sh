#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command starship; then
    echo "starship is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    installer_url_sh "starship" "https://starship.rs/install.sh" -s -- -y -b "$HOME/.local/bin"
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install starship
    else
        echo "Cannot install starship on Windows: scoop required."
        exit 1
    fi
fi

echo "starship installed."

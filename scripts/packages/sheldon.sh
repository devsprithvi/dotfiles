#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command sheldon; then
    echo "sheldon is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    installer_url_bash "sheldon" "https://rossmacarthur.github.io/install/crate.sh" \
        -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin"
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install sheldon
    else
        echo "Cannot install sheldon on Windows: scoop required."
        exit 1
    fi
fi

echo "sheldon installed."

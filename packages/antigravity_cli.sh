#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

if has_command agy; then
    echo "antigravity cli is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    install_from_url "antigravity cli" "https://antigravity.google/cli/install.sh"
elif os_is_windows; then
    install_from_url_windows "antigravity cli" "https://antigravity.google/cli/install.ps1"
fi

echo "antigravity cli installed."

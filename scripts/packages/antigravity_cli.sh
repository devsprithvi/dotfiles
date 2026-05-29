#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command agy; then
    echo "antigravity cli is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    installer_url_bash "antigravity cli" "https://antigravity.google/cli/install.sh"
elif os_is_windows; then
    installer_url_powershell "antigravity cli" "https://antigravity.google/cli/install.ps1"
fi

echo "antigravity cli installed."

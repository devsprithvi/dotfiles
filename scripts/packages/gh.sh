#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command gh; then
    echo "gh is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    installer_url_bash "gh" "https://raw.githubusercontent.com/cli/cli/trunk/install.sh"
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

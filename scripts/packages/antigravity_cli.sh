#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command agy; then
    echo "antigravity cli is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    mkdir -p "$HOME/.local/bin"
    # Install to user-level bin so it works without sudo in containers/Codespaces
    export AGY_INSTALL_DIR="$HOME/.local/bin"
    installer_url_bash "antigravity cli" "https://antigravity.google/cli/install.sh"

    # If the installer ignored AGY_INSTALL_DIR, check common locations and symlink
    if ! has_command agy; then
        for candidate in /usr/local/bin/agy /usr/bin/agy; do
            if [[ -x "${candidate}" ]]; then
                ln -sf "${candidate}" "$HOME/.local/bin/agy"
                echo "[agy] Symlinked ${candidate} → ~/.local/bin/agy"
                break
            fi
        done
    fi
elif os_is_windows; then
    installer_url_powershell "antigravity cli" "https://antigravity.google/cli/install.ps1"
fi

ensure_user_bin_in_path

if has_command agy; then
    echo "antigravity cli installed: $(command -v agy)"
else
    echo "WARNING: antigravity cli binary not found on PATH after install."
fi

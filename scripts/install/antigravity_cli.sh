#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command agy; then
    echo "Antigravity CLI (agy) is already installed."
    exit 0
fi

case "${machine}" in
    Linux|Mac)
        if ! has_command curl && ! has_command wget; then
            echo "Skipping Antigravity CLI installation because neither curl nor wget is available."
            exit 0
        fi

        ensure_local_bin_on_path
        mkdir -p "$HOME/.local/bin"
        download_to_stdout "https://antigravity.google/cli/install.sh" | bash -s -- --dir "$HOME/.local/bin"
        ensure_local_bin_on_path
        echo "Antigravity CLI installed to $HOME/.local/bin/agy"
        ;;
    Windows)
        if has_command powershell.exe; then
            powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "iwr https://antigravity.google/cli/install.ps1 | iex"
        else
            echo "Skipping Antigravity CLI installation on Windows because PowerShell is unavailable."
        fi
        ;;
esac

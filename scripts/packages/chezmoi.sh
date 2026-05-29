#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command chezmoi; then
    echo "Chezmoi is already installed."
    exit 0
fi

case "${machine}" in
    Linux|Mac)
        if ! has_command curl && ! has_command wget; then
            echo "Skipping Chezmoi installation because neither curl nor wget is available."
            exit 0
        fi

        prepare_local_bin
        download_to_stdout "https://get.chezmoi.io" | sh -s -- -b "$HOME/.local/bin"
        ensure_local_bin_on_path
        echo "Chezmoi installed to $HOME/.local/bin/chezmoi"
        ;;
    Windows)
        if has_command winget; then
            winget install twpayne.chezmoi
        elif has_command scoop; then
            scoop install chezmoi
        else
            echo "Skipping Chezmoi installation on Windows because neither winget nor Scoop is available."
        fi
        ;;
esac

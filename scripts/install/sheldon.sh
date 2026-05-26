#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command sheldon; then
    echo "Sheldon is already installed."
    exit 0
fi

case "${machine}" in
    Mac)
        require_package_manager brew "Homebrew is not installed. Please install Homebrew first."
        brew install sheldon
        ;;
    Windows)
        if has_command scoop; then
            scoop install sheldon
        else
            echo "Skipping Sheldon installation on Windows because Scoop is unavailable."
        fi
        ;;
    *)
        if ! has_command curl && ! has_command wget; then
            echo "Skipping Sheldon installation because neither curl nor wget is available."
            exit 0
        fi

        ensure_local_bin_on_path
        mkdir -p "$HOME/.local/bin"
        download_to_stdout "https://rossmacarthur.github.io/install/crate.sh" | bash -s -- --repo rossmacarthur/sheldon --to "$HOME/.local/bin"
        ;;
esac

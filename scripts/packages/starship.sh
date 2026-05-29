#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command starship; then
    echo "Starship is already installed."
    exit 0
fi

case "${machine}" in
    Windows)
        if has_command scoop; then
            scoop install starship
        else
            echo "Skipping Starship installation on Windows because Scoop is unavailable."
        fi
        ;;
    *)
        if ! has_command curl && ! has_command wget; then
            echo "Skipping Starship installation because neither curl nor wget is available."
            exit 0
        fi

        prepare_local_bin
        download_to_stdout "https://starship.rs/install.sh" | sh -s -- -y -b "$HOME/.local/bin"
        ;;
esac

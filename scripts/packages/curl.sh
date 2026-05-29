#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command curl; then
    echo "curl is already installed."
    exit 0
fi

case "${machine}" in
    Linux)
        if ! can_run_privileged; then
            echo "Skipping curl installation on Linux because root or passwordless sudo is unavailable."
            exit 0
        fi

        export DEBIAN_FRONTEND=noninteractive
        run_privileged apt-get update
        run_privileged apt-get install -y curl
        ;;
    Mac)
        require_package_manager brew "Homebrew is not installed. Please install Homebrew first."
        brew install curl
        ;;
    Windows)
        echo "Skipping curl installation on Windows. Install it manually if it is required in this environment."
        ;;
esac

#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if has_command gh; then
    echo "GitHub CLI (gh) is already installed."
    exit 0
fi

case "${machine}" in
    Linux)
        if ! can_run_privileged; then
            echo "Skipping GitHub CLI installation on Linux because root or passwordless sudo is unavailable."
            exit 0
        fi

        if ! has_command curl && ! has_command wget; then
            echo "Skipping GitHub CLI installation on Linux because neither curl nor wget is available."
            exit 0
        fi

        export DEBIAN_FRONTEND=noninteractive
        download_to_stdout "https://cli.github.com/packages/githubcli-archive-keyring.gpg" | run_privileged dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        run_privileged chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        run_privileged_shell "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" > /etc/apt/sources.list.d/github-cli.list"
        run_privileged apt-get update
        run_privileged apt-get install -y gh
        ;;
    Mac)
        require_package_manager brew "Homebrew is not installed. Please install Homebrew first."
        brew install gh
        ;;
    Windows)
        if has_command scoop; then
            scoop install gh
        else
            echo "Skipping GitHub CLI installation on Windows because Scoop is unavailable."
        fi
        ;;
esac

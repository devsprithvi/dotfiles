#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/os_detect.sh"
source "${SCRIPT_DIR}/command_utils.sh"

echo "Installing config-based tools (gh, starship, sheldon)..."

# GitHub CLI (gh)
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    if [ "${machine}" == "Linux" ]; then
        if can_run_privileged; then
            export DEBIAN_FRONTEND=noninteractive
            if ! command -v curl &> /dev/null; then
                echo "Skipping GitHub CLI install on Linux because curl is not available."
            else
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | run_privileged dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                run_privileged chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                run_privileged_shell "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" > /etc/apt/sources.list.d/github-cli.list"
                run_privileged apt-get update
                run_privileged apt-get install -y gh
            fi
        else
            echo "Skipping GitHub CLI install on Linux because root or passwordless sudo is unavailable."
        fi
    elif [ "${machine}" == "Mac" ]; then
        brew install gh
    elif [ "${machine}" == "Windows" ] && command -v scoop &> /dev/null; then
        scoop install gh
    fi
else
    echo "GitHub CLI (gh) is already installed."
fi

# Starship
if ! command -v starship &> /dev/null; then
    echo "Installing Starship..."
    if [ "${machine}" == "Windows" ] && command -v scoop &> /dev/null; then
        scoop install starship
    elif ! command -v curl &> /dev/null; then
        echo "Skipping Starship install because curl is not available."
    else
        STARSHIP_BIN_DIR="${HOME}/.local/bin"
        mkdir -p "${STARSHIP_BIN_DIR}"
        curl -sS https://starship.rs/install.sh | sh -s -- -y -b "${STARSHIP_BIN_DIR}"
        export PATH="${STARSHIP_BIN_DIR}:$PATH"
    fi
else
    echo "Starship is already installed."
fi

# Sheldon
if ! command -v sheldon &> /dev/null; then
    echo "Installing Sheldon..."
    if [ "${machine}" == "Mac" ] && command -v brew &> /dev/null; then
        brew install sheldon
    elif [ "${machine}" == "Windows" ] && command -v scoop &> /dev/null; then
        scoop install sheldon
    elif ! command -v curl &> /dev/null; then
        echo "Skipping Sheldon install because curl is not available."
    else
        mkdir -p ~/.local/bin
        curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
        export PATH="$HOME/.local/bin:$PATH"
    fi
else
    echo "Sheldon is already installed."
fi

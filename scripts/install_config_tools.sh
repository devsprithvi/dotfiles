#!/usr/bin/env bash
set -e

source ./scripts/os_detect.sh

echo "Installing config-based tools (gh, starship, sheldon)..."

# GitHub CLI (gh)
if ! command -v gh &> /dev/null; then
    echo "Installing GitHub CLI..."
    if [ "${machine}" == "Linux" ]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update && sudo apt-get install -y gh
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
    else
        curl -sS https://starship.rs/install.sh | sh -s -- -y
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
    else
        mkdir -p ~/.local/bin
        curl --proto '=https' -fLsS https://rossmacarthur.github.io/install/crate.sh | bash -s -- --repo rossmacarthur/sheldon --to ~/.local/bin
        export PATH="$HOME/.local/bin:$PATH"
    fi
else
    echo "Sheldon is already installed."
fi

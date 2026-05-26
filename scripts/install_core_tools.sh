#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source OS detection
source "${SCRIPT_DIR}/os_detect.sh"
source "${SCRIPT_DIR}/command_utils.sh"

echo "Installing core system tools (curl, git, zsh)..."

if [ "${machine}" == "Linux" ]; then
    if ! can_run_privileged; then
        echo "Skipping Linux core tool installation because root or passwordless sudo is unavailable."
        exit 0
    fi

    export DEBIAN_FRONTEND=noninteractive

    echo "Updating apt..."
    run_privileged apt-get update
    
    if ! command -v curl &> /dev/null; then
        echo "Installing curl..."
        run_privileged apt-get install -y curl
    else
        echo "curl is already installed."
    fi

    if ! command -v git &> /dev/null; then
        echo "Installing git..."
        run_privileged apt-get install -y git
    else
        echo "git is already installed."
    fi

    if ! command -v zsh &> /dev/null; then
        echo "Installing zsh..."
        run_privileged apt-get install -y zsh
    else
        echo "zsh is already installed."
    fi

elif [ "${machine}" == "Mac" ]; then
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Please install Homebrew first."
        exit 1
    fi
    for tool in curl git zsh; do
        if ! command -v $tool &> /dev/null; then
            echo "Installing $tool..."
            brew install $tool
        else
            echo "$tool is already installed."
        fi
    done

elif [ "${machine}" == "Windows" ]; then
    if command -v scoop &> /dev/null; then
        if ! command -v git &> /dev/null; then
            echo "Installing git..."
            scoop install git
        else
            echo "git is already installed."
        fi
    fi
fi

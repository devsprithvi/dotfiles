#!/usr/bin/env bash
set -e

# Source OS detection
source ./scripts/os_detect.sh

echo "Installing core system tools (curl, git, zsh)..."

if [ "${machine}" == "Linux" ]; then
    echo "Updating apt..."
    sudo apt-get update
    
    if ! command -v curl &> /dev/null; then
        echo "Installing curl..."
        sudo apt-get install -y curl
    else
        echo "curl is already installed."
    fi

    if ! command -v git &> /dev/null; then
        echo "Installing git..."
        sudo apt-get install -y git
    else
        echo "git is already installed."
    fi

    if ! command -v zsh &> /dev/null; then
        echo "Installing zsh..."
        sudo apt-get install -y zsh
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

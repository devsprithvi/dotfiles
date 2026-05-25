#!/usr/bin/env bash
set -e

echo "Starting dotfiles bootstrap..."

# 1. Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Windows;;
    MINGW*)     machine=Windows;;
    MSYS*)      machine=Windows;;
    *)          machine="UNKNOWN:${OS}"
esac
echo "Detected OS: ${machine}"

# 2. Install Core Tools (Zsh, Git, GitHub CLI)
echo "Installing core system tools..."
if [ "${machine}" == "Linux" ]; then
    sudo apt-get update
    sudo apt-get install -y curl git zsh
    
    if ! command -v gh &> /dev/null; then
        echo "Installing GitHub CLI..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update && sudo apt-get install -y gh
    fi
elif [ "${machine}" == "Mac" ]; then
    if ! command -v brew &> /dev/null; then
        echo "Homebrew is not installed. Please install Homebrew first."
        exit 1
    fi
    brew install curl git zsh gh
elif [ "${machine}" == "Windows" ]; then
    if command -v scoop &> /dev/null; then
        scoop install git gh
    fi
fi

# 3. Install Prompt & Shell Plugins (Starship, Sheldon)
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

# 4. Install Infisical CLI
if ! command -v infisical &> /dev/null; then
    echo "Infisical CLI could not be found. Installing..."
    if [ "${machine}" == "Linux" ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
        sudo apt-get update && sudo apt-get install -y infisical
    elif [ "${machine}" == "Mac" ]; then
        brew install infisical/get-cli/infisical
    elif [ "${machine}" == "Windows" ]; then
        if command -v scoop &> /dev/null; then
            scoop install infisical
        else
            echo "Scoop is not installed. Please install Scoop first, or install Infisical manually."
        fi
    fi
else
    echo "Infisical CLI is already installed."
fi

# 5. Authenticate Infisical
echo "Verifying Infisical authentication..."
if ! infisical secrets get ADMIN_PAT --env global --path /github --plain &> /dev/null; then
    echo "You are not authenticated with Infisical or the secret is not accessible."
    echo "Please provide your Infisical Machine Identity credentials to login."
    read -p "Client ID: " INFISICAL_CLIENT_ID
    read -s -p "Client Secret: " INFISICAL_CLIENT_SECRET
    echo ""
    
    # We use machine identity login
    infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" || \
    infisical login --method=machine-identity --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET"
else
    echo "Successfully accessed Infisical secrets!"
fi

# 6. Install Chezmoi
if ! command -v chezmoi &> /dev/null; then
    echo "Chezmoi could not be found. Installing..."
    if [ "${machine}" == "Linux" ] || [ "${machine}" == "Mac" ]; then
        sh -c "$(curl -fsLS get.chezmoi.io)"
        export PATH="./bin:$PATH"
    elif [ "${machine}" == "Windows" ]; then
        if command -v winget &> /dev/null; then
            winget install twpayne.chezmoi
        elif command -v scoop &> /dev/null; then
            scoop install chezmoi
        fi
    fi
else
    echo "Chezmoi is already installed."
fi

echo "==========================================="
echo "Bootstrap complete!"
echo "If this is a new machine, you can now run:"
echo "  chezmoi init --apply devsprithvi"
echo "==========================================="

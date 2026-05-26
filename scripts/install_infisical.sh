#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/os_detect.sh"
source "${SCRIPT_DIR}/command_utils.sh"

echo "Installing Infisical CLI..."

if ! command -v infisical &> /dev/null; then
    if [ "${machine}" == "Linux" ]; then
        if can_run_privileged; then
            export DEBIAN_FRONTEND=noninteractive
            if ! command -v curl &> /dev/null; then
                echo "Skipping Infisical CLI install on Linux because curl is not available."
            else
                curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | run_privileged env DEBIAN_FRONTEND=noninteractive bash
                run_privileged apt-get update
                run_privileged apt-get install -y infisical
            fi
        else
            echo "Skipping Infisical CLI install on Linux because root or passwordless sudo is unavailable."
        fi
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

if ! command -v infisical &> /dev/null; then
    echo "Skipping Infisical authentication because the CLI is not installed."
    exit 0
fi

echo "Verifying Infisical authentication..."
if ! infisical secrets get ADMIN_PAT --env global --path /github --plain &> /dev/null; then
    echo "You are not authenticated with Infisical or the secret is not accessible."
    
    if [ -n "$INFISICAL_CLIENT_ID" ] && [ -n "$INFISICAL_CLIENT_SECRET" ]; then
        echo "Logging in via Machine Identity credentials from environment variables..."
        infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" || \
        infisical login --method=machine-identity --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET"
    elif [ -f "/.dockerenv" ]; then
        echo "Skipping interactive Infisical login inside container bootstrap."
        echo "Set INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET to authenticate during bootstrap."
        exit 0
    elif [ ! -t 0 ]; then
        echo "Skipping Infisical login in non-interactive setup."
        echo "Set INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET to authenticate during bootstrap."
        exit 0
    else
        echo "Please provide your Infisical Machine Identity credentials to login."
        read -p "Client ID: " INFISICAL_CLIENT_ID_INPUT
        read -s -p "Client Secret: " INFISICAL_CLIENT_SECRET_INPUT
        echo ""
        
        infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID_INPUT" --client-secret="$INFISICAL_CLIENT_SECRET_INPUT" || \
        infisical login --method=machine-identity --client-id="$INFISICAL_CLIENT_ID_INPUT" --client-secret="$INFISICAL_CLIENT_SECRET_INPUT"
    fi
else
    echo "Successfully accessed Infisical secrets!"
fi

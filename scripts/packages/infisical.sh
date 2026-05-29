#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../lib/common.sh"

if ! has_command infisical; then
    case "${machine}" in
        Linux)
            if ! can_run_privileged; then
                echo "Skipping Infisical CLI installation on Linux because root or passwordless sudo is unavailable."
            elif ! has_command curl && ! has_command wget; then
                echo "Skipping Infisical CLI installation on Linux because neither curl nor wget is available."
            else
                export DEBIAN_FRONTEND=noninteractive
                download_to_stdout "https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh" | run_privileged env DEBIAN_FRONTEND=noninteractive bash
                run_privileged apt-get update
                run_privileged apt-get install -y infisical
            fi
            ;;
        Mac)
            require_package_manager brew "Homebrew is not installed. Please install Homebrew first."
            brew install infisical/get-cli/infisical
            ;;
        Windows)
            if has_command scoop; then
                scoop install infisical
            else
                echo "Skipping Infisical CLI installation on Windows because Scoop is unavailable."
            fi
            ;;
    esac
else
    echo "Infisical CLI is already installed."
fi

if ! has_command infisical; then
    echo "Skipping Infisical authentication because the CLI is not installed."
    exit 0
fi

echo "Verifying Infisical authentication..."
if infisical secrets get ADMIN_PAT --env global --path /github --plain &> /dev/null; then
    echo "Successfully accessed Infisical secrets!"
    exit 0
fi

echo "You are not authenticated with Infisical or the secret is not accessible."

if [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ]; then
    echo "Logging in via Machine Identity credentials from environment variables..."
    infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" || \
    infisical login --method=machine-identity --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET"
elif [ -f "/.dockerenv" ] || [ ! -t 0 ]; then
    echo "Skipping interactive Infisical login in non-interactive setup."
    echo "Set INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET to authenticate during bootstrap."
else
    echo "Please provide your Infisical Machine Identity credentials to login."
    read -p "Client ID: " INFISICAL_CLIENT_ID_INPUT
    read -s -p "Client Secret: " INFISICAL_CLIENT_SECRET_INPUT
    echo ""

    infisical login --method=universal-auth --client-id="$INFISICAL_CLIENT_ID_INPUT" --client-secret="$INFISICAL_CLIENT_SECRET_INPUT" || \
    infisical login --method=machine-identity --client-id="$INFISICAL_CLIENT_ID_INPUT" --client-secret="$INFISICAL_CLIENT_SECRET_INPUT"
fi

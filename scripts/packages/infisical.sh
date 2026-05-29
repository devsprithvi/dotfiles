#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command infisical; then
    echo "infisical is already installed."
else
    if os_is_linux || os_is_macos; then
        installer_url_bash "infisical" \
            "https://raw.githubusercontent.com/Infisical/infisical/main/scripts/install.sh"
    elif os_is_windows; then
        if has_command scoop; then
            installer_scoop_install infisical
        else
            echo "Cannot install infisical on Windows: scoop required."
            exit 1
        fi
    fi
fi

if ! has_command infisical; then
    echo "infisical is not available. Skipping authentication."
    exit 0
fi

# ── Authentication ──────────────────────────────────────────────────────────
echo "Verifying infisical authentication..."
if infisical secrets get ADMIN_PAT --env global --path /github --plain &> /dev/null; then
    echo "Already authenticated with infisical."
    exit 0
fi

echo "Not authenticated with infisical."

if [[ -n "${INFISICAL_CLIENT_ID:-}" && -n "${INFISICAL_CLIENT_SECRET:-}" ]]; then
    echo "Logging in via environment credentials..."
    infisical login --method=universal-auth \
        --client-id="$INFISICAL_CLIENT_ID" \
        --client-secret="$INFISICAL_CLIENT_SECRET" || \
    infisical login --method=machine-identity \
        --client-id="$INFISICAL_CLIENT_ID" \
        --client-secret="$INFISICAL_CLIENT_SECRET"
elif [[ -f "/.dockerenv" ]] || [[ ! -t 0 ]]; then
    echo "Non-interactive environment. Set INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET."
else
    echo "Please provide your Infisical Machine Identity credentials."
    read -p "Client ID: " INFISICAL_CLIENT_ID_INPUT
    read -s -p "Client Secret: " INFISICAL_CLIENT_SECRET_INPUT
    echo ""

    infisical login --method=universal-auth \
        --client-id="$INFISICAL_CLIENT_ID_INPUT" \
        --client-secret="$INFISICAL_CLIENT_SECRET_INPUT" || \
    infisical login --method=machine-identity \
        --client-id="$INFISICAL_CLIENT_ID_INPUT" \
        --client-secret="$INFISICAL_CLIENT_SECRET_INPUT"
fi

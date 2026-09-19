#!/usr/bin/env bash

# Ensure user's local binary directory is always on PATH when our utilities run.
export PATH="${HOME}/.local/bin:${PATH}"

# ── General Helpers ─────────────────────────────────────────────────────────

# Check if a specific command is available in the current environment
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# ── Privilege Helpers ───────────────────────────────────────────────────────

# Check if the current user is root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Check if passwordless sudo is available
has_passwordless_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

# Check if the script can execute commands with privileged rights
can_run_privileged() {
    is_root || has_passwordless_sudo
}

# Run a command with privilege (root or sudo) if available
run_privileged() {
    if is_root; then
        "$@"
    elif has_passwordless_sudo; then
        sudo -n "$@"
    else
        return 127
    fi
}

# ── Secret Fetching (Infisical) ─────────────────────────────────────────────

# Fetch a single secret value from the Infisical vault by key name.
# Usage:  fetch_infisical_secret "SECRET_KEY" [environment] [secret_path]
# Output: prints the secret value to stdout (empty string on failure)
# Return: 0 on success, 1 on any failure (silent — suitable for $() capture)
# Requires: INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET env vars, curl, python3
fetch_infisical_secret() {
    local secret_key="$1"
    local environment="${2:-global}"
    local secret_path="${3:-/}"
    local project_id="${INFISICAL_PROJECT_ID:-e3e7a48d-605a-4ae2-b202-2dbf45918227}"

    # Bail silently if credentials or tools aren't available
    [[ -z "${INFISICAL_CLIENT_ID:-}" || -z "${INFISICAL_CLIENT_SECRET:-}" ]] && return 1
    has_command curl   || return 1
    has_command python3 || return 1

    # Authenticate — obtain a short-lived access token
    local token
    token=$(curl -s --max-time 10 -X POST \
        "https://app.infisical.com/api/v1/auth/universal-auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"clientId\": \"${INFISICAL_CLIENT_ID}\", \"clientSecret\": \"${INFISICAL_CLIENT_SECRET}\"}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" 2>/dev/null)

    [[ -z "$token" ]] && return 1

    # URL-encode the secret path for the API query string
    local encoded_path
    encoded_path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${secret_path}', safe=''))" 2>/dev/null)

    # Fetch and extract the specific secret value
    curl -s --max-time 10 -X GET \
        "https://app.infisical.com/api/v3/secrets/raw?environment=${environment}&secretPath=${encoded_path}&workspaceId=${project_id}" \
        -H "Authorization: Bearer ${token}" \
        | python3 -c "
import sys, json
secrets = json.load(sys.stdin).get('secrets', [])
val = next((s['secretValue'] for s in secrets if s['secretKey'] == '${secret_key}'), '')
print(val)
" 2>/dev/null
}

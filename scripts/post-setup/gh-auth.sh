#!/usr/bin/env bash
set -eo pipefail

# ── Post-Setup: GitHub CLI Authentication ──────────────────────────────────
# Authenticates `gh` using the PAT from Infisical.
# chezmoi already wrote ~/.config/gh/hosts.yml with the token,
# but this ensures `gh auth status` passes and git credential
# helpers are configured.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if ! has_command gh; then
    echo "[gh-auth] gh CLI is not installed. Skipping."
    exit 0
fi

if ! has_command infisical; then
    echo "[gh-auth] infisical is not available. Skipping gh auth."
    exit 0
fi

# ── Check if already authenticated ─────────────────────────────────────────
if gh auth status &> /dev/null; then
    echo "[gh-auth] GitHub CLI is already authenticated."
    exit 0
fi

# ── Fetch PAT and authenticate ─────────────────────────────────────────────
echo "[gh-auth] Authenticating GitHub CLI via Infisical PAT..."

GH_TOKEN=$(infisical secrets get ADMIN_PAT --env global --path /github --plain 2>/dev/null || true)

if [[ -z "${GH_TOKEN}" ]]; then
    echo "[gh-auth] WARNING: Could not retrieve PAT from Infisical."
    echo "[gh-auth] gh will need to be authenticated manually: gh auth login"
    exit 0
fi

# gh auth login with token — non-interactive
echo "${GH_TOKEN}" | gh auth login --with-token && \
    echo "[gh-auth] GitHub CLI authenticated successfully." || {
    echo "[gh-auth] WARNING: gh auth login failed."
    echo "[gh-auth] You can authenticate manually: gh auth login"
}

# Set up git credential helper so git operations use gh's token
if has_command git; then
    gh auth setup-git &> /dev/null || true
    echo "[gh-auth] Git credential helper configured via gh."
fi

unset GH_TOKEN

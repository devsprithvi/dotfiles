#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Tailscale ──────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs the Tailscale VPN/mesh networking client and optionally
# authenticates + connects using an auth key from Infisical.
#
# Control:  ENABLE_TAILSCALE=1           to install (optional, off by default)
# Auth:     TAILSCALE_AUTHKEY env var    direct auth key (highest priority)
#           — or —
#           Infisical secret "TAILSCALE_AUTHKEY" at /tailscale (auto-fetched)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_TAILSCALE:-}" ]]; then
    echo "tailscale skipped (set ENABLE_TAILSCALE=1 to enable)."
    exit 0
fi

# ── Install ────────────────────────────────────────────────────────────────
if has_command tailscale; then
    echo "tailscale is already installed."
else
    install_tailscale
fi

# ── Optional: auto-connect with auth key ───────────────────────────────────
# An auth key allows fully non-interactive "tailscale up" on headless machines.
# Priority: env var > Infisical secret
auth_key="${TAILSCALE_AUTHKEY:-}"

if [[ -z "$auth_key" ]]; then
    auth_key="$(fetch_infisical_secret "TAILSCALE_AUTHKEY" "global" "/tailscale" 2>/dev/null || true)"
fi

if [[ -n "$auth_key" ]]; then
    # Check if already connected — don't re-auth unnecessarily
    if tailscale status >/dev/null 2>&1; then
        echo "[tailscale] Already connected to tailnet."
    else
        tailscale_up "$auth_key"
        echo "[tailscale] Connected to tailnet."
    fi
else
    echo "[tailscale] No auth key found. Run 'sudo tailscale up' manually to authenticate."
fi

echo "tailscale setup complete."


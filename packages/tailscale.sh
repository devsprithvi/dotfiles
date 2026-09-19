#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Tailscale (install only) ───────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs the Tailscale VPN/mesh networking client.
#
# Boundary: this script ONLY installs. Authenticating and connecting to a
# tailnet ("tailscale up") is a runtime action: services/index.sh run tailscale:up
# (via the generic runner services/run.sh + presets.sh).
#
# Control: ENABLE_TAILSCALE=1 to install (optional, off by default)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_TAILSCALE:-}" ]]; then
    echo "tailscale skipped (set ENABLE_TAILSCALE=1 to enable)."
    exit 0
fi

if has_command tailscale; then
    echo "tailscale is already installed."
    exit 0
fi

if os_is_linux; then
    # The official installer detects the distro and configures the repo + daemon.
    if ! can_run_privileged; then
        echo "ERROR: root/sudo required to install tailscale." >&2
        exit 1
    fi
    echo "[tailscale] Installing via official installer..."
    if has_command curl; then
        curl -fsSL https://tailscale.com/install.sh | run_privileged sh
    elif has_command wget; then
        wget -qO- https://tailscale.com/install.sh | run_privileged sh
    else
        echo "ERROR: curl or wget required to install tailscale." >&2
        exit 1
    fi
elif os_is_macos; then
    if has_command brew; then
        installer_brew_install tailscale
    else
        echo "ERROR: Homebrew required to install tailscale on macOS (or use the App Store app)." >&2
        exit 1
    fi
elif os_is_windows; then
    if has_command winget; then
        installer_winget_install "tailscale.tailscale"
    else
        echo "Cannot install tailscale on Windows: winget required."
        exit 1
    fi
fi

echo "tailscale installed."

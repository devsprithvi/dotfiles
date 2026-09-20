#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Tailscale (install only) ───────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs the Tailscale VPN/mesh networking client.
#
# Boundary: this script ONLY installs. Authenticating and connecting to a
# tailnet ("tailscale up") is a startup command (preset tailscale:up) — declared
# via DOTFILES_STARTUP and run by commands/run.sh + commands/presets/.
#
# Control: ENABLE_TAILSCALE=1 to install (optional, off by default)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "tailscale"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_TAILSCALE:-}" ]]; then
    log_info "tailscale skipped (set ENABLE_TAILSCALE=1 to enable)."
    exit 0
fi

if has_command tailscale; then
    log_info "tailscale is already installed."
    exit 0
fi

if os_is_linux; then
    # The official installer detects the distro and configures the repo + daemon.
    if ! can_run_privileged; then
        log_fatal "root/sudo required to install tailscale."
    fi
    log_info "Installing via official installer..."
    if has_command curl; then
        curl -fsSL https://tailscale.com/install.sh | run_privileged sh
    elif has_command wget; then
        wget -qO- https://tailscale.com/install.sh | run_privileged sh
    else
        log_fatal "curl or wget required to install tailscale."
    fi
elif os_is_macos; then
    if has_command brew; then
        installer_brew_install tailscale
    else
        log_fatal "Homebrew required to install tailscale on macOS (or use the App Store app)."
    fi
elif os_is_windows; then
    if has_command winget; then
        installer_winget_install "tailscale.tailscale"
    else
        log_fatal "Cannot install tailscale on Windows: winget required."
    fi
fi

log_success "tailscale installed."

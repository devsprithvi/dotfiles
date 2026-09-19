#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Microsoft Dev Tunnel (install only) ────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs Microsoft's standalone Dev Tunnels CLI binary (~/.local/bin/devtunnel).
#
# Boundary: this script ONLY installs. Authenticating and hosting ports are
# runtime actions: services/index.sh run devtunnel:host
# (via the generic runner services/run.sh + presets.sh).
#
# Control: ENABLE_DEVTUNNEL=1 (or ENABLE_DEV_TUNNEL=1) to install
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "devtunnel"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_DEVTUNNEL:-}" && -z "${ENABLE_DEV_TUNNEL:-}" ]]; then
    log_info "devtunnel skipped (set ENABLE_DEVTUNNEL=1 to enable)."
    exit 0
fi

DEST="$HOME/.local/bin/devtunnel"

if [[ -x "$DEST" ]] || has_command devtunnel; then
    log_info "devtunnel is already installed."
    exit 0
fi

# ── Windows: use winget ─────────────────────────────────────────────────────
if os_is_windows; then
    if has_command winget; then
        installer_winget_install "Microsoft.devtunnel"
    else
        log_warn "Skipping devtunnel on Windows: winget required."
    fi
    exit 0
fi

# ── Dependency resolution (Linux libsecret) ────────────────────────────────
if os_is_linux && can_run_privileged; then
    if os_distro_like debian && ! dpkg -s libsecret-1-0 >/dev/null 2>&1; then
        log_info "Installing libsecret dependency..."
        installer_apt_install libsecret-1-0 || true
    fi
fi

# ── Platform & architecture asset mapping ──────────────────────────────────
asset=""
if os_is_linux; then
    case "${OS_ARCH_ALT}" in
        amd64) asset="linux-x64-devtunnel" ;;
        arm64) asset="linux-arm64-devtunnel" ;;
        *)
            log_fatal "Unsupported Linux architecture (${OS_ARCH})."
            ;;
    esac
elif os_is_macos; then
    case "${OS_ARCH_ALT}" in
        amd64) asset="osx-x64-devtunnel" ;;
        arm64) asset="osx-arm64-devtunnel" ;;
        *)
            log_fatal "Unsupported macOS architecture (${OS_ARCH})."
            ;;
    esac
fi

url="https://tunnelsassetsprod.blob.core.windows.net/cli/${asset}"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

log_info "Downloading Microsoft Dev Tunnels CLI (${asset})..."
if ! curl -fsSL "$url" -o "$tmp"; then
    log_fatal "Failed to download devtunnel from $url"
fi

mkdir -p "$HOME/.local/bin"
mv "$tmp" "$DEST"
chmod +x "$DEST"

if "$DEST" --version >/dev/null 2>&1; then
    version="$("$DEST" --version 2>/dev/null | head -n 1)"
    log_success "devtunnel installed (${version:-ok})."
else
    log_warn "devtunnel installed at $DEST but verification exited non-zero."
    log_success "devtunnel installed (unverified)."
fi

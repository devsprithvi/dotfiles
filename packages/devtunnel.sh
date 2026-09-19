#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: Microsoft Dev Tunnel ───────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs Microsoft's standalone Dev Tunnels CLI binary (~/.local/bin/devtunnel).
# Used for port forwarding, remote access, and tunneling independently from VS Code.
#
# Control: ENABLE_DEVTUNNEL=1 (or ENABLE_DEV_TUNNEL=1) to install
# Auth:    Optional non-interactive login if DEVTUNNEL_TOKEN or GITHUB_PAT
#          is available in environment or Infisical.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_DEVTUNNEL:-}" && -z "${ENABLE_DEV_TUNNEL:-}" ]]; then
    echo "devtunnel skipped (set ENABLE_DEVTUNNEL=1 to enable)."
    exit 0
fi

DEST="$HOME/.local/bin/devtunnel"

if [[ -x "$DEST" ]] || has_command devtunnel; then
    echo "devtunnel is already installed."
    exit 0
fi

if os_is_windows; then
    if has_command winget; then
        installer_winget_install "Microsoft.devtunnel"
    else
        echo "Skipping devtunnel on Windows: winget required."
        exit 0
    fi
    exit 0
fi

# ── Dependency resolution (Linux libsecret) ────────────────────────────────
if os_is_linux && can_run_privileged; then
    if os_distro_like debian && ! dpkg -s libsecret-1-0 >/dev/null 2>&1; then
        echo "[devtunnel] Installing libsecret dependency..."
        installer_apt_install libsecret-1-0 || true
    fi
fi

# ── Platform & architecture asset URL mapping ──────────────────────────────
base_url="https://tunnelsassetsprod.blob.core.windows.net/cli"
asset_name=""

if os_is_linux; then
    case "${OS_ARCH}" in
        x86_64)         asset_name="linux-x64-devtunnel" ;;
        aarch64|arm64)  asset_name="linux-arm64-devtunnel" ;;
        *)
            echo "ERROR: Unsupported Linux architecture (${OS_ARCH})." >&2
            exit 1
            ;;
    esac
elif os_is_macos; then
    case "${OS_ARCH}" in
        x86_64)         asset_name="osx-x64-devtunnel" ;;
        aarch64|arm64)  asset_name="osx-arm64-devtunnel" ;;
        *)
            echo "ERROR: Unsupported macOS architecture (${OS_ARCH})." >&2
            exit 1
            ;;
    esac
else
    echo "Skipping devtunnel — unsupported platform (${OS_FAMILY})."
    exit 0
fi

download_url="${base_url}/${asset_name}"
mkdir -p "$HOME/.local/bin"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "[devtunnel] Downloading Microsoft Dev Tunnels CLI (${asset_name})..."
if ! curl -fsSL "$download_url" -o "$tmp"; then
    echo "ERROR: Failed to download devtunnel from $download_url" >&2
    exit 1
fi

mv "$tmp" "$DEST"
chmod +x "$DEST"

# ── Verify ─────────────────────────────────────────────────────────────────
if "$DEST" --version >/dev/null 2>&1; then
    version="$("$DEST" --version 2>/dev/null | head -n 1)"
    echo "devtunnel installed (${version:-ok})."
else
    echo "WARNING: devtunnel binary installed at $DEST but verification exited non-zero." >&2
    echo "devtunnel installed (unverified)."
fi

# ── Optional: Authenticate if token/PAT is provided ────────────────────────
token="${DEVTUNNEL_TOKEN:-}"
if [[ -z "$token" ]]; then
    token="$(fetch_infisical_secret "DEVTUNNEL_TOKEN" "global" "/tunnels" 2>/dev/null || true)"
fi
if [[ -z "$token" ]]; then
    token="$(fetch_infisical_secret "GITHUB_VSCODE_PAT" "global" "/github" 2>/dev/null || true)"
fi

if [[ -n "$token" ]]; then
    echo "[devtunnel] Authenticating with access token..."
    "$DEST" user login -d --access-token "$token" 2>/dev/null || {
        echo "[devtunnel] Note: Non-interactive token login attempted. Run 'devtunnel user login' if needed."
    }
else
    echo "[devtunnel] Ready. Run 'devtunnel user login' to authenticate with GitHub or Microsoft."
fi


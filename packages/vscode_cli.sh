#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: VS Code CLI (install only) ─────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs the standalone VS Code CLI binary (~/.local/bin/code) — the
# lightweight CLI, NOT the full desktop editor.
#
# Boundary: this script ONLY installs. Running a tunnel or the web server is a
# startup command (preset vscode:tunnel | vscode:web) — declared via
# DOTFILES_STARTUP and run by commands/run.sh + commands/presets/.
#
# Control: ENABLE_VSCODE_CLI=1 to install (optional, off by default)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "vscode-cli"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_VSCODE_CLI:-}" ]]; then
    log_info "vscode cli skipped (set ENABLE_VSCODE_CLI=1 to enable)."
    exit 0
fi

DEST="$HOME/.local/bin/code"

# Check the specific install path — not `has_command code` — because a full
# VS Code desktop installation also provides `code` on PATH.
if [[ -x "$DEST" ]]; then
    log_info "vscode cli is already installed."
    exit 0
fi

if os_is_windows; then
    log_info "Skipping VS Code CLI on Windows (use the desktop installer)."
    exit 0
fi

# ── Platform & architecture asset mapping ──────────────────────────────────
# Microsoft serves the standalone Linux CLI as the musl-static "alpine" build
# (there is no cli-linux-x64/arm64); it runs on mainstream glibc distros too.
# Only 32-bit ARM uses cli-linux-armhf. darwin assets are .zip, linux .tar.gz.
asset=""
if os_is_linux; then
    case "${OS_ARCH_ALT}" in
        amd64) asset="cli-alpine-x64" ;;
        arm64) asset="cli-alpine-arm64" ;;
        armhf) asset="cli-linux-armhf" ;;
        *)
            log_fatal "Unsupported Linux architecture (${OS_ARCH})."
            ;;
    esac
elif os_is_macos; then
    case "${OS_ARCH_ALT}" in
        amd64) asset="cli-darwin-x64" ;;
        arm64) asset="cli-darwin-arm64" ;;
        *)
            log_fatal "Unsupported macOS architecture (${OS_ARCH})."
            ;;
    esac
fi

url="https://code.visualstudio.com/sha/download?build=stable&os=${asset}"
tmp_ar="$(mktemp)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_ar" "$tmp_dir"' EXIT

log_info "Downloading VS Code CLI (${asset})..."
if ! curl -fsSL "$url" -o "$tmp_ar"; then
    log_fatal "Failed to download VS Code CLI from $url"
fi

# darwin assets are .zip; linux assets are .tar.gz.
case "${asset}" in
    cli-darwin-*)
        if ! has_command unzip; then
            log_fatal "'unzip' is required to extract the CLI archive."
        fi
        unzip -qo "$tmp_ar" -d "$tmp_dir"
        ;;
    *)
        tar -xf "$tmp_ar" -C "$tmp_dir"
        ;;
esac

# The archive contains a single executable named `code`.
extracted="$(find "$tmp_dir" -maxdepth 2 -type f -name 'code' | head -n 1)"
if [[ -z "$extracted" ]]; then
    log_fatal "'code' binary not found in downloaded archive."
fi

mkdir -p "$HOME/.local/bin"
mv "$extracted" "$DEST"
chmod +x "$DEST"

version="$("$DEST" --version 2>/dev/null | head -n 1)"
log_success "vscode cli installed (${version:-ok})."

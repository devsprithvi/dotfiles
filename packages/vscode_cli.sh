#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Package: VS Code CLI ────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Installs the standalone VS Code CLI binary (~/.local/bin/code).
# This is the lightweight CLI — NOT the full desktop editor.
# Used for: tunnels, serve-web, extension management on headless machines.
#
# Control: ENABLE_VSCODE_CLI=1 to install (optional, off by default)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

# ── Gate: opt-in only ──────────────────────────────────────────────────────
if [[ -z "${ENABLE_VSCODE_CLI:-}" ]]; then
    echo "vscode cli skipped (set ENABLE_VSCODE_CLI=1 to enable)."
    exit 0
fi

# Check the specific install path — not `has_command code` — because a full
# VS Code desktop installation also provides `code` on PATH.
if [[ -x "$HOME/.local/bin/code" ]]; then
    echo "vscode cli is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    install_vscode_cli
elif os_is_windows; then
    echo "Skipping VS Code CLI on Windows (use the desktop installer)."
    exit 0
fi

echo "vscode cli installed."


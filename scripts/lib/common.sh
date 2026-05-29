#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Core libraries ──────────────────────────────────────────────────────────
source "${LIB_DIR}/os.sh"
source "${LIB_DIR}/privilege.sh"

# ── Installer libraries ────────────────────────────────────────────────────
source "${LIB_DIR}/installers/common.sh"
source "${LIB_DIR}/installers/url.sh"
source "${LIB_DIR}/installers/apt.sh"
source "${LIB_DIR}/installers/dnf.sh"
source "${LIB_DIR}/installers/pacman.sh"
source "${LIB_DIR}/installers/yum.sh"
source "${LIB_DIR}/installers/apk.sh"
source "${LIB_DIR}/installers/zypper.sh"
source "${LIB_DIR}/installers/brew.sh"
source "${LIB_DIR}/installers/scoop.sh"
source "${LIB_DIR}/installers/choco.sh"
source "${LIB_DIR}/installers/winget.sh"

# ── Utilities ───────────────────────────────────────────────────────────────

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# ── Ensure user-level bin is on PATH ────────────────────────────────────────
# Many tools (chezmoi, sheldon, starship, agy) install to ~/.local/bin.
# In GitHub Codespaces and containers this directory is often NOT on PATH
# during the bootstrap session. This ensures it's always available.
ensure_user_bin_in_path() {
    local user_bin="$HOME/.local/bin"
    mkdir -p "${user_bin}"
    if [[ ":${PATH}:" != *":${user_bin}:"* ]]; then
        export PATH="${user_bin}:${PATH}"
    fi
}

# Auto-run on source so every script gets ~/.local/bin in PATH
ensure_user_bin_in_path

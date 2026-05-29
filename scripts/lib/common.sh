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

# Ensure user-local bin is always on PATH when our scripts run.
# Many tools (chezmoi, starship, sheldon, agy) install here.
export PATH="${HOME}/.local/bin:${PATH}"

has_command() {
    command -v "$1" >/dev/null 2>&1
}

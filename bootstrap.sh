#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Configuration ───────────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

GITHUB_USER="devsprithvi"
DOTFILES_REPO="dotfiles"
BIN_DIR="$HOME/.local/bin"

# ────────────────────────────────────────────────────────────────────────────
# ── Helper Functions ────────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Check if a specific command is available in the current environment
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Run a command with privilege (root or sudo) if available
run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "ERROR: Root privileges are required but sudo is not installed." >&2
        return 127
    fi
}

# Ensure user's local binary directory exists and is at the front of PATH
setup_path() {
    mkdir -p "$BIN_DIR"
    export PATH="$BIN_DIR:$PATH"
}

# ────────────────────────────────────────────────────────────────────────────
# ── Package Installations ───────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Install curl using the system package manager (fallback if curl is missing)
install_curl() {
    echo "[bootstrap] curl not found. Attempting auto-installation..."
    
    if has_command apt-get; then
        run_privileged apt-get update -qq && run_privileged apt-get install -y -qq curl
    elif has_command dnf; then
        run_privileged dnf install -y curl
    elif has_command pacman; then
        run_privileged pacman -Sy --noconfirm --needed curl
    elif has_command apk; then
        run_privileged apk add --no-cache curl
    elif has_command zypper; then
        run_privileged zypper --non-interactive install curl
    else
        echo "ERROR: curl is not installed and no supported package manager was found." >&2
        echo "Please install curl manually and run this script again." >&2
        exit 1
    fi
    
    if ! has_command curl; then
        echo "ERROR: Failed to install curl. Cannot continue." >&2
        exit 1
    fi
}

# Detect or install chezmoi on the system
install_chezmoi() {
    # If chezmoi is already available on PATH, we are good to go
    if has_command chezmoi; then
        echo "[bootstrap] chezmoi is already installed."
        return 0
    fi

    # Fallback check in case chezmoi exists in local bin but PATH isn't updated yet
    if [[ -x "$BIN_DIR/chezmoi" ]]; then
        echo "[bootstrap] chezmoi is already installed at $BIN_DIR/chezmoi."
        return 0
    fi

    echo "[bootstrap] chezmoi not found. Installing to $BIN_DIR..."
    
    # We require curl to download chezmoi from the installer URL
    if ! has_command curl; then
        install_curl
    fi

    curl -fsSL https://get.chezmoi.io | sh -s -- -b "$BIN_DIR"
    
    if [[ ! -x "$BIN_DIR/chezmoi" ]] && ! has_command chezmoi; then
        echo "ERROR: chezmoi was not installed successfully." >&2
        exit 1
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# ── Chezmoi Initialization ──────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

# Initialize and apply the chezmoi dotfiles repository
init_dotfiles() {
    echo "[bootstrap] Initializing dotfiles with chezmoi..."
    
    local repo_url="https://github.com/${GITHUB_USER}/${DOTFILES_REPO}.git"
    local chezmoi_bin="chezmoi"

    if [[ -x "$BIN_DIR/chezmoi" ]]; then
        chezmoi_bin="$BIN_DIR/chezmoi"
    fi

    # Apply the dotfiles repository directly using chezmoi
    "$chezmoi_bin" init --apply "$repo_url"
}

# ────────────────────────────────────────────────────────────────────────────
# ── Main Execution Flow ─────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║       Dotfiles Bootstrap                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    setup_path
    install_chezmoi
    init_dotfiles

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║       Bootstrap complete!                ║"
    echo "║       Open a new shell to continue.      ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
}

main "$@"


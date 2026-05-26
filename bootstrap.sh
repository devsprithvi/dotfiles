#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_installer() {
    local installer_name="$1"
    local step_name="${installer_name//_/ }"

    echo "[dotfiles] Installing ${step_name}..."
    bash "${SCRIPT_DIR}/scripts/install/${installer_name}.sh"
    echo "[dotfiles] Finished ${step_name}."
}

echo "Starting modular dotfiles bootstrap..."

run_installer "curl"
run_installer "git"
run_installer "zsh"
run_installer "gh"
run_installer "starship"
run_installer "sheldon"
run_installer "antigravity_cli"
run_installer "infisical"
run_installer "chezmoi"

echo "==========================================="
echo "Bootstrap complete!"
echo "If this is a new machine, you can now run:"
echo "  chezmoi init --apply devsprithvi"
echo "If chezmoi is not on your PATH yet, run:"
echo "  ~/.local/bin/chezmoi init --apply devsprithvi"
echo "==========================================="

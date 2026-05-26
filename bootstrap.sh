#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_step() {
    local step_name="$1"
    local script_path="$2"

    echo "[dotfiles] Starting ${step_name}..."
    bash "${script_path}"
    echo "[dotfiles] Finished ${step_name}."
}

echo "Starting modular dotfiles bootstrap..."

run_step "core tools" "${SCRIPT_DIR}/scripts/install_core_tools.sh"
run_step "config tools" "${SCRIPT_DIR}/scripts/install_config_tools.sh"
run_step "Infisical" "${SCRIPT_DIR}/scripts/install_infisical.sh"
run_step "Chezmoi" "${SCRIPT_DIR}/scripts/install_chezmoi.sh"

echo "==========================================="
echo "Bootstrap complete!"
echo "If this is a new machine, you can now run:"
echo "  chezmoi init --apply devsprithvi"
echo "If chezmoi is not on your PATH yet, run:"
echo "  ~/.local/bin/chezmoi init --apply devsprithvi"
echo "==========================================="

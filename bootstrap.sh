#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting modular dotfiles bootstrap..."

bash "${SCRIPT_DIR}/scripts/install_core_tools.sh"
bash "${SCRIPT_DIR}/scripts/install_config_tools.sh"
bash "${SCRIPT_DIR}/scripts/install_infisical.sh"
bash "${SCRIPT_DIR}/scripts/install_chezmoi.sh"

echo "==========================================="
echo "Bootstrap complete!"
echo "If this is a new machine, you can now run:"
echo "  chezmoi init --apply devsprithvi"
echo "==========================================="

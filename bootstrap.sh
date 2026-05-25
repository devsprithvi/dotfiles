#!/usr/bin/env bash
set -e

echo "Starting modular dotfiles bootstrap..."

bash ./scripts/install_core_tools.sh
bash ./scripts/install_config_tools.sh
bash ./scripts/install_infisical.sh
bash ./scripts/install_chezmoi.sh

echo "==========================================="
echo "Bootstrap complete!"
echo "If this is a new machine, you can now run:"
echo "  chezmoi init --apply devsprithvi"
echo "==========================================="

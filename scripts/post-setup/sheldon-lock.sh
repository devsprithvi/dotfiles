#!/usr/bin/env bash
set -eo pipefail

# ── Post-Setup: Sheldon Plugin Lock ────────────────────────────────────────
# Pre-downloads and locks sheldon plugins so the first shell launch
# is instant rather than waiting for plugin downloads.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if ! has_command sheldon; then
    echo "[sheldon-lock] sheldon is not installed. Skipping."
    exit 0
fi

SHELDON_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon"

# ── Lock zsh plugins ──────────────────────────────────────────────────────
if [[ -f "${SHELDON_CONFIG_DIR}/zsh.toml" ]]; then
    echo "[sheldon-lock] Locking zsh plugins..."
    sheldon --config-file "${SHELDON_CONFIG_DIR}/zsh.toml" lock && \
        echo "[sheldon-lock] zsh plugins locked." || \
        echo "[sheldon-lock] WARNING: Failed to lock zsh plugins."
fi

# ── Lock bash plugins ─────────────────────────────────────────────────────
if [[ -f "${SHELDON_CONFIG_DIR}/bash.toml" ]]; then
    echo "[sheldon-lock] Locking bash plugins..."
    sheldon --config-file "${SHELDON_CONFIG_DIR}/bash.toml" lock && \
        echo "[sheldon-lock] bash plugins locked." || \
        echo "[sheldon-lock] WARNING: Failed to lock bash plugins."
fi

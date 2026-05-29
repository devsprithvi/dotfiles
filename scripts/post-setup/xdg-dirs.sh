#!/usr/bin/env bash
set -eo pipefail

# ── Post-Setup: XDG Base Directories ──────────────────────────────────────
# Ensures standard XDG directories exist so tools don't create them
# with wrong permissions or fail silently on a fresh machine.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if os_is_windows; then
    echo "[xdg-dirs] Skipping XDG directory creation on Windows."
    exit 0
fi

echo "[xdg-dirs] Ensuring XDG base directories exist..."

# XDG Base Directory Specification defaults
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
LOCAL_BIN="$HOME/.local/bin"

dirs=(
    "${XDG_CONFIG_HOME}"
    "${XDG_DATA_HOME}"
    "${XDG_STATE_HOME}"
    "${XDG_CACHE_HOME}"
    "${LOCAL_BIN}"
)

for dir in "${dirs[@]}"; do
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
        echo "[xdg-dirs]   Created ${dir}"
    fi
done

echo "[xdg-dirs] XDG directories ready."

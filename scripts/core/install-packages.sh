#!/usr/bin/env bash
set -eo pipefail

# ── Core: Install Packages ─────────────────────────────────────────────────
# Called by chezmoi run_once during `chezmoi apply`.
# Installs all tools from scripts/packages/ in the correct order.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="${SCRIPT_DIR}/../packages"

source "${SCRIPT_DIR}/../lib/common.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Installing Packages                ║"
echo "╚══════════════════════════════════════════╝"
echo ""

os_print_summary

run_package() {
    local name="$1"
    local script="${PACKAGES_DIR}/${name}.sh"

    if [[ ! -f "${script}" ]]; then
        echo "[packages] ERROR: ${name}.sh not found. Skipping."
        return 1
    fi

    echo ""
    echo "[packages] ── ${name} ──────────────────────"
    bash "${script}"
    # Refresh PATH — the package may have installed to ~/.local/bin
    ensure_user_bin_in_path
}

# ── System prerequisites (may need sudo) ────────────────────────────────────
run_package "git"
run_package "curl"
run_package "zsh"

# ── User-level tools (no sudo) ─────────────────────────────────────────────
run_package "starship"
run_package "sheldon"
run_package "gh"
run_package "antigravity_cli"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       All packages installed!            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

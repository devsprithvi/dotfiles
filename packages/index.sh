#!/usr/bin/env bash
set -eo pipefail

# ────────────────────────────────────────────────────────────────────────────
# ── Packages Universal Index & Orchestrator ─────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# This file serves as the single entry point to install all defined packages
# in the correct dependency order.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Installing Packages                ║"
echo "╚══════════════════════════════════════════╝"
echo ""

os_print_summary

run_package() {
    local name="$1"
    local script="${SCRIPT_DIR}/${name}.sh"

    if [[ ! -f "${script}" ]]; then
        echo "[packages] ERROR: ${name}.sh not found. Skipping."
        return 1
    fi

    echo ""
    echo "[packages] ── ${name} ──────────────────────"
    bash "${script}"
}

# ── 1. System prerequisites (may need sudo) ─────────────────────────────────
run_package "git"
run_package "curl"
run_package "zsh"

# ── 2. User-level tools (no sudo) ───────────────────────────────────────────
run_package "starship"
run_package "sheldon"
run_package "gh"
run_package "infisical"
run_package "antigravity_cli"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       All packages installed!            ║"
echo "╚══════════════════════════════════════════╝"
echo ""

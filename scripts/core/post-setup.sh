#!/usr/bin/env bash
set -eo pipefail

# ── Core: Post-Setup ──────────────────────────────────────────────────────
# Called by chezmoi run_once_after during `chezmoi apply`.
# Performs system-level configuration AFTER all packages are installed
# and dotfiles are in place. This is where the machine becomes "yours".
#
# Order matters:
#   1. XDG directories   — foundation for everything else
#   2. Shell change       — set zsh as default login shell
#   3. GitHub CLI auth    — authenticate gh with PAT from Infisical
#   4. Sheldon lock       — pre-download shell plugins for instant first launch
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POST_SETUP_DIR="${SCRIPT_DIR}/../post-setup"

source "${SCRIPT_DIR}/../lib/common.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Post-Setup: System Config          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

os_print_summary

run_post_setup() {
    local name="$1"
    local script="${POST_SETUP_DIR}/${name}.sh"

    if [[ ! -f "${script}" ]]; then
        echo "[post-setup] WARNING: ${name}.sh not found. Skipping."
        return 0
    fi

    echo ""
    echo "[post-setup] ── ${name} ──────────────────────"
    bash "${script}"
}

# ── 1. Foundation ──────────────────────────────────────────────────────────
run_post_setup "xdg-dirs"

# ── 2. Shell ───────────────────────────────────────────────────────────────
run_post_setup "shell"

# ── 3. Authentication ─────────────────────────────────────────────────────
run_post_setup "gh-auth"

# ── 4. Plugin Initialization ──────────────────────────────────────────────
run_post_setup "sheldon-lock"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Post-setup complete!               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

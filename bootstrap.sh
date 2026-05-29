#!/usr/bin/env bash
set -eo pipefail

# ── Bootstrap ───────────────────────────────────────────────────────────────
# Entry point for a fresh machine.
# Installs curl, git, chezmoi, and infisical, then fetches the GitHub PAT
# from Infisical and runs `chezmoi init --apply` with inline auth to clone
# the private dotfiles repo seamlessly.
# All other tools are installed by chezmoi run_once scripts, NOT here.
# ────────────────────────────────────────────────────────────────────────────

GITHUB_USER="devsprithvi"
DOTFILES_REPO="dotfiles"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/scripts/lib/common.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Dotfiles Bootstrap                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""

os_print_summary

# ── Step 1: Install curl ───────────────────────────────────────────────────
# curl is needed to download chezmoi and other installers.
if ! has_command curl; then
    echo "[bootstrap] curl not found. Installing..."
    bash "${SCRIPT_DIR}/scripts/packages/curl.sh"
fi

if ! has_command curl; then
    echo ""
    echo "ERROR: Failed to install curl. Cannot continue."
    exit 1
fi

# ── Step 2: Install git ────────────────────────────────────────────────────
# git is needed by chezmoi to clone the dotfiles repo.
if ! has_command git; then
    echo "[bootstrap] git not found. Installing..."
    bash "${SCRIPT_DIR}/scripts/packages/git.sh"
fi

if ! has_command git; then
    echo ""
    echo "ERROR: Failed to install git. Cannot continue."
    exit 1
fi

# ── Step 3: Install chezmoi ─────────────────────────────────────────────────
echo "[bootstrap] Installing chezmoi..."
bash "${SCRIPT_DIR}/scripts/packages/chezmoi.sh"
ensure_user_bin_in_path

# ── Step 4: Install & authenticate infisical ────────────────────────────────
echo "[bootstrap] Installing infisical..."
bash "${SCRIPT_DIR}/scripts/packages/infisical.sh"
ensure_user_bin_in_path

# ── Step 5: Fetch PAT & initialize dotfiles ─────────────────────────────────
# The dotfiles repo is private, so we fetch the GitHub PAT from Infisical
# and pass it inline in the clone URL. This avoids needing git credentials
# or gh auth to be configured before the first clone.
echo ""
echo "[bootstrap] Fetching GitHub PAT from Infisical..."

GH_TOKEN=$(infisical secrets get ADMIN_PAT --env global --path /github --plain 2>/dev/null || true)

if [[ -z "${GH_TOKEN}" ]]; then
    echo ""
    echo "ERROR: Could not retrieve GitHub PAT from Infisical."
    echo "Ensure infisical is authenticated and ADMIN_PAT is set at /github."
    exit 1
fi

REPO_URL="https://${GH_TOKEN}@github.com/${GITHUB_USER}/${DOTFILES_REPO}.git"

echo "[bootstrap] Initializing dotfiles with chezmoi..."

if has_command chezmoi; then
    chezmoi init --apply "${REPO_URL}"
elif [[ -x "$HOME/.local/bin/chezmoi" ]]; then
    "$HOME/.local/bin/chezmoi" init --apply "${REPO_URL}"
else
    echo ""
    echo "ERROR: chezmoi was not installed successfully."
    exit 1
fi

# Clean up sensitive variable
unset GH_TOKEN REPO_URL

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Bootstrap complete!                ║"
echo "║       Open a new shell to continue.      ║"
echo "╚══════════════════════════════════════════╝"
echo ""

#!/usr/bin/env bash

# ────────────────────────────────────────────────────────────────────────────
# ── Utilities Universal Index ────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Sourcing this file loads the core system detection and helpers, and serves
# as the single entry point for our entire utility library.
# ────────────────────────────────────────────────────────────────────────────

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Step 1: Load Core System & Helper Libraries ─────────────────────────────
source "${LIB_DIR}/os.sh"
source "${LIB_DIR}/helpers.sh"

# ── Step 2: Load Installer Modules ──────────────────────────────────────────
# Symmetrically load the modular, self-contained installer wrappers.
source "${LIB_DIR}/installers/url.sh"
source "${LIB_DIR}/installers/apk.sh"
source "${LIB_DIR}/installers/apt.sh"
source "${LIB_DIR}/installers/dnf.sh"
source "${LIB_DIR}/installers/pacman.sh"
source "${LIB_DIR}/installers/brew.sh"
source "${LIB_DIR}/installers/scoop.sh"
source "${LIB_DIR}/installers/winget.sh"

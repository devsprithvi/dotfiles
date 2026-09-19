#!/usr/bin/env bash

# ────────────────────────────────────────────────────────────────────────────
# ── Utilities Universal Index ────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Sourcing this file loads the core system detection and helpers, and serves
# as the single entry point for our entire utility library.
# ────────────────────────────────────────────────────────────────────────────

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Step 1: Load Core System & Helper Libraries ─────────────────────────────
# os.sh first so the logger's session header can report OS/arch details.
source "${LIB_DIR}/os.sh"
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/../secrets/index.sh"
source "${LIB_DIR}/service_manager.sh"

# ── Step 2: Load Installer Modules ──────────────────────────────────────────
# Generic, reusable package-manager wrappers. Each module provides a thin
# function around a system package manager (apt, dnf, pacman, etc.). They live
# alongside their only consumers under packages/installers/ and are auto-loaded
# by that directory's index.
source "${LIB_DIR}/../packages/installers/index.sh"

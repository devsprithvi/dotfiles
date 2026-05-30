#!/usr/bin/env bash

installer_brew_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { echo "ERROR: Package name is required." >&2; return 1; }

    echo "[installer] Installing ${package_name} via Homebrew..."
    brew install "${package_name}"
}


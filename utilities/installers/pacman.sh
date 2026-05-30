#!/usr/bin/env bash

installer_pacman_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { echo "ERROR: Package name is required." >&2; return 1; }
    can_run_privileged || { echo "ERROR: pacman requires root or passwordless sudo." >&2; return 1; }

    echo "[installer] Installing ${package_name} via pacman..."
    run_privileged pacman -Sy --noconfirm --needed "${package_name}"
}


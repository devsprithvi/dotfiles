#!/usr/bin/env bash

installer_dnf_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { echo "ERROR: Package name is required." >&2; return 1; }
    can_run_privileged || { echo "ERROR: dnf requires root or passwordless sudo." >&2; return 1; }

    echo "[installer] Installing ${package_name} via dnf..."
    run_privileged dnf install -y "${package_name}"
}


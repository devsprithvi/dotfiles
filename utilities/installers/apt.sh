#!/usr/bin/env bash

installer_apt_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { echo "ERROR: Package name is required." >&2; return 1; }
    can_run_privileged || { echo "ERROR: apt-get requires root or passwordless sudo." >&2; return 1; }

    export DEBIAN_FRONTEND=noninteractive

    # Only run apt-get update once per session to save massive time
    if [[ -z "${_APT_UPDATED:-}" ]]; then
        echo "[installer] Updating apt package lists..."
        run_privileged apt-get update -qq
        _APT_UPDATED=1
    fi

    echo "[installer] Installing ${package_name} via apt..."
    run_privileged apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${package_name}"
}



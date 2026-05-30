#!/usr/bin/env bash

installer_apk_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { echo "ERROR: Package name is required." >&2; return 1; }
    can_run_privileged || { echo "ERROR: apk requires root or passwordless sudo." >&2; return 1; }

    echo "[installer] Installing ${package_name} via apk..."
    run_privileged apk add --no-cache "${package_name}"
}


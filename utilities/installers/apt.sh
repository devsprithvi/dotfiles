#!/usr/bin/env bash

installer_apt_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }
    can_run_privileged || { log_error "apt-get requires root or passwordless sudo."; return 1; }

    export DEBIAN_FRONTEND=noninteractive

    # Only run apt-get update once per session to save massive time
    if [[ -z "${_APT_UPDATED:-}" ]]; then
        log_info "Updating apt package lists..."
        log_run run_privileged apt-get update -qq
        _APT_UPDATED=1
    fi

    log_info "Installing ${package_name} via apt..."
    log_run run_privileged apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${package_name}"
}



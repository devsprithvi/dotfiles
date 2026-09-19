#!/usr/bin/env bash

installer_scoop_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }

    log_info "Installing ${package_name} via scoop..."
    log_run scoop install "${package_name}"
}


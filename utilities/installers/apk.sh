#!/usr/bin/env bash

installer_apk_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }
    can_run_privileged || { log_error "apk requires root or passwordless sudo."; return 1; }

    log_info "Installing ${package_name} via apk..."
    log_run run_privileged apk add --no-cache "${package_name}"
}


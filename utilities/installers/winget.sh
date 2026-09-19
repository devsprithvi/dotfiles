#!/usr/bin/env bash

installer_winget_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }

    log_info "Installing ${package_name} via winget..."
    log_run winget install --exact --id "${package_name}" --accept-package-agreements --accept-source-agreements
}


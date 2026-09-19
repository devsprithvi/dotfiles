#!/usr/bin/env bash

installer_brew_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }

    log_info "Installing ${package_name} via Homebrew..."
    log_run brew install "${package_name}"
}


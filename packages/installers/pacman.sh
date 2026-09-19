#!/usr/bin/env bash

installer_pacman_install() {
    local package_name="$1"

    [[ -z "${package_name}" ]] && { log_error "Package name is required."; return 1; }
    can_run_privileged || { log_error "pacman requires root or passwordless sudo."; return 1; }

    log_info "Installing ${package_name} via pacman..."
    log_run run_privileged pacman -Sy --noconfirm --needed "${package_name}"
}


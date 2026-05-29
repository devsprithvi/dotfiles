#!/usr/bin/env bash

installer_pacman_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "pacman" || return 1

    run_privileged pacman -Sy --noconfirm --needed "${package_name}"
}

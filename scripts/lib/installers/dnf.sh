#!/usr/bin/env bash

installer_dnf_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "dnf" || return 1

    run_privileged dnf install -y "${package_name}"
}

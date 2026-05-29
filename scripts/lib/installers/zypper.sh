#!/usr/bin/env bash

installer_zypper_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "zypper" || return 1

    run_privileged zypper --non-interactive install "${package_name}"
}

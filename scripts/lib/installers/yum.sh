#!/usr/bin/env bash

installer_yum_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "yum" || return 1

    run_privileged yum install -y "${package_name}"
}

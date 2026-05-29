#!/usr/bin/env bash

installer_apt_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "apt-get" || return 1

    export DEBIAN_FRONTEND=noninteractive
    run_privileged apt-get update
    run_privileged apt-get install -y "${package_name}"
}

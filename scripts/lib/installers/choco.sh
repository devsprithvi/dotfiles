#!/usr/bin/env bash

installer_choco_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1

    choco install -y "${package_name}"
}

#!/usr/bin/env bash

installer_scoop_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1

    scoop install "${package_name}"
}

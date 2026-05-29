#!/usr/bin/env bash

installer_apk_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1
    installer_require_privileged_access "apk" || return 1

    run_privileged apk add --no-cache "${package_name}"
}

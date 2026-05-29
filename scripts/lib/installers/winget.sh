#!/usr/bin/env bash

installer_winget_install() {
    local package_name="$1"

    installer_require_package_name "${package_name}" || return 1

    winget install --exact --id "${package_name}" --accept-package-agreements --accept-source-agreements
}

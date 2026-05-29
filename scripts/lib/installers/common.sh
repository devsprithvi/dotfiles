#!/usr/bin/env bash

installer_info() {
    printf '%s\n' "$*"
}

installer_warn() {
    printf 'Warning: %s\n' "$*" >&2
}

installer_error() {
    printf 'Error: %s\n' "$*" >&2
}

installer_debug() {
    case "${INSTALLER_DEBUG:-0}" in
        1|true|TRUE|yes|YES|on|ON)
            printf 'Debug: %s\n' "$*" >&2
            ;;
    esac
}

installer_require_package_name() {
    if [ -n "$1" ]; then
        return 0
    fi

    installer_error "Package name is required."
    return 1
}

installer_require_privileged_access() {
    if can_run_privileged; then
        return 0
    fi

    installer_error "${1:-This installer} requires root or passwordless sudo."
    return 1
}

installer_require_download_tool() {
    if has_command curl || has_command wget; then
        return 0
    fi

    installer_error "Neither curl nor wget is available."
    return 1
}

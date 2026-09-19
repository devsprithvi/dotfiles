#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "curl"

if has_command curl; then
    log_info "curl is already installed."
    exit 0
fi

if os_is_macos; then
    # curl is pre-installed on macOS
    log_info "curl should be pre-installed on macOS."
    exit 0
fi

if os_is_windows; then
    log_info "curl should be pre-installed on Windows."
    exit 0
fi

# Linux — system package, needs sudo
if os_is_linux; then
    if os_distro_like debian; then
        installer_apt_install curl
    elif os_distro_like fedora || os_distro_like rhel; then
        installer_dnf_install curl
    elif os_distro_like arch; then
        installer_pacman_install curl
    elif os_distro_like alpine; then
        installer_apk_install curl
    else
        log_fatal "Unknown distro '${OS_DISTRO}'. Cannot install curl automatically."
    fi
fi

if ! has_command curl; then
    log_fatal "Failed to install curl. Cannot continue."
fi

log_success "curl installed."

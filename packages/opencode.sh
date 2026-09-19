#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "opencode"

if has_command opencode; then
    log_info "opencode is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    install_from_url "opencode" "https://opencode.ai/install"
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install opencode
    else
        log_fatal "Cannot install opencode on Windows: scoop required (or use WSL — recommended)."
    fi
fi

log_success "opencode installed."

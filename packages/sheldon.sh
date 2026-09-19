#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/index.sh"
log_set_component "sheldon"

if has_command sheldon; then
    log_info "sheldon is already installed."
    exit 0
fi

if os_is_linux || os_is_macos; then
    install_from_url "sheldon" "https://rossmacarthur.github.io/install/crate.sh" \
        --repo rossmacarthur/sheldon --to "$HOME/.local/bin"
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install sheldon
    else
        log_fatal "Cannot install sheldon on Windows: scoop required."
    fi
fi

log_success "sheldon installed."

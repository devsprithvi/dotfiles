#!/usr/bin/env bash

is_root() {
    [ "$(id -u)" -eq 0 ]
}

has_passwordless_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

can_run_privileged() {
    is_root || has_passwordless_sudo
}

run_privileged() {
    if is_root; then
        "$@"
    elif has_passwordless_sudo; then
        sudo -n "$@"
    else
        return 127
    fi
}

run_privileged_shell() {
    if is_root; then
        sh -lc "$1"
    elif has_passwordless_sudo; then
        sudo -n sh -lc "$1"
    else
        return 127
    fi
}

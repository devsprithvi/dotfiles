#!/usr/bin/env bash

# Ensure user's local binary directory is always on PATH when our utilities run.
export PATH="${HOME}/.local/bin:${PATH}"

# ── General Helpers ─────────────────────────────────────────────────────────

# Check if a specific command is available in the current environment
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# ── Privilege Helpers ───────────────────────────────────────────────────────

# Check if the current user is root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Check if passwordless sudo is available
has_passwordless_sudo() {
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

# Check if the script can execute commands with privileged rights
can_run_privileged() {
    is_root || has_passwordless_sudo
}

# Run a command with privilege (root or sudo) if available
run_privileged() {
    if is_root; then
        "$@"
    elif has_passwordless_sudo; then
        sudo -n "$@"
    else
        return 127
    fi
}

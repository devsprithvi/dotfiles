#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${LIB_DIR}/os.sh"
source "${LIB_DIR}/privilege.sh"

has_command() {
    command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ]
}

ensure_local_bin_on_path() {
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
}

persist_local_bin_on_path() {
    local export_line='export PATH="$HOME/.local/bin:$PATH"'
    local shell_rc

    for shell_rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
        touch "$shell_rc"

        if ! grep -Fqx "$export_line" "$shell_rc"; then
            printf '\n%s\n' "$export_line" >> "$shell_rc"
        fi
    done
}

prepare_local_bin() {
    mkdir -p "$HOME/.local/bin"
    ensure_local_bin_on_path
    persist_local_bin_on_path
}

download_to_stdout() {
    local url="$1"

    if has_command curl; then
        curl -fsSL "$url"
    elif has_command wget; then
        wget -qO- "$url"
    else
        return 127
    fi
}

require_package_manager() {
    local manager="$1"
    local message="$2"

    if ! has_command "$manager"; then
        echo "$message"
        exit 1
    fi
}

#!/usr/bin/env bash

# Fetch a script from a URL to stdout using curl or wget as a fallback
fetch_url() {
    local url="$1"
    if has_command curl; then
        curl -fsSL "$url"
    elif has_command wget; then
        wget -qO- "$url"
    else
        installer_error "Neither curl nor wget is available."
        return 127
    fi
}

# Download and execute a shell installation script on macOS/Linux using bash
install_from_url() {
    local tool_name="$1" url="$2"
    shift 2

    installer_info "Installing ${tool_name} from URL..."
    fetch_url "${url}" | bash -s -- "$@"
}

# Download and execute a PowerShell script on Windows
install_from_url_windows() {
    local tool_name="$1" url="$2"

    if ! has_command powershell.exe; then
        installer_error "PowerShell is required but not found."
        return 1
    fi

    installer_info "Installing ${tool_name} on Windows..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod '${url}')"
}

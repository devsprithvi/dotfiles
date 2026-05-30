#!/usr/bin/env bash

# Fetch a script from a URL to stdout using curl or wget as a fallback
fetch_url() {
    local url="$1"
    if has_command curl; then
        curl -fsSL "$url"
    elif has_command wget; then
        wget -qO- "$url"
    else
        echo "ERROR: Neither curl nor wget is available." >&2
        return 127
    fi
}

# Download and execute a shell installation script on macOS/Linux using bash
install_from_url() {
    local tool_name="$1" url="$2"
    shift 2

    echo "[installer] Installing ${tool_name} from URL..."
    fetch_url "${url}" | bash -s -- "$@"
}

# Download and execute a PowerShell script on Windows
install_from_url_windows() {
    local tool_name="$1" url="$2"

    if ! has_command powershell.exe; then
        echo "ERROR: PowerShell is required but not found." >&2
        return 1
    fi

    echo "[installer] Installing ${tool_name} on Windows..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod '${url}')"
}


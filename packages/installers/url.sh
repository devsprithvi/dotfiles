#!/usr/bin/env bash

# Fetch a script from a URL to stdout using curl or wget as a fallback
fetch_url() {
    local url="$1"
    if has_command curl; then
        curl -fsSL "$url"
    elif has_command wget; then
        wget -qO- "$url"
    else
        log_error "Neither curl nor wget is available."
        return 127
    fi
}

# Download and execute a shell installation script on macOS/Linux
install_from_url() {
    local tool_name="$1" url="$2"
    shift 2

    local shell_bin="bash"
    if [[ "$1" == "--shell" ]]; then
        shell_bin="$2"
        shift 2
    fi

    log_info "Installing ${tool_name} from ${url}..."
    # A remote-installer pipe (fetch | shell) can't be handed to log_run as a
    # single command, so run the pipe directly and bracket it with explicit
    # result logging. The installer's own stdout still reaches the console.
    if fetch_url "${url}" | "${shell_bin}" -s -- "$@"; then
        log_success "${tool_name} installer completed."
    else
        local rc="${PIPESTATUS[0]}"
        log_error "${tool_name} installer failed (fetch/exec exit ${rc})."
        return 1
    fi
}

# Download and execute a PowerShell script on Windows
install_from_url_windows() {
    local tool_name="$1" url="$2"

    if ! has_command powershell.exe; then
        log_error "PowerShell is required but not found."
        return 1
    fi

    log_info "Installing ${tool_name} on Windows..."
    if log_run powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod '${url}')"; then
        log_success "${tool_name} installer completed."
    else
        log_error "${tool_name} installer failed."
        return 1
    fi
}


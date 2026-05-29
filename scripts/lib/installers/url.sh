#!/usr/bin/env bash

# ── Download helper (used by installer functions below) ─────────────────────

_download_to_stdout() {
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

# ── URL-based installers ───────────────────────────────────────────────────

installer_url_sh() {
    local tool_name="$1"
    local url="$2"

    shift 2

    installer_info "Installing ${tool_name} from ${url}..."
    _download_to_stdout "${url}" | sh "$@"
}

installer_url_bash() {
    local tool_name="$1"
    local url="$2"

    shift 2

    installer_info "Installing ${tool_name} from ${url}..."
    _download_to_stdout "${url}" | bash "$@"
}

installer_url_powershell() {
    local tool_name="$1"
    local url="$2"

    if ! has_command powershell.exe; then
        installer_error "PowerShell is required for ${tool_name}."
        return 1
    fi

    installer_info "Installing ${tool_name} from ${url}..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Invoke-RestMethod '${url}')"
}

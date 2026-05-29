#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_OS_LIB_LOADED:-}" ]] && return 0
_OS_LIB_LOADED=1

# ── OS Family ───────────────────────────────────────────────────────────────
_kernel="$(uname -s)"

case "${_kernel}" in
    Linux*)             OS_FAMILY="linux"   ;;
    Darwin*)            OS_FAMILY="macos"   ;;
    CYGWIN*|MINGW*|MSYS*) OS_FAMILY="windows" ;;
    *)                  OS_FAMILY="unknown" ;;
esac

# ── Architecture ────────────────────────────────────────────────────────────
OS_ARCH="$(uname -m)"

# Normalized / alternate name (Debian & Go convention)
case "${OS_ARCH}" in
    x86_64)             OS_ARCH_ALT="amd64"   ;;
    aarch64|arm64)      OS_ARCH_ALT="arm64"   ;;
    armv7l|armv6l)      OS_ARCH_ALT="armhf"   ;;
    i386|i686)          OS_ARCH_ALT="386"     ;;
    *)                  OS_ARCH_ALT="${OS_ARCH}" ;;
esac

# ── Distro Detection ───────────────────────────────────────────────────────
OS_DISTRO="unknown"
OS_DISTRO_LIKE=""
OS_DISTRO_VERSION=""
OS_CODENAME=""
OS_PRETTY_NAME=""

if [[ "${OS_FAMILY}" == "linux" ]]; then
    # /etc/os-release is the standard on all modern distros
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release

        OS_DISTRO="${ID:-unknown}"
        OS_DISTRO_LIKE="${ID_LIKE:-}"
        OS_DISTRO_VERSION="${VERSION_ID:-}"
        OS_CODENAME="${VERSION_CODENAME:-}"
        OS_PRETTY_NAME="${PRETTY_NAME:-${OS_DISTRO}}"
    elif command -v lsb_release >/dev/null 2>&1; then
        OS_DISTRO="$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        OS_DISTRO_VERSION="$(lsb_release -sr 2>/dev/null)"
        OS_CODENAME="$(lsb_release -sc 2>/dev/null)"
        OS_PRETTY_NAME="$(lsb_release -sd 2>/dev/null)"
    fi

elif [[ "${OS_FAMILY}" == "macos" ]]; then
    OS_DISTRO="macos"
    if command -v sw_vers >/dev/null 2>&1; then
        OS_DISTRO_VERSION="$(sw_vers -productVersion)"
        OS_PRETTY_NAME="macOS ${OS_DISTRO_VERSION}"
    fi

elif [[ "${OS_FAMILY}" == "windows" ]]; then
    OS_DISTRO="windows"
    OS_PRETTY_NAME="Windows (${_kernel})"
fi

# ── Environment Flags ──────────────────────────────────────────────────────
OS_IS_WSL=false
OS_IS_CONTAINER=false

if [[ "${OS_FAMILY}" == "linux" ]]; then
    # WSL detection
    if [[ -f /proc/version ]] && grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
        OS_IS_WSL=true
    fi

    # Container detection
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc\|kubepods' /proc/1/cgroup 2>/dev/null; then
        OS_IS_CONTAINER=true
    fi
fi

# ── Backward Compatibility ─────────────────────────────────────────────────
# Existing install scripts use: case "${machine}" in Linux|Mac|Windows)
case "${OS_FAMILY}" in
    linux)   machine="Linux"   ;;
    macos)   machine="Mac"     ;;
    windows) machine="Windows" ;;
    *)       machine="UNKNOWN:${_kernel}" ;;
esac

# ── Export ──────────────────────────────────────────────────────────────────
export OS_FAMILY OS_ARCH OS_ARCH_ALT
export OS_DISTRO OS_DISTRO_LIKE OS_DISTRO_VERSION OS_CODENAME OS_PRETTY_NAME
export OS_IS_WSL OS_IS_CONTAINER
export machine

# ── Query Helpers ───────────────────────────────────────────────────────────

os_is_linux()   { [[ "${OS_FAMILY}" == "linux"   ]]; }
os_is_macos()   { [[ "${OS_FAMILY}" == "macos"   ]]; }
os_is_windows() { [[ "${OS_FAMILY}" == "windows" ]]; }

# Check if the current distro is, or derives from, a given distro.
# Usage: os_distro_like debian  →  true on Ubuntu, Pop!_OS, Mint, Debian, etc.
os_distro_like() {
    local target="$1"
    [[ "${OS_DISTRO}" == "${target}" ]] && return 0

    local entry
    for entry in ${OS_DISTRO_LIKE}; do
        [[ "${entry}" == "${target}" ]] && return 0
    done
    return 1
}

# Print all detected values — useful for debugging bootstrap runs.
os_print_summary() {
    printf '\n  OS Detection Summary\n'
    printf '  ────────────────────\n'
    printf '  %-16s %s\n' \
        "Family"       "${OS_FAMILY}" \
        "Distro"       "${OS_DISTRO}" \
        "Distro Like"  "${OS_DISTRO_LIKE:-—}" \
        "Version"      "${OS_DISTRO_VERSION:-—}" \
        "Codename"     "${OS_CODENAME:-—}" \
        "Pretty Name"  "${OS_PRETTY_NAME:-—}" \
        "Arch"         "${OS_ARCH}" \
        "Arch (alt)"   "${OS_ARCH_ALT}" \
        "WSL"          "${OS_IS_WSL}" \
        "Container"    "${OS_IS_CONTAINER}" \
        "machine"      "${machine}"
    printf '\n'
}

unset _kernel

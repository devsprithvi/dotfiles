#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# git is typically pre-installed, but we ensure it is available
# and configured at the user level.

if has_command git; then
    echo "git is already installed."
    exit 0
fi

if os_is_macos; then
    # macOS provides git via Xcode Command Line Tools
    xcode-select --install 2>/dev/null || true
elif os_is_windows; then
    if has_command scoop; then
        installer_scoop_install git
    elif has_command winget; then
        installer_winget_install Git.Git
    else
        echo "Cannot install git on Windows: scoop or winget required."
        exit 1
    fi
elif os_is_linux; then
    if ! can_run_privileged; then
        echo "git requires root or sudo to install. Skipping."
        exit 0
    fi

    if os_distro_like debian; then
        export DEBIAN_FRONTEND=noninteractive
        run_privileged apt-get update -qq
        run_privileged apt-get install -y -qq git
    elif os_distro_like fedora || os_distro_like rhel; then
        run_privileged dnf install -y git
    elif os_distro_like arch; then
        run_privileged pacman -Sy --noconfirm --needed git
    elif os_distro_like alpine; then
        run_privileged apk add --no-cache git
    elif os_distro_like suse; then
        run_privileged zypper --non-interactive install git
    else
        echo "Unknown distro '${OS_DISTRO}'. Cannot install git automatically."
        exit 1
    fi
fi

echo "git installed."

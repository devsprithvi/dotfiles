#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command curl; then
    echo "curl is already installed."
    exit 0
fi

if os_is_macos; then
    # curl is pre-installed on macOS
    echo "curl should be pre-installed on macOS."
    exit 0
fi

if os_is_windows; then
    echo "curl should be pre-installed on Windows."
    exit 0
fi

# Linux — system package, needs sudo
if ! can_run_privileged; then
    echo "curl requires root or sudo to install. Skipping."
    exit 0
fi

if os_distro_like debian; then
    export DEBIAN_FRONTEND=noninteractive
    run_privileged apt-get update -qq
    run_privileged apt-get install -y -qq curl
elif os_distro_like fedora || os_distro_like rhel; then
    run_privileged dnf install -y curl
elif os_distro_like arch; then
    run_privileged pacman -Sy --noconfirm --needed curl
elif os_distro_like alpine; then
    run_privileged apk add --no-cache curl
elif os_distro_like suse; then
    run_privileged zypper --non-interactive install curl
else
    echo "Unknown distro '${OS_DISTRO}'. Cannot install curl automatically."
    exit 1
fi

echo "curl installed."

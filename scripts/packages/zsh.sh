#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

if has_command zsh; then
    echo "zsh is already installed."
    exit 0
fi

# zsh is a system-level shell — it genuinely needs privileged install on Linux.
# On macOS it is pre-installed. On Windows it is not practical.

if os_is_macos; then
    echo "zsh should be pre-installed on macOS."
    exit 0
fi

if os_is_windows; then
    echo "Skipping zsh on Windows."
    exit 0
fi

# Linux — this is the one tool that needs sudo
if ! can_run_privileged; then
    echo "zsh requires root or sudo to install. Skipping."
    exit 0
fi

if os_distro_like debian; then
    export DEBIAN_FRONTEND=noninteractive
    run_privileged apt-get update -qq
    run_privileged apt-get install -y -qq zsh
elif os_distro_like fedora || os_distro_like rhel; then
    run_privileged dnf install -y zsh
elif os_distro_like arch; then
    run_privileged pacman -Sy --noconfirm --needed zsh
elif os_distro_like alpine; then
    run_privileged apk add --no-cache zsh
elif os_distro_like suse; then
    run_privileged zypper --non-interactive install zsh
else
    echo "Unknown distro '${OS_DISTRO}'. Cannot install zsh automatically."
    exit 1
fi

echo "zsh installed."

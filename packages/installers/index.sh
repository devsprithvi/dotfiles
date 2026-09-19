#!/usr/bin/env bash

# ── Guard: skip if already sourced ──────────────────────────────────────────
[[ -n "${_INSTALLERS_INDEX_LOADED:-}" ]] && return 0
_INSTALLERS_INDEX_LOADED=1

# ────────────────────────────────────────────────────────────────────────────
# ── Installers Index ─────────────────────────────────────────────────────────
# ────────────────────────────────────────────────────────────────────────────
# Auto-loads every package-manager wrapper in this directory. These are the
# generic, idempotent helpers (installer_apt_install, installer_brew_install,
# ...) that the individual package scripts in packages/ call so they don't
# duplicate distro-specific install logic.
#
# Adding a new package manager is a single new file here — no wiring needed.
#
# Depends on the utilities logger/helpers (log_*, has_command, run_privileged,
# can_run_privileged), which are already loaded by utilities/index.sh before
# this file is sourced.
# ────────────────────────────────────────────────────────────────────────────

INSTALLERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-load every wrapper. Drop a file in here to add a package manager.
for _installer_file in "${INSTALLERS_DIR}/"*.sh; do
    [[ "$_installer_file" == "${INSTALLERS_DIR}/index.sh" ]] && continue
    [[ -e "$_installer_file" ]] && source "$_installer_file"
done
unset _installer_file
